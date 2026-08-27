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
}
