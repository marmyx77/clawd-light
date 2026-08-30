import LampBoardCore
import Foundation
import TestKit

/// Reading which files a live process holds open.
///
/// This is the evidence a Codex session rests on. A rollout on disk proves a
/// session existed; a process holding it open proves it exists now. Everything
/// here is about not mistaking one for the other, and about not mistaking a
/// probe that failed for a session that ended.
enum OpenFilesSuite {

    /// Field output as `lsof -nP -F pcftn` writes it: one letter, one value.
    private static let sample = """
    p4643
    ccodex
    fcwd
    tDIR
    n/Users/dev/project
    f7
    tREG
    n/Users/dev/.codex/sessions/2026/08/30/rollout-2026-08-30T07-47-10-abc.jsonl
    f9
    tREG
    n/Users/dev/Library/Caches/something.bin
    p8100
    ccodex
    f7
    tREG
    n/Users/dev/.codex/sessions/2026/08/29/rollout-2026-08-29T23-37-36-def.jsonl
    """

    static let suite = TestSuite("Open files", [

        TestCase("Every regular file comes out with its process") { t in
            let files = LsofOpenFiles.parse(sample)
            t.expectEqual(files.count, 3, "three regular files")
            t.expectEqual(files.first?.pid, 4643, "the first process")
            t.expectEqual(files.first?.command, "codex", "and what it is running")
        },

        TestCase("A directory is not a file it holds open") { t in
            // `cwd` is a DIR row and arrives in the same listing. Counting it
            // would make every process look like it holds its project open, which
            // is the one thing this must never say.
            let paths = LsofOpenFiles.parse(sample).map(\.path)
            t.expect(!paths.contains("/Users/dev/project"), "the working directory stays out")
        },

        TestCase("Only what lives under the Codex root is a rollout") { t in
            let rollouts = LsofOpenFiles.under("/Users/dev/.codex", in: LsofOpenFiles.parse(sample))
            t.expectEqual(rollouts.count, 2, "two rollouts")
            t.expect(rollouts.allSatisfy { $0.path.contains("/sessions/") }, "and both are sessions")
        },

        TestCase("A folder whose name merely starts the same way is not inside it") { t in
            // `~/.codexes` is not `~/.codex`, and a prefix comparison that forgot
            // the separator would adopt somebody else's files as sessions.
            let output = """
            p1
            ccodex
            f7
            tREG
            n/Users/dev/.codexes/rollout-fake.jsonl
            """
            t.expect(
                LsofOpenFiles.under("/Users/dev/.codex", in: LsofOpenFiles.parse(output)).isEmpty,
                "not a descendant"
            )
        },

        TestCase("A process that holds two rollouts open is holding two") { t in
            // The photograph taken on one machine showed one file per process, and
            // that is a photograph rather than a contract. The parser must not be
            // the place where a second session is quietly lost.
            let output = """
            p4643
            ccodex
            f7
            tREG
            n/Users/dev/.codex/sessions/a.jsonl
            f8
            tREG
            n/Users/dev/.codex/sessions/b.jsonl
            """
            let rollouts = LsofOpenFiles.under("/Users/dev/.codex", in: LsofOpenFiles.parse(output))
            t.expectEqual(rollouts.count, 2, "two sessions, one process")
            t.expectEqual(Set(rollouts.map(\.pid)), [4643], "the same process")
        },

        TestCase("A descriptor that is not a regular file carries nothing over") { t in
            // The type belongs to the descriptor, not to the process: without
            // clearing it at each `f`, a socket following a file would inherit
            // REG and be reported as an open rollout.
            let output = """
            p1
            ccodex
            f7
            tREG
            n/Users/dev/.codex/sessions/real.jsonl
            f8
            tunix
            n/Users/dev/.codex/sessions/not-a-file.sock
            """
            let files = LsofOpenFiles.parse(output)
            t.expectEqual(files.count, 1, "only the regular one")
            t.expectEqual(files.first?.path, "/Users/dev/.codex/sessions/real.jsonl", "and it is the right one")
        },

        TestCase("Nothing at all is an empty answer, never a crash") { t in
            t.expect(LsofOpenFiles.parse("").isEmpty, "empty output")
            t.expect(LsofOpenFiles.parse("garbage\nmore garbage").isEmpty, "and nonsense")
        },
    ])
}
