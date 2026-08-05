import Foundation

/// Adds and removes the clawd-light hooks inside `~/.claude/settings.json`
/// without touching the rest of the user's configuration.
///
/// It works on dictionaries, not on files: the I/O lives in the app shell, so
/// this logic — which modifies an important user file — stays verifiable.
public enum HookConfigMerger {

    /// Events registered by default.
    ///
    /// These are the edges of the turn plus the subagent ones: the whole traffic
    /// light state is derived from them, at a cost of a handful of `curl` calls
    /// per turn rather than one per tool call.
    ///
    /// The two subagent events cost in proportion to the **number of agents**, not
    /// to tool calls: a thirty-three agent workflow is sixty-six requests over
    /// three quarters of an hour, against the thousands `PreToolUse` would produce.
    /// That is the price of not showing green for a session still working in the
    /// background.
    public static let defaultEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "Notification",
        "Stop",
        "StopFailure",
        "SessionEnd",
        "SubagentStart",
        "SubagentStop",
    ]

    /// Extra events for anyone who wants yellow mid-turn as well.
    /// They cost one process spawn for every single tool call.
    public static let toolEvents = ["PreToolUse", "PostToolUse"]

    /// Hook timeout, in seconds. Twice curl's `--max-time`.
    static let hookTimeout = 3

    // MARK: - Installation

    /// Returns a copy of `settings` with the clawd-light hooks registered.
    /// Hooks already present for the same events are preserved.
    ///
    /// - Parameter rewakeScriptPath: when given, a **second** `Stop` hook is
    ///   registered for the chat window's message delivery. It is separate from
    ///   the traffic light hook on purpose: that one must return in milliseconds,
    ///   this one waits for minutes, and putting both behaviours in one script
    ///   would mean the traffic light inherits the waiting.
    public static func install(
        into settings: [String: Any],
        scriptPath: String,
        rewakeScriptPath: String? = nil,
        events: [String] = defaultEvents
    ) -> [String: Any] {
        // Clean up any previous installation first, so that changing the event
        // list doesn't leave orphaned registrations behind.
        var result = uninstall(
            from: settings, scriptPaths: [scriptPath, rewakeScriptPath].compactMap { $0 }
        )
        var hooks = (result["hooks"] as? [String: Any]) ?? [:]

        for event in events {
            let existing = (hooks[event] as? [[String: Any]]) ?? []
            hooks[event] = existing + [matcherGroup(scriptPath: scriptPath)]
        }

        if let rewakeScriptPath, events.contains("Stop") {
            let existing = (hooks["Stop"] as? [[String: Any]]) ?? []
            hooks["Stop"] = existing + [rewakeGroup(scriptPath: rewakeScriptPath)]
        }

        result["hooks"] = hooks
        return result
    }

    /// Returns a copy of `settings` with no hook pointing at `scriptPath`.
    public static func uninstall(from settings: [String: Any], scriptPath: String) -> [String: Any] {
        uninstall(from: settings, scriptPaths: [scriptPath])
    }

    /// Returns a copy of `settings` with no hook pointing at any of `scriptPaths`.
    public static func uninstall(
        from settings: [String: Any], scriptPaths: [String]
    ) -> [String: Any] {
        var result = settings
        guard let hooks = result["hooks"] as? [String: Any] else { return result }

        let doomed = Set(scriptPaths)
        var cleaned: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                cleaned[event] = value
                continue
            }
            let survivors = groups.compactMap { group -> [String: Any]? in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let kept = entries.filter { entry in
                    guard let command = entry["command"] as? String else { return true }
                    return !doomed.contains(command)
                }
                if kept.isEmpty { return nil }
                var updated = group
                updated["hooks"] = kept
                return updated
            }
            if !survivors.isEmpty {
                cleaned[event] = survivors
            }
        }

        if cleaned.isEmpty {
            result.removeValue(forKey: "hooks")
        } else {
            result["hooks"] = cleaned
        }
        return result
    }

    /// `true` when at least one hook already points at `scriptPath`.
    public static func isInstalled(in settings: [String: Any], scriptPath: String) -> Bool {
        installedEvents(in: settings, scriptPath: scriptPath).isEmpty == false
    }

    /// Events for which `scriptPath` is registered, in alphabetical order.
    public static func installedEvents(in settings: [String: Any], scriptPath: String) -> [String] {
        guard let hooks = settings["hooks"] as? [String: Any] else { return [] }

        let events = hooks.compactMap { event, value -> String? in
            guard let groups = value as? [[String: Any]] else { return nil }
            let found = groups.contains { group in
                guard let entries = group["hooks"] as? [[String: Any]] else { return false }
                return entries.contains { ($0["command"] as? String) == scriptPath }
            }
            return found ? event : nil
        }
        return events.sorted()
    }

    // MARK: - Helpers

    private static func matcherGroup(scriptPath: String) -> [String: Any] {
        [
            "hooks": [
                [
                    "type": "command",
                    "command": scriptPath,
                    "timeout": hookTimeout,
                ] as [String: Any]
            ]
        ]
    }

    /// The message-delivery hook.
    ///
    /// Deliberately carries **no `timeout`**. `asyncRewake` puts the hook on a
    /// detached path that never registers one, and adding the key would be a
    /// statement about a mechanism we do not control — the sort of thing that
    /// looks harmless until a release starts honouring it and every listener is
    /// killed three seconds in.
    private static func rewakeGroup(scriptPath: String) -> [String: Any] {
        [
            "hooks": [
                [
                    "type": "command",
                    "command": scriptPath,
                    "asyncRewake": true,
                    "rewakeMessage": Mailbox.rewakePreamble,
                    "rewakeSummary": Mailbox.rewakeSummary,
                ] as [String: Any]
            ]
        ]
    }
}
