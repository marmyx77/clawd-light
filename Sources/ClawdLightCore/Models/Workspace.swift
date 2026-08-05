import Foundation

/// A working folder open in a VS Code window.
public struct Workspace: Sendable, Equatable, Hashable {
    /// Absolute path of the workspace root folder.
    public let path: String

    public init(path: String) {
        self.path = PathNormalizer.normalize(path)
    }

    /// Name shown next to the traffic light — it matches what VS Code writes in
    /// the window title, and it is the key used to find that window again.
    public var name: String {
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? path : last
    }
}

/// Path normalization, kept separate because both the resolver and `Workspace` use it.
public enum PathNormalizer {
    /// Strips trailing slashes and collapses doubled ones, without touching the filesystem.
    ///
    /// Deliberately does not resolve symlinks: `cwd` and `workspaceFolders` come from
    /// the same source (Claude Code) and are already consistent with each other.
    /// Resolving links would mean I/O on every signal in exchange for no real case covered.
    public static func normalize(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        let collapsed = path.replacingOccurrences(
            of: "/+", with: "/", options: .regularExpression
        )
        guard collapsed.count > 1, collapsed.hasSuffix("/") else { return collapsed }
        return String(collapsed.dropLast())
    }

    /// `true` when `candidate` is `parent` or one of its subfolders.
    ///
    /// The comparison runs component by component, not by string prefix: otherwise
    /// `/dev/clawd-light-old` would come out as contained in `/dev/clawd-light`.
    public static func isDescendant(_ candidate: String, of parent: String) -> Bool {
        let candidate = normalize(candidate)
        let parent = normalize(parent)
        if candidate == parent { return true }
        return candidate.hasPrefix(parent + "/")
    }
}
