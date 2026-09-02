import LampBoardCore
import Foundation
import TestKit

/// The summary the menu bar icon stands for.
enum MenuBarSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private static func session(
        _ id: String,
        _ status: SessionStatus,
        path: String,
        harness: Harness = .claudeCode
    ) -> SessionState {
        SessionState(
            id: id,
            status: status,
            workspace: Workspace(path: path),
            updatedAt: t0,
            statusSince: t0,
            harness: harness
        )
    }

    private static func summary(
        _ sessions: [SessionState],
        options: ColumnOptions = ColumnOptions(),
        calm: Set<String> = []
    ) -> MenuBarSummary {
        let state = TrafficLightState(
            sessions: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        )
        return MenuBarSummary.of(
            rendering: ColumnLayout.render(state, options: options),
            calmWorkspaces: calm
        )
    }

    static let suite = TestSuite("Menu bar summary", [

        TestCase("An empty column has nothing to say") { t in
            let s = summary([])
            t.expect(s.isEmpty, "no lamp")
            t.expectEqual(s.count, 0, "and nothing to count")
            t.expect(!(s.blinks), "and nothing to blink about")
            t.expectEqual(s.tooltip, "LampBoard: no sessions", "and it says so")
        },

        TestCase("The icon carries the most urgent thing the column is showing") { t in
            // The order here is deliberately not the urgency order: the summary
            // must rank them, not take the first.
            let s = summary([
                session("a", .working, path: "/dev/one"),
                session("b", .awaiting, path: "/dev/two"),
                session("c", .idle, path: "/dev/three"),
            ])
            t.expectEqual(s.lamp, .awaiting, "amber outranks the rest")
            t.expectEqual(s.count, 1, "and there is one of it")
        },

        TestCase("It counts how many rows carry that state") { t in
            let s = summary([
                session("a", .ready, path: "/dev/one"),
                session("b", .ready, path: "/dev/two"),
                session("c", .working, path: "/dev/three"),
            ])
            t.expectEqual(s.lamp, .ready, "green is the most urgent here")
            t.expectEqual(s.count, 2, "two rows of it")
            t.expectEqual(s.counts[.working], 1, "and the rest is still counted")
        },

        TestCase("Only the three states a click clears make it blink") { t in
            // The same three the row's own click puts back to rest. A blink that
            // fired on `working` would be on for most of the day, and a signal
            // that is always on is not a signal.
            for status in [SessionStatus.awaiting, .ready, .failed] {
                let s = summary([session("x", status, path: "/dev/one")])
                t.expect(s.blinks, "\(status.rawValue) blinks")
                t.expect(s.needsAttention, "\(status.rawValue) is news")
            }
            for status in [SessionStatus.working, .waiting, .idle] {
                let s = summary([session("x", status, path: "/dev/one")])
                t.expect(!(s.blinks), "\(status.rawValue) holds still")
                t.expect(!(s.needsAttention), "\(status.rawValue) is not news")
            }
        },

        TestCase("A project told not to blink still colours the icon") { t in
            // *Don't blink* silences the movement and not the state, on a row and
            // for the same reason up here.
            let s = summary(
                [session("x", .awaiting, path: "/dev/one")],
                calm: [Workspace(path: "/dev/one").key]
            )
            t.expectEqual(s.lamp, .awaiting, "the colour stays")
            t.expect(!(s.blinks), "the movement does not")
        },

        TestCase("One silenced project does not silence another") { t in
            let s = summary(
                [
                    session("x", .awaiting, path: "/dev/quiet"),
                    session("y", .awaiting, path: "/dev/loud"),
                ],
                calm: [Workspace(path: "/dev/quiet").key]
            )
            t.expect(s.blinks, "the one that was not silenced still asks")
            t.expectEqual(s.count, 2, "and both are counted")
        },

        TestCase("A hidden project that needs attention still reaches the icon") { t in
            // Hidden is not forgotten: the column keeps a summary line that lights
            // up, and an icon that ignored it would move the "hide means forget"
            // failure into the menu bar, where it is harder to notice.
            let s = summary(
                [
                    session("x", .awaiting, path: "/dev/hidden"),
                    session("y", .idle, path: "/dev/shown"),
                ],
                options: ColumnOptions(hidden: [Workspace(path: "/dev/hidden").key])
            )
            t.expectEqual(s.lamp, .awaiting, "the hidden row's state reaches the icon")
            t.expect(s.blinks, "and it blinks")
        },

        TestCase("The filter changes what the icon answers for") { t in
            // With "only what's waiting" on, a working session is not on screen,
            // so the icon must not speak for it. The icon summarises the column,
            // never the state behind it.
            let sessions = [
                session("a", .working, path: "/dev/one"),
                session("b", .ready, path: "/dev/two"),
            ]
            let all = summary(sessions)
            let filtered = summary(sessions, options: ColumnOptions(onlyWaiting: true))
            t.expectEqual(all.counts[.working], 1, "unfiltered, the working row counts")
            t.expectNil(filtered.counts[.working], "filtered, it is not on screen")
            t.expectEqual(filtered.lamp, .ready, "and the green is what is left")
        },

        TestCase("Grouping is respected, because rows are what a person sees") { t in
            // Two sessions, one project, one row. The icon counts one.
            let s = summary([
                session("a", .ready, path: "/dev/project"),
                session("b", .ready, path: "/dev/project", harness: .codex),
            ])
            t.expectEqual(s.count, 1, "one row, not two sessions")
        },

        TestCase("A count of things asking for nothing is not shown") { t in
            // Seen in the menu bar on the first build: a resting ring with `6`
            // beside it, because six projects were idle. The number is only worth
            // the space when it counts something that wants a person.
            let resting = summary([
                session("a", .idle, path: "/dev/one"),
                session("b", .idle, path: "/dev/two"),
            ])
            t.expectEqual(resting.count, 2, "the count is still there for the tooltip")
            t.expect(!(resting.needsAttention), "but nothing here wants anybody")

            let asking = summary([
                session("c", .awaiting, path: "/dev/three"),
                session("d", .awaiting, path: "/dev/four"),
            ])
            t.expect(asking.needsAttention, "two blocked sessions do")
            t.expectEqual(asking.count, 2, "and the number says how many")
        },

        TestCase("The tooltip names states in order of urgency") { t in
            let s = summary([
                session("a", .idle, path: "/dev/one"),
                session("b", .awaiting, path: "/dev/two"),
                session("c", .working, path: "/dev/three"),
            ])
            t.expectEqual(
                s.tooltip,
                "LampBoard: 1 waiting for your answer, 1 working, 1 idle",
                "most urgent first, and it names the state rather than the colour"
            )
        },
    ])
}
