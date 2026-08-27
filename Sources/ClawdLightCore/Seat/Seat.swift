import Foundation

/// A terminal application this app knows how to select a tab in.
///
/// Like `IDEKind`, a deliberately short table: an entry is a promise that a click
/// leads somewhere, and an entry added on a hunt for coverage is a row you can
/// see and a click that does nothing — worse than no row at all.
public struct TerminalKind: Sendable, Equatable, Hashable {
    /// How a tab is found and raised.
    public enum Raising: Sendable, Equatable {
        /// The dictionary exposes the tab's `tty` (Terminal.app, iTerm2).
        case appleScriptTTY
        /// The dictionary exposes a title and a working directory, no tty (Ghostty).
        case appleScriptTitle
        /// `wezterm cli list` and `activate-pane`.
        case wezterm
        /// `kitten @ ls` and `focus-window`, when remote control is on.
        case kitty
    }

    /// Name of the `.app` bundle, without the extension — how the chain names it.
    public let bundleName: String
    public let bundleIdentifier: String
    /// The name System Events and `tell application` use.
    public let applicationName: String
    public let raising: Raising

    public init(bundleName: String, bundleIdentifier: String, applicationName: String, raising: Raising) {
        self.bundleName = bundleName
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.raising = raising
    }

    public static let terminal = TerminalKind(
        bundleName: "Terminal", bundleIdentifier: "com.apple.Terminal",
        applicationName: "Terminal", raising: .appleScriptTTY
    )
    public static let iTerm = TerminalKind(
        bundleName: "iTerm", bundleIdentifier: "com.googlecode.iterm2",
        applicationName: "iTerm2", raising: .appleScriptTTY
    )
    public static let ghostty = TerminalKind(
        bundleName: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty",
        applicationName: "Ghostty", raising: .appleScriptTitle
    )
    public static let kitty = TerminalKind(
        bundleName: "kitty", bundleIdentifier: "net.kovidgoyal.kitty",
        applicationName: "kitty", raising: .kitty
    )
    public static let wezterm = TerminalKind(
        bundleName: "WezTerm", bundleIdentifier: "com.github.wez.wezterm",
        applicationName: "WezTerm", raising: .wezterm
    )

    public static let all: [TerminalKind] = [.terminal, .iTerm, .ghostty, .kitty, .wezterm]

    /// The terminal whose bundle an executable lives in, if we know it.
    public static func matching(bundleName: String) -> TerminalKind? {
        all.first { $0.bundleName == bundleName }
    }
}

/// The place a session's process lives in — what a click on a terminal row has
/// to bring to the front.
public enum Seat: Sendable, Equatable {
    /// A tab of a known terminal application, on that tty.
    case terminal(TerminalKind, tty: String)
    /// A tmux pane; the client's tab is found through the server.
    case tmux(serverPid: Int32, tty: String)
    /// A zellij pane; the client's tab is found through the server's socket.
    case zellij(serverPid: Int32, sessionName: String)
    /// An editor's own terminal or panel: raised the way editor rows are.
    case editor(IDEKind)
    /// Some application we cannot select a tab in; it can still be activated.
    case application(bundlePath: String)
    /// A chain that ends nowhere recognisable — a detached daemon, a login shell.
    case unknown

    /// What a log line or a message should call it.
    public var label: String {
        switch self {
        case .terminal(let kind, let tty): return "\(kind.applicationName) \(tty)"
        case .tmux(let pid, let tty): return "tmux server \(pid), pane on \(tty)"
        case .zellij(let pid, let name): return "zellij server \(pid), session \(name)"
        case .editor(let ide): return ide.declaredName
        case .application(let path): return (path as NSString).lastPathComponent
        case .unknown: return "an unknown place"
        }
    }
}
