import AppKit
import SwiftUI

/// The grab area of a row's handle, as an AppKit view.
///
/// AppKit and not a SwiftUI gesture, because of one question the window asks
/// before any gesture gets a look at the event: `mouseDownCanMoveWindow`. The
/// panel is movable by its background — that is how you put it where you want
/// it — and for a SwiftUI subtree the answer is yes. So the first drag that began
/// on a SwiftUI handle moved the whole panel ninety-six points down and reordered
/// nothing. A real `NSView` can answer no, take the mouse events itself, and
/// report the vertical travel back to SwiftUI, which does the rest.
struct DragHandle: NSViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeNSView(context: Context) -> HandleView { HandleView() }

    func updateNSView(_ view: HandleView, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
    }

    final class HandleView: NSView {
        var onChanged: ((CGFloat) -> Void)?
        var onEnded: (() -> Void)?
        private var origin: NSPoint?

        override init(frame: NSRect) {
            super.init(frame: frame)
            toolTip = "Drag to reorder"
        }

        required init?(coder: NSCoder) { nil }

        /// The one answer that matters: this drag is ours, not the window's.
        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            origin = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let origin else { return }
            // Screen coordinates grow upward; a row's offset grows downward.
            onChanged?(origin.y - NSEvent.mouseLocation.y)
        }

        override func mouseUp(with event: NSEvent) {
            origin = nil
            onEnded?()
        }
    }
}
