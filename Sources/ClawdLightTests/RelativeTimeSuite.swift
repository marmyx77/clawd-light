import ClawdLightCore
import Foundation
import TestKit

enum RelativeTimeSuite {

    /// Fixed calendar: the tests must not depend on the machine's time zone.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 7, day: day, hour: hour, minute: minute
        )) ?? Date(timeIntervalSince1970: 0)
    }

    private static func label(_ moment: Date, now: Date) -> String {
        RelativeTime.label(for: moment, now: now, calendar: calendar)
    }

    static let suite = TestSuite("Last interaction label", [

        TestCase("Today shows the time") { t in
            t.expectEqual(label(date(29, 14, 49), now: date(29, 16, 10)), "14:49")
        },

        TestCase("The time is two digits") { t in
            t.expectEqual(label(date(29, 9, 5), now: date(29, 16, 0)), "09:05")
        },

        TestCase("A few seconds ago still shows the time") { t in
            t.expectEqual(label(date(29, 16, 10), now: date(29, 16, 10)), "16:10")
        },

        // The row says "1d" and not "yesterday" for eighteen points of width: the
        // word cost 49.83 points against 13.72, on the column's narrowest field,
        // and the tooltip below says the whole thing in words.
        TestCase("The previous day is a day, counted") { t in
            t.expectEqual(label(date(28, 22, 30), now: date(29, 10, 0)), "1d")
        },

        // The case an hours-based difference would get wrong: forty minutes pass
        // between the two moments, but the day has changed.
        TestCase("“Yesterday” follows the calendar, not the elapsed hours") { t in
            t.expectEqual(label(date(28, 23, 50), now: date(29, 0, 30)), "1d")
        },

        // And the mirror image: almost 24 hours, but it's still today.
        TestCase("Twenty-three hours within the same day stay a time") { t in
            t.expectEqual(label(date(29, 0, 10), now: date(29, 23, 50)), "00:10")
        },

        TestCase("From two to six days it counts days") { t in
            t.expectEqual(label(date(27, 12, 0), now: date(29, 10, 0)), "2d")
            t.expectEqual(label(date(23, 12, 0), now: date(29, 10, 0)), "6d")
        },

        TestCase("From a week onwards it shows the date") { t in
            t.expectEqual(label(date(22, 12, 0), now: date(29, 10, 0)), "22/07")
            t.expectEqual(label(date(1, 8, 30), now: date(29, 10, 0)), "01/07")
        },

        // A clock skew must not produce "-1d ago".
        TestCase("A moment in the future shows the time") { t in
            t.expectEqual(label(date(29, 16, 11), now: date(29, 16, 10)), "16:11")
        },

        TestCase("Today's tooltip quotes the time") { t in
            t.expectEqual(
                RelativeTime.detailedLabel(
                    for: date(29, 14, 49), now: date(29, 16, 0), calendar: calendar
                ),
                "last activity at 14:49"
            )
        },

        TestCase("The tooltip for past days quotes date and time") { t in
            t.expectEqual(
                RelativeTime.detailedLabel(
                    for: date(27, 9, 5), now: date(29, 16, 0), calendar: calendar
                ),
                "last activity 27/07 at 09:05"
            )
        },

        // The pair is the point: the row abbreviates only because the tooltip
        // spells it out. Before the panel drew its own tooltips (D32) this
        // sentence was written and never displayed, and the row had to carry the
        // whole word on its own.
        TestCase("What the row abbreviates, the tooltip says in words") { t in
            let moment = date(28, 22, 30), now = date(29, 10, 0)
            t.expectEqual(label(moment, now: now), "1d", "the row is two characters")
            t.expectEqual(
                RelativeTime.detailedLabel(for: moment, now: now, calendar: calendar),
                "last activity yesterday at 22:30",
                "and the tooltip is the sentence"
            )
        },
    ])
}
