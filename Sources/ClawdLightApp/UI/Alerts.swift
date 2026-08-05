import AppKit

/// The app's dialog windows.
///
/// The app runs as an accessory (no Dock icon), so every alert has to activate
/// the process explicitly: otherwise it appears behind the other windows and the
/// user sees the app freeze without understanding why.
@MainActor
enum Alerts {

    static func info(title: String, message: String) {
        present(title: title, message: message, style: .informational, buttons: ["OK"])
    }

    static func warn(title: String, message: String) {
        present(title: title, message: message, style: .warning, buttons: ["OK"])
    }

    /// - Returns: `true` when the user confirmed.
    @discardableResult
    static func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        present(
            title: title,
            message: message,
            style: .informational,
            buttons: [confirmTitle, "Cancel"]
        ) == .alertFirstButtonReturn
    }

    @discardableResult
    private static func present(
        title: String,
        message: String,
        style: NSAlert.Style,
        buttons: [String]
    ) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        for button in buttons {
            alert.addButton(withTitle: button)
        }
        return alert.runModal()
    }
}
