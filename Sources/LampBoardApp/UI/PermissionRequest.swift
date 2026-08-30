import AppKit
import LampBoardCore

/// Asking for a permission, in the order that gets a yes.
///
/// A System Settings window that opens by itself, with no sentence attached, is
/// a demand. The same window, after a paragraph saying what the permission is
/// used for and what refusing costs, is a request — and the difference is not
/// politeness: somebody who is told they may refuse, and what it costs, has the
/// information needed to agree. Somebody who is only shown a switch assumes the
/// cost is being hidden from them.
enum PermissionRequest {

    /// Explains the permission and, if the person agrees, sends them where it
    /// is granted. Returns `true` when they chose to go.
    @discardableResult
    @MainActor
    static func offer(_ issue: PanelIssue) -> Bool {
        var message = issue.explanation + "\n\n" + issue.reassurance

        // The Terminal recipe is for one situation only: somebody who has already
        // been here, turned the switch on, and found it made no difference. Shown
        // to everybody it is three lines of shell in a dialog whose first reader
        // has done nothing wrong yet, and it turns a four-step instruction into a
        // wall nobody finishes.
        //
        // So it appears from the second time onward. Anybody seeing this window
        // twice for the same permission has followed the steps and is still stuck,
        // which is exactly the case the recipe describes.
        if case .accessibilityMissing = issue, hasOfferedBefore(issue) {
            message += "\n\n" + PanelIssue.staleEntryCure
        }
        remember(issue)

        guard Alerts.confirm(
            title: issue.summary,
            message: message,
            confirmTitle: "Open System Settings"
        ) else { return false }

        // The system prompt first. When nothing has been decided yet, this single
        // dialog grants it without going through Settings at all — and when
        // something has been decided, it costs nothing and the pane opens anyway.
        if case .accessibilityMissing = issue {
            VSCodeFocuser.requestAccessibilityPermission()
        }

        if let url = issue.settingsURL { NSWorkspace.shared.open(url) }
        return true
    }

    /// Whether this exact permission has been explained before.
    ///
    /// Across launches, not only within one: the person who turns a switch on and
    /// finds nothing changed usually restarts the app before coming back, and a
    /// counter that forgot at quit would show them the short version forever.
    private static func hasOfferedBefore(_ issue: PanelIssue) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: issue))
    }

    private static func remember(_ issue: PanelIssue) {
        UserDefaults.standard.set(true, forKey: key(for: issue))
    }

    /// One key per kind, and Automation gets one per target application: being
    /// stuck on VS Code says nothing about Ghostty.
    private static func key(for issue: PanelIssue) -> String {
        switch issue {
        case .accessibilityMissing: return "permission.offered.accessibility"
        case .automationMissing(let app): return "permission.offered.automation.\(app)"
        }
    }
}
