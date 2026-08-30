import LampBoardCore
import Foundation
import TestKit

/// The sessions inside one row, told apart from one another.
///
/// A project can hold several conversations at once, and until now the column
/// could only say how many. Measured on a real machine: three Claude sessions in
/// one folder, identical in every field the panel draws, differing only by a
/// UUID nobody sees. These cases are about the two things that make them
/// separable, a stable order and a name each.
enum RowSessionsSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private static func session(
        _ id: String,
        _ status: SessionStatus,
        born: TimeInterval,
        title: String? = nil,
        path: String = "/dev/project"
    ) -> SessionState {
        SessionState(
            id: id,
            status: status,
            workspace: Workspace(path: path),
            updatedAt: t0.addingTimeInterval(born + 100),
            statusSince: t0.addingTimeInterval(born + 100),
            origin: .editor,
            title: title,
            firstSeenAt: t0.addingTimeInterval(born)
        )
    }

    private static func row(_ sessions: [SessionState]) -> ColumnRow {
        ColumnRow(id: "/dev/project", workspace: Workspace(path: "/dev/project"), sessions: sessions)
    }

    static let suite = TestSuite("Row sessions", [

        TestCase("The sessions of a row are listed in the order they were opened") { t in
            // Not by urgency, which is what `sessions` itself is sorted by. The
            // column does not reorder itself (D23) and neither may the list inside
            // a row: a sub-row that jumps because a turn finished is the same
            // defect one level down, and it is worse there, because the rows are
            // closer together and a misclick opens the wrong conversation.
            let members = row([
                session("second", .ready, born: 200),
                session("first", .working, born: 100),
            ]).members

            t.expectEqual(members.map(\.id), ["first", "second"], "birth order")
            t.expectEqual(members.map(\.ordinal), [1, 2], "numbered along that order")
        },

        TestCase("The order holds still when a session changes state") { t in
            // The whole point of ordering by birth: this is the case that made the
            // grouped row unusable, two sessions swapping places every time one of
            // them started or finished a turn.
            let first = session("first", .working, born: 100)
            let second = session("second", .idle, born: 200)

            let before = row([first, second]).members.map(\.id)
            let after = row([second.with(status: .awaiting, at: t0), first]).members.map(\.id)

            t.expectEqual(before, after, "the same two, in the same places")
        },

        TestCase("A session with a title is called by it") { t in
            let members = row([session("a", .working, born: 100, title: "Refactor the parser")]).members
            t.expectEqual(members.first?.name, "Refactor the parser", "its own name")
        },

        TestCase("A session with no title yet is called by its position") { t in
            // A title appears after the first exchange, not before, so for the
            // first seconds of a conversation there is nothing to read. An empty
            // name would make two fresh sessions indistinguishable at exactly the
            // moment somebody opened the second one and is looking for it.
            let members = row([
                session("a", .working, born: 100),
                session("b", .working, born: 200),
            ]).members

            t.expectEqual(members.map(\.name), ["#1", "#2"], "position, until there is a title")
        },

        TestCase("A row holding one session still lists it") { t in
            let members = row([session("only", .ready, born: 100, title: "One thing")]).members
            t.expectEqual(members.count, 1, "one member")
            t.expectEqual(members.first?.ordinal, 1, "and it is the first")
        },

        TestCase("Two sessions born in the same instant keep a stable order") { t in
            // Adoption from the filesystem gives a whole set the same timestamp.
            // Ties broken by id rather than left to the sort, because an unstable
            // sort would renumber the list between two identical renders.
            let members = row([
                session("bbb", .working, born: 100),
                session("aaa", .working, born: 100),
            ]).members

            t.expectEqual(members.map(\.id), ["aaa", "bbb"], "the tie is broken, not left open")
        },

        TestCase("When a session was first seen survives every copy") { t in
            // `firstSeenAt` is the only stable thing about a session: `updatedAt`
            // and `statusSince` both move. A copy that dropped it would renumber
            // the list on the next signal, which is the defect this exists to
            // prevent.
            let born = t0.addingTimeInterval(50)
            let original = SessionState(
                id: "a", status: .working, workspace: Workspace(path: "/dev/project"),
                updatedAt: t0, statusSince: t0, firstSeenAt: born
            )

            let moved = original
                .with(status: .ready, at: t0.addingTimeInterval(900))
                .with(title: "Named later")
                .with(harness: .codex)

            t.expectEqual(moved.firstSeenAt, born, "still the moment it appeared")
        },

        TestCase("A session built without one is first seen when it was last updated") { t in
            // Every construction site that predates this field, including the
            // fixtures, still has to produce a session with a defensible answer.
            let updated = t0.addingTimeInterval(400)
            let session = SessionState(
                id: "a", status: .working, workspace: Workspace(path: "/dev/project"),
                updatedAt: updated, statusSince: updated
            )
            t.expectEqual(session.firstSeenAt, updated, "the only moment it knows")
        },
    ])
}
