import ClawdLightCore
import Foundation
import TestKit

enum StopFailureReasonSuite {

    static let suite = TestSuite("Turn interruption causes", [

        TestCase("Recognizes the documented categories") { t in
            t.expectEqual(StopFailureReason(rawValue: "rate_limit"), .rateLimit)
            t.expectEqual(StopFailureReason(rawValue: "overloaded"), .overloaded)
            t.expectEqual(StopFailureReason(rawValue: "authentication_failed"), .authenticationFailed)
            t.expectEqual(StopFailureReason(rawValue: "billing_error"), .billingError)
            t.expectEqual(StopFailureReason(rawValue: "max_output_tokens"), .maxOutputTokens)
        },

        TestCase("Every category has a short, non-empty label") { t in
            for reason in StopFailureReason.allCases {
                let label = reason.shortLabel
                t.expect(!label.isEmpty, "\(reason.rawValue) has no label")
                t.expect(label.count <= 12, "«\(label)» too long for the row (\(label.count))")
            }
        },

        // A missing field or a new value must not leave the row mute.
        TestCase("An unknown value falls back to a generic label") { t in
            t.expectEqual(StopFailureReason.from(rawValue: "something_new"), .unknown)
            t.expectEqual(StopFailureReason.from(rawValue: nil), .unknown)
            t.expectEqual(StopFailureReason.from(rawValue: ""), .unknown)
            t.expect(!StopFailureReason.unknown.shortLabel.isEmpty, "generic label empty")
        },

        // Here the content exists and is worth reading: it is the only exception.
        TestCase("Truncation by length is not a dead turn") { t in
            t.expect(StopFailureReason.maxOutputTokens.hasUsableOutput, "must have readable output")
            for reason in StopFailureReason.allCases where reason != .maxOutputTokens {
                t.expect(!reason.hasUsableOutput, "\(reason.rawValue) must have no output")
            }
        },
    ])
}

enum CompactDurationSuite {

    static let suite = TestSuite("Compact duration", [

        TestCase("Below a minute it shows seconds") { t in
            t.expectEqual(CompactDuration.label(seconds: 0), "0s")
            t.expectEqual(CompactDuration.label(seconds: 45), "45s")
        },

        TestCase("From minutes up it rounds down") { t in
            t.expectEqual(CompactDuration.label(seconds: 60), "1m")
            t.expectEqual(CompactDuration.label(seconds: 119), "1m")
            t.expectEqual(CompactDuration.label(seconds: 42 * 60), "42m")
        },

        TestCase("From an hour up it shows hours and minutes") { t in
            t.expectEqual(CompactDuration.label(seconds: 3600), "1h")
            t.expectEqual(CompactDuration.label(seconds: 3600 + 25 * 60), "1h25")
            t.expectEqual(CompactDuration.label(seconds: 7 * 3600), "7h")
        },

        TestCase("A negative duration produces no garbage") { t in
            t.expectEqual(CompactDuration.label(seconds: -10), "0s")
        },

        // It has to sit next to the workspace name without squeezing it out.
        TestCase("The label stays short at any duration") { t in
            for seconds in [0, 59, 60, 3599, 3600, 86_400, 999_999] {
                let label = CompactDuration.label(seconds: TimeInterval(seconds))
                t.expect(label.count <= 6, "«\(label)» too long for \(seconds)s")
            }
        },
    ])
}
