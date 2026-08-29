import LampBoardCore
import Foundation
import TestKit

enum LiveSessionSuite {

    private static let modifiedAt = Date(timeIntervalSince1970: 1_800_000_000)

    /// Payload copied from a real file in ~/.claude/sessions/, with the path and
    /// project name anonymized.
    private static let realPayload = Data("""
    {"pid":10653,"sessionId":"8a46d71c-09c1-4a74-8530-3ff10d609933",
     "cwd":"/Users/dev/Development/event-tracker","startedAt":1785181419811,
     "procStart":"Mon Jul 27 19:43:38 2026","version":"2.1.220","peerProtocol":1,
     "kind":"interactive","entrypoint":"claude-vscode","name":"event-tracker-64",
     "nameSource":"derived"}
    """.utf8)

    static let suite = TestSuite("Live sessions declared by the filesystem", [

        TestCase("Decodes a real session file") { t in
            guard let live = try? LiveSessionParser.parse(data: realPayload, modifiedAt: modifiedAt) else {
                return t.fail("decoding failed")
            }
            t.expectEqual(live.pid, 10653, "pid")
            t.expectEqual(live.sessionId, "8a46d71c-09c1-4a74-8530-3ff10d609933", "sessionId")
            t.expectEqual(live.cwd, "/Users/dev/Development/event-tracker", "cwd")
            t.expectEqual(live.entrypoint, "claude-vscode", "entrypoint")
            t.expectEqual(live.name, "event-tracker-64", "name")
            t.expectEqual(live.kind, "interactive", "kind")
            t.expect(live.deservesTrafficLight, "must deserve a traffic light")
        },

        TestCase("A terminal session still deserves a traffic light") { t in
            let data = Data("""
            {"pid":1,"sessionId":"x","cwd":"/tmp","entrypoint":"cli","kind":"interactive"}
            """.utf8)
            let live = try? LiveSessionParser.parse(data: data, modifiedAt: modifiedAt)
            // What decides whether the row exists is the workspace resolver, not
            // the command the session was started with: `claude` from the
            // integrated terminal runs in the same VS Code window.
            t.expectEqual(live?.deservesTrafficLight, true)
        },

        TestCase("A non-interactive session is excluded") { t in
            let data = Data("""
            {"pid":1,"sessionId":"x","cwd":"/tmp","entrypoint":"sdk","kind":"background"}
            """.utf8)
            let live = try? LiveSessionParser.parse(data: data, modifiedAt: modifiedAt)
            // Nobody is waiting in front of an automated session.
            t.expectEqual(live?.deservesTrafficLight, false)
        },

        // This used to assert the opposite — that `kind` alone decided, because
        // Claude Code writes it itself and that beats deducing from a command
        // name. Both halves of that were true and the conclusion was still wrong,
        // because **both fields** are written by Claude Code and they answer
        // different questions: `kind` says whether the loop is interactive,
        // `entrypoint` says whether a person started it.
        //
        // The case that settled it is real, not synthetic: claude-mem's observer
        // writes `kind: interactive` with `entrypoint: sdk-cli`, thousands of
        // times a day. The old rule let every one of them through. Locally that
        // stayed invisible because no editor window claims its folder; reading
        // another machine removed that accidental filter and the column filled up.
        //
        // "One row too many can be seen and fixed" holds for one row. It does not
        // hold for two thousand a day.
        TestCase("An SDK session is excluded even when it calls itself interactive") { t in
            let data = Data("""
            {"pid":1,"sessionId":"x","cwd":"/tmp","entrypoint":"sdk","kind":"interactive"}
            """.utf8)
            let live = try? LiveSessionParser.parse(data: data, modifiedAt: modifiedAt)
            t.expectEqual(live?.deservesTrafficLight, false)
        },

        TestCase("An interactive session with an interactive entrypoint is kept") { t in
            let data = Data("""
            {"pid":1,"sessionId":"x","cwd":"/tmp","entrypoint":"cli","kind":"interactive"}
            """.utf8)
            let live = try? LiveSessionParser.parse(data: data, modifiedAt: modifiedAt)
            t.expectEqual(live?.deservesTrafficLight, true)
        },

        TestCase("With neither kind nor entrypoint the session is kept") { t in
            let data = Data(#"{"pid":1,"sessionId":"x","cwd":"/tmp"}"#.utf8)
            let live = try? LiveSessionParser.parse(data: data, modifiedAt: modifiedAt)
            // One row too many can be seen and fixed; a missing row stays silent.
            t.expectEqual(live?.deservesTrafficLight, true)
        },

        TestCase("Rejects a file without a sessionId") { t in
            let data = Data(#"{"pid":1,"cwd":"/tmp"}"#.utf8)
            t.expectThrows(LiveSessionError.missingField("sessionId")) {
                _ = try LiveSessionParser.parse(data: data, modifiedAt: modifiedAt)
            }
        },

        TestCase("Rejects a file without an absolute cwd") { t in
            let data = Data(#"{"pid":1,"sessionId":"x","cwd":"relative"}"#.utf8)
            t.expectThrows(LiveSessionError.missingField("cwd")) {
                _ = try LiveSessionParser.parse(data: data, modifiedAt: modifiedAt)
            }
        },

        TestCase("Rejects malformed JSON") { t in
            t.expectThrows(LiveSessionError.invalidJSON) {
                _ = try LiveSessionParser.parse(data: Data("{".utf8), modifiedAt: modifiedAt)
            }
        },
    ])
}

enum ReconcileSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let workspace = Workspace(path: "/dev/project")

    private static func session(_ id: String, _ status: SessionStatus) -> SessionState {
        SessionState(id: id, status: status, workspace: workspace, updatedAt: t0, statusSince: t0)
    }

    private static func state(_ sessions: [SessionState]) -> TrafficLightState {
        TrafficLightState(sessions: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) }))
    }

    static let suite = TestSuite("Realignment with the live processes", [

        // Close a Claude panel: the row has to vanish at once, not after 12 hours.
        TestCase("Rows with no live process disappear") { t in
            let subject = state([session("alive", .ready), session("dead", .working)])
            let after = StateReducer.reduce(
                subject, action: .reconcile(alive: ["alive"]), now: t0
            )

            t.expectEqual(after.sessions.count, 1, "rows left")
            t.expectNotNil(after.sessions["alive"], "the live row must remain")
        },

        // If the read fails the set arrives empty: wiping everything would be the
        // worst possible reaction to a transient error.
        TestCase("An empty set does not clear the column") { t in
            let subject = state([session("a", .ready), session("b", .idle)])
            let after = StateReducer.reduce(subject, action: .reconcile(alive: []), now: t0)

            t.expectEqual(after.sessions.count, 2)
        },

        TestCase("A row unknown to the filesystem but alive stays") { t in
            let subject = state([session("a", .working)])
            let after = StateReducer.reduce(
                subject, action: .reconcile(alive: ["a", "other"]), now: t0
            )
            t.expectEqual(after.sessions.count, 1)
        },

        TestCase("Adoption creates the row only when it's missing") { t in
            let subject = state([session("a", .ready)])
            let after = StateReducer.reduce(
                subject, action: .adopt(session("a", .idle)), now: t0
            )
            t.expectEqual(after.sessions["a"]?.status, .ready, "must not overwrite")

            let added = StateReducer.reduce(
                subject, action: .adopt(session("b", .idle)), now: t0
            )
            t.expectEqual(added.sessions.count, 2, "the new row must be added")
        },
    ])
}
