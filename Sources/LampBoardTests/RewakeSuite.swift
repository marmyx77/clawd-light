import LampBoardCore
import Foundation
import TestKit

/// The listener script, and the promises its shape makes.
enum RewakeScriptSuite {

    private static let script = RewakeScriptBuilder.script(inboxPath: "/tmp/inbox")

    static let suite = TestSuite("Rewake listener script", [

        // The two lines the whole feature rests on. Without the flag the process
        // is killed with the turn; without exit 2 the message is never sent.
        TestCase("It carries the flag and the exit code that make it work") { t in
            t.expect(script.contains("asyncRewake"), "the hook option is not mentioned")
            t.expect(script.contains("exit 2"), "the send is missing")
        },

        // A hook that fails can interrupt a Claude Code turn. Every path out of
        // the script except the deliberate one has to be a success.
        TestCase("Every other way out is exit 0") { t in
            let exits = script
                .split(separator: "\n")
                .map { String($0).trimmed }
                .filter { $0.hasPrefix("exit ") }
            t.expect(!exits.isEmpty, "no exits at all?")
            for line in exits {
                t.expect(line == "exit 0" || line == "exit 2", "unexpected exit: \(line)")
            }
            t.expect(exits.filter { $0 == "exit 2" }.count == 1, "exactly one send")
        },

        TestCase("It refuses to arm without an open chat window") { t in
            t.expect(script.contains(".open"), "the arming marker is not checked")
        },

        // Three defenses against a process that outlives everything: it only arms
        // for an open window, it gives up, and it stands down for a peer.
        TestCase("It cannot wait for ever, and not in company") { t in
            t.expect(script.contains("MAX_WAIT"), "no upper bound on the wait")
            t.expect(
                script.contains(String(RewakeScriptBuilder.maxWaitSeconds)),
                "the bound is not the one the app documents"
            )
            t.expect(script.contains("kill -0"), "no check for an existing listener")
            t.expect(script.contains("trap"), "the pid file is not cleaned up on exit")
        },

        TestCase("It claims the message before delivering it") { t in
            guard let removal = script.range(of: "rm -f \"$MSG\""),
                  let send = script.range(of: "printf '%s' \"$TEXT\"")
            else {
                return t.fail("the claim-then-send shape is gone")
            }
            // Delivering first and deleting after would resend the message if the
            // process died in between, and a duplicate reads as the user repeating
            // themselves.
            t.expect(removal.lowerBound < send.lowerBound, "delivers before claiming")
        },

        TestCase("The session id it extracts cannot be a path") { t in
            // The pattern is anchored to the shape of a uuid, so a surprising
            // payload yields nothing rather than something usable as a filename.
            t.expect(script.contains("[A-Za-z0-9-]"), "the id pattern is not restricted")
        },
    ])
}

/// Registering the second `Stop` hook without disturbing the first.
enum RewakeRegistrationSuite {

    private static let hookPath = "/Users/dev/.lampboard/hook.sh"
    private static let rewakePath = "/Users/dev/.lampboard/rewake.sh"

    private static func entries(in settings: [String: Any], event: String) -> [[String: Any]] {
        let groups = (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
    }

    static let suite = TestSuite("Rewake registration", [

        TestCase("Stop carries both hooks, and only Stop") { t in
            let settings = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath
            )
            let stop = entries(in: settings, event: "Stop")
            t.expectEqual(stop.count, 2, "two hooks on Stop")
            t.expect(
                stop.contains { $0["command"] as? String == rewakePath },
                "the listener is not registered"
            )
            // Anywhere else it would block a turn for no reason at all.
            for event in HookConfigMerger.defaultEvents where event != "Stop" {
                t.expect(
                    !entries(in: settings, event: event)
                        .contains { $0["command"] as? String == rewakePath },
                    "the listener leaked onto \(event)"
                )
            }
        },

        TestCase("The traffic light hook keeps its timeout, the listener has none") { t in
            let settings = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath
            )
            let stop = entries(in: settings, event: "Stop")
            let light = stop.first { $0["command"] as? String == hookPath }
            let listener = stop.first { $0["command"] as? String == rewakePath }

            t.expect(light?["timeout"] != nil, "the traffic light hook lost its timeout")
            // A timeout here would be a statement about a mechanism we do not
            // control: harmless until a release starts honoring it and kills
            // every listener three seconds in.
            t.expectNil(listener?["timeout"], "the listener must carry no timeout")
            t.expectEqual(listener?["asyncRewake"] as? Bool, true, "asyncRewake")
        },

        // The preamble is what tells a delivered message apart from a background
        // agent reporting in, on the way back. Change it in one place only.
        TestCase("The preamble registered is the one the decoder looks for") { t in
            let settings = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath
            )
            let listener = entries(in: settings, event: "Stop")
                .first { $0["command"] as? String == rewakePath }
            t.expectEqual(
                listener?["rewakeMessage"] as? String, Mailbox.rewakePreamble, "preamble"
            )
        },

        TestCase("Uninstalling removes both") { t in
            let installed = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath
            )
            let cleaned = HookConfigMerger.uninstall(
                from: installed, scriptPaths: [hookPath, rewakePath]
            )
            t.expectNil(cleaned["hooks"], "registrations left behind: \(cleaned)")
        },

        // The failure this guards against: uninstall that only knows the traffic
        // light path leaves a listener spawning a process at the end of every turn
        // for a panel that no longer exists.
        TestCase("Uninstalling only the traffic light leaves the listener behind") { t in
            let installed = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath
            )
            let partial = HookConfigMerger.uninstall(from: installed, scriptPath: hookPath)
            t.expect(
                entries(in: partial, event: "Stop")
                    .contains { $0["command"] as? String == rewakePath },
                "this test documents why uninstall takes both paths"
            )
        },

        TestCase("Without a listener path nothing changes") { t in
            let settings = HookConfigMerger.install(into: [:], scriptPath: hookPath)
            t.expectEqual(entries(in: settings, event: "Stop").count, 1, "only the light")
        },

        TestCase("A hook belonging to somebody else is preserved") { t in
            let theirs: [String: Any] = [
                "hooks": ["Stop": [["hooks": [["type": "command", "command": "/opt/theirs.sh"]]]]]
            ]
            let settings = HookConfigMerger.install(
                into: theirs, scriptPath: hookPath, rewakeScriptPath: rewakePath
            )
            t.expect(
                entries(in: settings, event: "Stop")
                    .contains { $0["command"] as? String == "/opt/theirs.sh" },
                "we ate somebody else's hook"
            )
        },
    ])
}

/// Turning message delivery off has to actually remove it.
enum MessageDeliverySwitchSuite {

    private static let hookPath = "/Users/dev/.lampboard/hook.sh"
    private static let rewakePath = "/Users/dev/.lampboard/rewake.sh"

    private static func registered(_ settings: [String: Any]) -> [String] {
        let groups = (settings["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
    }

    static let suite = TestSuite("Message delivery switch", [

        TestCase("On registers the listener") { t in
            let settings = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath,
                registerMessageDelivery: true
            )
            t.expect(registered(settings).contains(rewakePath), "listener")
        },

        // The defect this suite exists for. Passing no path meant the cleanup did
        // not know about the listener, so switching off left it registered and
        // running while the interface reported it was off.
        TestCase("Off removes a listener that was already there") { t in
            let on = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath,
                registerMessageDelivery: true
            )
            let off = HookConfigMerger.install(
                into: on, scriptPath: hookPath, rewakeScriptPath: rewakePath,
                registerMessageDelivery: false
            )
            t.expect(!registered(off).contains(rewakePath), "the listener must be gone")
            t.expect(registered(off).contains(hookPath), "the traffic light stays")
        },

        TestCase("Off twice is still off") { t in
            let settings = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath,
                registerMessageDelivery: false
            )
            t.expectEqual(registered(settings), [hookPath], "only the traffic light")
        },
    ])
}
