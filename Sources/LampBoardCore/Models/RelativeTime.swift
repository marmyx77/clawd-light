import Foundation

/// Turns the moment of the last interaction into a short label to sit next to
/// the traffic light.
///
/// The thresholds reason in **calendar days**, not in elapsed hours: at 00:30 on
/// Tuesday an event from 23:50 on Monday is "yesterday", even though only forty
/// minutes have passed. That is how the person looking at it reads it.
public enum RelativeTime {

    /// Label to show in the row: one number and one letter, never wider.
    ///
    /// It used to show a clock time for anything from today, `14:49`, and a date
    /// past a week, `22/07`. Both were replaced for the same reason, and it is not
    /// only width: a clock time has to be **computed** against the current time
    /// before it means anything, while `3h` is read. Reported from use, on a panel
    /// where the name is the field that matters and was losing to a timestamp
    /// nobody was subtracting in their head.
    ///
    /// It also reasons in elapsed time now rather than in calendar days. Saying
    /// "yesterday" for something forty minutes old was right for a person thinking
    /// in days, and wrong in a column where the neighbouring row says `40m` for
    /// the same distance. The calendar wording survives where there is room for
    /// it: `spelled` and `detailedLabel` still say "yesterday, 22:30".
    public static func label(
        for date: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        ShortSpan.label(since: date, now: now)
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

    /// The moment, as a value in a field rather than as a sentence.
    ///
    /// `detailedLabel` says "last activity yesterday at 22:30", which reads well
    /// on its own line and badly next to a label that already says ACTIVITY. This
    /// is the same fact with the sentence taken off.
    public static func spelled(
        for date: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let days = calendarDaysBetween(date, and: now, calendar: calendar)
        switch days {
        case ..<1:
            return time(date, calendar: calendar)
        case 1:
            return "yesterday, \(time(date, calendar: calendar))"
        default:
            return "\(shortDate(date, calendar: calendar)), \(time(date, calendar: calendar))"
        }
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
