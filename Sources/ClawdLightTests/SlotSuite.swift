import ClawdLightCore
import Foundation
import TestKit

/// Keyboard slots: the arrangement, and the property that justifies the feature.
enum SlotAssignmentSuite {

    private static let limit = 9

    static let suite = TestSuite("Slot arrangement", [

        TestCase("Pinning appends to the first free slot") { t in
            var slots: [String] = []
            slots = SlotAssignment.toggling("/dev/a", in: slots, limit: limit)
            slots = SlotAssignment.toggling("/dev/b", in: slots, limit: limit)
            t.expectEqual(slots, ["/dev/a", "/dev/b"], "order")
            t.expectEqual(SlotAssignment.slot(of: "/dev/b", in: slots), 2, "slot of b")
        },

        // The whole point: a project already bound keeps the key it had.
        TestCase("Pinning a new project does not move the existing ones") { t in
            let before = ["/dev/a", "/dev/b"]
            let after = SlotAssignment.toggling("/dev/c", in: before, limit: limit)
            t.expectEqual(SlotAssignment.slot(of: "/dev/a", in: after), 1, "a")
            t.expectEqual(SlotAssignment.slot(of: "/dev/b", in: after), 2, "b")
            t.expectEqual(SlotAssignment.slot(of: "/dev/c", in: after), 3, "c")
        },

        TestCase("Unpinning removes and compacts") { t in
            let after = SlotAssignment.toggling("/dev/a", in: ["/dev/a", "/dev/b"], limit: limit)
            t.expectEqual(after, ["/dev/b"], "list")
            t.expectEqual(SlotAssignment.slot(of: "/dev/b", in: after), 1, "b moved up")
        },

        TestCase("A project with no slot has none") { t in
            t.expectNil(SlotAssignment.slot(of: "/dev/zzz", in: ["/dev/a"]))
        },

        // Silently dropping the oldest would unbind a key the user is still
        // pressing — the exact surprise this design exists to avoid.
        TestCase("Beyond the limit, pinning is ignored rather than evicting") { t in
            let full = (1...limit).map { "/dev/\($0)" }
            let after = SlotAssignment.toggling("/dev/extra", in: full, limit: limit)
            t.expectEqual(after, full, "the list is unchanged")
            t.expectNil(SlotAssignment.slot(of: "/dev/extra", in: after), "no slot given")
        },

        TestCase("Moving swaps with the neighbor") { t in
            let after = SlotAssignment.moving("/dev/c", by: -1, in: ["/dev/a", "/dev/b", "/dev/c"])
            t.expectEqual(after, ["/dev/a", "/dev/c", "/dev/b"], "order")
        },

        TestCase("Moving past either edge changes nothing") { t in
            let list = ["/dev/a", "/dev/b"]
            t.expectEqual(SlotAssignment.moving("/dev/a", by: -1, in: list), list, "before the first")
            t.expectEqual(SlotAssignment.moving("/dev/b", by: 1, in: list), list, "past the last")
            t.expectEqual(SlotAssignment.moving("/dev/zzz", by: 1, in: list), list, "unknown project")
        },

        TestCase("Normalizing drops duplicates and caps the length") { t in
            let messy = ["/dev/a", "/dev/b", "/dev/a", "/dev/c"]
            t.expectEqual(
                SlotAssignment.normalized(messy, limit: limit),
                ["/dev/a", "/dev/b", "/dev/c"],
                "duplicates"
            )
            t.expectEqual(
                SlotAssignment.normalized(["/dev/a", "/dev/b", "/dev/c"], limit: 2),
                ["/dev/a", "/dev/b"],
                "cap"
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

        TestCase("A pinned row carries its slot, an unpinned one carries none") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/alfa"),
                    session("b", .idle, path: "/dev/beta"),
                ]),
                options: ColumnOptions(grouped: true, pinned: ["/dev/beta"])
            )
            t.expectEqual(result.row(inSlot: 1)?.workspace.name, "beta", "slot 1")
            t.expectEqual(result.rows.first { $0.workspace.name == "alfa" }?.slot, nil, "alfa")
        },

        TestCase("Pinned rows sort by slot, not alphabetically") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/zulu"),
                    session("b", .idle, path: "/dev/alfa"),
                ]),
                options: ColumnOptions(grouped: true, pinned: ["/dev/zulu", "/dev/alfa"])
            )
            t.expectEqual(result.rows.map(\.workspace.name), ["zulu", "alfa"], "order")
        },

        // The property the whole feature rests on. Without it a bound key points
        // somewhere new every time a session changes state, and a shortcut that
        // acts on the wrong session is worse than no shortcut.
        TestCase("A slot does not move when urgency reorders the column") { t in
            let calm = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/one"),
                    session("b", .idle, path: "/dev/two"),
                    session("c", .idle, path: "/dev/three"),
                ]),
                options: ColumnOptions(grouped: true, pinned: ["/dev/one", "/dev/two"])
            )

            // Now the second pinned project blocks, and an unpinned one goes green.
            let busy = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/one"),
                    session("b", .awaiting, path: "/dev/two"),
                    session("c", .ready, path: "/dev/three"),
                ]),
                options: ColumnOptions(grouped: true, pinned: ["/dev/one", "/dev/two"])
            )

            t.expectEqual(calm.row(inSlot: 1)?.workspace.name, "one", "slot 1 before")
            t.expectEqual(busy.row(inSlot: 1)?.workspace.name, "one", "slot 1 after")
            t.expectEqual(calm.row(inSlot: 2)?.workspace.name, "two", "slot 2 before")
            t.expectEqual(busy.row(inSlot: 2)?.workspace.name, "two", "slot 2 after")
        },

        // The accepted price, pinned down so nobody "fixes" it by accident.
        TestCase("A pinned project that starts waiting stays in its slot") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/one"),
                    session("b", .awaiting, path: "/dev/two"),
                ]),
                options: ColumnOptions(grouped: true, pinned: ["/dev/one", "/dev/two"])
            )
            // Slot order wins among the pinned: the amber one does not jump above.
            t.expectEqual(result.rows.map(\.workspace.name), ["one", "two"], "order")
            // But it is still above everything unpinned.
            t.expect(result.rows.allSatisfy(\.isPinned), "premise")
        },

        TestCase("An empty slot returns nothing rather than the neighbor") { t in
            let result = ColumnLayout.render(
                state([session("a", .idle, path: "/dev/one")]),
                options: ColumnOptions(grouped: true, pinned: ["/dev/one", "/dev/absent"])
            )
            // `/dev/absent` is pinned but has no live session. Opening slot 2 must
            // not open slot 1: for a key pressed without looking, opening the
            // wrong project is the worst possible outcome.
            t.expectNil(result.row(inSlot: 2), "slot 2")
            t.expectEqual(result.row(inSlot: 1)?.workspace.name, "one", "slot 1 still works")
        },

        TestCase("An unassigned slot number returns nothing") { t in
            let result = ColumnLayout.render(
                state([session("a", .idle, path: "/dev/one")]),
                options: ColumnOptions(grouped: true, pinned: ["/dev/one"])
            )
            t.expectNil(result.row(inSlot: 5))
        },

        // With grouping off a project has several rows, all carrying its slot.
        // The key still has to open one thing, and the same one a click opens.
        TestCase("Without grouping the slot opens the most urgent row") { t in
            let result = ColumnLayout.render(
                state([
                    session("calm", .idle, path: "/dev/one"),
                    session("blocked", .awaiting, path: "/dev/one"),
                ]),
                options: ColumnOptions(grouped: false, pinned: ["/dev/one"])
            )
            t.expectEqual(result.row(inSlot: 1)?.primary.id, "blocked", "row opened")
            t.expectEqual(result.occupiedSlots.count, 1, "one entry per slot")
        },

        TestCase("The filter never hides a slot") { t in
            let result = ColumnLayout.render(
                state([
                    session("a", .idle, path: "/dev/one"),
                    session("b", .ready, path: "/dev/two"),
                ]),
                options: ColumnOptions(grouped: true, onlyWaiting: true, pinned: ["/dev/one"])
            )
            // An addressable row that the filter can remove is an address that
            // sometimes fails for a reason the user forgot they configured.
            t.expectEqual(result.row(inSlot: 1)?.workspace.name, "one", "slot survives")
        },
    ])
}
