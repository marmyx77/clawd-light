import ClawdLightCore
import Combine
import Foundation
import SwiftUI

/// What one chat window is looking at.
///
/// It holds two things that update on different clocks and must not be confused:
/// the **conversation**, which comes from the transcript on disk, and the
/// **status**, which comes from the hooks. The transcript says what was said; the
/// traffic light says whether anything is coming. A window that inferred one from
/// the other would be wrong in both directions — a long silence is not an idle
/// session, and a green dot is not a message.
@MainActor
final class ChatSession: ObservableObject {

    @Published private(set) var conversation: Conversation
    @Published private(set) var status: SessionStatus
    @Published private(set) var unread: Int = 0

    /// A message written but not yet picked up by the session.
    ///
    /// Shown to the user, because the delay is real and unexplained waiting is
    /// what makes a chat feel broken: if Claude is mid-turn the message sits on
    /// disk until that turn ends, which can be minutes.
    @Published private(set) var pending: String?

    /// Why the last send failed, if it did.
    @Published private(set) var sendError: String?

    /// `true` when a listener is armed and a message would be picked up promptly.
    ///
    /// False is the cold start: the chat window is open, but no turn has ended
    /// since, so nothing is waiting to carry a message. It resolves itself the
    /// moment the session does anything at all — and until then the window says
    /// so instead of showing a spinner for something that will not happen.
    @Published private(set) var listening = false

    /// `true` when answering from the panel is switched on.
    ///
    /// Off is the default and the safe resting state — see D15. The composer is
    /// disabled rather than hidden, because a chat window with no visible way to
    /// answer reads as broken, and one that accepts text going nowhere is worse.
    var canSend: Bool { mailbox.isSendingEnabled }

    let sessionId: String
    let workspace: Workspace

    private let store: StateStore
    private let reader: TranscriptReader
    private let mailbox: MailboxWriter
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// When the user last had this window in front of them.
    private var lastRead: Date?

    init(session: SessionState, store: StateStore, mailbox: MailboxWriter = MailboxWriter()) {
        self.mailbox = mailbox
        self.sessionId = session.id
        self.workspace = session.workspace
        self.store = store
        self.status = session.status
        self.conversation = Conversation(sessionId: session.id)
        self.reader = TranscriptReader(path: Self.transcriptPath(for: session))
    }

    /// Where to read from: what the hooks said, or a checked guess.
    ///
    /// A session adopted from `~/.claude/sessions/` carries no transcript path,
    /// and after a restart of clawd-light that is every session — so without the
    /// fallback the chat window would stay empty until somebody pressed enter
    /// again. The derived path is **verified on disk** before being used, because
    /// it is wrong for sessions running in a git worktree, where `cwd` reports the
    /// main repository and the transcript is filed under the worktree.
    private static func transcriptPath(for session: SessionState) -> String {
        if let known = session.transcriptPath { return known }

        let candidate = TranscriptLocator.candidateURL(
            sessionId: session.id, cwd: session.workspace.path
        )
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate.path : ""
    }

    /// `true` when there is a transcript to read at all.
    ///
    /// False for a session adopted from the filesystem before any hook fired. The
    /// window says so instead of showing an empty conversation, which would read
    /// as "nothing was said here".
    var hasTranscript: Bool { !reader.path.isEmpty }

    // MARK: - Lifecycle

    func start() {
        listening = mailbox.isListening(sessionId: sessionId)
        guard hasTranscript else { return }
        loadEverything()
        followStatus()
        startPolling()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
    }

    // MARK: - Sending

    /// Leaves a message for the session.
    ///
    /// Returns `true` when it was written. Written is **not** delivered: if the
    /// session is mid-turn the message waits on disk until the turn ends, which
    /// is why `pending` exists and why the composer clears only on success.
    @discardableResult
    func send(_ text: String) -> Bool {
        sendError = nil
        switch mailbox.send(text, to: sessionId) {
        case .success:
            pending = text.trimmed
            Diagnostics.log("chat \(sessionId): queued \(text.trimmed.count) chars")
            return true
        case .failure(let error):
            sendError = error.description
            Diagnostics.log("chat \(sessionId): send refused — \(error.description)")
            return false
        }
    }

    /// The window came to the front: everything in it counts as read.
    func markRead() {
        lastRead = Date()
        unread = 0
    }

    // MARK: - Reading

    private func loadEverything() {
        let entries = reader.readAll()
        conversation = Conversation(
            sessionId: sessionId, title: reader.title, entries: entries
        )
            .trimmed(to: AppConfig.chatHistoryLimit)

        // An empty window has two very different causes — the file wasn't there,
        // or it was there and nothing in it was recognised — and they look
        // identical on screen. This is the line that tells them apart.
        Diagnostics.log("""
        chat \(sessionId): \(entries.count) entries from \(reader.path) \
        (\(entries.filter { $0.kind == .human }.count) human, \
        \(entries.filter { $0.kind == .assistant }.count) assistant) \
        title=\(reader.title ?? "<none>")
        """)
        // Opening a window is reading it: the count starts from now, not from the
        // beginning of a conversation that may be three days old.
        markRead()
    }

    private func refresh() {
        // Before the early return below, on purpose. The listener takes the
        // message off disk seconds before the turn produces anything to read, and
        // behind that guard the composer would keep saying "waiting" for a message
        // that had already gone.
        if pending != nil, !mailbox.hasPending(sessionId: sessionId) {
            pending = nil
        }
        listening = mailbox.isListening(sessionId: sessionId)

        let fresh = reader.readNewEntries()
        guard !fresh.isEmpty || reader.title != conversation.title else { return }

        conversation = conversation
            .appending(fresh, title: reader.title)
            .trimmed(to: AppConfig.chatHistoryLimit)
        unread = conversation.unreadCount(since: lastRead)

        if !fresh.isEmpty {
            Diagnostics.log(
                "chat \(sessionId): +\(fresh.count) entries, \(unread) unread"
            )
        }
    }

    /// Polling, and not a filesystem watcher.
    ///
    /// `DispatchSource` on a file that gets replaced — which a transcript does, on
    /// `/clear` and on a fork — needs re-arming on a vnode that no longer exists,
    /// and getting that wrong stops the window updating with no visible symptom. A
    /// one-second `stat` costs nothing next to being silently frozen, and the
    /// reader already returns immediately when the size hasn't moved.
    private func startPolling() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(
            withTimeInterval: AppConfig.transcriptPollInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The dot in the header follows the column, because it *is* the column: the
    /// same state, read from the same store, so the two can never disagree.
    private func followStatus() {
        store.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, let session = state.sessions[self.sessionId] else { return }
                self.status = session.status
            }
            .store(in: &cancellables)
    }
}
