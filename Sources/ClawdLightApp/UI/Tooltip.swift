import AppKit
import SwiftUI

/// The panel's own tooltips, because AppKit's never appear here.
///
/// WHY THIS EXISTS
/// `.help(…)` compiles, reads well, and shows nothing in this app. A tooltip is
/// put on screen by `NSToolTipManager`, which wants the window under the pointer
/// to be key and the application to be active — and this panel is neither by
/// design: it is a `nonactivatingPanel` that becomes key only in the instant of a
/// click, so that clicking a light does not take the focus away from the editor
/// (D5). Every `.help` on a row was therefore dead text, and the row's whole
/// second layer — the exact context figure, the model, the folder under a renamed
/// row, the slot — was written and never displayed.
///
/// So the panel carries its own. One borderless window, reused, that ignores the
/// mouse entirely and never becomes key: it cannot be hovered, cannot be clicked,
/// and cannot take the focus from anything.
@MainActor
enum Tooltip {

    /// How long the pointer has to rest before the text appears.
    ///
    /// Long enough that crossing the column on the way somewhere else stays
    /// silent, short enough that stopping on a row feels answered. AppKit's own
    /// delay is user-configurable and unreadable from here; this is the value the
    /// prototype was played with.
    private static let delay: TimeInterval = 0.45

    /// The tooltip is never wider than this, and wraps instead. A row's text runs
    /// to eight lines when a project holds several sessions.
    private static let maximumWidth: CGFloat = 340

    private static var panel: NSPanel?
    private static var pending: DispatchWorkItem?
    private static var dismissals: Any?

    /// Shows `text` under the pointer once it has rested there.
    ///
    /// Calling it again with different text while one is up replaces it without
    /// waiting: moving between two rows should read as one tooltip following the
    /// pointer, not as a flicker and a new delay.
    static func show(_ text: String) {
        pending?.cancel()

        if panel?.isVisible == true {
            present(text)
            return
        }

        let work = DispatchWorkItem { present(text) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    static func hide() {
        pending?.cancel()
        pending = nil
        panel?.orderOut(nil)
    }

    // MARK: - Internals

    private static func present(_ text: String) {
        let panel = panel ?? makePanel()
        Self.panel = panel

        let size = measure(text)
        let hosting = NSHostingView(rootView: TooltipContent(text: text, width: size.width - padding.width))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        // `orderFrontRegardless` and never `makeKey`: the point of the panel this
        // belongs to is that nothing here ever takes the focus.
        panel.orderFrontRegardless()

        startWatchingForDismissal()
    }

    /// The window's size, measured from the text rather than asked of SwiftUI.
    ///
    /// `NSHostingView.fittingSize` answers before the view has a width to wrap
    /// against, so it lays the text out one word per line and reports a height of
    /// three thousand points — measured, on the first version of this: a tooltip
    /// 358 by 3,332, positioned two thousand points off the top of the screen.
    /// Here the width is decided first and the height follows from it, which is
    /// the order the reader experiences too.
    private static func measure(_ text: String) -> NSSize {
        let font = NSFont.systemFont(ofSize: fontSize)
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: maximumWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        // A point of slack in each direction: SwiftUI's line breaking and
        // AppKit's agree to within a hair, and a hair is enough to clip a
        // descender or drop the last line.
        return NSSize(
            width: min(maximumWidth, ceil(bounds.width) + 1) + padding.width,
            height: ceil(bounds.height) + 1 + padding.height
        )
    }

    private static let fontSize: CGFloat = 11
    /// Nine points left and right, seven above and below.
    private static let padding = NSSize(width: 18, height: 14)

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Above the panel it explains, below the system menus. A tooltip that a
        // context menu opens behind would be a tooltip covering the menu.
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        return panel
    }

    /// Below and to the right of the pointer, kept inside the screen it is on.
    ///
    /// Cocoa's origin is bottom-left, so "below the pointer" is a *smaller* y —
    /// the sign that is wrong in every first version of this function.
    private static func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = mouse.x + 14
        var y = mouse.y - size.height - 12

        if x + size.width > bounds.maxX { x = max(bounds.minX, mouse.x - size.width - 14) }
        // No room underneath — the pointer is near the bottom of the screen —
        // so it goes above instead of being clamped into a strip it does not fit.
        if y < bounds.minY { y = min(bounds.maxY - size.height, mouse.y + 18) }
        return NSPoint(x: x, y: y)
    }

    /// A click or a scroll takes it away.
    ///
    /// Hovering is not the only way a tooltip becomes wrong: a right-click opens
    /// the row's menu over the very row being explained, and `.contextMenu` gives
    /// no notice that it did. A local monitor sees every event this app gets,
    /// which is exactly the set of events that can make the text stale.
    private static func startWatchingForDismissal() {
        guard dismissals == nil else { return }
        dismissals = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { event in
            MainActor.assumeIsolated { hide() }
            return event
        }
    }
}

/// The text, and the surface it sits on.
private struct TooltipContent: View {
    let text: String
    /// The width the text has to wrap at — decided by `Tooltip.measure`, so that
    /// the window and its contents cannot disagree about where the lines break.
    let width: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(TooltipBackground())
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct TooltipBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .toolTip
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension View {
    /// The panel's tooltip. Replaces `.help(…)`, which shows nothing in a window
    /// that is never key — see `Tooltip`.
    func tooltip(_ text: String) -> some View {
        onHover { inside in
            if inside { Tooltip.show(text) } else { Tooltip.hide() }
        }
    }
}
