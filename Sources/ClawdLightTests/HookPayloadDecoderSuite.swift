import ClawdLightCore
import Foundation
import TestKit

enum HookPayloadDecoderSuite {

    // MARK: - Helpers

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private static var validStop: [String: Any] {
        [
            "session_id": "f512ecae-4294-45bf-9cf1-fdf45a44dd79",
            "hook_event_name": "Stop",
            "cwd": "/Users/dev/Development/clawd-light",
            "last_assistant_message": "Done.",
        ]
    }

    private static func payload(_ changes: [String: Any?]) -> Data {
        var object = validStop
        for (key, value) in changes {
            if let value { object[key] = value } else { object.removeValue(forKey: key) }
        }
        return json(object)
    }

    // MARK: - Suite

    static let suite = TestSuite("Hook payload decoding", [

        TestCase("The transcript path is carried through") { t in
            // Built from the configured Claude directory rather than written out:
            // the path has to be inside it to be accepted, and the directory is
            // wherever this run's home points — the fake one under test.
            let inside = AppConfig.claudeDirectory
                .appendingPathComponent("projects/p/s.jsonl").path
            let signal = try? HookPayloadDecoder.decode(
                payload(["transcript_path": inside])
            )
            t.expectEqual(signal?.transcriptPath, inside, "path")
        },

        // `POST /signal` has no token, and this value is opened for reading. A
        // forged signal naming a file outside `~/.claude` used to produce a row
        // holding it — measured on the running app — so the decoder is where the
        // boundary is enforced, before anything stores it.
        TestCase("A transcript path outside the Claude directory is refused") { t in
            for path in ["/etc/passwd", "/tmp/anything.jsonl"] {
                let signal = try? HookPayloadDecoder.decode(
                    payload(["transcript_path": path])
                )
                t.expectNil(signal?.transcriptPath, path)
            }
        },

        // The path gets opened for reading. A relative one would resolve against
        // whatever the app's working directory happens to be, which is a file
        // nobody asked for — so it is dropped rather than kept.
        TestCase("A relative transcript path is dropped, not resolved") { t in
            let signal = try? HookPayloadDecoder.decode(payload(["transcript_path": "s.jsonl"]))
            t.expectNil(signal?.transcriptPath, "relative path")
        },

        TestCase("A missing transcript path is not an error") { t in
            // Every event carries it today, and the app must still work the day
            // one doesn't: the chat window is a feature, the traffic light is the
            // product.
            let signal = try? HookPayloadDecoder.decode(payload(["transcript_path": nil]))
            t.expectEqual(signal?.event, .stop, "the signal still decodes")
            t.expectNil(signal?.transcriptPath, "path")
        },

        TestCase("Decodes a complete Stop signal") { t in
            guard let signal = try? HookPayloadDecoder.decode(
                json(validStop), entrypoint: "claude-vscode"
            ) else {
                return t.fail("decoding failed")
            }
            t.expectEqual(signal.sessionId, "f512ecae-4294-45bf-9cf1-fdf45a44dd79", "session_id")
            t.expectEqual(signal.event, .stop, "event")
            t.expectEqual(signal.cwd, "/Users/dev/Development/clawd-light", "cwd")
            t.expectEqual(signal.lastAssistantMessage, "Done.", "message")
            t.expectEqual(signal.entrypoint, "claude-vscode", "entrypoint")
            t.expect(!signal.isFromSubagent, "must not count as a subagent")
            t.expect(signal.deservesTrafficLight, "must deserve a traffic light")
        },

        TestCase("The host header is carried, and only in a usable shape") { t in
            let remote = try? HookPayloadDecoder.decode(json(validStop), entrypoint: "cli", host: "node")
            t.expectEqual(remote?.host, "node", "host")

            let local = try? HookPayloadDecoder.decode(json(validStop), entrypoint: "cli")
            t.expectNil(local?.host, "no header, no host")

            // The value ends up in a row label and, later, in an ssh argument.
            let hostile = try? HookPayloadDecoder.decode(json(validStop), host: "-oProxyCommand=evil")
            t.expectNil(hostile?.host, "a name ssh would misread is dropped, the signal is kept")

            // A path on the node is not a path here: the chat window would open
            // an empty conversation and call it "nothing was said".
            // The remote path is a node's, so it is dropped for carrying a host at
            // all; the local one has to be inside this home's Claude directory,
            // which is the separate rule `TranscriptPathPolicy` enforces.
            let remotePath = payload(["transcript_path": "/home/dev/.claude/projects/p/s.jsonl"])
            t.expectNil((try? HookPayloadDecoder.decode(remotePath, host: "node"))?.transcriptPath, "a remote transcript path is dropped")

            let localPath = payload(["transcript_path":
                AppConfig.claudeDirectory.appendingPathComponent("projects/p/s.jsonl").path])
            t.expect((try? HookPayloadDecoder.decode(localPath))?.transcriptPath != nil, "a local one is kept")
        },

        TestCase("Decodes a permission request notification") { t in
            let data = payload([
                "hook_event_name": "Notification",
                "notification_type": "permission_prompt",
            ])
            guard let signal = try? HookPayloadDecoder.decode(data) else {
                return t.fail("decoding failed")
            }
            t.expectEqual(signal.event, .notification, "event")
            t.expectEqual(signal.notificationKind, .permissionPrompt, "subtype")
        },

        TestCase("An unknown notification subtype is not an error") { t in
            let data = payload([
                "hook_event_name": "Notification",
                "notification_type": "something_new",
            ])
            guard let signal = try? HookPayloadDecoder.decode(data) else {
                return t.fail("decoding failed")
            }
            t.expectEqual(signal.event, .notification, "event")
            t.expectNil(signal.notificationKind, "subtype")
        },

        TestCase("Extra fields are ignored") { t in
            let data = payload([
                "future_field": ["nested": true],
                "effort": ["level": "xhigh"],
            ])
            t.expectNoThrow("payload with extra fields") {
                _ = try HookPayloadDecoder.decode(data)
            }
        },

        TestCase("Normalizes the cwd") { t in
            let data = payload(["cwd": "/Users/dev//Development/clawd-light/"])
            let signal = try? HookPayloadDecoder.decode(data)
            t.expectEqual(signal?.cwd, "/Users/dev/Development/clawd-light", "cwd")
        },

        TestCase("Recognizes a subagent from the agent_id") { t in
            let signal = try? HookPayloadDecoder.decode(payload(["agent_id": "agent_01"]))
            t.expectEqual(signal?.isFromSubagent, true, "subagent")
        },

        // MARK: Validation

        TestCase("Rejects malformed JSON") { t in
            t.expectThrows(HookPayloadError.invalidJSON) {
                _ = try HookPayloadDecoder.decode(Data("{ not json".utf8))
            }
        },

        TestCase("Rejects JSON that isn't an object") { t in
            t.expectThrows(HookPayloadError.notAnObject) {
                _ = try HookPayloadDecoder.decode(Data("[1, 2, 3]".utf8))
            }
        },

        TestCase("Rejects a missing session_id") { t in
            let data = payload(["session_id": nil])
            t.expectThrows(HookPayloadError.missingField("session_id")) {
                _ = try HookPayloadDecoder.decode(data)
            }
        },

        TestCase("Rejects an empty session_id") { t in
            let data = payload(["session_id": "   "])
            t.expectThrows(HookPayloadError.emptyField("session_id")) {
                _ = try HookPayloadDecoder.decode(data)
            }
        },

        TestCase("Rejects a session_id of the wrong type") { t in
            let data = payload(["session_id": 42])
            t.expectThrows(HookPayloadError.missingField("session_id")) {
                _ = try HookPayloadDecoder.decode(data)
            }
        },

        TestCase("Rejects a missing hook_event_name") { t in
            let data = payload(["hook_event_name": nil])
            t.expectThrows(HookPayloadError.missingField("hook_event_name")) {
                _ = try HookPayloadDecoder.decode(data)
            }
        },

        TestCase("Rejects a relative cwd") { t in
            let data = payload(["cwd": "relative/path"])
            t.expectThrows(HookPayloadError.relativePath(field: "cwd", value: "relative/path")) {
                _ = try HookPayloadDecoder.decode(data)
            }
        },

        TestCase("An irrelevant event is ignored, not a fault") { t in
            let data = payload(["hook_event_name": "PreCompact"])
            t.expectThrows(HookPayloadError.ignoredEvent("PreCompact")) {
                _ = try HookPayloadDecoder.decode(data)
            }
            t.expectEqual(HookPayloadError.ignoredEvent("PreCompact").isFailure, false, "ignoredEvent")
            t.expectEqual(HookPayloadError.invalidJSON.isFailure, true, "invalidJSON")
        },

        TestCase("Rejects a body beyond the limit") { t in
            let data = Data(String(repeating: "a", count: AppConfig.maxRequestBodyBytes + 1).utf8)
            t.expectThrows(HookPayloadError.bodyTooLarge(data.count)) {
                _ = try HookPayloadDecoder.decode(data)
            }
        },

        // MARK: Entrypoint

        TestCase("A missing entrypoint does not exclude the session") { t in
            let signal = try? HookPayloadDecoder.decode(json(validStop), entrypoint: nil)
            t.expectEqual(signal?.deservesTrafficLight, true, "entrypoint missing")
        },

        TestCase("A terminal session is no longer excluded") { t in
            let signal = try? HookPayloadDecoder.decode(json(validStop), entrypoint: "cli")
            // `claude` launched in VS Code's integrated terminal runs in the same
            // window and the same project: what decides whether it deserves a row
            // is the folder, which the resolver knows, not the command's name.
            t.expectEqual(signal?.deservesTrafficLight, true, "entrypoint cli")
        },

        TestCase("A non-interactive session is excluded") { t in
            // Every value observed in binary 2.1.220. `sdk-cli` is the one
            // `claude -p` actually reports: it was missing from the list until a
            // contract probe recorded a real session instead of trusting the
            // documentation. See `Contracts/assumptions.md`, `entrypoint.values`.
            for entrypoint in ["sdk", "sdk-cli", "sdk-ts", "sdk-py", "print"] {
                let signal = try? HookPayloadDecoder.decode(
                    json(validStop), entrypoint: entrypoint
                )
                t.expectEqual(signal?.deservesTrafficLight, false, "entrypoint \(entrypoint)")
            }
        },

        TestCase("The interactive entrypoints keep their traffic light") { t in
            // `cli` is deliberately here: `claude` from VS Code's integrated
            // terminal reports it, and it runs in the same window as the project.
            for entrypoint in ["claude-vscode", "vscode", "jetbrains", "cli"] {
                let signal = try? HookPayloadDecoder.decode(
                    json(validStop), entrypoint: entrypoint
                )
                t.expectEqual(signal?.deservesTrafficLight, true, "entrypoint \(entrypoint)")
            }
        },

        TestCase("An entrypoint never seen before is not discarded") { t in
            let signal = try? HookPayloadDecoder.decode(
                json(validStop), entrypoint: "claude-something-from-2027"
            )
            // The list is of exclusions, not admissions: when it's wrong it shows
            // one row too many rather than hiding one.
            t.expectEqual(signal?.deservesTrafficLight, true, "unknown entrypoint")
        },

        // MARK: Subagents

        TestCase("SubagentStart increments the counter") { t in
            let data = Data("""
            {"session_id":"s","hook_event_name":"SubagentStart","cwd":"/tmp",
             "agent_id":"a1","agent_type":"general-purpose"}
            """.utf8)
            let signal = try? HookPayloadDecoder.decode(data)
            t.expectEqual(signal?.event, .subagentStart, "event")
            t.expectEqual(signal?.subagentDelta, 1, "delta")
            t.expectEqual(signal?.isFromSubagent, true, "carries agent_id")
        },

        TestCase("SubagentStop decrements the counter") { t in
            let data = Data("""
            {"session_id":"s","hook_event_name":"SubagentStop","cwd":"/tmp",
             "agent_id":"a1","last_assistant_message":"done"}
            """.utf8)
            let signal = try? HookPayloadDecoder.decode(data)
            t.expectEqual(signal?.subagentDelta, -1, "delta")
        },

        TestCase("A normal event does not move the counter") { t in
            let signal = try? HookPayloadDecoder.decode(json(validStop))
            t.expectNil(signal?.subagentDelta, "delta")
        },
    ])
}
