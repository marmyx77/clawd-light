import ClawdLightCore
import Darwin
import Foundation

/// Reads the live Claude Code sessions from `~/.claude/sessions/`.
///
/// The directory holds one file per process, but the files survive the death of
/// the process: the name is the PID, and the liveness check is `kill(pid, 0)`.
/// It costs one syscall per file and sends no signal at all — it only asks the
/// kernel whether that process still exists.
struct LiveSessionReader {
    private let directory: URL
    private let fileManager: FileManager

    init(
        directory: URL = AppConfig.liveSessionsDirectory,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Sessions whose process is actually running.
    /// An unreadable file is skipped rather than failing the whole read.
    func readLiveSessions() -> [LiveSession] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter { $0.pathExtension == "json" }
            .compactMap(read)
            .filter { isRunning(pid: $0.pid) }
    }

    // MARK: - Internal

    private func read(_ url: URL) -> LiveSession? {
        guard
            let data = try? Data(contentsOf: url),
            let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
            let modifiedAt = attributes.contentModificationDate
        else {
            return nil
        }
        guard let session = try? LiveSessionParser.parse(data: data, modifiedAt: modifiedAt) else {
            return nil
        }
        return session.with(modifiedAt: lastActivity(of: session, fallback: modifiedAt))
    }

    /// When this session last did anything.
    ///
    /// **Not** the session file's timestamp, which is what it used to be. That file
    /// is written once, when the session starts, and never touched again: a session
    /// opened a week ago and working right now reports a week of silence. The
    /// column then pruned it as stale, so the traffic light went dark on precisely
    /// the session it exists to show.
    ///
    /// The transcript is the real signal — it grows with every message and every
    /// tool result. Measured on the session that exposed this: transcript 1.3
    /// minutes old, session file 173.6 hours.
    ///
    /// Falls back to the session file when the transcript cannot be found, which
    /// happens for a session running inside a git worktree.
    private func lastActivity(of session: LiveSession, fallback: Date) -> Date {
        let candidate = TranscriptLocator.candidateURL(
            sessionId: session.sessionId, cwd: session.cwd
        )
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: candidate.path
        ), let modified = attributes[.modificationDate] as? Date else {
            return fallback
        }
        return max(modified, fallback)
    }

    /// `kill(pid, 0)` sends nothing: it only checks existence and permissions.
    /// `EPERM` means the process exists but belongs to another user, so it still
    /// counts as alive.
    private func isRunning(pid: Int) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }
}
