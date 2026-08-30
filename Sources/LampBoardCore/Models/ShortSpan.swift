import Foundation

/// How long ago, in the smallest field that can still be read at a glance.
///
/// One number and one letter, and **never more than two digits**. That ceiling is
/// the whole design: this field shares a 240 point line with the name and holds
/// `layoutPriority(1)`, so every point it takes comes off the name on that row
/// alone. A clock time was worse than it looked, because `11:24` is five
/// characters that also have to be *computed* against the current time before
/// they mean anything, while `3h` is read.
///
/// The unit steps up whenever the number would reach three digits, so the label
/// stays the same width for a session that answered a minute ago and one that
/// stopped a year ago. Between one hour and ten it carries a decimal, `1.7h`,
/// because `1h` covers everything from one hour to two and on a session you are
/// deciding whether to interrupt that is the difference that matters.
public enum ShortSpan {

    /// The label for an elapsed number of seconds.
    ///
    /// Seconds survive below a minute because a turn that started ten seconds ago
    /// is the one case where the number moves while you watch it, and `0m` would
    /// hide exactly that.
    public static func label(seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))

        if total < 60 { return "\(total)s" }

        // Minutes run to 99 rather than to 59: `90m` and `1h` are the same fact,
        // and the one with the digits is the one that says how long more precisely.
        let minutes = total / 60
        if minutes < 100 { return "\(minutes)m" }

        // Below ten hours there is room for a decimal, and the decimal is worth
        // having: `1h` covers everything from one hour to two, which on a session
        // you are deciding whether to interrupt is the difference that matters.
        // At ten it stops, because `10.5h` is three digits and the field is two.
        if minutes < 600 {
            let tenths = (minutes * 10 + 30) / 60
            return "\(tenths / 10).\(tenths % 10)h"
        }

        let hours = minutes / 60
        if hours < 48 { return "\(hours)h" }

        let days = hours / 24
        if days < 14 { return "\(days)d" }

        let weeks = days / 7
        if weeks < 52 { return "\(weeks)w" }

        return "\(min(days / 365, 99))y"
    }

    /// The label for a moment in the past.
    ///
    /// A moment in the future is almost always a clock skew of a few seconds, and
    /// reading it as "now" is less confusing than a negative span.
    public static func label(since moment: Date, now: Date) -> String {
        label(seconds: max(0, now.timeIntervalSince(moment)))
    }
}
