import ClawdLightCore
import Foundation
import TestKit

enum HookConfigMergerSuite {

    private static let scriptPath = "/Users/dev/.clawd-light/hook.sh"

    /// A realistic settings.json: it already holds user configuration that the
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
            t.expect(commands.contains(scriptPath), "clawd-light hook missing")
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
                "the clawd-light hooks are still there"
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
    ])
}
