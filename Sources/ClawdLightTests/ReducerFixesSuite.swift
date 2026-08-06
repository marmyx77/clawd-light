import ClawdLightCore
import Foundation
import TestKit

/// Regressions for the five corrections that came out of the signal audit.
/// Each case describes the situation in which the column used to state a falsehood.
enum ReducerFixesSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let workspace = Workspace(path: "/Users/dev/Development/clawd-light")
    private static let sessionId = "sess-1"

    private static func signal(
        _ event: HookEventKind,
        notification: NotificationKind? = nil,
        source: String? = nil,
        failure: String? = nil,
        message: String? = nil
    ) -> HookSignal {
        HookSignal(
            sessionId: sessionId,
            event: event,
            cwd: workspace.path,
            notificationKind: notification,
            entrypoint: "claude-vscode",
            lastAssistantMessage: message,
            sessionSource: source,
            failureReason: failure.map { StopFailureReason.from(rawValue: $0) }
        )
    }

    private static func apply(
        _ signals: [HookSignal],
        to state: TrafficLightState = .empty,
        at date: Date? = nil
    ) -> TrafficLightState {
        signals.reduce(state) { partial, signal in
            StateReducer.reduce(
                partial, action: .signal(signal, workspace: workspace), now: date ?? t0
            )
        }
    }

    private static func session(_ state: TrafficLightState) -> SessionState? {
        state.sessions[sessionId]
    }

    static let suite = TestSuite("State machine corrections", [

        // MARK: StopFailure — a dead turn is not an answer

        TestCase("A turn that was cut down does not go green") { t in
            let state = apply([
                signal(.userPromptSubmit),
                signal(.stopFailure, failure: "rate_limit", message: "API Error: Rate limit reached"),
            ])
            t.expectEqual(session(state)?.status, .failed)
            t.expectEqual(session(state)?.failureReason, .rateLimit)
        },

        TestCase("With no declared cause it is still a failure") { t in
            let state = apply([signal(.userPromptSubmit), signal(.stopFailure)])
            t.expectEqual(session(state)?.status, .failed)
            t.expectEqual(session(state)?.failureReason, .unknown)
        },

        // The one exception: the text is there and it's worth reading.
        TestCase("Truncation by length is still an answer to read") { t in
            let state = apply([
                signal(.userPromptSubmit),
                signal(.stopFailure, failure: "max_output_tokens", message: "…"),
            ])
            t.expectEqual(session(state)?.status, .ready)
        },

        TestCase("A failed turn clears on click") { t in
            let state = StateReducer.reduce(
                apply([signal(.stopFailure, failure: "overloaded")]),
                action: .markSeen(sessionId: sessionId),
                now: t0
            )
            t.expectEqual(session(state)?.status, .idle)
        },

        // Unlike green and amber, a failure does not block a restart.
        TestCase("A turn that resumes leaves the error red") { t in
            let state = apply([
                signal(.stopFailure, failure: "overloaded"),
                signal(.userPromptSubmit),
            ])
            t.expectEqual(session(state)?.status, .working)
        },

        // MARK: idle_prompt — it's a timer, not an answer

        TestCase("The inactivity timer does not invent an answer") { t in
            let state = apply([
                signal(.userPromptSubmit),
                signal(.notification, notification: .idlePrompt),
            ])
            t.expectEqual(session(state)?.status, .working)
        },

        TestCase("The inactivity timer does not rejuvenate the timestamp") { t in
            let before = apply([signal(.stop)], at: t0)
            let after = apply(
                [signal(.notification, notification: .idlePrompt)],
                to: before,
                at: t0.addingTimeInterval(3600)
            )
            t.expectEqual(session(after)?.status, .ready, "status")
            t.expectEqual(session(after)?.updatedAt, t0, "updatedAt")
            t.expectEqual(session(after)?.statusSince, t0, "statusSince")
        },

        TestCase("The timer does not clear a blinking amber") { t in
            let state = apply([
                signal(.notification, notification: .permissionPrompt),
                signal(.notification, notification: .idlePrompt),
            ])
            t.expectEqual(session(state)?.status, .awaiting)
        },

        // If the row doesn't exist, discovering it as idle beats not seeing it.
        TestCase("On an unknown session the timer creates an idle row") { t in
            let state = apply([signal(.notification, notification: .idlePrompt)])
            t.expectEqual(session(state)?.status, .idle)
        },

        // MARK: SessionStart(compact) — it fires mid-turn

        TestCase("Compaction does not clear the yellow") { t in
            let state = apply([
                signal(.userPromptSubmit),
                signal(.sessionStart, source: "compact"),
            ])
            t.expectEqual(session(state)?.status, .working)
        },

        TestCase("Compaction does not even touch the stopwatches") { t in
            let before = apply([signal(.userPromptSubmit)], at: t0)
            let after = apply(
                [signal(.sessionStart, source: "compact")],
                to: before,
                at: t0.addingTimeInterval(600)
            )
            t.expectEqual(session(after)?.statusSince, t0, "statusSince")
            t.expectEqual(session(after)?.updatedAt, t0, "updatedAt")
        },

        TestCase("Compaction does not clear an answer waiting to be read") { t in
            let state = apply([signal(.stop), signal(.sessionStart, source: "compact")])
            t.expectEqual(session(state)?.status, .ready)
        },

        TestCase("Compaction creates no rows out of nothing") { t in
            t.expectEqual(apply([signal(.sessionStart, source: "compact")]).sessions.count, 0)
        },

        TestCase("The other startups are unchanged") { t in
            t.expectEqual(session(apply([signal(.sessionStart)]))?.status, .idle, "no source")
            t.expectEqual(
                session(apply([signal(.sessionStart, source: "startup")]))?.status, .idle, "startup"
            )
            t.expectEqual(
                session(apply([signal(.sessionStart, source: "resume")]))?.status, .idle, "resume"
            )
        },

        // MARK: MCP dialog — it blocks as much as a permission request

        TestCase("An MCP dialog puts the session into waiting") { t in
            let state = apply([
                signal(.userPromptSubmit),
                signal(.notification, notification: .elicitationDialog),
            ])
            t.expectEqual(session(state)?.status, .awaiting)
            t.expectEqual(session(state)?.status.shouldBlink, true, "must blink")
        },

        // MARK: The immortal yellow — Stop doesn't fire if you interrupt with Esc

        TestCase("An abandoned yellow does not survive pruning") { t in
            let state = apply([signal(.userPromptSubmit)], at: t0)
            let later = t0.addingTimeInterval(AppConfig.sessionStaleAfter + 1)

            t.expectEqual(StateReducer.reduce(state, action: .prune(), now: later).sessions.count, 0)
        },

        TestCase("A long but live turn survives pruning") { t in
            let state = apply([signal(.userPromptSubmit)], at: t0)
            let soon = t0.addingTimeInterval(AppConfig.sessionStaleAfter - 60)

            t.expectEqual(StateReducer.reduce(state, action: .prune(), now: soon).sessions.count, 1)
        },
    ])
}

enum OrderingSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private static func session(
        _ id: String, _ status: SessionStatus, workspace: String, since: TimeInterval
    ) -> SessionState {
        SessionState(
            id: id,
            status: status,
            workspace: Workspace(path: workspace),
            updatedAt: t0.addingTimeInterval(since),
            statusSince: t0.addingTimeInterval(since)
        )
    }

    private static func state(_ sessions: [SessionState]) -> TrafficLightState {
        TrafficLightState(sessions: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) }))
    }

    static let suite = TestSuite("Column ordering", [

        TestCase("Urgency comes before everything") { t in
            let ordered = state([
                session("a", .idle, workspace: "/dev/a", since: 0),
                session("b", .working, workspace: "/dev/b", since: 0),
                session("c", .failed, workspace: "/dev/c", since: 0),
                session("d", .ready, workspace: "/dev/d", since: 0),
                session("e", .awaiting, workspace: "/dev/e", since: 0),
            ]).ordered

            t.expectEqual(ordered.map(\.status), [.awaiting, .ready, .failed, .working, .idle])
        },

        // Between two that are waiting, the one waiting longest rises — not the
        // one with the alphabetically luckier name.
        TestCase("For equal states the longest wait rises") { t in
            let ordered = state([
                session("1", .awaiting, workspace: "/dev/alpha", since: 300),
                session("2", .awaiting, workspace: "/dev/zulu", since: 0),
            ]).ordered

            t.expectEqual(ordered.map(\.workspace.name), ["zulu", "alpha"])
        },

        TestCase("For equal waits the order stays stable") { t in
            let ordered = state([
                session("1", .ready, workspace: "/dev/zulu", since: 0),
                session("2", .ready, workspace: "/dev/alpha", since: 0),
            ]).ordered

            t.expectEqual(ordered.map(\.workspace.name), ["alpha", "zulu"])
        },

        TestCase("A failed turn counts among the ones to look at") { t in
            let subject = state([
                session("a", .failed, workspace: "/dev/a", since: 0),
                session("b", .idle, workspace: "/dev/b", since: 0),
            ])
            t.expectEqual(subject.unseenCount, 1)
        },
    ])
}

/// A session you can see running is never pruned for being quiet.
///
/// The defect: the file a session's age was read from is written once at startup
/// and never touched again. A session opened a week ago and working right now
/// reported a week of silence, pruning removed it, and the traffic light went dark
/// on exactly the session it exists to show.
enum LivePruningSuite {

    private static let workspace = Workspace(path: "/dev/project")

    private static func ancient(_ id: String, now: Date) -> SessionState {
        SessionState(
            id: id,
            status: .idle,
            workspace: workspace,
            // Seven days, which is what a week-old session file really reports.
            updatedAt: now.addingTimeInterval(-7 * 24 * 3600),
            statusSince: now.addingTimeInterval(-7 * 24 * 3600)
        )
    }

    static let suite = TestSuite("Pruning and liveness", [

        TestCase("A live process survives however old its last signal looks") { t in
            let now = Date()
            let state = TrafficLightState(sessions: ["alive": ancient("alive", now: now)])
            let after = StateReducer.reduce(
                state, action: .prune(alive: ["alive"]), now: now
            )
            t.expectEqual(after.sessions.count, 1, "a session we can see must not be pruned")
        },

        TestCase("Without that proof, age still wins") { t in
            let now = Date()
            let state = TrafficLightState(sessions: ["gone": ancient("gone", now: now)])
            let after = StateReducer.reduce(state, action: .prune(), now: now)
            t.expect(after.sessions.isEmpty, "an unaccounted-for session still goes")
        },

        TestCase("Liveness protects only the ones named") { t in
            let now = Date()
            let state = TrafficLightState(sessions: [
                "alive": ancient("alive", now: now),
                "dead": ancient("dead", now: now),
            ])
            let after = StateReducer.reduce(
                state, action: .prune(alive: ["alive"]), now: now
            )
            t.expectEqual(Array(after.sessions.keys), ["alive"], "survivors")
        },

        TestCase("A recent session needs no protection") { t in
            let now = Date()
            let fresh = SessionState(
                id: "fresh", status: .working, workspace: workspace,
                updatedAt: now, statusSince: now
            )
            let state = TrafficLightState(sessions: ["fresh": fresh])
            t.expectEqual(
                StateReducer.reduce(state, action: .prune(), now: now).sessions.count, 1,
                "survives"
            )
        },
    ])
}

/// A turn that ends with shells still running has not finished the work.
///
/// The same lie as green-during-subagents, arriving by a different door: the
/// session writes its recap, hands control back, and a background shell carries on
/// for minutes. Green claims two things — there is something to read, and nothing
/// more is coming — and the second half is false.
///
/// Examined on the first day and deliberately left alone, on the reasoning that
/// the turn had genuinely ended. Use overruled the reasoning.
enum BackgroundTaskSuite {

    private static let workspace = Workspace(path: "/dev/project")

    private static func stop(runningTasks: Int) -> HookSignal {
        HookSignal(
            sessionId: "s1",
            event: .stop,
            cwd: "/dev/project",
            entrypoint: "claude-vscode",
            lastAssistantMessage: "here is the recap",
            runningBackgroundTasks: runningTasks
        )
    }

    private static func apply(_ signal: HookSignal) -> SessionStatus? {
        StateReducer.reduce(
            .empty, action: .signal(signal, workspace: workspace), now: Date()
        ).sessions["s1"]?.status
    }

    static let suite = TestSuite("Background tasks", [

        TestCase("A turn with nothing running goes green") { t in
            t.expectEqual(apply(stop(runningTasks: 0)), .ready, "status")
        },

        // The case the user found by using it.
        TestCase("A turn with a shell still running stays yellow") { t in
            t.expectEqual(apply(stop(runningTasks: 1)), .working, "green would be a lie")
        },

        TestCase("Several running shells are still just working") { t in
            t.expectEqual(apply(stop(runningTasks: 4)), .working, "status")
        },

        // Green comes back on its own: the task finishes, wakes the session, and
        // that turn ends with nothing running. No counter to get stuck.
        TestCase("Green returns when the next turn ends clean") { t in
            let now = Date()
            let busy = StateReducer.reduce(
                .empty, action: .signal(stop(runningTasks: 1), workspace: workspace), now: now
            )
            let after = StateReducer.reduce(
                busy,
                action: .signal(stop(runningTasks: 0), workspace: workspace),
                now: now.addingTimeInterval(60)
            )
            t.expectEqual(after.sessions["s1"]?.status, .ready, "status")
        },

        // Only `running` counts. A finished task left in the list would hold the
        // row yellow for ever — the stuck-counter failure the subagent design
        // needed a safety net for.
        TestCase("Only the running ones count") { t in
            let payload: [String: Any] = [
                "session_id": "s1", "hook_event_name": "Stop", "cwd": "/dev/project",
                "background_tasks": [
                    ["id": "a", "type": "shell", "status": "completed"],
                    ["id": "b", "type": "shell", "status": "failed"],
                ],
            ]
            let data = try! JSONSerialization.data(withJSONObject: payload)
            let signal = try? HookPayloadDecoder.decode(data, entrypoint: "claude-vscode")
            t.expectEqual(signal?.runningBackgroundTasks, 0, "finished tasks are not work")
        },

        TestCase("A payload with no background tasks at all is fine") { t in
            let payload: [String: Any] = [
                "session_id": "s1", "hook_event_name": "Stop", "cwd": "/dev/project",
            ]
            let data = try! JSONSerialization.data(withJSONObject: payload)
            let signal = try? HookPayloadDecoder.decode(data, entrypoint: "claude-vscode")
            t.expectEqual(signal?.runningBackgroundTasks, 0, "absent means none")
        },
    ])
}
