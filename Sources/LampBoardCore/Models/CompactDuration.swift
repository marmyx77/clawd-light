import Foundation

/// A duration in the most compact form possible, for the row's right-hand slot.
///
/// Meant for the live states, where "how long" matters more than "since when": on
/// a session that is working, `7h` says in half a second something that `08:14`
/// forces you to compute.
public enum CompactDuration {

    /// - Returns: `45s`, `42m`, `1h25`, `7h`. Never more than six characters.
    public static func label(seconds: TimeInterval) -> String {
        ShortSpan.label(seconds: seconds)
    }

}
