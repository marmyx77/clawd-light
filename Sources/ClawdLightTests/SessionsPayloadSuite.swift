import ClawdLightCore
import Foundation
import TestKit

/// The JSON contract of the read endpoint.
///
/// Worth verifying because it is the only part of the project somebody
/// **outside** can read: changing it quietly breaks whoever consumes it.
enum SessionsPayloadSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    /// A working session with two subagents: declared state and displayed state
    /// coincide, so the field checks don't get tangled up with the derivation,
    /// which has a case of its own below.
    private static var example: SessionState {
        SessionState(
            id: "abc-123",
            status: .working,
            workspace: Workspace(path: "/dev/project-alpha"),
            lastMessage: "Working on it.",
            updatedAt: t0,
            statusSince: t0.addingTimeInterval(-60),
            activeSubagents: 2,
            entrypoint: "claude-vscode",
            origin: .terminal,
            title: "Wire the release script"
        )
    }

    static let suite = TestSuite("Sessions JSON contract", [

        TestCase("A snapshot preserves the fields that matter") { t in
            let snapshot = SessionsCodec.snapshot(of: example)
            t.expectEqual(snapshot.id, "abc-123", "id")
            t.expectEqual(snapshot.status, "working", "status")
            t.expectEqual(snapshot.workspace, "project-alpha", "name")
            t.expectEqual(snapshot.path, "/dev/project-alpha", "path")
            t.expectEqual(snapshot.activeSubagents, 2, "subagents")
            t.expectEqual(snapshot.lastMessage, "Working on it.", "preview")
            t.expectEqual(snapshot.entrypoint, "claude-vscode", "entrypoint")
            t.expectEqual(snapshot.origin, "terminal", "origin")
            t.expectEqual(snapshot.title, "Wire the release script", "title")
        },

        TestCase("The exposed status is the displayed one, not the declared one") { t in
            let session = SessionState(
                id: "x",
                status: .ready,
                workspace: Workspace(path: "/dev/a"),
                updatedAt: t0,
                statusSince: t0,
                activeSubagents: 1
            )
            // Whoever reads the endpoint has to see what the column sees:
            // exposing `ready` while the dot is yellow would be two truths.
            // A live subagent over a green base is a session waiting, not working (D22).
            t.expectEqual(SessionsCodec.snapshot(of: session).status, "waiting", "status")
        },

        TestCase("Encoding and decoding are reversible") { t in
            let original = SessionsResponse(
                generatedAt: t0,
                sessions: [SessionsCodec.snapshot(of: example)]
            )
            guard let data = try? SessionsCodec.encode(original),
                  let decoded = try? SessionsCodec.decode(data)
            else {
                return t.fail("round trip failed")
            }
            t.expectEqual(decoded, original, "response")
        },

        TestCase("Dates travel as ISO 8601") { t in
            let response = SessionsResponse(generatedAt: t0, sessions: [])
            guard let data = try? SessionsCodec.encode(response),
                  let text = String(data: data, encoding: .utf8)
            else {
                return t.fail("encoding failed")
            }
            // A number would force every reader to guess the unit, and one that
            // guesses wrong doesn't find out until it looks at a timestamp.
            t.expect(text.contains("2025-"), "expected an ISO timestamp, got: \(text)")
        },

        TestCase("The keys come out sorted") { t in
            guard let data = try? SessionsCodec.encode(
                SessionsResponse(generatedAt: t0, sessions: [SessionsCodec.snapshot(of: example)])
            ), let text = String(data: data, encoding: .utf8) else {
                return t.fail("encoding failed")
            }
            guard let workspace = text.range(of: "\"workspace\""),
                  let status = text.range(of: "\"status\"") else {
                return t.fail("keys not found")
            }
            // Makes comparing two responses a readable diff.
            t.expect(status.lowerBound < workspace.lowerBound, "keys not sorted")
        },

        TestCase("Paths are not escaped with backslashes") { t in
            guard let data = try? SessionsCodec.encode(
                SessionsResponse(generatedAt: t0, sessions: [SessionsCodec.snapshot(of: example)])
            ), let text = String(data: data, encoding: .utf8) else {
                return t.fail("encoding failed")
            }
            t.expect(!text.contains("\\/"), "escaped paths: \(text)")
        },
    ])
}
