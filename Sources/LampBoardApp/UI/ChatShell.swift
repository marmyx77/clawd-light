import LampBoardCore
import Combine
import Foundation
import SwiftUI

/// The extended view: every conversation on the left, the selected one on the right.
///
/// # Why one window and not one per conversation
///
/// The first version gave each conversation a window of its own — the ICQ shape.
/// It was argued for well and it lost to use: switching between projects means
/// hunting for a window, and with a dozen of them the desk becomes the thing you
/// manage instead of the work. A list you click down is faster than a window you
/// look for.
///
/// The panel is untouched by any of this. It keeps its own job — peripheral,
/// never taking focus, always visible — and this window is the one you open when
/// you sit down. Two jobs, two surfaces; see [D14](docs/04-decisions.md).
///
/// # What it costs, and the one number that matters
///
/// Every conversation you visit keeps its parsed transcript in memory so coming
/// back is instant, but **only the selected one polls its file**, and **only the
/// selected one arms a message listener**. So the running cost of this window is
/// one file poll and at most one waiting process, whatever the size of the list.
@MainActor
final class ChatShell: ObservableObject {

    /// The rows on the left, in the same order the panel shows them.
    ///
    /// Deliberately the same `ColumnLayout.render` the panel uses: two orderings
    /// for the same list is two things to keep in agreement, and the one the eye
    /// already learned from the panel is the one that should not move.
    @Published private(set) var rows: [ColumnRow] = []

    /// The session shown on the right.
    @Published private(set) var selectedId: String?

    private let store: StateStore
    private let preferences: Preferences
    private let mailbox: MailboxWriter

    /// Conversations already visited, kept so switching back is instant.
    ///
    /// They are cheap when idle — a trimmed transcript is a few tens of kilobytes
    /// and the timer is stopped — and re-reading an eight-thousand-line file on
    /// every switch is exactly the lag that makes a chat feel slow.
    private var sessions: [String: ChatSession] = [:]
    private let previews = TranscriptPreviewReader()
    private var cancellables = Set<AnyCancellable>()

    init(store: StateStore, preferences: Preferences, mailbox: MailboxWriter) {
        self.store = store
        self.preferences = preferences
        self.mailbox = mailbox
    }

    // MARK: - Lifecycle

    func start(selecting sessionId: String? = nil) {
        rebuildRows()
        store.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildRows() }
            .store(in: &cancellables)

        select(sessionId ?? rows.first?.primary.id)
    }

    func stop() {
        cancellables.removeAll()
        for session in sessions.values { session.stop() }
        // Only the selected conversation ever holds a marker, so this closes the
        // one listener that can exist.
        if let selectedId { releaseMailbox(of: selectedId) }
        sessions.removeAll()
        selectedId = nil
    }

    // MARK: - Selection

    /// The conversation currently on the right, if any.
    var selected: ChatSession? {
        guard let selectedId else { return nil }
        return sessions[selectedId]
    }

    func select(_ sessionId: String?) {
        guard selectedId != sessionId else {
            selected?.markRead()
            return
        }

        if let previous = selectedId {
            sessions[previous]?.stop()
            releaseMailbox(of: previous)
        }

        selectedId = sessionId
        guard let sessionId, let state = sessionState(for: sessionId) else { return }

        let session = sessions[sessionId] ?? ChatSession(
            session: state, store: store, mailbox: mailbox
        )
        sessions[sessionId] = session

        if case .failure(let error) = mailbox.open(sessionId: sessionId) {
            Diagnostics.log("chat \(sessionId): mailbox not opened: \(error.description)")
        }
        session.start()
        session.markRead()
    }

    /// Selects the conversation a row stands for.
    ///
    /// The row's `primary` session, which is the most urgent one — the same
    /// session a click in the panel opens. Two gestures that disagreed about which
    /// conversation a project *is* would be a defect nobody could describe.
    func select(row: ColumnRow) {
        select(row.primary.id)
    }

    /// Withdraws the marker, unless a message is still waiting.
    ///
    /// Leaving it armed for a pending message is the whole point: you typed it,
    /// so it has to arrive, even if you looked away at another conversation
    /// before it did. Dropping it silently on a switch would lose a message the
    /// interface had already accepted.
    private func releaseMailbox(of sessionId: String) {
        if !mailbox.close(sessionId: sessionId) {
            Diagnostics.log("chat \(sessionId): message still pending, listener left armed")
        }
    }

    // MARK: - Rows

    private func rebuildRows() {
        let rendering = ColumnLayout.render(
            store.state,
            options: ColumnOptions(
                // The extended view never hides and never filters: it is the place
                // you go to look at everything, and a list that quietly omits a
                // project is the opposite of that.
                onlyWaiting: false,
                order: preferences.rowOrder,
                hidden: [],
                names: preferences.rowNames
            )
        )

        // One line per **conversation**, not per project. The panel groups because
        // a column of a dozen dots has to be readable at a glance; this window is
        // where you come to look at one conversation, so a project that holds three
        // is three lines here.
        //
        // Each takes the name resolved for it — its own if you gave it one, then
        // its title, then its lane's, then its position. That last part is a
        // correction: the name used to be looked up by folder and agent, so
        // renaming one conversation renamed every other one in the same folder.
        rows = rendering.rows.flatMap { row in
            row.members.map { member in
                ColumnRow(
                    id: member.id,
                    workspace: row.workspace,
                    sessions: [member.session],
                    slot: row.slot,
                    alias: member.name
                )
            }
        }

        // The selected conversation can end: a session closes, its process dies,
        // pruning removes it. Falling back to the top of the list beats showing an
        // empty pane with no explanation.
        if let selectedId, sessionState(for: selectedId) == nil {
            select(rows.first?.primary.id)
        }
    }

    /// Renames **one conversation**, and nothing else.
    ///
    /// This window is the only place where every line is a single conversation,
    /// so it is where a conversation gets a name of its own. The panel's own
    /// Rename names the project, because there a row is a project.
    ///
    /// It exists because the opposite was reported from use: with one line per
    /// session, renaming one renamed every other session in the same folder, since
    /// the most specific key held the folder and the agent and never the
    /// conversation.
    @MainActor
    func rename(row: ColumnRow) {
        guard let answer = Alerts.ask(
            title: "Rename \u{201C}\(row.displayName)\u{201D}",
            message: "Only what this window and the panel show changes, and only for "
                + "this conversation. Its project keeps its own name. Leave it empty "
                + "to go back to the original.",
            initialValue: RowNames.name(ofSession: row.id, in: preferences.rowNames) ?? "",
            placeholder: row.primary.title ?? row.workspace.name,
            confirmTitle: "Rename"
        ) else { return }
        preferences.rowNames = RowNames.renaming(session: row.id, to: answer, in: preferences.rowNames)
        rebuildRows()
    }

    private func sessionState(for sessionId: String) -> SessionState? {
        store.state.sessions[sessionId]
    }

    /// The one-line preview under a row's name: the last thing actually said.
    ///
    /// Read from the transcript rather than from `last_assistant_message`, which
    /// the hooks hand us for free but which is wrong twice: it is only ever
    /// Claude's side, so a project you just wrote to shows the previous answer,
    /// and on an interrupted turn it holds the **error text** instead of anything
    /// anybody said.
    ///
    /// The cost is contained in the reader — the tail of the file only, cached on
    /// its size — so drawing the list is one `stat` per row when nothing moved.
    /// The hook value stays as the fallback for a session whose transcript we
    /// cannot find.
    func preview(for row: ColumnRow) -> String? {
        let session = row.primary
        let path = session.transcriptPath
            ?? TranscriptLocator.candidateURL(
                sessionId: session.id, cwd: session.workspace.path
            ).path
        return previews.preview(ofTranscriptAt: path, for: session.id)
            ?? session.lastMessage.map { MarkdownParser.plainSummary(of: $0) }
    }
}
