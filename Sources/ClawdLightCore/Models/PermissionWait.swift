import Foundation

/// What to do on each tick while a click waits for a permission.
///
/// Separated from the timer that drives it so the decision can be tested without
/// a run loop, and because the interesting case is not the waiting — it is the
/// tie. When the permission arrives on the same tick the wait expires, the two
/// rules disagree: one says finish, the other says give up. Finishing has to win.
/// Somebody who granted the permission at the last second granted it, and the
/// click they are owed is not less owed for being late.
public enum PermissionWait {

    public enum Step: Equatable, Sendable {
        /// Nothing yet: keep the click, keep watching.
        case keepWaiting
        /// The permission arrived: run the click that was interrupted.
        case finish
        /// Long enough. Forget the click; the user will make it again if they
        /// still want it, and by then the answer will be immediate.
        case giveUp
    }

    public static func step(granted: Bool, now: Date, deadline: Date) -> Step {
        if granted { return .finish }
        return now >= deadline ? .giveUp : .keepWaiting
    }
}
