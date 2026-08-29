import LampBoardCore
import Foundation
import TestKit

enum HookConfigMergerSuite {

    private static let scriptPath = "/Users/dev/.lampboard/hook.sh"

    /// A realiztic settings.json: it already holds user configuration that the
    /// installation must not touch.
    private static var existingSettings: [String: Any] {
        [
            "model": "opus[1m]",
            "language": "Italian",
            "permissions": ["defaultMode": "auto"],
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "Bash",
                        "hooks": [
                            ["type": "command", "command": "/Users/dev/.claude/guard.sh"]
                        ],
                    ] as [String: Any]
                ]
            ],
        ]
    }

    private static func entries(
        _ settings: [String: Any], event: String
    ) -> [[String: Any]] {
        (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    }

    static let suite = TestSuite("Hook registration in settings.json", [

        TestCase("Registers all the default events") { t in
            let result = HookConfigMerger.install(into: [:], scriptPath: scriptPath)

            t.expectEqual(
                HookConfigMerger.installedEvents(in: result, scriptPath: scriptPath),
                HookConfigMerger.defaultEvents.sorted()
            )
        },

        TestCase("Leaves the other configuration keys alone") { t in
            let result = HookConfigMerger.install(into: existingSettings, scriptPath: scriptPath)

            t.expectEqual(result["model"] as? String, "opus[1m]", "model")
            t.expectEqual(result["language"] as? String, "Italian", "language")
            t.expectNotNil(result["permissions"], "permissions")
        },

        // The case that would ruin somebody's day: overwriting the user's hooks.
        TestCase("Preserves pre-existing hooks on the same event") { t in
            let result = HookConfigMerger.install(
                into: existingSettings, scriptPath: scriptPath,
                events: HookConfigMerger.defaultEvents + HookConfigMerger.toolEvents
            )

            let preToolUse = entries(result, event: "PreToolUse")
            t.expectEqual(preToolUse.count, 2, "groups on PreToolUse")

            let commands = preToolUse.flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            }
            t.expect(commands.contains("/Users/dev/.claude/guard.sh"), "user hook lost")
            t.expect(commands.contains(scriptPath), "lampboard hook missing")
        },

        TestCase("Installing twice does not duplicate the registrations") { t in
            let once = HookConfigMerger.install(into: existingSettings, scriptPath: scriptPath)
            let twice = HookConfigMerger.install(into: once, scriptPath: scriptPath)

            t.expectEqual(entries(twice, event: "Stop").count, 1, "groups on Stop")
            t.expectEqual(
                HookConfigMerger.installedEvents(in: twice, scriptPath: scriptPath),
                HookConfigMerger.defaultEvents.sorted()
            )
        },

        TestCase("Changing the event list leaves no orphaned registrations") { t in
            let wide = HookConfigMerger.install(
                into: [:], scriptPath: scriptPath,
                events: HookConfigMerger.defaultEvents + HookConfigMerger.toolEvents
            )
            let narrow = HookConfigMerger.install(into: wide, scriptPath: scriptPath)

            t.expectEqual(
                HookConfigMerger.installedEvents(in: narrow, scriptPath: scriptPath),
                HookConfigMerger.defaultEvents.sorted()
            )
        },

        TestCase("Uninstalling removes only our hooks") { t in
            let installed = HookConfigMerger.install(into: existingSettings, scriptPath: scriptPath)
            let removed = HookConfigMerger.uninstall(from: installed, scriptPath: scriptPath)

            t.expect(
                !HookConfigMerger.isInstalled(in: removed, scriptPath: scriptPath),
                "the lampboard hooks are still there"
            )
            let userHooks = entries(removed, event: "PreToolUse")
            t.expectEqual(userHooks.count, 1, "the user's hook should have stayed")
        },

        TestCase("Uninstalling from a configuration with no hooks breaks nothing") { t in
            let settings: [String: Any] = ["model": "opus"]
            let result = HookConfigMerger.uninstall(from: settings, scriptPath: scriptPath)

            t.expectEqual(result["model"] as? String, "opus", "model")
            t.expectNil(result["hooks"], "hooks")
        },

        TestCase("The hooks key disappears when it's left empty") { t in
            let installed = HookConfigMerger.install(into: [:], scriptPath: scriptPath)
            let removed = HookConfigMerger.uninstall(from: installed, scriptPath: scriptPath)

            t.expectNil(removed["hooks"], "hooks")
        },

        TestCase("isInstalled tells different scripts apart") { t in
            let installed = HookConfigMerger.install(into: [:], scriptPath: scriptPath)

            t.expect(HookConfigMerger.isInstalled(in: installed, scriptPath: scriptPath), "our script")
            t.expect(
                !HookConfigMerger.isInstalled(in: installed, scriptPath: "/other/hook.sh"),
                "a different script must not count as installed"
            )
        },

        TestCase("Every registration has a type, a command and a timeout") { t in
            let result = HookConfigMerger.install(into: [:], scriptPath: scriptPath)
            guard let entry = entries(result, event: "Stop").first?["hooks"] as? [[String: Any]],
                  let hook = entry.first else {
                return t.fail("registration on Stop missing")
            }

            t.expectEqual(hook["type"] as? String, "command", "type")
            t.expectEqual(hook["command"] as? String, scriptPath, "command")
            t.expectNotNil(hook["timeout"], "timeout")
        },
    ])
}

enum HookScriptBuilderSuite {

    static let suite = TestSuite("Hook script generation", [

        TestCase("Contains the right shebang, port and path") { t in
            let script = HookScriptBuilder.script(port: 9877)

            t.expect(script.hasPrefix("#!/bin/bash"), "shebang missing")
            t.expect(script.contains("http://127.0.0.1:9877/signal"), "wrong URL in:\n\(script)")
            t.expect(script.contains("X-Claude-Entrypoint"), "entrypoint header missing")
        },

        // A failing hook can interrupt a Claude Code turn.
        TestCase("Always exits 0") { t in
            let script = HookScriptBuilder.script()

            t.expect(script.contains("exit 0"), "the forced exit 0 is missing")
            t.expect(script.contains("|| true"), "curl can make the script fail")
        },

        TestCase("Has short timeouts so it doesn't slow the turn down") { t in
            let script = HookScriptBuilder.script()

            t.expect(script.contains("--connect-timeout 1"), "connect-timeout missing")
            t.expect(script.contains("--max-time 2"), "max-time missing")
        },

        TestCase("Honors the requested port") { t in
            t.expect(
                HookScriptBuilder.script(port: 12345).contains(":12345/signal"),
                "the port is not propagated"
            )
        },

        // The script installed on another machine has to say which machine, or
        // its signals would be looked up among local editor windows and dropped.
        TestCase("A script for another machine names it in a header and posts to its own port") { t in
            let remote = HookScriptBuilder.script(port: 31000, host: "node")
            t.expect(
                remote.contains("--header 'X-LampBoard-Host: node' \\\n     --data-binary"),
                "host header missing or misplaced in:\n\(remote)"
            )
            t.expect(remote.contains("posts through the ssh tunnel"), "the script says where it runs")
            // The per-user loopback port the tunnel binds over there — never the
            // Mac's own port, which another account on that machine could share.
            t.expect(remote.contains("'http://127.0.0.1:31000/signal'"), "posts to the tunnel's far end in:\n\(remote)")
            t.expect(!HookScriptBuilder.script(port: 9877).contains("X-LampBoard-Host"), "a local script carries no host")
        },

        TestCase("The remote port is the user's, and both sides compute it the same way") { t in
            t.expectEqual(AppConfig.remotePort(forUID: 1000), 31000, "uid 1000")
            t.expectEqual(AppConfig.remotePort(forUID: 0), 30000, "root, should anyone")
            t.expectEqual(AppConfig.remotePort(forUID: 21000), 31000, "wraps inside the range")
            t.expect(
                RemoteInstallScripts.prepareTunnel.contains("30000 + max(uid, 0) % 20000"),
                "the Python formula must stay textually identical to AppConfig.remotePort"
            )
        },

        // The boundary that keeps "any process on your machine can start a turn in
        // your voice" (D15) from extending to every process on the node.
        TestCase("The remote merge registers no message delivery") { t in
            let merged = HookConfigMerger.install(
                into: [:], scriptPath: "/home/dev/.lampboard/hook.sh",
                rewakeScriptPath: nil, registerMessageDelivery: false
            )
            let hooks = (merged["hooks"] as? [String: Any]) ?? [:]
            let stop = (hooks["Stop"] as? [[String: Any]]) ?? []
            t.expectEqual(stop.count, 1, "one Stop group: the traffic light's")
            let text = String(decoding: try! JSONSerialization.data(withJSONObject: merged), as: UTF8.self)
            t.expect(!text.contains("asyncRewake") && !text.contains("rewake"), "no rewake anywhere in the remote settings")
        },
    ])
}
