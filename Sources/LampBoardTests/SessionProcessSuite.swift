import LampBoardCore
import Foundation
import TestKit

/// Tracing a row to the process it runs in, without ending the wrong one.
///
/// Claude Code writes one file per running session in `~/.claude/sessions`, named
/// after the process id and carrying the session id beside it. Measured on this
/// machine: fifteen such files, three of them for the same project, and the one
/// that mattered named the process a closed tab had left behind — pid 6848,
/// alive nine hours after its tab went.
///
/// The fixtures are the shape of a real file with the paths made anonymous.
enum SessionProcessSuite {

    private static func file(pid: Int = 6848,
                             sessionId: String = "34ccc6c5-34e5-4a4c-b3dc-2e4d4063db5f",
                             started: String = "Mon Aug 31 08:32:11 2026") -> Data {
        """
        {"pid": \(pid), "sessionId": "\(sessionId)", "cwd": "/dev/project",
         "procStart": "\(started)", "version": "2.1.251", "kind": "interactive",
         "entrypoint": "claude-vscode"}
        """.data(using: .utf8)!
    }

    static let suite = TestSuite("The process behind a row", [

        TestCase("A session file names its process") { t in
            guard let process = SessionProcess.from(json: file()) else {
                t.expect(false, "the file should have parsed"); return
            }
            t.expectEqual(process.pid, 6848, "pid")
            t.expectEqual(process.sessionId, "34ccc6c5-34e5-4a4c-b3dc-2e4d4063db5f", "session")
            t.expectEqual(process.cwd, "/dev/project", "folder")
        },

        TestCase("A file without a start time is not usable") { t in
            // Without it there is no way to tell a reused pid from the original,
            // and a pid that cannot be checked must never be signalled.
            let data = """
            {"pid": 6848, "sessionId": "s1", "cwd": "/dev/project"}
            """.data(using: .utf8)!
            t.expectNil(SessionProcess.from(json: data), "no start time, no answer")
        },

        TestCase("A file without a session id is not usable either") { t in
            let data = """
            {"pid": 6848, "cwd": "/dev/project", "procStart": "Mon Aug 31 08:32:11 2026"}
            """.data(using: .utf8)!
            t.expectNil(SessionProcess.from(json: data), "nothing to match a row against")
        },

        TestCase("Something that is not a session file is not read as one") { t in
            t.expectNil(SessionProcess.from(json: Data("not json".utf8)), "unreadable is nil")
            t.expectNil(SessionProcess.from(json: Data("[]".utf8)), "an array is not a record")
        },

        TestCase("A pid that has been reused is refused") { t in
            // The defect this guards against: the file outlives the process, the
            // system hands the number to something else, and a panel that trusted
            // the file would end a stranger.
            guard let process = SessionProcess.from(json: file()) else {
                t.expect(false, "fixture"); return
            }
            t.expect(process.isStill(startedAt: "Mon Aug 31 08:32:11 2026"),
                     "same start time, same process")
            t.expect(!process.isStill(startedAt: "Mon Aug 31 17:04:55 2026"),
                     "a different start time is a different process")
            t.expect(!process.isStill(startedAt: ""),
                     "and no answer from the system is not a match")
        },

        TestCase("The comparison survives the padding ps puts around its output") { t in
            guard let process = SessionProcess.from(json: file()) else {
                t.expect(false, "fixture"); return
            }
            t.expect(process.isStill(startedAt: "  Mon Aug 31 08:32:11 2026  "),
                     "ps pads, the file does not, and they still name the same instant")
        },
    ])
}
