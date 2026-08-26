import ClawdLightCore
import Foundation
import TestKit

/// The sixth state: the turn is over, and something Claude started is still
/// running and will wake it.
///
/// Yellow said "Claude is working". After a `Stop` with a monitor on a CI run and a
/// shell serving the tests, Claude is not working: it has stopped, and it is
/// **waiting** — for an event that will start a new turn. Painting that yellow
/// was a half-truth, and a half-truth that lasted an hour per CI run reads as a
/// defect. This state says exactly what the payload says: *"session is paused
/// waiting for background work to wake it"*.
enum WaitingSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private static let workspace = Workspace(path: "/dev/project")

    private static func signal(
        _ event: HookEventKind, agentId: String? = nil, inFlight: [String] = []
    ) -> HookSignal {
        HookSignal(
            sessionId: "s1", event: event, cwd: "/dev/project", agentId: agentId,
            entrypoint: "claude-vscode", inFlightBackgroundTaskTypes: inFlight
        )
    }

    private static func apply(_ signals: [HookSignal]) -> SessionState? {
        signals.reduce(TrafficLightState.empty) { current, signal in
            StateReducer.reduce(current, action: .signal(signal, workspace: workspace), now: t0)
        }.sessions["s1"]
    }

    static let suite = TestSuite("Waiting on background work", [

        // The case from the log: Stop with inFlight=3[monitor,monitor,shell].
        TestCase("A turn that ends with work still running is waiting, not working") { t in
            let s = apply([signal(.userPromptSubmit), signal(.stop, inFlight: ["monitor", "monitor", "shell"])])
            t.expectEqual(s?.status, .waiting, "Claude has stopped; the light must not say it is working")
            t.expectEqual(s?.baseStatus, .waiting, "declared, not derived")
        },

        TestCase("The row remembers what it is waiting on") { t in
            let s = apply([signal(.userPromptSubmit), signal(.stop, inFlight: ["monitor", "monitor", "shell"])])
            t.expectEqual(s?.waitingOn, ["monitor", "monitor", "shell"], "the types, in Claude Code's order")
        },

        TestCase("Housekeeping alone is not a wait") { t in
            t.expectEqual(apply([signal(.userPromptSubmit), signal(.stop, inFlight: ["dream"])])?.status, .ready, "status")
        },

        TestCase("A clean turn is still green") { t in
            let s = apply([signal(.userPromptSubmit), signal(.stop)])
            t.expectEqual(s?.status, .ready, "status")
            t.expectEqual(s?.waitingOn, [], "nothing to wait on")
        },

        // The wake-up: the shell finishes, Claude Code starts a turn to report it.
        TestCase("The wake-up turn puts it back to work and forgets the wait") { t in
            let s = apply([
                signal(.userPromptSubmit), signal(.stop, inFlight: ["shell"]),
                signal(.userPromptSubmit),
            ])
            t.expectEqual(s?.status, .working, "status")
            t.expectEqual(s?.waitingOn, [], "a new turn starts from nothing")
        },

        TestCase("And when that turn ends clean, green") { t in
            let s = apply([
                signal(.userPromptSubmit), signal(.stop, inFlight: ["shell"]),
                signal(.userPromptSubmit), signal(.stop),
            ])
            t.expectEqual(s?.status, .ready, "status")
        },

        // A wake-up always begins with a prompt, so a tool event with no prompt
        // before it is the tail of the turn that already closed.
        TestCase("A trailing tool event does not disturb the wait") { t in
            let s = apply([signal(.userPromptSubmit), signal(.stop, inFlight: ["shell"]), signal(.postToolUse)])
            t.expectEqual(s?.status, .waiting, "status")
        },

        // MARK: Subagents

        TestCase("A turn that ends with a subagent still running is waiting") { t in
            let s = apply([
                signal(.userPromptSubmit), signal(.subagentStart, agentId: "a1"),
                signal(.stop, inFlight: ["subagent"]),
            ])
            t.expectEqual(s?.status, .waiting, "displayed")
            t.expectEqual(s?.activeSubagents, 1, "counter")
        },

        // The counter used to paint yellow over any base state. A subagent alive
        // after the parent's Stop is a session waiting, not one working.
        TestCase("A subagent outliving a clean Stop makes the row wait, not work") { t in
            let s = apply([signal(.userPromptSubmit), signal(.subagentStart, agentId: "a1"), signal(.stop)])
            t.expectEqual(s?.status, .waiting, "displayed")
            t.expectEqual(s?.baseStatus, .ready, "the green is set aside, not lost")
        },

        // A background agent launched at the end of a turn sends its start
        // *after* the parent's Stop. That row has stopped; it is waiting, and a
        // first draft that painted it yellow was caught by an older test.
        TestCase("A subagent starting after the Stop is a background agent: the row waits") { t in
            let s = apply([signal(.userPromptSubmit), signal(.stop), signal(.subagentStart, agentId: "a1")])
            t.expectEqual(s?.status, .waiting, "displayed")
            t.expectEqual(s?.baseStatus, .ready, "the green is set aside underneath")
        },

        TestCase("A pending permission still beats everything") { t in
            let s = apply([
                signal(.userPromptSubmit), signal(.stop, inFlight: ["shell"]),
                HookSignal(sessionId: "s1", event: .notification, cwd: "/dev/project",
                           notificationKind: .permissionPrompt, entrypoint: "claude-vscode"),
            ])
            t.expectEqual(s?.status, .awaiting, "status")
        },

        // MARK: The state's own properties

        TestCase("Waiting is calm: no blink, nothing unread, but it does resist a trailing signal") { t in
            t.expect(!SessionStatus.waiting.shouldBlink, "blinking is spent on awaiting only")
            t.expect(!SessionStatus.waiting.clearsOnFocus, "a click has nothing to clear")
            t.expect(SessionStatus.waiting.blocksDowngrade, "a trailing PostToolUse must not repaint it yellow")
        },

        TestCase("It sits below working and above idle") { t in
            t.expect(SessionStatus.working.urgencyRank < SessionStatus.waiting.urgencyRank, "working first")
            t.expect(SessionStatus.waiting.urgencyRank < SessionStatus.idle.urgencyRank, "idle last")
        },

        TestCase("A click on a waiting row changes nothing") { t in
            let state = [signal(.userPromptSubmit), signal(.stop, inFlight: ["shell"])].reduce(TrafficLightState.empty) {
                StateReducer.reduce($0, action: .signal($1, workspace: workspace), now: t0)
            }
            let clicked = StateReducer.reduce(state, action: .markSeen(sessionId: "s1"), now: t0)
            t.expectEqual(clicked.sessions["s1"]?.status, .waiting, "the wait is a fact about the session, not about you")
        },
    ])
}
