import LampBoardCore
import Foundation
import TestKit

/// The order of the column: how a project gets a place, and how it moves.
enum RowOrderSuite {

    static let suite = TestSuite("Row order", [

        TestCase("A project seen for the first time is appended, the known ones keep their places") { t in
            let after = RowOrder.absorbing(["/dev/new", "/dev/b", "/dev/a"], into: ["/dev/b", "/dev/a"])
            t.expectEqual(after, ["/dev/b", "/dev/a", "/dev/new"], "order")
        },

        // Called on every state change: the same input has to give the same list,
        // or the column would drift on its own — the very thing this exists to stop.
        TestCase("Absorbing is deterministic — newcomers by name — and idempotent") { t in
            let once = RowOrder.absorbing(["/dev/zulu", "/x/alfa", "/dev/mike"], into: [])
            t.expectEqual(once, ["/x/alfa", "/dev/mike", "/dev/zulu"], "by name")
            t.expectEqual(RowOrder.absorbing(["/dev/mike", "/dev/zulu"], into: once), once, "idempotent")
        },

        TestCase("Placing before a visible neighbour is expressed in the full order") { t in
            // `/dev/h` is hidden: the user does not see it, so the drop is
            // relative to a, b and c only — and h keeps its place next to a.
            let after = RowOrder.placing(
                "/dev/c", at: 0, among: ["/dev/a", "/dev/b", "/dev/c"],
                in: ["/dev/a", "/dev/h", "/dev/b", "/dev/c"]
            )
            t.expectEqual(after, ["/dev/c", "/dev/a", "/dev/h", "/dev/b"], "order")
        },

        TestCase("Placing at the bottom goes right after the last visible row") { t in
            let after = RowOrder.placing(
                "/dev/a", at: 2, among: ["/dev/a", "/dev/b", "/dev/c"],
                in: ["/dev/a", "/dev/b", "/dev/c", "/dev/h"]
            )
            t.expectEqual(after, ["/dev/b", "/dev/c", "/dev/a", "/dev/h"], "order")
        },

        TestCase("Placing clamps the index instead of failing") { t in
            let order = ["/dev/a", "/dev/b", "/dev/c"]
            t.expectEqual(RowOrder.placing("/dev/a", at: 99, among: order, in: order), ["/dev/b", "/dev/c", "/dev/a"], "too far down")
            t.expectEqual(RowOrder.placing("/dev/c", at: -3, among: order, in: order), ["/dev/c", "/dev/a", "/dev/b"], "too far up")
        },

        // Grouping off draws one row per session: the visible list repeats a path.
        TestCase("Placing tolerates a visible list with repeated paths") { t in
            let after = RowOrder.placing(
                "/dev/b", at: 0, among: ["/dev/a", "/dev/a", "/dev/b", "/dev/b"],
                in: ["/dev/a", "/dev/b"]
            )
            t.expectEqual(after, ["/dev/b", "/dev/a"], "order")
        },

        TestCase("Moving swaps with the visible neighbour and skips what is not shown") { t in
            let after = RowOrder.moving(
                "/dev/a", by: 1, among: ["/dev/a", "/dev/b"], in: ["/dev/a", "/dev/h", "/dev/b"]
            )
            t.expectEqual(after, ["/dev/h", "/dev/b", "/dev/a"], "a goes below b; h stays above b")
        },

        TestCase("Moving past either edge changes nothing") { t in
            let order = ["/dev/a", "/dev/b"]
            t.expectEqual(RowOrder.moving("/dev/a", by: -1, among: order, in: order), order, "before the first")
            t.expectEqual(RowOrder.moving("/dev/b", by: 1, among: order, in: order), order, "past the last")
            t.expectEqual(RowOrder.moving("/dev/zzz", by: 1, among: order, in: order), order, "unknown project")
        },

        TestCase("A slot is a position within the limit, and nothing beyond it") { t in
            let order = (1...12).map { "/dev/\($0)" }
            t.expectEqual(RowOrder.slot(of: "/dev/1", in: order, limit: 9), 1, "first")
            t.expectEqual(RowOrder.slot(of: "/dev/9", in: order, limit: 9), 9, "ninth")
            t.expectNil(RowOrder.slot(of: "/dev/10", in: order, limit: 9), "tenth")
            t.expectNil(RowOrder.slot(of: "/dev/zzz", in: order, limit: 9), "unknown")
        },

        TestCase("Normalizing drops duplicates and keeps the first occurrence") { t in
            t.expectEqual(
                RowOrder.normalized(["/dev/a", "/dev/b", "/dev/a", "/dev/c"]),
                ["/dev/a", "/dev/b", "/dev/c"],
                "duplicates"
            )
        },
    ])
}

/// Slots as the column renders them.
enum ColumnSlotSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private static func session(
        _ id: String, _ status: SessionStatus, path: String, since: TimeInterval = 0
    ) -> SessionState {
        SessionState(
            id: id,
            status: status,
            workspace: Workspace(path: path),
            updatedAt: t0.addingTimeInterval(since),
            statusSince: t0.addingTimeInterval(since)
        )
    }

    private static func state(_ sessions: [SessionState]) -> TrafficLightState {
        TrafficLightState(sessions: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) }))
    }

    static let suite = TestSuite("Slots in the column", [

        TestCase("A row's slot is its position in the order") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/alfa"),
                    session("b", .idle, path: "/dev/beta"),
                ]),
                options: ColumnOptions(grouped: true, order: ["/dev/beta", "/dev/alfa"])
            )
            t.expectEqual(result.row(inSlot: 1)?.workspace.name, "beta", "slot 1")
            t.expectEqual(result.row(inSlot: 2)?.workspace.name, "alfa", "slot 2")
            t.expectEqual(result.rows.map(\.workspace.name), ["beta", "alfa"], "drawn in slot order")
        },

        TestCase("Below the ninth place there is no slot, but the row is still drawn") { t in
            let paths = (1...10).map { "/dev/p\($0)" }
            let result = ColumnLayout.render(
                state(paths.enumerated().map { session("s\($0)", .idle, path: $1) }),
                options: ColumnOptions(grouped: true, order: paths)
            )
            t.expectEqual(result.rows.count, 10, "rows")
            t.expectEqual(result.rows[8].slot, 9, "ninth")
            t.expectNil(result.rows[9].slot, "tenth")
        },

        TestCase("A project with no live session leaves its slot empty rather than shifting the others") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/one"),
                    session("c", .idle, path: "/dev/three"),
                ]),
                options: ColumnOptions(grouped: true, order: ["/dev/one", "/dev/two", "/dev/three"])
            )
            t.expectNil(result.row(inSlot: 2), "slot 2 is empty")
            t.expectEqual(result.row(inSlot: 3)?.workspace.name, "three", "three keeps slot 3")
        },

        // The property the whole feature rests on. A bound key must point at the
        // same project whatever the sessions are doing.
        TestCase("A slot does not move when a session changes state") { t in
            let order = ["/dev/one", "/dev/two", "/dev/three"]
            let calm = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/one"),
                    session("b", .idle, path: "/dev/two"),
                    session("c", .idle, path: "/dev/three"),
                ]),
                options: ColumnOptions(grouped: true, order: order)
            )
            let busy = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/one"),
                    session("b", .awaiting, path: "/dev/two"),
                    session("c", .ready, path: "/dev/three"),
                ]),
                options: ColumnOptions(grouped: true, order: order)
            )
            t.expectEqual(calm.rows.map(\.workspace.name), busy.rows.map(\.workspace.name), "same rows, same places")
            t.expectEqual(busy.row(inSlot: 2)?.workspace.name, "two", "slot 2 after")
            t.expectEqual(busy.row(inSlot: 3)?.status, .ready, "the green is where it always was")
        },
    ])
}
