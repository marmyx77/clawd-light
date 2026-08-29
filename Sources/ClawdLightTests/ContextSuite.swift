import ClawdLightCore
import Foundation
import TestKit

/// Reading how full a session's context is, out of its transcript.
///
/// Every case here is a shape found in a real file. The naive version of this
/// reader — "take the last record with a usage block, divide by a million" —
/// fails four of them, and two of the failures print a confident number that is
/// wrong by more than an order of magnitude.
enum ContextSuite {

    private static func reply(
        model: String = "claude-opus-5", input: Int = 2, creation: Int = 2_277,
        read: Int = 358_899, timestamp: String = "2026-08-29T08:08:07.456Z"
    ) -> String {
        """
        {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"\(model)",\
        "usage":{"input_tokens":\(input),"cache_creation_input_tokens":\(creation),\
        "cache_read_input_tokens":\(read),"output_tokens":1457}}}
        """
    }

    private static let refusal = """
        {"type":"assistant","message":{"model":"<synthetic>","usage":\
        {"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},\
        "content":[{"type":"text","text":"Prompt is too long"}]}}
        """

    private static let prompt = #"{"type":"user","message":{"role":"user","content":"go on"}}"#
    private static let compaction = #"{"type":"system","subtype":"compact_boundary","compactMetadata":{"preTokens":999298}}"#

    static let suite = TestSuite("Context saturation", [

        TestCase("The three input fields are the context, and they are summed") { t in
            // Verified against Claude Code's own status line, which reports this
            // same sum as total_input_tokens. Deriving it would have been a guess
            // that nobody could check from outside.
            let reading = ContextScanner.read(tail: reply())
            t.expectEqual(reading?.tokens, 361_178, "2 + 2,277 + 358,899")
            t.expectEqual(reading?.model, "claude-opus-5", "model")
            t.expectEqual(reading?.window, 1_000_000, "window")
            t.expectEqual(reading?.percent, 36, "percent")
            t.expectEqual(reading?.label, "36%", "label")
        },

        TestCase("A refusal does not become a reading of zero") { t in
            // The expensive one. `<synthetic>` records carry an all-zero usage,
            // and one of them literally says "Prompt is too long" — so the naive
            // reader prints 0% at the moment the session is full.
            let reading = ContextScanner.read(tail: reply() + "\n" + refusal)
            t.expectEqual(reading?.tokens, 361_178, "the real reply was found behind it")
            t.expectEqual(reading?.confidence, .unknown, "and the refusal makes it untrustworthy")
            t.expectNil(reading?.percent, "so no number is offered")
            t.expectEqual(reading?.label, "—", "the dash, never a blank")
        },

        TestCase("Anything loaded after the reply makes it a floor") { t in
            let reading = ContextScanner.read(tail: reply() + "\n" + prompt)
            t.expectEqual(reading?.confidence, .floor, "something arrived after")
            t.expectEqual(reading?.label, "≥36%", "and the ≥ says so")
        },

        TestCase("A compaction makes the number describe a session that is gone") { t in
            let reading = ContextScanner.read(tail: reply() + "\n" + compaction)
            t.expectEqual(reading?.confidence, .unknown, "the context was rewritten")
            t.expectNil(reading?.percent, "no figure")
        },

        TestCase("Zero at the top level falls back to the last iteration") { t in
            let line = """
                {"type":"assistant","message":{"model":"claude-opus-5","usage":\
                {"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,\
                "iterations":[{"input_tokens":1,"cache_read_input_tokens":400},\
                {"input_tokens":3,"cache_creation_input_tokens":796,"cache_read_input_tokens":851000}]}}}
                """
            t.expectEqual(ContextScanner.read(tail: line)?.tokens, 851_799, "the last iteration")
        },

        TestCase("The model is taken from the record the tokens came from") { t in
            // A session switches models mid-flight — twenty-eight times in one
            // real transcript — so the newest reply's model is the only one that
            // describes these tokens. Here the older record is on a 200k model
            // and must not be used to divide the newer one.
            let older = reply(model: "claude-sonnet-4-5", read: 100_000)
            let newer = reply(model: "claude-opus-5", read: 358_899)
            let reading = ContextScanner.read(tail: older + "\n" + newer)
            t.expectEqual(reading?.model, "claude-opus-5", "the newest by position")
            t.expectEqual(reading?.window, 1_000_000, "and its window")
        },

        TestCase("A dated model id still finds its window") { t in
            t.expectEqual(ContextWindows.window(for: "claude-sonnet-4-5-20250929"), 200_000, "dated")
            t.expectEqual(ContextWindows.window(for: "claude-sonnet-4-5"), 200_000, "plain")
            t.expectEqual(ContextWindows.window(for: "claude-haiku-4-5-20251001"), 200_000, "dated haiku")
        },

        TestCase("Only an eight-digit tail is a date") { t in
            // `claude-3-5-haiku` ends in digits that are part of its name. A
            // looser rule would strip them and lose the model.
            t.expectEqual(ContextWindows.window(for: "claude-3-5-haiku"), 200_000, "kept whole")
            t.expectEqual(ContextWindows.stripped("claude-3-5-haiku"), "claude-3-5-haiku", "unchanged")
        },

        TestCase("An unknown model gets no percentage rather than a guess") { t in
            let reading = ContextScanner.read(tail: reply(model: "claude-something-next"))
            t.expectNotNil(reading, "the tokens are still read")
            t.expectNil(reading?.window, "but no denominator")
            t.expectNil(reading?.percent, "so no percentage")
            t.expectEqual(reading?.label, "—", "the dash")
            t.expect(reading?.explanation.contains("no window recorded") == true, "and the tooltip says why")
        },

        TestCase("A tail with nothing usable in it reads as nothing") { t in
            t.expectNil(ContextScanner.read(tail: ""), "empty")
            t.expectNil(ContextScanner.read(tail: prompt + "\n" + refusal), "no reply in it")
            t.expectNil(ContextScanner.read(tail: "{ half a record"), "a truncated first line")
        },

        TestCase("A partial first line is skipped, not fatal") { t in
            // The caller reads from an arbitrary offset near the end of the file,
            // so the first line is almost always cut in half.
            let reading = ContextScanner.read(tail: "read_input_tokens\":9}}}\n" + reply())
            t.expectEqual(reading?.tokens, 361_178, "the whole record behind it")
        },

        TestCase("The sentence for the tooltip carries the whole truth") { t in
            let reading = ContextScanner.read(tail: reply() + "\n" + prompt)
            let text = reading?.explanation ?? ""
            t.expect(text.contains("≥36%"), "the figure")
            t.expect(text.contains("at least"), "that it is a floor")
            // Formatted for whoever is reading it: this Mac groups thousands
            // with dots, another with commas. The test asks the same question
            // the code answers, instead of hardcoding one country's answer.
            t.expect(text.contains((1_000_000).formatted()), "the window")
            t.expect(text.contains("claude-opus-5"), "the model")
        },
    ])
}
