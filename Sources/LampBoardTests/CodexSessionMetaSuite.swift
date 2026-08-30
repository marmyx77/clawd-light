import LampBoardCore
import TestKit

/// Where a Codex session found by the scanner takes its folder from.
///
/// This is the replacement for a security property, not a convenience. The old
/// gate bounded `/signal` by requiring a Claude Code window lock to claim the
/// folder, which a machine running only Codex does not have. Reading the folder
/// out of a file that a live process holds open keeps the bound: the row exists
/// because the file does, and nothing anybody sends decides where it points.
enum CodexSessionMetaSuite {

    private static let real = """
    {"timestamp":"2026-08-30T10:25:28.715Z","type":"session_meta","payload":{"session_id":"01a05233-e911-7f40-85cf-3d6507301744","cwd":"/Users/dev/Development/kindle-transcription","originator":"Codex Desktop","source":"vscode","cli_version":"0.151.0"}}
    {"timestamp":"2026-08-30T10:25:31.000Z","type":"event_msg","payload":{"type":"task_started"}}
    """

    static let suite = TestSuite("Codex session meta", [

        TestCase("The folder comes out of the file, with the session it belongs to") { t in
            let meta = CodexSessionMetaReader.read(head: real)
            t.expectEqual(meta?.cwd, "/Users/dev/Development/kindle-transcription", "the folder")
            t.expectEqual(meta?.sessionId, "01a05233-e911-7f40-85cf-3d6507301744", "the session")
        },

        TestCase("The surface fields come through as written, never matched") { t in
            let meta = CodexSessionMetaReader.read(head: real)
            t.expectEqual(meta?.originator, "Codex Desktop", "kept as text")
            t.expectEqual(meta?.source, "vscode", "and so is this")
            t.expectEqual(meta?.cliVersion, "0.151.0", "with the version that wrote it")
        },

        TestCase("`id` is accepted where `session_id` is missing") { t in
            let head = #"{"type":"session_meta","payload":{"id":"abc","cwd":"/dev/p"}}"#
            t.expectEqual(CodexSessionMetaReader.read(head: head)?.sessionId, "abc", "the other name")
        },

        TestCase("A first record that is not session_meta is refused") { t in
            // The format is declared unstable by the people who write it, so the
            // shape being wrong is a thing that will happen. The right answer is a
            // row that never appears, not one that is quietly wrong.
            let head = #"{"type":"event_msg","payload":{"type":"task_started","cwd":"/dev/p"}}"#
            t.expect(CodexSessionMetaReader.read(head: head) == nil, "wrong record, no session")
        },

        TestCase("A relative folder is refused rather than resolved") { t in
            // Resolving it would mean choosing a base directory, and the only one
            // available is ours. A row pointing at LampBoard's own working
            // directory because a rollout said `.` is the failure this prevents.
            let head = #"{"type":"session_meta","payload":{"session_id":"a","cwd":"project"}}"#
            t.expect(CodexSessionMetaReader.read(head: head) == nil, "not absolute, not accepted")
        },

        TestCase("An empty session id is not an id") { t in
            let head = #"{"type":"session_meta","payload":{"session_id":"","cwd":"/dev/p"}}"#
            t.expect(CodexSessionMetaReader.read(head: head) == nil, "nothing to key a row on")
        },

        TestCase("The folder is normalised, so two spellings are one row") { t in
            let head = #"{"type":"session_meta","payload":{"session_id":"a","cwd":"/dev//p/"}}"#
            t.expectEqual(CodexSessionMetaReader.read(head: head)?.cwd, "/dev/p", "one spelling")
        },

        TestCase("A subagent's rollout carries its parent's name, and says so") { t in
            // Measured on this machine, 30 August: of 26 rollouts, 3 had a
            // `source` that is an object rather than a surface, and a
            // `session_id` naming a **different** conversation. Two of the three
            // named the same parent.
            //
            // Read the old way — `session_id` first, `source` only when it is a
            // string — each of these became a second evidence for a session that
            // already had one. Arriving first it took the parent's row: its
            // transcript, and with it the folder's clock and the context ring.
            let head = #"{"type":"session_meta","payload":{"session_id":"01a051df-parent","id":"01a052f0-child","cwd":"/dev/p","originator":"Codex Desktop","source":{"subagent":{"other":"guardian"}}}}"#
            guard let meta = CodexSessionMetaReader.read(head: head) else {
                t.expect(false, "the record did not parse")
                return
            }
            t.expectEqual(meta.sessionId, "01a051df-parent", "the conversation it belongs to")
            t.expectEqual(meta.rolloutId, "01a052f0-child", "and the file's own name for itself")
            t.expectEqual(meta.subagent, "guardian", "who was doing the work")
            t.expect(meta.isSubagent, "so it is not a row of its own")
            t.expectNil(meta.source, "and an object is not a surface")
        },

        TestCase("Ids that disagree are enough, whatever the source becomes") { t in
            // The safety net, for a format its own authors call unstable. Two
            // signs, either sufficient: the marker under `source`, and the ids
            // simply not matching. A rollout whose `id` is not its `session_id`
            // is not that session's rollout, whatever else the file grows.
            let head = #"{"type":"session_meta","payload":{"session_id":"parent","id":"other","cwd":"/dev/p","source":"vscode"}}"#
            t.expect(CodexSessionMetaReader.read(head: head)?.isSubagent == true,
                     "the disagreement is the signal")

            // And a marker with no name is still a marker: an unnamed subagent
            // is a subagent, not a conversation.
            let unnamed = #"{"type":"session_meta","payload":{"session_id":"p","id":"p","cwd":"/dev/p","source":{"subagent":{}}}}"#
            t.expect(CodexSessionMetaReader.read(head: unnamed)?.isSubagent == true, "still one")
        },

        TestCase("The command line writes only an id, and that is a whole session") { t in
            // The other shape on this machine, 4 of the 26: `session_id` is
            // null and `id` carries the only name there is. Each field falls
            // back to the other, so this is an ordinary row and not a subagent.
            let head = #"{"type":"session_meta","payload":{"session_id":null,"id":"01a04f67-cli","cwd":"/dev/p","originator":"codex_cli_rs"}}"#
            guard let meta = CodexSessionMetaReader.read(head: head) else {
                t.expect(false, "the record did not parse")
                return
            }
            t.expectEqual(meta.sessionId, "01a04f67-cli", "the name it has")
            t.expectEqual(meta.rolloutId, "01a04f67-cli", "which is also the file's")
            t.expect(!meta.isSubagent, "and nothing about it says subagent")
        },

        TestCase("Garbage produces nothing and no crash") { t in
            t.expect(CodexSessionMetaReader.read(head: "") == nil, "empty")
            t.expect(CodexSessionMetaReader.read(head: "{{{ not json") == nil, "nonsense")
            t.expect(CodexSessionMetaReader.read(head: #"{"type":"session_meta"}"#) == nil, "no payload")
        },
    ])
}
