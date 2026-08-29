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

        // Only for Accessibility: it is the one macOS keys on the signature in a
        // way that leaves records behind, and the one where the list can show a
        // switch that is on while the running app holds nothing.
        if case .accessibilityMissing = issue {
            message += "\n\n" + PanelIssue.staleEntryCure
        }

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
}
