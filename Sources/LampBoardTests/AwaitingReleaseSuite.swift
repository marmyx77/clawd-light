import LampBoardCore
import Foundation
import TestKit

/// When a question has been answered, the row must stop asking.
///
/// `awaiting` is the one state that overrides everything else, subagents included:
/// a permission prompt blocks the turn and needs the user *now*. That is right
/// while the prompt is open and wrong the moment it is answered — and nothing in
/// the hook stream says "answered".
///
/// Measured on a real session (`debug.log`, 22 Aug): a permission prompt at
/// 08:48:27 put the row amber; fifteen subagent events over the following
/// thirty-three minutes left it amber; only the user's *next prompt*, at 09:21:48,
/// released it. Work had plainly resumed — subagents were being spawned — and the
/// column kept flashing at somebody who had already answered.
enum AwaitingReleaseSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private static let workspace = Workspace(path: "/dev/project")

    private static func signal(
        _ event: HookEventKind,
        notification: NotificationKind? = nil,
        agentId: String? = nil
    ) -> HookSignal {
        HookSignal(
            sessionId: "s1",
            event: event,
            cwd: "/dev/project",
            notificationKind: notification,
            agentId: agentId,
            entrypoint: "claude-vscode"
        )
    }

    private static func apply(_ signals: [HookSignal]) -> SessionStatus? {
        signals.reduce(TrafficLightState.empty) { current, signal in
            StateReducer.reduce(
                current, action: .signal(signal, workspace: workspace), now: t0
            )
        }.sessions["s1"]?.status
    }

    /// The prompt, opened.
    private static let asking: [HookSignal] = [
        signal(.userPromptSubmit),
        signal(.notification, notification: .permissionPrompt),
    ]

    static let suite = TestSuite("Releasing an answered question", [

        TestCase("A permission prompt still raises the question") { t in
            t.expectEqual(apply(asking), .awaiting, "status")
        },

        // The case from the log. A subagent cannot be spawned by a main loop that
        // is blocked on a prompt, so its birth is proof the prompt was answered.
        TestCase("A subagent starting proves the answer arrived") { t in
            t.expectEqual(
                apply(asking + [signal(.subagentStart, agentId: "a1")]),
                .working,
                "a subagent cannot start while the turn is blocked"
            )
        },

        // A subagent that was already running when the prompt opened can finish
        // while the turn is still blocked. Its death proves nothing.
        TestCase("A subagent finishing proves nothing on its own") { t in
            t.expectEqual(
                apply(asking + [signal(.subagentStop, agentId: "a1")]),
                .awaiting,
                "the question is still open"
            )
        },

        TestCase("A tool completing releases the question") { t in
            t.expectEqual(
                apply(asking + [signal(.postToolUse)]),
                .working,
                "a tool that ran is a permission that was granted"
            )
        },

        // But a tool *starting* does not, and the asymmetry is not fussiness.
        // `PreToolUse` carries `permissionDecision` in its own output schema: it
        // runs inside the permission decision, therefore before the prompt. One
        // arriving after the prompt is out of order, and releasing on it would
        // clear a question that is still open.
        TestCase("A tool starting does not release it") { t in
            t.expectEqual(
                apply(asking + [signal(.preToolUse)]),
                .awaiting,
                "PreToolUse runs before the prompt, not after the answer"
            )
        },

        // The rule that protects `ready` from a trailing PostToolUse must survive
        // untouched: that one is about an answer waiting to be read, and a late
        // signal from the closed turn must not erase it.
        TestCase("Green still resists a trailing tool event") { t in
            t.expectEqual(
                apply([signal(.userPromptSubmit), signal(.stop), signal(.postToolUse)]),
                .ready,
                "the waiting answer must not be erased"
            )
        },

        TestCase("A cut-short turn still resists one too") { t in
            let state = [
                signal(.userPromptSubmit),
                HookSignal(
                    sessionId: "s1", event: .stopFailure, cwd: "/dev/project",
                    entrypoint: "claude-vscode", failureReason: .rateLimit
                ),
                signal(.postToolUse),
            ]
            t.expectEqual(apply(state), .failed, "the cause of the error must survive")
        },

        // Two prompts in a row: the second must not be swallowed by the release
        // rule of the first.
        TestCase("A second question still raises the row") { t in
            t.expectEqual(
                apply(asking + [
                    signal(.postToolUse),
                    signal(.notification, notification: .permissionPrompt),
                ]),
                .awaiting,
                "status"
            )
        },

        TestCase("Waiting for input behaves the same as a permission prompt") { t in
            let ask = [signal(.userPromptSubmit), signal(.notification, notification: .agentNeedsInput)]
            t.expectEqual(apply(ask), .awaiting, "raised")
            t.expectEqual(apply(ask + [signal(.postToolUse)]), .working, "released")
        },
    ])
}
