import ClawdLightCore
import Foundation
import TestKit

/// Coverage: the sessions that exist and that the panel has to see.
///
/// This is the most serious defect to correct, because it is invisible. A wrong
/// traffic light gets noticed and you learn to distrust it; a row that isn't
/// there says nothing, and teaches you to trust an incomplete column.
enum CoverageSuite {

    static let secondWorkspace = "/tmp/clawd-e2e/project-beta"
    static let terminalWorkspace = "/tmp/clawd-e2e/project-terminal"

    static func suite(_ app: AppUnderTest) -> TestSuite {
        TestSuite("E2E · coverage", [

            // MARK: - 1.1 integrated-terminal sessions

            TestCase("a terminal-started session inside a workspace counts") { a in
                let id = "e2e-terminal"
                // `cli` is the entrypoint of `claude` launched by hand. If the cwd
                // sits inside a folder VS Code has open, the session runs in the
                // *integrated* terminal: same window, same project, same click
                // that brings it to the front.
                app.sendHook(
                    HookPayloads.userPromptSubmit(sessionId: id, cwd: terminalWorkspace),
                    entrypoint: "cli"
                )
                a.expect(
                    app.waitUntil { app.status(of: id) == "working" },
                    "status: \(app.status(of: id))"
                )
            },

            TestCase("a terminal session outside every workspace stays excluded") { a in
                let id = "e2e-terminal-outside"
                app.sendHook(
                    HookPayloads.userPromptSubmit(sessionId: id, cwd: "/tmp/no-workspace-here"),
                    entrypoint: "cli"
                )
                usleep(400_000)
                // The criterion is the folder, not how the session was started:
                // here the folder belongs to no window.
                a.expectEqual(app.status(of: id), "absent", "status")
            },

            TestCase("an entrypoint never seen before is not discarded") { a in
                let id = "e2e-unknown-entrypoint"
                app.sendHook(
                    HookPayloads.userPromptSubmit(sessionId: id, cwd: secondWorkspace),
                    entrypoint: "claude-something-from-2027"
                )
                a.expect(
                    app.waitUntil { app.status(of: id) == "working" },
                    "status: \(app.status(of: id))"
                )
            },

            // MARK: - 1.2 subagent counter


            // A machine's hooks reach this one through the tunnel and say where
            // they ran. No local editor window claims `/home/…`, and without the
            // header the signal would be dropped for exactly that reason.
            TestCase("a signal from another machine gets a row on that machine") { a in
                let id = "e2e-remote-\(UUID().uuidString.prefix(8))"
                let cwd = "/home/dev/.notes"
                a.expectEqual(
                    app.sendHook(HookPayloads.userPromptSubmit(sessionId: id, cwd: cwd), entrypoint: "cli", host: "node"),
                    204, "accepted"
                )
                usleep(300_000)
                guard let session = app.session(id: id) else {
                    return a.fail("the remote session got no row")
                }
                a.expectEqual(session.status, "working", "status")
                a.expectEqual(session.host, "node", "host")
                a.expectEqual(session.workspace, ".notes", "its own folder is the workspace")

                // The same signal without the header is a terminal session in a
                // folder no window here has open: no row, as before.
                let local = "e2e-remote-local-\(UUID().uuidString.prefix(8))"
                app.sendHook(HookPayloads.userPromptSubmit(sessionId: local, cwd: cwd), entrypoint: "cli")
                usleep(300_000)
                a.expectEqual(app.status(of: local), "absent", "no host, no row")
            },
            TestCase("a subagent starting after the Stop turns the row blue") { a in
                // It arrives after the parent's Stop, so it is a background agent:
                // the session has stopped and is waiting for it — not working (D22).
                let id = "e2e-subagent"
                app.sendHook(HookPayloads.stop(sessionId: id, cwd: secondWorkspace))
                a.expect(
                    app.waitUntil { app.status(of: id) == "ready" },
                    "premise: \(app.status(of: id))"
                )

                app.sendHook(HookPayloads.subagentStart(
                    sessionId: id, cwd: secondWorkspace, agentId: "agent-1"
                ))
                a.expect(
                    app.waitUntil { app.status(of: id) == "waiting" },
                    "status: \(app.status(of: id))"
                )
                a.expectEqual(app.session(id: id)?.activeSubagents, 1, "counter")
            },

            TestCase("two subagents count two") { a in
                let id = "e2e-subagent"
                app.sendHook(HookPayloads.subagentStart(
                    sessionId: id, cwd: secondWorkspace, agentId: "agent-2"
                ))
                a.expect(
                    app.waitUntil { app.session(id: id)?.activeSubagents == 2 },
                    "counter: \(app.session(id: id)?.activeSubagents ?? -1)"
                )
            },

            TestCase("with a subagent still alive the session stays blue, not green") { a in
                let id = "e2e-subagent"
                app.sendHook(HookPayloads.subagentStop(
                    sessionId: id, cwd: secondWorkspace, agentId: "agent-1"
                ))
                a.expect(
                    app.waitUntil { app.session(id: id)?.activeSubagents == 1 },
                    "counter: \(app.session(id: id)?.activeSubagents ?? -1)"
                )
                // The parent's turn isn't over: no `Stop` has arrived and an agent
                // is still working.
                a.expectEqual(app.status(of: id), "waiting", "status")
            },

            TestCase("the turn ending with an agent alive is a wait, not a finish") { a in
                let id = "e2e-subagent"
                // This is the background-agent case: the parent turn returns
                // control — `Stop` — while the agents keep going for tens of
                // minutes. Taking that `Stop` literally would paint it green;
                // calling it "working" would be the other half-truth (D22).
                app.sendHook(HookPayloads.stop(sessionId: id, cwd: secondWorkspace))
                usleep(400_000)
                a.expectEqual(app.status(of: id), "waiting", "status")
                a.expectEqual(app.session(id: id)?.activeSubagents, 1, "counter")
            },

            TestCase("when the last agent finishes the green set aside resurfaces") { a in
                let id = "e2e-subagent"
                app.sendHook(HookPayloads.subagentStop(
                    sessionId: id, cwd: secondWorkspace, agentId: "agent-2"
                ))
                // Nobody had to remember the green: the displayed state is
                // derived, so the earlier `Stop` comes back on its own.
                a.expect(
                    app.waitUntil { app.status(of: id) == "ready" },
                    "status: \(app.status(of: id))"
                )
                a.expectEqual(app.session(id: id)?.activeSubagents, 0, "counter")
            },

            TestCase("a stop with no start does not push the counter below zero") { a in
                let id = "e2e-orphan-subagent"
                app.sendHook(HookPayloads.stop(sessionId: id, cwd: secondWorkspace))
                a.expect(
                    app.waitUntil { app.status(of: id) == "ready" },
                    "premise: \(app.status(of: id))"
                )

                // It really happens: the app starts mid-turn and only sees the end.
                app.sendHook(HookPayloads.subagentStop(
                    sessionId: id, cwd: secondWorkspace, agentId: "ghost"
                ))
                usleep(400_000)
                a.expectEqual(app.session(id: id)?.activeSubagents, 0, "counter")
                a.expectEqual(app.status(of: id), "ready", "status")
            },

            TestCase("a new prompt clears a counter left hanging") { a in
                let id = "e2e-hanging-subagent"
                // Two starts and no stops: that's what's left if the app is
                // restarted while agents are running.
                app.sendHook(HookPayloads.subagentStart(
                    sessionId: id, cwd: secondWorkspace, agentId: "lost-1"
                ))
                app.sendHook(HookPayloads.subagentStart(
                    sessionId: id, cwd: secondWorkspace, agentId: "lost-2"
                ))
                a.expect(
                    app.waitUntil { app.session(id: id)?.activeSubagents == 2 },
                    "premise: \(app.session(id: id)?.activeSubagents ?? -1)"
                )

                app.sendHook(HookPayloads.userPromptSubmit(sessionId: id, cwd: secondWorkspace))
                a.expect(
                    app.waitUntil { app.session(id: id)?.activeSubagents == 0 },
                    "counter: \(app.session(id: id)?.activeSubagents ?? -1)"
                )
            },

            TestCase("a subagent creates the row of a session never seen before") { a in
                let id = "e2e-subagent-discovery"
                app.sendHook(HookPayloads.subagentStart(
                    sessionId: id, cwd: secondWorkspace, agentId: "first"
                ))
                a.expect(
                    app.waitUntil { app.status(of: id) == "working" },
                    "status: \(app.status(of: id))"
                )
            },

            TestCase("a stop does not materialize a row out of nothing") { a in
                let id = "e2e-subagent-never-seen"
                app.sendHook(HookPayloads.subagentStop(
                    sessionId: id, cwd: secondWorkspace, agentId: "end-only"
                ))
                usleep(400_000)
                // Inventing a state out of its own conclusion is the simplest way
                // to fill the column with rows nobody needs.
                a.expectEqual(app.status(of: id), "absent", "status")
            },

            TestCase("events inside a subagent do not move the traffic light") { a in
                let id = "e2e-subagent-internal"
                app.sendHook(HookPayloads.stop(sessionId: id, cwd: secondWorkspace))
                a.expect(
                    app.waitUntil { app.status(of: id) == "ready" },
                    "premise: \(app.status(of: id))"
                )

                // A tool call *inside* a subagent carries `agent_id`: it is work
                // happening under the parent's turn and does not describe it.
                app.sendHook(HookPayloads.toolUseInsideSubagent(
                    sessionId: id, cwd: secondWorkspace, agentId: "agent-9"
                ))
                usleep(400_000)
                a.expectEqual(app.status(of: id), "ready", "status")
                a.expectEqual(app.session(id: id)?.activeSubagents, 0, "counter")
            },
        ])
    }
}
