import Foundation

/// Which Codex a session is running in, read from the executable behind its pid.
///
/// Better evidence than the rollout's own `originator`, and the difference is not
/// theoretical: in one week that field has been seen as `codex_cli_rs`,
/// `codex-tui`, `codex_exec` and `Codex Desktop`, and the transcript format it
/// lives in is declared unstable by its own documentation. The path of the binary
/// holding the file open is decided by where the program was installed, which is
/// a fact about this machine rather than a promise from a vendor.
public enum CodexSurface: String, Sendable, Equatable, CaseIterable {
    /// The copy shipped inside the ChatGPT desktop application.
    case chatgptApp
    /// The copy shipped inside the VS Code extension.
    case editorExtension
    /// A `codex` installed on its own: Homebrew, npm, a build.
    case commandLine
    /// Something new, or a path we cannot read. Never guessed into one of the
    /// others: an unknown surface still gets a row, it just cannot promise a
    /// window.
    case unknown

    /// What can be said about raising this surface.
    ///
    /// `commandLine` is deliberately not a promise. The same Homebrew binary runs
    /// in Terminal, Ghostty, tmux and VS Code's integrated terminal, so the
    /// executable proves which program it is and not where it is being typed.
    /// That answer comes from the process ancestry, the same way it already does
    /// for a Claude session in a terminal.
    public var focusIsDecidedByExecutable: Bool {
        switch self {
        case .chatgptApp, .editorExtension: return true
        case .commandLine, .unknown: return false
        }
    }

    public var label: String {
        switch self {
        case .chatgptApp: return "ChatGPT app"
        case .editorExtension: return "VS Code extension"
        case .commandLine: return "command line"
        case .unknown: return "unknown"
        }
    }

    /// Reads the surface off the executable's path.
    ///
    /// Matching is on path segments rather than on substrings anywhere, so a
    /// project folder called `ChatGPT.app` in somebody's home cannot make a
    /// terminal session claim to be the desktop application.
    public static func of(executable path: String) -> CodexSurface {
        let segments = path.split(separator: "/").map(String.init)
        if segments.contains("ChatGPT.app") { return .chatgptApp }
        // The extension lives under a versioned folder whose name starts with the
        // publisher, and the marketplace guarantees the publisher and not the
        // version, so the prefix is what is matched.
        if segments.contains(where: { $0.hasPrefix("openai.chatgpt-") })
            || segments.contains(".vscode") || segments.contains(".cursor") {
            return .editorExtension
        }
        return segments.last == "codex" ? .commandLine : .unknown
    }
}
