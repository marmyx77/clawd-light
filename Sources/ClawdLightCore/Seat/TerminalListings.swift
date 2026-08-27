import Foundation

/// What `wezterm cli list --format json` prints: one record per pane.
///
/// Measured: `tty_name` is the pane's pty as a device path, `cwd` a `file://`
/// URL, and there is **no pid** — the tty is the key.
public enum WezTermListing {
    public struct Pane: Sendable, Equatable {
        public let paneId: Int
        public let tabId: Int
        public let windowId: Int
        public let tty: String?
        public let cwd: String?
        public let title: String
    }

    public static func parse(_ json: Data) -> [Pane] {
        guard let records = (try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]] else { return [] }
        return records.compactMap { record in
            guard let pane = record["pane_id"] as? Int else { return nil }
            let cwd = (record["cwd"] as? String).flatMap { URL(string: $0)?.path }
            return Pane(
                paneId: pane,
                tabId: record["tab_id"] as? Int ?? 0,
                windowId: record["window_id"] as? Int ?? 0,
                tty: (record["tty_name"] as? String).flatMap(TTYName.normalized),
                cwd: cwd,
                title: record["title"] as? String ?? ""
            )
        }
    }

    /// The pane on that tty, if any.
    public static func pane(onTTY tty: String, in panes: [Pane]) -> Pane? {
        guard let wanted = TTYName.normalized(tty) else { return nil }
        return panes.first { $0.tty == wanted }
    }
}

/// What `kitten @ ls` prints: OS windows → tabs → windows, each window with the
/// pid of the process it runs and the processes in its foreground.
public enum KittyListing {
    public struct Window: Sendable, Equatable {
        public let id: Int
        public let pid: Int32?
        public let cwd: String?
        public let title: String
        public let foregroundPids: [Int32]
    }

    public static func parse(_ json: Data) -> [Window] {
        guard let osWindows = (try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]] else { return [] }
        return osWindows.flatMap { os -> [Window] in
            let tabs = os["tabs"] as? [[String: Any]] ?? []
            return tabs.flatMap { tab -> [Window] in
                let windows = tab["windows"] as? [[String: Any]] ?? []
                return windows.compactMap { w in
                    guard let id = w["id"] as? Int else { return nil }
                    let foreground = (w["foreground_processes"] as? [[String: Any]] ?? [])
                        .compactMap { ($0["pid"] as? Int).map(Int32.init) }
                    return Window(
                        id: id, pid: (w["pid"] as? Int).map(Int32.init),
                        cwd: w["cwd"] as? String, title: w["title"] as? String ?? "",
                        foregroundPids: foreground
                    )
                }
            }
        }
    }

    /// The window running, or fronting, any of these pids — the session's chain.
    public static func window(hostingAnyOf pids: Set<Int32>, in windows: [Window]) -> Window? {
        windows.first { w in
            (w.pid.map(pids.contains) ?? false) || w.foregroundPids.contains(where: pids.contains)
        }
    }
}

/// Ghostty's dictionary has no tty: a terminal has an `id`, a `name` (its
/// current title) and a `working directory`. The match is done here, in Swift,
/// on what the session knows — its folder and its conversation title — and
/// only the chosen `id` goes back into a script.
public enum GhosttyMatcher {
    public struct Terminal: Sendable, Equatable {
        public let id: String
        public let name: String
        public let workingDirectory: String

        public init(id: String, name: String, workingDirectory: String) {
            self.id = id
            self.name = name
            self.workingDirectory = workingDirectory
        }
    }

    /// Claude Code's own mark in a terminal title: `✳ <title>`.
    public static let claudeMarker = "✳"

    /// The terminal whose title carries the conversation title wins; failing
    /// that, one whose working directory is the session's folder; failing that,
    /// the **only** terminal Claude Code has marked as its own (`✳` in the
    /// title). `nil` when nothing says anything — better nothing than a wrong tab.
    ///
    /// The last rule exists because of what was measured: a `claude` started as
    /// Ghostty's command reports an **empty** working directory (Ghostty learns
    /// it from the shell's OSC 7, and there is no shell), and before the first
    /// exchange the title is just `✳ Claude Code`. One marked terminal is not a
    /// guess; two are.
    public static func best(among terminals: [Terminal], cwd: String, title: String?) -> Terminal? {
        if let title = title?.trimmed.nilIfEmpty,
           let byTitle = terminals.first(where: { $0.name.contains(title) }) {
            return byTitle
        }
        let folder = PathNormalizer.normalize(cwd)
        if let byFolder = terminals.first(where: {
            !$0.workingDirectory.isEmpty && PathNormalizer.normalize($0.workingDirectory) == folder
        }) {
            return byFolder
        }
        let marked = terminals.filter { $0.name.contains(claudeMarker) }
        return marked.count == 1 ? marked[0] : nil
    }

    /// `true` for an id that may enter a script: Ghostty's are opaque tokens,
    /// and anything outside this alphabet is refused rather than escaped.
    public static func isUsable(id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9._:-]{1,128}$", options: .regularExpression) != nil
    }
}
