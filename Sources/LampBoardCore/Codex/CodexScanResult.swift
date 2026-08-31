import Foundation

/// A Codex session proven to exist right now.
///
/// A value, and here rather than beside the scanner that produces it, because
/// what the panel **decides** about these has to be testable without a disk. The
/// scanner walks processes and asks `lsof`; `CodexAdmission` decides what any of
/// it means, and that division is the one this project already draws between
/// `ClaudeDesktopScanner` and `DesktopConversation`.
public struct CodexEvidence: Sendable, Equatable {
    /// From the rollout's own first record, never from anything sent to us.
    public let meta: CodexSessionMeta
    /// The rollout the process holds open.
    public let rolloutPath: String
    public let pid: Int32
    /// The binary behind the pid, which is what names the surface.
    public let executable: String
    public let surface: CodexSurface
    /// The last record in the rollout that carries a timestamp.
    public let lastActivity: Date

    public init(
        meta: CodexSessionMeta, rolloutPath: String, pid: Int32,
        executable: String, surface: CodexSurface, lastActivity: Date
    ) {
        self.meta = meta
        self.rolloutPath = rolloutPath
        self.pid = pid
        self.executable = executable
        self.surface = surface
        self.lastActivity = lastActivity
    }
}

/// What the scanner learned, and whether it learned anything at all.
///
/// The distinction is the point of the type. A probe that answered and saw no
/// open rollout is evidence that the sessions are over; a probe that could not
/// run, or ran out of time, is **absence of evidence**, and treating the two the
/// same would delete every Codex row the first time a network mount made `lsof`
/// pause. The store already draws this line for a remote host that has gone
/// quiet, and it draws it here for the same reason.
public enum CodexScanResult: Sendable, Equatable {
    case observed([CodexEvidence])
    case unavailable(String)
}
