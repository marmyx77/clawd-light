import LampBoardCore
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

        TestCase("A live turn is counted in seconds, then in minutes") { t in
            // Seconds survive below a minute because a turn that started ten
            // seconds ago is the one case where the number moves while you are
            // looking at it, and `0m` would hide exactly that.
            t.expectEqual(label(date(29, 16, 9), now: date(29, 16, 10)), "1m")
            t.expectEqual(ShortSpan.label(seconds: 30), "30s")
            t.expectEqual(label(date(29, 14, 49), now: date(29, 16, 10)), "81m")
        },

        TestCase("Minutes run to 99 before the hour takes over") { t in
            // `90m` and `1h` are the same fact, and the one with the digits says
            // it more precisely. The unit steps up only when the number would
            // reach three digits, which is the whole rule.
            t.expectEqual(label(date(29, 14, 31), now: date(29, 16, 10)), "99m")
            t.expectEqual(label(date(29, 14, 30), now: date(29, 16, 10)), "1.7h")
        },

        TestCase("The label never grows past two digits and a letter") { t in
            // The ceiling is the design. This field shares a 240 point line with
            // the name and has layout priority over it, so every character it
            // takes comes off the name on that row alone.
            let cases = [
                (date(29, 16, 10), "0s"), (date(29, 15, 0), "70m"),
                (date(28, 10, 0), "30h"), (date(25, 10, 0), "4d"),
                (date(1, 10, 0), "4w"),
            ]
            for (moment, expected) in cases {
                let text = label(moment, now: date(29, 16, 10))
                t.expectEqual(text, expected, "\(expected)")
                t.expect(text.count <= 4, "“\(text)” fits the field")
            }
        },

        TestCase("Hours give way to days at two days, days to weeks at a fortnight") { t in
            t.expectEqual(label(date(27, 16, 11), now: date(29, 16, 10)), "47h")
            t.expectEqual(label(date(27, 16, 10), now: date(29, 16, 10)), "2d")
            t.expectEqual(label(date(16, 16, 10), now: date(29, 16, 10)), "13d")
            t.expectEqual(label(date(15, 16, 10), now: date(29, 16, 10)), "2w")
        },

        // A clock skew must not produce a negative span.
        TestCase("A moment in the future reads as now") { t in
            t.expectEqual(label(date(29, 16, 11), now: date(29, 16, 10)), "0s")
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
            t.expectEqual(label(moment, now: now), "11h", "the row is three characters")
            t.expectEqual(
                RelativeTime.detailedLabel(for: moment, now: now, calendar: calendar),
                "last activity yesterday at 22:30",
                "and the tooltip is the sentence"
            )
        },
    ])
}
