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

    /// What `SessionState.entrypoint` carries for a Codex session, so the click
    /// can find its way back here. Prefixed, because that field already holds
    /// `claude-vscode` for the other harness and the two vocabularies must not be
    /// able to collide.
    public var entrypoint: String { "codex-\(rawValue)" }

    /// The surface an entrypoint names, or `nil` when it is not a Codex one.
    public static func named(entrypoint: String?) -> CodexSurface? {
        guard let entrypoint, entrypoint.hasPrefix("codex-") else { return nil }
        return CodexSurface(rawValue: String(entrypoint.dropFirst("codex-".count))) ?? .unknown
    }

    /// The application to raise, where raising one is the right answer.
    ///
    /// Only for the surfaces that **are** an application. A `codex` from Homebrew
    /// running in a terminal is not raised by opening a bundle: the window is the
    /// terminal's, and finding it is the seat's business.
    public var bundleIdentifier: String? {
        switch self {
        case .chatgptApp: return "com.openai.codex"
        case .editorExtension, .commandLine, .unknown: return nil
        }
    }

    /// Reads the surface off the executable's path.
    ///
    /// Matched on the **bundle's own shape**, not on a name appearing somewhere in
    /// the path. `ChatGPT.app` alone is a folder anybody can make, and a project
    /// called that in somebody's home would have made every terminal session in it
    /// claim to be the desktop application. `ChatGPT.app/Contents` is a bundle.
    ///
    /// The first version matched the bare segment, and a test written to prove it
    /// was safe is what showed it was not.
    public static func of(executable path: String) -> CodexSurface {
        let segments = path.split(separator: "/").map(String.init)
        if let app = segments.firstIndex(of: "ChatGPT.app"),
           segments.indices.contains(app + 1), segments[app + 1] == "Contents" {
            return .chatgptApp
        }
        // The extension lives under a versioned folder whose name starts with the
        // publisher, and the marketplace guarantees the publisher and not the
        // version, so the prefix is what is matched. Measured on this machine:
        // `~/.vscode/extensions/openai.chatgpt-26.825.51511-darwin-arm64/bin/…`.
        if segments.contains(where: { $0.hasPrefix("openai.chatgpt-") }) {
            return .editorExtension
        }
        // The editor's own directory is weaker evidence and used to be taken on
        // its own, which was too generous: a bare `.vscode` or `.cursor`
        // *anywhere* in the path counts every project's own `.vscode` folder,
        // and a `codex` a person keeps in one would have claimed to run inside
        // an editor. The structure is what the editor actually guarantees, so
        // the two segments have to be adjacent and in that order.
        if let editor = segments.firstIndex(where: { $0 == ".vscode" || $0 == ".cursor" }),
           segments.indices.contains(editor + 1), segments[editor + 1] == "extensions" {
            return .editorExtension
        }
        return segments.last == "codex" ? .commandLine : .unknown
    }
}
