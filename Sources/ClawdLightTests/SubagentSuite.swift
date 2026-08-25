import ClawdLightCore
import Foundation
import TestKit

/// The subagent counter and the derived state that follows from it.
enum SubagentSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private static let workspace = Workspace(path: "/dev/project")

    private static func signal(
        _ event: HookEventKind,
        session: String = "s1",
        agentId: String? = nil
    ) -> HookSignal {
        HookSignal(
            sessionId: session,
            event: event,
            cwd: "/dev/project",
            agentId: agentId,
            entrypoint: "claude-vscode"
        )
    }

    private static func apply(
        _ signals: [HookSignal],
        to state: TrafficLightState = .empty
    ) -> TrafficLightState {
        signals.reduce(state) { current, signal in
            StateReducer.reduce(
                current, action: .signal(signal, workspace: workspace), now: t0
            )
        }
    }

    static let suite = TestSuite("Subagents", [

        // MARK: Counter

        TestCase("A start increments and puts the session to work") { t in
            let state = apply([signal(.subagentStart, agentId: "a1")])
            t.expectEqual(state.sessions["s1"]?.activeSubagents, 1, "counter")
            t.expectEqual(state.sessions["s1"]?.status, .working, "status")
        },

        TestCase("Three starts count three") { t in
            let state = apply([
                signal(.subagentStart, agentId: "a1"),
                signal(.subagentStart, agentId: "a2"),
                signal(.subagentStart, agentId: "a3"),
            ])
            t.expectEqual(state.sessions["s1"]?.activeSubagents, 3, "counter")
        },

        TestCase("A stop decrements") { t in
            let state = apply([
                signal(.subagentStart, agentId: "a1"),
                signal(.subagentStart, agentId: "a2"),
                signal(.subagentStop, agentId: "a1"),
            ])
            t.expectEqual(state.sessions["s1"]?.activeSubagents, 1, "counter")
        },

        TestCase("The counter never goes below zero") { t in
            let state = apply([
                signal(.stop),
                signal(.subagentStop, agentId: "ghost"),
                signal(.subagentStop, agentId: "ghost-2"),
            ])
            // This happens when the app starts mid-turn and only sees the stops.
            t.expectEqual(state.sessions["s1"]?.activeSubagents, 0, "counter")
        },

        TestCase("A stop does not create a row out of nothing") { t in
            let state = apply([signal(.subagentStop, agentId: "a1")])
            t.expectEqual(state.sessions.count, 0, "sessions")
        },

        // MARK: Derived state

        TestCase("The turn ending doesn't clear the yellow while an agent works") { t in
            let state = apply([
                signal(.userPromptSubmit),
                signal(.subagentStart, agentId: "a1"),
                signal(.stop),
            ])
            // This is the background-agent case: `Stop` arrives when the parent
            // turn returns control, not when the work finishes.
            t.expectEqual(state.sessions["s1"]?.status, .working, "displayed status")
            t.expectEqual(state.sessions["s1"]?.baseStatus, .ready, "declared status")
        },

        TestCase("When the last agent finishes the green resurfaces") { t in
            let state = apply([
                signal(.userPromptSubmit),
                signal(.subagentStart, agentId: "a1"),
                signal(.stop),
                signal(.subagentStop, agentId: "a1"),
            ])
            // Nobody had to remember the green: the state is derived.
            t.expectEqual(state.sessions["s1"]?.status, .ready, "status")
        },

        TestCase("A pending permission beats the subagents") { t in
            let state = apply([
                signal(.subagentStart, agentId: "a1"),
                HookSignal(
                    sessionId: "s1",
                    event: .notification,
                    cwd: "/dev/project",
                    notificationKind: .permissionPrompt,
                    entrypoint: "claude-vscode"
                ),
            ])
            // It blocks everything, subagents included, and it needs you now.
            t.expectEqual(state.sessions["s1"]?.status, .awaiting, "status")
        },

        // MARK: Interaction with the other rules

        TestCase("A new prompt clears a counter left hanging") { t in
            let state = apply([
                signal(.subagentStart, agentId: "a1"),
                signal(.subagentStart, agentId: "a2"),
                signal(.userPromptSubmit),
            ])
            t.expectEqual(state.sessions["s1"]?.activeSubagents, 0, "counter")
            t.expectEqual(state.sessions["s1"]?.status, .working, "status")
        },

        TestCase("A late signal does not erase the green set aside") { t in
            let state = apply([
                signal(.stop),
                signal(.subagentStart, agentId: "a1"),
                signal(.postToolUse),
                signal(.subagentStop, agentId: "a1"),
            ])
            // The `PostToolUse` arrives while the row *appears* yellow: if the
            // protection looked at the appearance instead of the declared state,
            // the green would vanish without ever being read.
            t.expectEqual(state.sessions["s1"]?.status, .ready, "status")
        },

        TestCase("A subagent's other events stay ignored") { t in
            let state = apply([
                signal(.stop),
                signal(.preToolUse, agentId: "a1"),
            ])
            t.expectEqual(state.sessions["s1"]?.status, .ready, "status")
            t.expectEqual(state.sessions["s1"]?.activeSubagents, 0, "counter")
        },

        TestCase("A late signal does not erase the cause of an error") { t in
            let state = apply([
                HookSignal(
                    sessionId: "s1",
                    event: .stopFailure,
                    cwd: "/dev/project",
                    entrypoint: "claude-vscode",
                    failureReason: .rateLimit
                ),
                signal(.postToolUse),
            ])
            // The `PostToolUse` is the tail of the turn that was just cut short,
            // not a restart: taking it at face value painted a session yellow
            // when it wasn't working at all, and erased the reason it stopped.
            t.expectEqual(state.sessions["s1"]?.status, .failed, "status")
            t.expectEqual(state.sessions["s1"]?.failureReason, .rateLimit, "reason")
        },

        TestCase("A new prompt, on the other hand, restarts a failed session") { t in
            let state = apply([
                HookSignal(
                    sessionId: "s1",
                    event: .stopFailure,
                    cwd: "/dev/project",
                    entrypoint: "claude-vscode",
                    failureReason: .rateLimit
                ),
                signal(.userPromptSubmit),
            ])
            // Here yellow is the correct information and red would be a leftover:
            // `failed` has to yield to a genuine restart.
            t.expectEqual(state.sessions["s1"]?.status, .working, "status")
            t.expectNil(state.sessions["s1"]?.failureReason, "reason")
        },

        TestCase("The session ending removes the row even with active agents") { t in
            let state = apply([
                signal(.subagentStart, agentId: "a1"),
                signal(.sessionEnd),
            ])
            t.expectEqual(state.sessions.count, 0, "sessions")
        },
    ])
}
