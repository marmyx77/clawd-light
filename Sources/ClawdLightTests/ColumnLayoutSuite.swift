import ClawdLightCore
import Foundation
import TestKit

/// Computing the rows: grouping, filtering, pinning, summary.
enum ColumnLayoutSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private static func session(
        _ id: String,
        _ status: SessionStatus,
        path: String,
        since: TimeInterval = 0,
        subagents: Int = 0
    ) -> SessionState {
        SessionState(
            id: id,
            status: status,
            workspace: Workspace(path: path),
            updatedAt: t0.addingTimeInterval(since),
            statusSince: t0.addingTimeInterval(since),
            activeSubagents: subagents
        )
    }

    private static func state(_ sessions: [SessionState]) -> TrafficLightState {
        TrafficLightState(sessions: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) }))
    }

    static let suite = TestSuite("Column composition", [

        // MARK: Grouping

        TestCase("Sessions from the same project share a row") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/alfa"),
                    session("b", .idle, path: "/dev/alfa"),
                    session("c", .idle, path: "/dev/beta"),
                ]),
                options: ColumnOptions(grouped: true)
            )
            t.expectEqual(result.rows.count, 2, "rows")
            t.expectEqual(result.rows.first { $0.id == "/dev/alfa" }?.count, 2, "sessions in alfa")
        },

        TestCase("Without grouping every session gets its own row") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/alfa"),
                    session("b", .idle, path: "/dev/alfa"),
                ]),
                options: .plain
            )
            t.expectEqual(result.rows.count, 2, "rows")
        },

        TestCase("The group's dot shows the most urgent state") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/alfa"),
                    session("b", .awaiting, path: "/dev/alfa"),
                    session("c", .working, path: "/dev/alfa"),
                ]),
                options: ColumnOptions(grouped: true)
            )
            t.expectEqual(result.rows.first?.status, .awaiting, "row status")
        },

        TestCase("Clicking a group opens the most urgent session") { t in
            let result = ColumnLayout.render(
                state([
                    session("idle-one", .idle, path: "/dev/alfa"),
                    session("blocked", .awaiting, path: "/dev/alfa"),
                ]),
                options: ColumnOptions(grouped: true)
            )
            t.expectEqual(result.rows.first?.primary.id, "blocked", "session opened")
        },

        TestCase("The click clears only the sessions in the most urgent state") { t in
            let result = ColumnLayout.render(
                state([
                    session("green", .ready, path: "/dev/alfa"),
                    session("blocked", .awaiting, path: "/dev/alfa"),
                ]),
                options: ColumnOptions(grouped: true)
            )
            // The green has to survive the click: were it to vanish, grouping
            // would lose an answer nobody ever read.
            t.expectEqual(result.rows.first?.sessionIdsToClear, ["blocked"], "to clear")
        },

        TestCase("The group's subagents add up") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .working, path: "/dev/alfa", subagents: 2),
                    session("b", .working, path: "/dev/alfa", subagents: 3),
                ]),
                options: ColumnOptions(grouped: true)
            )
            t.expectEqual(result.rows.first?.activeSubagents, 5, "subagents")
        },

        // MARK: Ordering

        TestCase("The rows come out sorted by urgency") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/one"),
                    session("b", .ready, path: "/dev/two"),
                    session("c", .awaiting, path: "/dev/three"),
                    session("d", .working, path: "/dev/four"),
                ]),
                options: ColumnOptions(grouped: true)
            )
            t.expectEqual(
                result.rows.map(\.status),
                [.awaiting, .ready, .working, .idle],
                "order"
            )
        },

        TestCase("For equal states whoever waited longest comes first") { t in
            let result = ColumnLayout.render(
                state([
                    session("recent", .ready, path: "/dev/one", since: 600),
                    session("old", .ready, path: "/dev/two", since: 0),
                ]),
                options: ColumnOptions(grouped: true)
            )
            t.expectEqual(result.rows.first?.workspace.name, "two", "first row")
        },

        TestCase("Pinned projects stay on top even when idle") { t in
            let result = ColumnLayout.render(
                state([
                    session("urgent", .awaiting, path: "/dev/alfa"),
                    session("pinned", .idle, path: "/dev/beta"),
                ]),
                options: ColumnOptions(grouped: true, pinned: ["/dev/beta"])
            )
            t.expectEqual(result.rows.first?.workspace.name, "beta", "first row")
            t.expectEqual(result.rows.first?.isPinned, true, "pinned")
        },

        // MARK: Filter

        TestCase("The filter leaves only what's waiting for something") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/one"),
                    session("b", .working, path: "/dev/two"),
                    session("c", .ready, path: "/dev/three"),
                    session("d", .awaiting, path: "/dev/four"),
                    session("e", .failed, path: "/dev/five"),
                ]),
                options: ColumnOptions(grouped: true, onlyWaiting: true)
            )
            t.expectEqual(result.rows.count, 3, "rows left")
            t.expect(
                result.rows.allSatisfy { $0.status.clearsOnFocus },
                "rows that are waiting for nothing were left in"
            )
        },

        TestCase("The filter says how many sessions it set aside") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/one"),
                    session("b", .idle, path: "/dev/one"),
                    session("c", .ready, path: "/dev/two"),
                ]),
                options: ColumnOptions(grouped: true, onlyWaiting: true)
            )
            // Keeping quiet about the number would suggest there's nothing else.
            t.expectEqual(result.filteredOut, 2, "sessions filtered out")
        },

        TestCase("The filter does not hide pinned projects") { t in
            let result = ColumnLayout.render(
                state([session("a", .idle, path: "/dev/alfa")]),
                options: ColumnOptions(grouped: true, onlyWaiting: true, pinned: ["/dev/alfa"])
            )
            t.expectEqual(result.rows.count, 1, "rows")
        },

        // MARK: Hidden

        TestCase("A hidden project leaves the rows") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/alfa"),
                    session("b", .idle, path: "/dev/beta"),
                ]),
                options: ColumnOptions(grouped: true, hidden: ["/dev/beta"])
            )
            t.expectEqual(result.rows.count, 1, "rows")
            t.expectEqual(result.rows.first?.workspace.name, "alfa", "row left")
        },

        TestCase("The summary counts the hidden sessions") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/beta"),
                    session("b", .idle, path: "/dev/beta"),
                    session("c", .idle, path: "/dev/gamma"),
                ]),
                options: ColumnOptions(grouped: true, hidden: ["/dev/beta", "/dev/gamma"])
            )
            t.expectEqual(result.hidden?.sessionCount, 3, "hidden sessions")
            t.expectEqual(result.hidden?.workspaceNames, ["beta", "gamma"], "projects")
        },

        TestCase("The summary lights up when a hidden one asks for attention") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/beta"),
                    session("b", .awaiting, path: "/dev/beta"),
                ]),
                options: ColumnOptions(grouped: true, hidden: ["/dev/beta"])
            )
            // This is what stops "hide" from turning into "forget".
            t.expectEqual(result.hidden?.status, .awaiting, "summary status")
            t.expectEqual(result.hidden?.needsAttention, true, "needs attention")
        },

        TestCase("With nothing hidden there is no summary row") { t in
            let result = ColumnLayout.render(
                state([session("a", .idle, path: "/dev/alfa")]),
                options: ColumnOptions(grouped: true)
            )
            t.expectNil(result.hidden, "summary")
        },

        TestCase("An empty column produces nothing") { t in
            let result = ColumnLayout.render(.empty, options: ColumnOptions(grouped: true))
            t.expectEqual(result.rows.count, 0, "rows")
            t.expectNil(result.hidden, "summary")
        },

        // MARK: Stability

        TestCase("The row identifier does not jitter between two computations") { t in
            let sessions = state([
                session("a", .idle, path: "/dev/alfa"),
                session("b", .working, path: "/dev/alfa"),
            ])
            let first = ColumnLayout.render(sessions, options: ColumnOptions(grouped: true))
            let second = ColumnLayout.render(sessions, options: ColumnOptions(grouped: true))
            // An unstable id would rebuild the rows on every update, and the
            // panel would flicker.
            t.expectEqual(first.rows.map(\.id), second.rows.map(\.id), "identifiers")
        },
    ])
}
