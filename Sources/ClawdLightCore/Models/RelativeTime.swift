import Foundation

/// Turns the moment of the last interaction into a short label to sit next to
/// the traffic light.
///
/// The thresholds reason in **calendar days**, not in elapsed hours: at 00:30 on
/// Tuesday an event from 23:50 on Monday is "yesterday", even though only forty
/// minutes have passed. That is how the person looking at it reads it.
public enum RelativeTime {

    /// Label to show in the row.
    ///
    /// - today → `14:49`
    /// - yesterday → `1d`
    /// - 2 to 6 days → `2d`
    /// - a week or more → `22/07`
    ///
    /// WHY IT IS THIS TERSE
    /// This field and the project's name share one line of 240 points, and the
    /// timestamp has `layoutPriority(1)`: every point it takes comes off the name,
    /// on that row alone. Measured at 11 points: `yesterday` is 49.83 points and
    /// `1d` is 13.72 — thirty-six points of name, on precisely the rows that had
    /// nothing to say for a day and could least afford to be called `AWorld…nance`.
    ///
    /// The words moved rather than disappearing: `detailedLabel` says "last
    /// activity yesterday at 22:30" in the tooltip. That trade only became
    /// available today — until the panel drew its own tooltips (D32) the sentence
    /// existed and was never once displayed, so the row was the only surface there
    /// was and had to carry the whole word.
    public static func label(
        for date: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        // A timestamp in the future is almost always a clock skew of a few
        // seconds: treating it as "now" is less confusing than "-1d ago".
        guard date <= now else {
            return time(date, calendar: calendar)
        }

        let days = calendarDaysBetween(date, and: now, calendar: calendar)

        switch days {
        case ..<1:
            return time(date, calendar: calendar)
        case 1...6:
            return "\(days)d"
        default:
            return shortDate(date, calendar: calendar)
        }
    }

    /// Extended description for the tooltip, where there is room to be precise.
    public static func detailedLabel(
        for date: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let days = calendarDaysBetween(date, and: now, calendar: calendar)
        guard days >= 1 else {
            return "last activity at \(time(date, calendar: calendar))"
        }
        // The one the row cannot say. `1d` is a count of days; "yesterday" is the
        // day, and it is the word somebody actually thinks in.
        if days == 1 {
            return "last activity yesterday at \(time(date, calendar: calendar))"
        }
        return "last activity \(shortDate(date, calendar: calendar)) at \(time(date, calendar: calendar))"
    }

    // MARK: - Helpers

    /// Calendar days separating the two moments, ignoring the time of day.
    private static func calendarDaysBetween(
        _ earlier: Date,
        and later: Date,
        calendar: Calendar
    ) -> Int {
        let start = calendar.startOfDay(for: earlier)
        let end = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private static func time(_ date: Date, calendar: Calendar) -> String {
        formatter(dateFormat: "HH:mm", calendar: calendar).string(from: date)
    }

    private static func shortDate(_ date: Date, calendar: Calendar) -> String {
        formatter(dateFormat: "dd/MM", calendar: calendar).string(from: date)
    }

    /// `en_US_POSIX` is the locale to use with a fixed `dateFormat`: it is the only
    /// one guaranteed not to reinterpret the pattern according to the user's regional
    /// settings, which is exactly what you don't want when the format is already decided.
    private static func formatter(dateFormat: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
}
