import AppKit

/// The floating panel.
///
/// `nonactivatingPanel` is the choice that makes the widget usable: without it,
/// clicking a traffic light would activate clawd-light and take the focus away
/// from VS Code an instant before giving it back, with a visible flicker on every
/// click.
final class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Above normal windows but below the system menus.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        animationBehavior = .none

        // It must not show up in the window switcher, nor be resizable.
        isExcludedFromWindowsMenu = true
    }

    /// A borderless panel doesn't become key on its own, but it needs to so that
    /// clicks reach the SwiftUI views.
    override var canBecomeKey: Bool { true }

    /// It must never become the main window: the user's work is elsewhere and the
    /// app has no other windows.
    override var canBecomeMain: Bool { false }
}
