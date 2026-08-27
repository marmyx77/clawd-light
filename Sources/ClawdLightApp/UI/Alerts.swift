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

    /// A one-line question. Returns the text, trimmed, or `nil` on cancel.
    static func ask(
        title: String, message: String, initialValue: String, placeholder: String, confirmTitle: String
    ) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = initialValue
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
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
