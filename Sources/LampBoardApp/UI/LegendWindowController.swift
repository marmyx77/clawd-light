import AppKit
import LampBoardCore
import SwiftUI

/// Owns the legend window.
///
/// A window and not a popover: the panel never takes focus, and a popover hung
/// off a non-activating window is a surface you cannot scroll, cannot leave open
/// beside the column, and cannot find again once it has closed itself. This is
/// the same shape as Settings — titled, closable, in ⌘-tab — because it is the
/// same kind of thing: something you open, read, and keep open while you learn
/// the column.
@MainActor
final class LegendWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let store: StateStore
    private let rendering: () -> ColumnRendering

    init(store: StateStore, rendering: @escaping () -> ColumnRendering) {
        self.store = store
        self.rendering = rendering
    }

    func show() {
        if let window {
            bringToFront(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "What the lights mean"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: LegendView(store: store, rendering: rendering)
        )
        window.delegate = self
        window.center()

        self.window = window
        bringToFront(window)
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
