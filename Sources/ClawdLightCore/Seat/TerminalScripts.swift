import Foundation

/// The AppleScript that selects a tab by its tty, per terminal.
///
/// The tty is the only value that enters the source, and only after `TTYName`
/// has accepted it: a device path matching `^/dev/ttys[0-9]+$` cannot close a
/// string or start a statement. Titles never come here — they are compared in
/// Swift (D6, the same reason VS Code windows are raised by a name Swift chose).
///
/// Each script raises **exactly** the tab and errors with `-1728` when no tab is
/// on that tty, the code the VS Code path already treats as "the target is not
/// there": the caller then activates nothing rather than the wrong window.
public enum TerminalScripts {
    /// Terminal.app: `Terminal.sdef` exposes `tty` on every tab.
    public static func selectTab(tty raw: String, in kind: TerminalKind) -> String? {
        guard let tty = TTYName.normalized(raw) else { return nil }
        switch kind.raising {
        case .appleScriptTTY where kind == .terminal:
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return "raised"
                        end if
                    end repeat
                end repeat
            end tell
            error "no tab on \(tty)" number -1728
            """
        case .appleScriptTTY where kind == .iTerm:
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select t
                                select s
                                activate
                                return "raised"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            error "no session on \(tty)" number -1728
            """
        default:
            return nil
        }
    }

    /// Ghostty: every terminal's id, title and working directory, for the match
    /// that happens in Swift. `terminal` is an element of the application.
    public static let ghosttyList = """
    tell application "Ghostty"
        set out to {}
        repeat with t in terminals
            set end of out to {id of t, name of t, working directory of t}
        end repeat
        return out
    end tell
    """

    /// Ghostty: focus one terminal by the id the listing gave — validated by
    /// `GhosttyMatcher.isUsable` before it is quoted.
    public static func ghosttyFocus(terminalId: String) -> String? {
        guard GhosttyMatcher.isUsable(id: terminalId) else { return nil }
        return """
        tell application "Ghostty"
            focus (first terminal whose id is "\(AppleScriptString.escaped(terminalId))")
            activate
        end tell
        """
    }

    /// Terminal.app and iTerm2: the tab whose title contains a fragment — the
    /// zellij session name, which zellij writes into the tab's title. The
    /// fallback when the client cannot be paired with its server.
    ///
    /// The fragment is validated against the same pattern a zellij session name
    /// has to match (`SeatClassifier.zellijSessionName`): letters, digits, dot,
    /// underscore, dash. Nothing else enters the source.
    public static func selectTab(titleContaining raw: String, in kind: TerminalKind) -> String? {
        let fragment = raw.trimmed
        guard fragment.range(of: "^[A-Za-z0-9._-]{1,128}$", options: .regularExpression) != nil else { return nil }
        switch kind {
        case .terminal:
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if name of t contains "\(fragment)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return "raised"
                        end if
                    end repeat
                end repeat
            end tell
            error "no tab titled \(fragment)" number -1728
            """
        case .iTerm:
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if name of s contains "\(fragment)" then
                                select t
                                select s
                                activate
                                return "raised"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            error "no session titled \(fragment)" number -1728
            """
        default:
            return nil
        }
    }
}
