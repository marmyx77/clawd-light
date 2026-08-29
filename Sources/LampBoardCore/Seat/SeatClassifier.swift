import Foundation

/// Reads a session's ancestry and says where it lives.
///
/// The chain starts at the `claude` process and goes up. The first ancestor that
/// names a known place decides; what is measured on a real machine, and pinned
/// by the fixtures in `SeatSuite`:
///
///     claude → -zsh → login → Terminal                        a Terminal.app tab
///     claude → zsh → zellij --server …/<session>  (ppid 1)     a zellij pane
///     claude → zsh → tmux: server                             a tmux pane
///     claude → Code Helper (Plugin) → Code                    the Claude panel
///     claude → zsh → Code Helper → Code                       VS Code's integrated terminal
///
/// The two VS Code helpers are told apart by their bundle name, not by the word
/// "Helper": the pty host lives in `Code Helper.app`, the extension host in
/// `Code Helper (Plugin).app`, and both are editor seats.
public enum SeatClassifier {
    public static func classify(_ chain: [ProcessAncestor]) -> Seat {
        guard let first = chain.first else { return .unknown }
        let tty = first.tty

        for ancestor in chain.dropFirst() {
            if let bundle = ancestor.bundleName {
                if let kind = TerminalKind.matching(bundleName: bundle) {
                    guard let tty else { return .application(bundlePath: ancestor.bundlePath ?? ancestor.executablePath) }
                    return .terminal(kind, tty: tty)
                }
                if let ide = editor(bundleName: bundle) { return .editor(ide) }
            }
            switch ancestor.executableName {
            case "tmux", "tmux: server":
                if let tty { return .tmux(serverPid: ancestor.pid, tty: tty) }
            case "zellij":
                if let name = zellijSessionName(in: ancestor.arguments) {
                    return .zellij(serverPid: ancestor.pid, sessionName: name)
                }
            default:
                break
            }
        }

        // Nothing known on the way up. The outermost application, if there is
        // one, can at least be brought to the front.
        if let app = chain.dropFirst().last(where: { $0.bundlePath != nil }), let path = app.bundlePath {
            return .application(bundlePath: path)
        }
        return .unknown
    }

    /// The editor whose bundle this is: VS Code and its helpers, Cursor and its.
    public static func editor(bundleName: String) -> IDEKind? {
        if bundleName == "Visual Studio Code" || bundleName.hasPrefix("Code Helper") { return .visualStudioCode }
        if bundleName == "Cursor" || bundleName.hasPrefix("Cursor Helper") { return .cursor }
        return nil
    }

    /// The session name out of `zellij --server <dir>/<session>`.
    ///
    /// Validated, not just read: the name is what a title match and, later, a
    /// socket lookup are keyed on, and it comes from another process's arguments.
    public static func zellijSessionName(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--server"), index + 1 < arguments.count else { return nil }
        let name = (arguments[index + 1] as NSString).lastPathComponent
        guard name.range(of: "^[A-Za-z0-9._-]{1,128}$", options: .regularExpression) != nil else { return nil }
        return name
    }
}
