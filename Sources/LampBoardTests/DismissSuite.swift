import LampBoardCore
import Foundation
import TestKit

/// Taking a row off the column, and what it takes to bring it back.
///
/// A row can outlive what it describes. Measured on this machine: a chat tab
/// closed while its `claude` process stayed loaded — nine hours later the row was
/// still there, correctly, because the conversation really was loaded — and a
/// Codex daemon holding thirty-nine rollouts open, some of them for conversations
/// closed long before. Neither case is a defect in the reading: the existence of
/// a tab is published nowhere, so the machine cannot tell a live row from an
/// abandoned one. This is the person deciding, and the rules that keep the
/// decision from being undone by the next sweep.
enum DismissSuite {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let workspace = Workspace(path: "/dev/project")

    private static func session(_ id: String, at moment: Date) -> SessionState {
        SessionState(id: id, status: .idle, workspace: workspace,
                     updatedAt: moment, statusSince: moment, harness: .codex)
    }

    private static func signal(_ id: String) -> HookSignal {
        HookSignal(sessionId: id, event: .userPromptSubmit, cwd: "/dev/project",
                   entrypoint: "claude-vscode")
    }

    static let suite = TestSuite("Taking a row off the column", [

        TestCase("A dismissed row leaves, and the moment is kept") { t in
            let before = StateReducer.reduce(
                .empty, action: .adopt(session("s1", at: t0)), now: t0
            )
            t.expect(before.sessions["s1"] != nil, "the row was there to begin with")

            let after = StateReducer.reduce(before, action: .dismiss(sessionId: "s1"), now: t0)
            t.expectNil(after.sessions["s1"], "the row is off the column")
            t.expectEqual(after.dismissed["s1"], t0, "and the moment is on record")
        },

        TestCase("The next sweep does not put it straight back") { t in
            // The whole point. The process is still alive and the rollout still
            // open — that is what made the row outlive its tab — so the sweep
            // offers the same session again a second later.
            let dismissed = StateReducer.reduce(
                StateReducer.reduce(.empty, action: .adopt(session("s1", at: t0)), now: t0),
                action: .dismiss(sessionId: "s1"), now: t0.addingTimeInterval(60)
            )
            let sweep = StateReducer.reduce(
                dismissed, action: .adopt(session("s1", at: t0)), now: t0.addingTimeInterval(65)
            )
            t.expectNil(sweep.sessions["s1"], "the same evidence does not bring it back")
        },

        TestCase("Evidence newer than the dismissal brings it back") { t in
            // A conversation that was reopened, or that wrote to its rollout
            // again. The click said "not here any more"; this says otherwise, and
            // it is the more recent of the two.
            let dismissed = StateReducer.reduce(
                StateReducer.reduce(.empty, action: .adopt(session("s1", at: t0)), now: t0),
                action: .dismiss(sessionId: "s1"), now: t0.addingTimeInterval(60)
            )
            let later = StateReducer.reduce(
                dismissed,
                action: .adopt(session("s1", at: t0.addingTimeInterval(120))),
                now: t0.addingTimeInterval(125)
            )
            t.expect(later.sessions["s1"] != nil, "it came back")
            t.expectNil(later.dismissed["s1"], "and the dismissal is forgotten, not left to fire again")
        },

        TestCase("A session that speaks comes back whatever was clicked") { t in
            // A hook fires because a turn moved. No date comparison is needed or
            // wanted: the row is telling us it is there.
            let dismissed = StateReducer.reduce(
                .empty, action: .dismiss(sessionId: "s2"), now: t0.addingTimeInterval(600)
            )
            let spoke = StateReducer.reduce(
                dismissed, action: .signal(signal("s2"), workspace: workspace), now: t0
            )
            t.expect(spoke.sessions["s2"] != nil, "the signal built the row")
            t.expectNil(spoke.dismissed["s2"], "and cleared the dismissal")
        },

        TestCase("Dismissing one row leaves the others alone") { t in
            var state = StateReducer.reduce(.empty, action: .adopt(session("s1", at: t0)), now: t0)
            state = StateReducer.reduce(state, action: .adopt(session("s2", at: t0)), now: t0)
            let after = StateReducer.reduce(state, action: .dismiss(sessionId: "s1"), now: t0)
            t.expectNil(after.sessions["s1"], "the one that was clicked is gone")
            t.expect(after.sessions["s2"] != nil, "the other one is untouched")
        },

        TestCase("A sweep does not empty the register") { t in
            // The defect this replaces: `reconcile` runs on every sweep and built
            // a new state without carrying the dismissals, so the register was
            // empty five seconds after the click and the row came back. Reported
            // as "three seconds and it is there again".
            let dismissed = StateReducer.reduce(
                StateReducer.reduce(.empty, action: .adopt(session("s1", at: t0)), now: t0),
                action: .dismiss(sessionId: "s1"), now: t0.addingTimeInterval(60)
            )
            let swept = StateReducer.reduce(
                dismissed,
                action: .reconcile(alive: ["s9"], harness: .codex, evenIfEmpty: true),
                now: t0.addingTimeInterval(65)
            )
            t.expectEqual(swept.dismissed["s1"], t0.addingTimeInterval(60),
                          "the sweep left the register alone")

            let forgotten = StateReducer.reduce(
                swept, action: .forget(origin: .terminal), now: t0.addingTimeInterval(70)
            )
            t.expectEqual(forgotten.dismissed["s1"], t0.addingTimeInterval(60),
                          "and so did forgetting a surface")

            let back = StateReducer.reduce(
                forgotten, action: .adopt(session("s1", at: t0)), now: t0.addingTimeInterval(75)
            )
            t.expectNil(back.sessions["s1"], "so the row stayed off the column")
        },

        TestCase("A dismissal survives the copies the state makes of itself") { t in
            // `upserting`, `removing` and `pruning` all build a new state. Any one
            // of them dropping the record would make the row come back on the next
            // sweep, which is the defect this whole thing exists to prevent.
            let dismissed = StateReducer.reduce(
                .empty, action: .dismiss(sessionId: "s1"), now: t0
            )
            let touched = dismissed
                .upserting(session("other", at: t0))
                .removing(sessionId: "nobody")
            t.expectEqual(touched.dismissed["s1"], t0, "the record came through every copy")
        },
    ])
}
