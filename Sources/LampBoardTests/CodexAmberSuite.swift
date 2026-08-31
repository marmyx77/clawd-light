import LampBoardCore
import Foundation
import TestKit

/// Amber is for a turn a person is blocking, on both harnesses.
///
/// Codex asks for approval of a tool call whether a person or its own reviewer
/// will answer, and the event does not say which. Measured during one audit:
/// three requests answered automatically kept a row blinking amber for 6.0 s,
/// 6.4 s and 31.0 s, because amber lifts at `PostToolUse` — when the command
/// ends, not when the approval lands. D34 says a Codex row carries the same six
/// meanings as a Claude Code one; this is what makes that true of amber.
enum CodexAmberSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let workspace = Workspace(path: "/dev/project")

    private static func request(reviewer: ApprovalReviewer?) -> HookSignal {
        HookSignal(
            sessionId: "s1",
            event: .permissionRequest,
            cwd: "/dev/project",
            entrypoint: "codex-chatgptApp",
            harness: .codex,
            approvalReviewer: reviewer
        )
    }

    private static func working() -> HookSignal {
        HookSignal(
            sessionId: "s1", event: .userPromptSubmit, cwd: "/dev/project",
            entrypoint: "codex-chatgptApp", harness: .codex
        )
    }

    private static func status(after signals: [HookSignal]) -> SessionStatus? {
        signals.reduce(TrafficLightState.empty) { current, signal in
            StateReducer.reduce(current, action: .signal(signal, workspace: workspace), now: t0)
        }.sessions["s1"]?.status
    }

    static let suite = TestSuite("Amber only when somebody is waiting", [

        TestCase("A request its own reviewer will answer leaves the row working") { t in
            t.expectEqual(
                status(after: [working(), request(reviewer: .automatic)]), .working,
                "nobody is waiting, so nothing blinks: asking itself for permission is work"
            )
        },

        TestCase("A request a person has to answer still turns the row amber") { t in
            t.expectEqual(
                status(after: [working(), request(reviewer: .person)]), .awaiting,
                "the turn really is blocked, and this is the state that says so"
            )
        },

        TestCase("A rollout that did not say shows the request rather than hiding it") { t in
            // The format is undocumented. An absent answer is an absence of
            // information, and the safe reading of it is the one that costs a
            // glance instead of a turn stopped without anybody knowing.
            t.expectEqual(
                status(after: [working(), request(reviewer: nil)]), .awaiting,
                "not knowing shows the question"
            )
        },

        TestCase("The exemption is Codex's own, and does not reach Claude Code") { t in
            // Claude Code has no automatic reviewer and never sets this field. If
            // the guard were written on the event alone it would swallow a real
            // permission prompt on the other harness.
            let claude = HookSignal(
                sessionId: "s2", event: .notification, cwd: "/dev/project",
                notificationKind: .permissionPrompt, entrypoint: "claude-vscode"
            )
            let state = StateReducer.reduce(
                .empty, action: .signal(claude, workspace: workspace), now: t0
            )
            t.expectEqual(
                state.sessions["s2"]?.status, .awaiting,
                "Claude Code's prompt is untouched by any of this"
            )
        },
    ])
}
