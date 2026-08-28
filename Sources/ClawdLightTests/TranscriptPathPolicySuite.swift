import ClawdLightCore
import Foundation
import TestKit

/// Which transcript paths the app will open.
///
/// `POST /signal` carries no token, and the path it names was later read and
/// rendered. Measured on the running app before this rule existed: a forged
/// signal naming `/etc/passwd` produced a row holding that path within a second.
enum TranscriptPathPolicySuite {
    private static let root = URL(fileURLWithPath: "/Users/dev/.claude", isDirectory: true)

    static let suite = TestSuite("Transcript path policy", [

        TestCase("A real transcript is accepted") { t in
            t.expectEqual(
                TranscriptPathPolicy.accepted(
                    "/Users/dev/.claude/projects/-Users-dev-app/abc.jsonl", under: root),
                "/Users/dev/.claude/projects/-Users-dev-app/abc.jsonl",
                "where Claude Code actually writes them"
            )
        },

        TestCase("A file outside the Claude directory is refused") { t in
            for path in ["/etc/passwd",
                         "/Users/dev/.ssh/id_ed25519",
                         "/Users/dev/Documents/contract.pdf",
                         "/tmp/anything.jsonl"] {
                t.expectNil(TranscriptPathPolicy.accepted(path, under: root), path)
            }
        },

        TestCase("Climbing out with .. does not count as being inside") { t in
            // The whole point of standardising before comparing: this string
            // starts with the root and ends up at the other end of the disk.
            t.expectNil(
                TranscriptPathPolicy.accepted(
                    "/Users/dev/.claude/../../../etc/passwd", under: root),
                "traversal"
            )
            t.expectNil(
                TranscriptPathPolicy.accepted(
                    "/Users/dev/.claude/projects/../../.ssh/id_rsa", under: root),
                "traversal from deeper in"
            )
        },

        TestCase("A sibling whose name merely starts the same is not inside") { t in
            // Without the trailing separator in the comparison, this passes —
            // and an attacker who can create one directory gets a free pass.
            t.expectNil(
                TranscriptPathPolicy.accepted("/Users/dev/.claude-evil/x.jsonl", under: root),
                "prefix is not containment"
            )
        },

        TestCase("Relative, empty and missing values are refused") { t in
            t.expectNil(TranscriptPathPolicy.accepted(nil, under: root), "missing")
            t.expectNil(TranscriptPathPolicy.accepted("", under: root), "empty")
            t.expectNil(TranscriptPathPolicy.accepted("  ", under: root), "blank")
            t.expectNil(
                TranscriptPathPolicy.accepted("projects/abc.jsonl", under: root),
                "relative: it would resolve against whatever directory we happen to be in"
            )
        },

        TestCase("The root itself is not a transcript") { t in
            t.expectNil(TranscriptPathPolicy.accepted("/Users/dev/.claude", under: root), "the directory")
        },
    ])
}
