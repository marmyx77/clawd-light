import Foundation

/// A working folder a session is running in.
///
/// Locally that means a folder open in a VS Code window. On another machine it
/// means the session's own folder: asking whether a VS Code window claims it is
/// meaningless for a session in a tmux pane on a headless node, and applying the
/// local criterion there is what kept those rows invisible.
public struct Workspace: Sendable, Equatable, Hashable {
    /// Absolute path of the workspace root folder.
    public let path: String

    /// The machine it lives on, as it is written in `~/.ssh/config`. `nil` means
    /// this one.
    ///
    /// Part of the identity, not decoration: two machines can hold the same path,
    /// and a row per machine is the only honest answer. Without this they would
    /// collapse into one and the column would show a folder in two states at once.
    public let host: String?

    public init(path: String, host: String? = nil) {
        self.path = PathNormalizer.normalize(path)
        self.host = host?.trimmed.nilIfEmpty
    }

    /// `true` when the folder is on another machine.
    ///
    /// What it gates is behaviour, not just looks: there is no local window to
    /// bring to the front, and no local transcript to open.
    public var isRemote: Bool { host != nil }

    /// Name shown next to the traffic light — it matches what VS Code writes in
    /// the window title, and it is the key used to find that window again.
    ///
    /// Deliberately **without** the host: this value is matched against window
    /// titles, and adding anything to it would break that match.
    public var name: String {
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? path : last
    }

    /// What a person reads in the column. Same as `name` here, plus where it is.
    public var label: String {
        guard let host else { return name }
        return "\(name) @\(host)"
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
