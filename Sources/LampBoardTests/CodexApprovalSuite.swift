import LampBoardCore
import Foundation
import TestKit

/// Who answers a Codex permission request, and why the row depends on it.
///
/// The fixtures are the shape measured in real rollouts on this machine, cut
/// down to the records that matter and with the paths made anonymous. Both
/// values were seen in the same afternoon, and one session switched from the
/// first to the second halfway through: that is why the reviewer is read for
/// every request rather than once for the session.
enum CodexApprovalSuite {

    private static func context(_ reviewer: String, policy: String = "on-request") -> String {
        """
        {"timestamp":"2026-08-31T12:56:04.546Z","type":"turn_context","payload":\
        {"approval_policy":"\(policy)","approvals_reviewer":"\(reviewer)",\
        "sandbox_policy":{"type":"workspace-write"}}}
        """
    }

    private static let message = """
    {"timestamp":"2026-08-31T12:56:05.000Z","type":"response_item",\
    "payload":{"type":"message","role":"assistant"}}
    """

    static let suite = TestSuite("Codex approval reviewer", [

        TestCase("A reviewer that answers by itself is read as automatic") { t in
            let lines = [context("auto_review"), message]
            t.expectEqual(
                CodexApproval.reviewer(inRollout: lines), .automatic,
                "auto_review is the reviewer nobody has to wait for"
            )
        },

        TestCase("A reviewer that is a person is read as a person") { t in
            t.expectEqual(
                CodexApproval.reviewer(inRollout: [context("user"), message]), .person,
                "user means the turn really is blocked"
            )
        },

        TestCase("The last context wins, because it changes mid-session") { t in
            // Measured during an audit: `user` at the start, `auto_review` from
            // the record where the setting changed. Reading the first one would
            // describe a session that no longer exists.
            let lines = [context("user"), message, context("auto_review"), message]
            t.expectEqual(
                CodexApproval.reviewer(inRollout: lines), .automatic,
                "the reviewer in force is the most recent one"
            )
        },

        TestCase("A rollout that does not say gives no answer, rather than a guess") { t in
            t.expectNil(
                CodexApproval.reviewer(inRollout: [message]),
                "no turn_context means the rollout did not say"
            )
        },

        TestCase("An unknown reviewer is not forced into one of the two we know") { t in
            // The format is undocumented and Codex calls it unstable. A third
            // value must read as "cannot tell", which shows the request, and not
            // as the one that hides it.
            t.expectNil(
                CodexApproval.reviewer(inRollout: [context("something_new")]),
                "a value we have never seen is not an answer"
            )
        },

        TestCase("A truncated first line is skipped, not fatal") { t in
            // The reader takes the tail of the file, so the first line is
            // routinely half a record.
            let lines = ["ontext\":{\"approvals_reviewer\":\"user\"}}", context("auto_review")]
            t.expectEqual(
                CodexApproval.reviewer(inRollout: lines), .automatic,
                "what does not decode is skipped, and the readable record answers"
            )
        },

        TestCase("A record that is not a turn_context is not read as one") { t in
            let impostor = """
            {"type":"response_item","payload":{"approvals_reviewer":"auto_review"}}
            """
            t.expectNil(
                CodexApproval.reviewer(inRollout: [impostor]),
                "the field only means this inside a turn_context"
            )
        },
    ])
}
