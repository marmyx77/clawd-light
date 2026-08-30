import Foundation

/// Who is holding a rollout open right now.
///
/// The scanner asks this of every Codex process at once, to draw the column. The
/// click asks it of one file, to find the terminal tab that session is typed in:
/// a Codex session leaves no session file naming its pid — that is Claude Code's
/// habit, not Codex's — so the descriptor is the only thread from a row back to
/// a process, and from a process back to a window.
public enum CodexHolders {

    /// The pid holding `path` open, or `nil` when nothing does.
    ///
    /// Paths are compared as the filesystem spells them, not as strings: `lsof`
    /// prints the real path, and a rollout under a temporary home is reached
    /// through `/var`, which is a link to `/private/var` on every Mac. The same
    /// mismatch already made a whole scan match nothing and report it as no
    /// sessions.
    ///
    /// A file open in more than one process picks the lowest pid among those
    /// running `codex`, and only falls back to the lowest pid overall. The order
    /// `lsof` prints in is not a promise, and a click that raises a different tab
    /// each time would be worse than one that raises none.
    public static func first(holding path: String, in files: [OpenFile]) -> Int32? {
        let wanted = CanonicalPath.of(path)
        let holders = files.filter { CanonicalPath.of($0.path) == wanted }
        guard !holders.isEmpty else { return nil }
        let codex = holders.filter { $0.command == "codex" }
        return (codex.isEmpty ? holders : codex).map(\.pid).min()
    }
}
