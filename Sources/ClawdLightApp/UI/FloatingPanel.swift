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

    /// Delivers the first click.
    ///
    /// AppKit spends a mouse-down in a window that is not key on making it key,
    /// and hands the event to the view only if the view under the pointer says
    /// `acceptsFirstMouse`. That view is not ours to answer for: the rows sit
    /// inside SwiftUI's own scroll view, which says no — overriding the answer on
    /// the hosting view changed nothing, because nobody asked the hosting view.
    ///
    /// Every return from the editor leaves the panel non-key, so without this the
    /// first click of every visit only knocked, and the user learned to click
    /// twice — with the second click landing on whatever row had moved into the
    /// place of the one the first had just cleared. So the panel makes itself key
    /// *before* handing the event on: by then it is a click in a key window, and
    /// it is delivered like any other. The app is still not activated — the
    /// editor keeps its focus, which is the whole point of the panel.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseUp:
            // The second click of a double-click is dropped, both halves of it,
            // so the tap gesture never sees a mouse-up without its mouse-down.
            // Nothing in the panel is bound to a double-click, and the row under
            // the pointer is often no longer the row the first click hit: the
            // first click marks a green as seen, the column reorders under the
            // pointer, and a fast second click used to open whatever had moved
            // into that place.
            if event.clickCount > 1 {
                if event.type == .leftMouseDown { Diagnostics.log("second click of a double-click dropped") }
                return
            }
            if event.type == .leftMouseDown, !isKeyWindow { makeKey() }
        case .rightMouseDown, .otherMouseDown:
            if !isKeyWindow { makeKey() }
        default:
            break
        }
        super.sendEvent(event)
    }

    // Key status is what decides whether a click is delivered or merely used.
    // Logging the transitions is what lets the per-signal log say, of a click,
    // "the panel was not key and the row still opened" — the one sentence that
    // proves the click-through works.
    override func becomeKey() {
        super.becomeKey()
        Diagnostics.log("panel became key")
    }

    override func resignKey() {
        super.resignKey()
        Diagnostics.log("panel resigned key")
    }
}
