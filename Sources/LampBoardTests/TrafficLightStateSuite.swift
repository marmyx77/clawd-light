import LampBoardCore
import Foundation
import TestKit

enum TrafficLightStateSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private static func session(
        _ id: String,
        _ status: SessionStatus,
        workspace: String
    ) -> SessionState {
        SessionState(
            id: id,
            status: status,
            workspace: Workspace(path: workspace),
            updatedAt: t0,
            statusSince: t0
        )
    }

    private static func state(_ sessions: [SessionState]) -> TrafficLightState {
        TrafficLightState(sessions: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) }))
    }

    static let suite = TestSuite("Column state", [

        TestCase("Sessions sort by urgency") { t in
            let ordered = state([
                session("a", .idle, workspace: "/dev/alpha"),
                session("b", .ready, workspace: "/dev/bravo"),
                session("c", .awaiting, workspace: "/dev/charlie"),
                session("d", .working, workspace: "/dev/delta"),
            ]).ordered

            t.expectEqual(ordered.map(\.status), [.awaiting, .ready, .working, .idle])
        },

        // For equal states the order has to be stable, otherwise the traffic
        // lights dance under the cursor on every update.
        TestCase("For equal states the order is alphabetical and stable") { t in
            let ordered = state([
                session("1", .idle, workspace: "/dev/zulu"),
                session("2", .idle, workspace: "/dev/alpha"),
                session("3", .idle, workspace: "/dev/mike"),
            ]).ordered

            t.expectEqual(ordered.map(\.workspace.name), ["alpha", "mike", "zulu"])
        },

        TestCase("Counts the sessions waiting on the user") { t in
            let subject = state([
                session("a", .idle, workspace: "/dev/a"),
                session("b", .ready, workspace: "/dev/b"),
                session("c", .awaiting, workspace: "/dev/c"),
                session("d", .working, workspace: "/dev/d"),
            ])
            t.expectEqual(subject.unseenCount, 2)
        },

        TestCase("Reports the most urgent state") { t in
            let subject = state([
                session("a", .idle, workspace: "/dev/a"),
                session("b", .working, workspace: "/dev/b"),
            ])
            t.expectEqual(subject.mostUrgentStatus, .working)
            t.expectNil(TrafficLightState.empty.mostUrgentStatus, "empty column")
        },

        TestCase("Upsert replaces without duplicating") { t in
            let subject = state([session("a", .idle, workspace: "/dev/a")])
                .upserting(session("a", .ready, workspace: "/dev/a"))

            t.expectEqual(subject.sessions.count, 1, "count")
            t.expectEqual(subject.sessions["a"]?.status, .ready, "status")
        },

        TestCase("Removing a nonexistent session changes nothing") { t in
            let subject = state([session("a", .idle, workspace: "/dev/a")])
            t.expect(subject.removing(sessionId: "b") == subject, "the state changed")
        },

        TestCase("Upsert does not mutate the original state") { t in
            let original = state([session("a", .idle, workspace: "/dev/a")])
            _ = original.upserting(session("b", .ready, workspace: "/dev/b"))
            t.expectEqual(original.sessions.count, 1)
        },
    ])
}

enum SessionStatusSuite {

    static let suite = TestSuite("State semantics", [

        TestCase("Only amber blinks") { t in
            t.expectEqual(SessionStatus.allCases.filter(\.shouldBlink), [.awaiting])
        },

        TestCase("The click clears green, amber and error red") { t in
            t.expectEqual(
                Set(SessionStatus.allCases.filter(\.clearsOnFocus)), [.ready, .awaiting, .failed]
            )
        },

        // A failed turn clears on click like the others, but it must not survive
        // a restart: if the turn resumes, yellow is the correct information.
        TestCase("Green, amber and blue resist a trailing signal") { t in
            t.expectEqual(
                Set(SessionStatus.allCases.filter(\.blocksDowngrade)), [.ready, .awaiting, .waiting]
            )
        },

        TestCase("Every state has a distinct urgency rank") { t in
            let ranks = SessionStatus.allCases.map(\.urgencyRank)
            t.expectEqual(Set(ranks).count, SessionStatus.allCases.count)
        },
    ])
}
