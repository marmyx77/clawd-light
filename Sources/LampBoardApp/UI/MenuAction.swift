import AppKit

/// An `NSMenuItem` target that runs a closure.
///
/// `target`/`action` is Objective-C dispatch, so the target has to be a real
/// `NSObject` that answers to the selector. A Swift class with an `@objc` method
/// compiles and then silently does nothing when the entry is chosen, and a menu
/// entry that does nothing is indistinguishable from one that did its job. This
/// is four lines to make that impossible.
///
/// `NSMenuItem` holds its target **weakly**, so whoever builds the menu keeps
/// these alive for as long as the menu can be used.
final class MenuAction: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }

    @objc func fire() { run() }
}
