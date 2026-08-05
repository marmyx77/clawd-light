import Foundation

/// A duration in the most compact form possible, for the row's right-hand slot.
///
/// Meant for the live states, where "how long" matters more than "since when": on
/// a session that is working, `7h` says in half a second something that `08:14`
/// forces you to compute.
public enum CompactDuration {

    /// - Returns: `45s`, `42m`, `1h25`, `7h`. Never more than six characters.
    public static func label(seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))

        if total < 60 {
            return "\(total)s"
        }

        let minutes = total / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainder = minutes % 60

        // Past a day the minutes add nothing and would push the label beyond the
        // space available.
        if hours >= 24 || remainder == 0 {
            return "\(hours)h"
        }
        return "\(hours)h\(remainder < 10 ? "0" : "")\(remainder)"
    }
}
