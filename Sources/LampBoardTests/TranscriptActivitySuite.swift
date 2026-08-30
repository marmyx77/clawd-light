import LampBoardCore
import Foundation
import TestKit

/// When a conversation last said something, as opposed to when its file moved.
///
/// Reported from use: three projects untouched for days all read as active within
/// the hour. They had not been touched; their transcripts had, by bookkeeping
/// records written around the session rather than by it.
enum TranscriptActivitySuite {

    private static func moment(_ text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }

    static let suite = TestSuite("Transcript activity", [

        TestCase("Bookkeeping appended after the last exchange is not activity") { t in
            // The measured case, reduced. The conversation ended on 26 August; the
            // two lines under it were written days later and carry no timestamp,
            // and they were enough to move the file and with it the row.
            let tail = """
            {"type":"assistant","timestamp":"2026-08-26T14:14:33Z","message":{"role":"assistant"}}
            {"type":"last-prompt","text":"…"}
            {"type":"bridge-session","id":"abc"}
            """
            t.expectEqual(
                TranscriptActivity.lastTimestamp(inTailChunk: tail, isWholeFile: true),
                moment("2026-08-26T14:14:33Z"),
                "the last thing that happened, not the last thing written"
            )
        },

        TestCase("The last timestamp wins, not the first one found") { t in
            let tail = """
            {"type":"user","timestamp":"2026-08-26T09:00:00Z"}
            {"type":"assistant","timestamp":"2026-08-30T11:30:00Z"}
            """
            t.expectEqual(
                TranscriptActivity.lastTimestamp(inTailChunk: tail, isWholeFile: true),
                moment("2026-08-30T11:30:00Z"), "the most recent"
            )
        },

        TestCase("Fractional seconds parse, because transcripts carry both forms") { t in
            let tail = #"{"type":"assistant","timestamp":"2026-08-30T11:30:00.472Z"}"#
            t.expect(
                TranscriptActivity.lastTimestamp(inTailChunk: tail, isWholeFile: true) != nil,
                "milliseconds are not a reason to give up"
            )
        },

        TestCase("A chunk read from the middle drops its first, broken line") { t in
            // Reading the tail of a file lands mid-line. Parsing that fragment
            // would at best fail and at worst find a timestamp inside a truncated
            // string, which is a date nobody wrote.
            let tail = """
            mp":"2026-01-01T00:00:00Z","type":"assistant"}
            {"type":"assistant","timestamp":"2026-08-30T11:30:00Z"}
            """
            t.expectEqual(
                TranscriptActivity.lastTimestamp(inTailChunk: tail),
                moment("2026-08-30T11:30:00Z"), "only the whole lines"
            )
        },

        TestCase("Nothing timestamped in the tail is an honest nothing") { t in
            // Not a guess and not zero: the caller falls back to the file's own
            // date, which is wrong in the way this fixes but is at least a date
            // somebody's filesystem stands behind.
            let tail = """
            {"type":"last-prompt"}
            {"type":"bridge-session"}
            """
            t.expect(
                TranscriptActivity.lastTimestamp(inTailChunk: tail, isWholeFile: true) == nil,
                "no answer rather than an invented one"
            )
        },

        TestCase("Garbage produces no crash and no date") { t in
            t.expect(TranscriptActivity.lastTimestamp(inTailChunk: "", isWholeFile: true) == nil, "empty")
            t.expect(TranscriptActivity.lastTimestamp(inTailChunk: "{{{\nnot json", isWholeFile: true) == nil,
                     "nonsense")
        },

        TestCase("A timestamp that is not a date is not a date") { t in
            let tail = #"{"type":"assistant","timestamp":"yesterday afternoon"}"#
            t.expect(TranscriptActivity.lastTimestamp(inTailChunk: tail, isWholeFile: true) == nil,
                     "unparseable is nil, never today")
        },
    ])
}
