import LampBoardCore
import AppKit
import Darwin
import Foundation

/// One Claude Desktop conversation running on this Mac, and everything the
/// machine can honestly say about it.
struct DesktopEvidence: Sendable, Equatable {
    /// The transcript's own id, which is a Claude Code session id like any
    /// other and is what the row is keyed by.
    let id: String
    /// The folder, the name and the model, from the index beside the home.
    let index: DesktopSessionIndex
    let transcriptPath: String?
    /// Whether a turn is running, derived from the transcript. `nil` when the
    /// transcript says nothing readable, which is not the same as "idle".
    let phase: TranscriptTurn.Phase?
    /// The last record that carried a moment, or the application's own reckoning
    /// when the transcript carried none.
    let lastActivity: Date
    /// `true` when a live process still holds this conversation's session file.
    ///
    /// Corroboration, never presence: see `ClaudeDesktopScanner`.
    let isAnswering: Bool
}

/// What a sweep learned, and whether it learned anything.
///
/// The same distinction the Codex scanner draws, for the same reason: a probe
/// that answered and found nothing means the conversations are over, a probe
/// that could not run means nothing at all, and treating them alike would empty
/// the column the first time a directory could not be listed.
enum DesktopScanResult: Sendable, Equatable {
    case observed([DesktopEvidence])
    case unavailable(String)
}

/// Finds the Claude Desktop conversations that run on this Mac.
///
/// Claude Desktop starts a session in one of two places. A **cloud** session
/// runs on Anthropic's servers and leaves nothing here to read: its hooks are a
/// documented, open gap (anthropics/claude-code#40495, three root causes, open
/// since March), its transcript never touches this disk, and no probe tried —
/// descriptor, socket, network route, session file — found anything at all. A
/// **local** session runs here, as a child of the application, and writes
/// exactly the files every terminal session writes.
///
/// ## Why presence is not the session file
///
/// The first version of this scanner asked the question every other surface
/// asks: which session files name a process that is still alive? It was wrong,
/// and the way it was wrong is instructive. A Claude Desktop session's agent
/// process lives for **one turn**. The application starts it to answer and
/// removes its session file when it exits — measured here on 30 August: a turn
/// whose last word landed at 22:44:38 left an empty `.claude/sessions`
/// directory stamped 22:44. A row built on that appears while the model is
/// working and vanishes at the exact moment there is an answer to read, which
/// is the one moment this panel exists for.
///
/// So the durable evidence is the pair the application keeps for itself: the
/// **index** beside each session home, which names the folder, the title and the
/// transcript, and the **transcript**, which is the conversation's own record of
/// what it did. The session file is still read, and still means something — a
/// process holding it is a turn running right now — but it can only ever
/// corroborate a colour, never grant or withdraw a row.
///
/// ## What bounds the column
///
/// Three gates, each of them the application's own answer rather than ours:
/// the app must be running (quit it and the rows go), the conversation must
/// have a folder the application resolved as **local**, and it must not be
/// archived. What is left is bounded in time by `AppConfig.sessionStaleAfter`,
/// the same window every other row obeys when it stops hearing news.
final class ClaudeDesktopScanner {

    private let root: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let isApplicationRunning: () -> Bool

    /// Cached per home, keyed by the index file's size and date. The index is
    /// rewritten on every turn and read on every sweep, and a sweep runs often.
    private var indexCache: [String: (stamp: String, value: DesktopSessionIndex)] = [:]

    init(
        home: URL = AppConfig.homeDirectory,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        isApplicationRunning: @escaping () -> Bool = ClaudeDesktopScanner.applicationIsRunning
    ) {
        self.root = ClaudeDesktop.sessionsRoot(inHome: home)
        self.fileManager = fileManager
        self.now = now
        self.isApplicationRunning = isApplicationRunning
    }

    /// `true` when Claude Desktop is running, so that quitting it takes its
    /// conversations off the panel rather than leaving them there for the twelve
    /// hours it takes a silent row to go stale.
    ///
    /// Against a fake home the question is not asked, and that is the same rule
    /// `AppConfig.isUsingHomeOverride` exists to enforce everywhere else: a run
    /// pointed at a fixture must not consult the real machine, or whether the
    /// developer happens to have Claude Desktop open decides the test.
    static func applicationIsRunning() -> Bool {
        if AppConfig.isUsingHomeOverride { return true }
        return !NSRunningApplication
            .runningApplications(withBundleIdentifier: ClaudeDesktop.bundleIdentifier)
            .isEmpty
    }

    func scan() -> DesktopScanResult {
        // Quitting the application ends every local conversation it was running.
        // An absence, not an outage: the caller may prune on it.
        guard isApplicationRunning() else { return .observed([]) }
        guard fileManager.fileExists(atPath: root.path) else { return .observed([]) }
        guard let homes = sessionHomes() else {
            return .unavailable("the Claude Desktop session directory could not be listed")
        }

        let horizon = now().addingTimeInterval(-AppConfig.sessionStaleAfter)
        return .observed(homes.compactMap { evidence(inHome: $0, notBefore: horizon) })
    }

    // MARK: - Walking

    /// Every `local_<uuid>` directory, two levels down: the application groups
    /// them by organisation and then by account.
    private func sessionHomes() -> [URL]? {
        guard let organisations = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }

        var homes: [URL] = []
        for organisation in organisations {
            let accounts = (try? fileManager.contentsOfDirectory(
                at: organisation, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            for account in accounts {
                let entries = (try? fileManager.contentsOfDirectory(
                    at: account, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                )) ?? []
                homes += entries.filter { ClaudeDesktop.isSessionHome($0.lastPathComponent) }
            }
        }
        return homes
    }

    // MARK: - One conversation

    /// The three cheap gates first, so a home that cannot be a row costs one
    /// read of a small file rather than a walk of its transcript.
    private func evidence(inHome home: URL, notBefore horizon: Date) -> DesktopEvidence? {
        guard let index = index(forHome: home),
              DesktopConversation.deservesRow(index, since: horizon),
              let id = index.cliSessionId
        else { return nil }

        let configuration = home.appendingPathComponent(".claude", isDirectory: true)
        let transcript = transcriptPath(in: configuration, sessionId: id)
        let tail = transcript.map(Self.tail(of:))
        return DesktopEvidence(
            id: id,
            index: index,
            transcriptPath: transcript,
            phase: tail.flatMap { TranscriptTurn.phase(inTailChunk: $0.text, isWholeFile: $0.whole) },
            lastActivity: tail.flatMap {
                TranscriptActivity.lastTimestamp(inTailChunk: $0.text, isWholeFile: $0.whole)
            } ?? index.lastActivityAt ?? .distantPast,
            isAnswering: isAnswering(in: configuration)
        )
    }

    /// `true` while a process is still holding this conversation's session file.
    ///
    /// The file is written when the application starts a turn and removed when
    /// that process exits, so its presence is a turn in flight. Both checks stay
    /// — the pid must be alive and must be the process the file was written for
    /// — because a crash leaves the file behind, and one from April is still on
    /// this disk to prove it.
    private func isAnswering(in configuration: URL) -> Bool {
        let directory = configuration.appendingPathComponent("sessions", isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        for entry in entries where entry.pathExtension == "json" {
            guard let data = try? Data(contentsOf: entry),
                  let modifiedAt = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                      .contentModificationDate,
                  let session = try? LiveSessionParser.parse(data: data, modifiedAt: modifiedAt),
                  session.pid > 0,
                  let info = ProcessTree.info(of: pid_t(session.pid))
            else { continue }
            if let raw = session.procStart, let start = ProcStart.parse(raw),
               !start.matches(processStartedAt: info.startedAt) { continue }
            return true
        }
        return false
    }

    private func index(forHome home: URL) -> DesktopSessionIndex? {
        let path = ClaudeDesktop.indexPath(forHome: home)
        let attributes = try? path.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let stamp = "\(attributes?.fileSize ?? -1)/\(attributes?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        if let cached = indexCache[path.path], cached.stamp == stamp { return cached.value }

        guard let data = try? Data(contentsOf: path), let read = DesktopSessionIndex.parse(data) else {
            return nil
        }
        indexCache[path.path] = (stamp, read)
        return read
    }

    /// The transcript is found by the id the index names rather than by
    /// rebuilding the encoded folder name: the encoding is the application's
    /// business and has changed before, the id has not.
    private func transcriptPath(in configuration: URL, sessionId: String) -> String? {
        let projects = configuration.appendingPathComponent("projects", isDirectory: true)
        guard let folders = try? fileManager.contentsOfDirectory(
            at: projects, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        for folder in folders {
            let candidate = folder.appendingPathComponent("\(sessionId).jsonl")
            if fileManager.fileExists(atPath: candidate.path) { return candidate.path }
        }
        return nil
    }

    /// The end of the transcript, or the whole of it when it is short.
    private static func tail(of path: String) -> (text: String, whole: Bool) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return ("", true) }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let limit = UInt64(TranscriptActivity.tailLimit)
        let whole = size <= limit
        if !whole { try? handle.seek(toOffset: size - limit) } else { try? handle.seek(toOffset: 0) }
        let data = (try? handle.readToEnd()) ?? Data()
        return (String(decoding: data, as: UTF8.self), whole)
    }
}
