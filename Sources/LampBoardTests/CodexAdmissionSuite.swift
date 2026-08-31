import LampBoardCore
import Foundation
import TestKit

/// The rule that says an unanswered probe is not an ended session.
///
/// It lived as one line inside the store, where nothing could reach it: making a
/// test produce an unavailable probe would have meant making `lsof` genuinely
/// hang on a mount that does not answer. Deleting the line left the suite green,
/// which is the definition of a permanent false negative.
enum CodexAdmissionSuite {

    private static let moment = Date(timeIntervalSince1970: 1_788_000_000)

    private static func evidence(_ id: String, cwd: String = "/dev/project") -> CodexEvidence {
        CodexEvidence(
            meta: CodexSessionMeta(sessionId: id, cwd: cwd),
            rolloutPath: "/dev/\(id).jsonl", pid: 1, executable: "/usr/local/bin/codex",
            surface: .commandLine, lastActivity: moment
        )
    }

    static let suite = TestSuite("Codex admission", [

        TestCase("A probe that could not answer changes nothing at all") { t in
            // Not "nothing is running": "we did not get to look". The caller has
            // to add no rows, remove no rows, and leave the confirmed set alone —
            // and `nil` is the only answer that cannot be mistaken for an empty
            // one by a caller in a hurry.
            t.expectNil(
                CodexAdmission.verdict(on: .unavailable("lsof timed out"), holding: ["a", "b"]),
                "an unavailable probe yields no verdict"
            )
            t.expectNil(
                CodexAdmission.verdict(on: .unavailable("no lsof here"), holding: []),
                "and it says the same when nothing was held either"
            )
        },

        TestCase("A probe that answered and saw nothing is an ending") { t in
            // The opposite case, and the one Codex gives for free: closing the
            // conversation closes the descriptor. The probe ran, so an empty
            // answer is evidence and the rows go.
            guard let verdict = CodexAdmission.verdict(on: .observed([]), holding: ["a"]) else {
                t.expect(false, "an observation always yields a verdict, even an empty one")
                return
            }
            t.expect(verdict.arriving.isEmpty, "nothing arrives")
            t.expect(verdict.alive.isEmpty, "and nothing survives, which is what prunes the row")
        },

        TestCase("Only what the panel does not know already is arriving") { t in
            // Adoption never overwrites a row that exists — what the hooks know
            // about a session is more precise than what a file can say — so the
            // rows already held are separated here rather than at the call site.
            guard let verdict = CodexAdmission.verdict(
                on: .observed([evidence("a"), evidence("b"), evidence("c")]), holding: ["b"]
            ) else {
                t.expect(false, "no verdict")
                return
            }
            t.expectEqual(verdict.arriving.map(\.meta.sessionId).sorted(), ["a", "c"], "the new ones")
            t.expectEqual(verdict.alive, ["a", "b", "c"], "while all three keep their place")
        },
    ])
}
