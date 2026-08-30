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

        TestCase("Garbage produces nothing and no crash") { t in
            t.expect(CodexSessionMetaReader.read(head: "") == nil, "empty")
            t.expect(CodexSessionMetaReader.read(head: "{{{ not json") == nil, "nonsense")
            t.expect(CodexSessionMetaReader.read(head: #"{"type":"session_meta"}"#) == nil, "no payload")
        },
    ])
}
