import Foundation

/// The process a Claude Code session is running in.
///
/// Claude Code writes one file per running session in `~/.claude/sessions`, named
/// after the process id and carrying the session id beside it. That is the only
/// place on this machine where the two are stated together: the process holds no
/// descriptor on its transcript and names nothing in its environment, so without
/// this file a row cannot be traced to what runs it.
///
/// Codex has no equivalent, and that is a fact about Codex rather than a gap
/// here: its conversations are served by one shared daemon, so there is no
/// process that belongs to a single conversation and nothing to end without
/// ending every other one too.
public struct SessionProcess: Sendable, Equatable {

    public let pid: Int32

    public let sessionId: String

    /// The folder the session was started in.
    public let cwd: String

    /// When the process started, as the file records it.
    ///
    /// The whole reason this type carries it. Process ids are reused, and the
    /// file outlives the process it describes — measured here, fifteen files of
    /// which several named processes that had ended. Ending a pid because a file
    /// says so, without checking that the pid is still the same process, is how
    /// a panel comes to kill something a person never asked about.
    public let startedAt: String

    public init(pid: Int32, sessionId: String, cwd: String, startedAt: String) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.startedAt = startedAt
    }

    /// Reads one session file. `nil` when it is not one, or is missing a field
    /// this depends on — an unreadable file is never guessed at.
    public static func from(json data: Data) -> SessionProcess? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let record = object as? [String: Any],
              let pid = record["pid"] as? Int,
              let sessionId = record["sessionId"] as? String,
              !sessionId.isEmpty,
              let started = record["procStart"] as? String, !started.isEmpty
        else { return nil }
        return SessionProcess(
            pid: Int32(pid),
            sessionId: sessionId,
            cwd: record["cwd"] as? String ?? "",
            startedAt: started
        )
    }

    /// Whether the pid on record is still the process this describes.
    ///
    /// Compared against what the system says the process started at, with both
    /// sides trimmed: `ps` pads its output and the file does not. A mismatch
    /// means the id was reused, and the answer is to do nothing.
    public func isStill(startedAt observed: String) -> Bool {
        let mine = startedAt.trimmingCharacters(in: .whitespaces)
        let theirs = observed.trimmingCharacters(in: .whitespaces)
        return !mine.isEmpty && mine == theirs
    }
}
