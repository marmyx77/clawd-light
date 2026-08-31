import LampBoardCore
import Foundation
import TestKit

/// A Codex session becoming a row **without a single hook**.
///
/// The other end-to-end chain sends a signal and checks what the panel does with
/// it, and it would have gone green while Codex inside the ChatGPT app stayed
/// invisible: that surface registers our hooks, marks them trusted, runs a whole
/// session and sends nothing. A suite that can only ask questions through
/// `/signal` cannot see the case this feature exists for.
///
/// So nothing here touches the HTTP route. A file is written, a process holds it
/// open, and the row has to appear on its own.
enum CodexScannerSuite {

    /// A process called `codex` that holds a file open and does nothing else.
    ///
    /// `tail -f` copied under that name, and two details cost an hour each.
    ///
    /// **A shell will not do.** The obvious fixture was `/bin/sh -c 'exec 3< …'`,
    /// and the scanner never saw it: the name it matches on is `p_comm`, and bash
    /// sets its own, so a copy called `codex` reports itself as `bash`. `tail`
    /// does not rename itself.
    ///
    /// **And the copy has to be signed.** Copying a system binary strips its
    /// signature, and on Apple Silicon an unsigned one does not run at all. The
    /// first version died before it opened anything, which looked exactly like the
    /// scanner failing to find it.
    private final class FakeCodex {
        private let process = Process()
        let executable: URL

        init(holding path: String, in directory: URL) throws {
            executable = directory.appendingPathComponent("codex")
            try? FileManager.default.removeItem(at: executable)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: "/usr/bin/tail"), to: executable
            )
            let signing = Process()
            signing.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            signing.arguments = ["-f", "-s", "-", executable.path]
            signing.standardOutput = FileHandle.nullDevice
            signing.standardError = FileHandle.nullDevice
            try signing.run()
            signing.waitUntilExit()

            process.executableURL = executable
            process.arguments = ["-f", path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        }

        func letGo() {
            process.terminate()
            process.waitUntilExit()
        }
    }

    /// A moment in the recent past, written the way a rollout writes one.
    ///
    /// Not a fixed date, and the reason is a night this suite spent red. Every
    /// fixture here used to say `2026-08-30T09:00:00Z`, which worked until the
    /// clock passed `sessionStaleAfter` — twelve hours — after it. Then the row
    /// was adopted and pruned as stale inside the same sweep, and four cases
    /// began failing at a particular time of day, on code that had not changed.
    ///
    /// A test whose result depends on when it is run is not measuring the code.
    private static func momentsAgo(_ seconds: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date().addingTimeInterval(-seconds))
    }

    /// A subagent's rollout: the parent's `session_id`, its own `id`, and a
    /// `source` that is an object rather than a surface. Measured shape.
    private static func writeSubagentRollout(
        in home: URL, parent: String, child: String, cwd: String
    ) throws -> String {
        let directory = home
            .appendingPathComponent(".codex/sessions/2026/08/30", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("rollout-child-\(child).jsonl")
        let line = #"{"timestamp":"\#(momentsAgo(60))","type":"session_meta","payload":{"session_id":"\#(parent)","id":"\#(child)","cwd":"\#(cwd)","originator":"Codex Desktop","source":{"subagent":{"other":"guardian"}}}}"#
        try line.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    /// A rollout as Codex writes one: the metadata first, then events.
    private static func writeRollout(
        in home: URL, sessionId: String, cwd: String, lastSpoken: String
    ) throws -> String {
        let directory = home
            .appendingPathComponent(".codex/sessions/2026/08/30", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("rollout-2026-08-30T09-00-00-\(sessionId).jsonl")

        let lines = [
            #"{"timestamp":"\#(lastSpoken)","type":"session_meta","payload":{"session_id":"\#(sessionId)","cwd":"\#(cwd)","originator":"codex-tui","source":"cli","cli_version":"0.151.0"}}"#,
            #"{"timestamp":"\#(lastSpoken)","type":"event_msg","payload":{"type":"task_started"}}"#,
            // No timestamp, and it must not become the moment: this is the shape
            // that made three Claude projects read as active while untouched.
            #"{"type":"bridge-session","id":"x"}"#,
        ]
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    static func suite(app: AppUnderTest) -> TestSuite {
        TestSuite("E2E · Codex found without hooks", [

            TestCase("a session nobody announced becomes a row") { a in
                let cwd = "/tmp/lampboard-e2e-codex-project"
                guard let path = try? writeRollout(
                    in: app.home, sessionId: "e2e-codex-1", cwd: cwd,
                    lastSpoken: momentsAgo(300)
                ), let held = try? FakeCodex(holding: path, in: app.home) else {
                    a.expect(false, "the fixture could not be set up")
                    return
                }
                defer { held.letGo() }

                a.expect(
                    app.waitUntil { app.session(id: "e2e-codex-1") != nil },
                    "no hook was sent, and the row still has to arrive"
                )

                let session = app.session(id: "e2e-codex-1")
                a.expectEqual(session?.harness, "codex", "the agent it belongs to")
                a.expectEqual(session?.workspace, "lampboard-e2e-codex-project",
                              "the folder comes from the file, never from a request")
                a.expectEqual(session?.status, "idle",
                              "an open descriptor proves it is loaded, not that it is working")
            },

            TestCase("the executable it runs from decides what a click may promise") { a in
                // A `codex` of its own, not one inside an application bundle, so
                // the surface is the command line and the row must not offer a
                // window: the same binary runs in Terminal, Ghostty and tmux.
                a.expectEqual(
                    app.session(id: "e2e-codex-1")?.entrypoint,
                    CodexSurface.commandLine.entrypoint,
                    "read from the binary, not from what the transcript calls itself"
                )
            },

            TestCase("a conversation open since yesterday keeps its row") { a in
                // The defect that made the panel flicker, and it only appeared
                // once the clock had moved: a rollout whose last word is older
                // than sessionStaleAfter was pruned for being old at the end of
                // every sweep, and re-adopted when the probe answered a moment
                // later. Six rows, on and off, four times a minute.
                //
                // An open rollout is a conversation loaded, not a model working,
                // so its last word can be days old while the process holding it
                // is alive. That descriptor is a confirmation, and the age rule
                // is the bound for rows nobody can confirm.
                let old = AppConfig.sessionStaleAfter + 3600
                guard let path = try? writeRollout(
                        in: app.home, sessionId: "e2e-codex-old", cwd: "/tmp/lampboard-e2e-codex-old",
                        lastSpoken: momentsAgo(old)
                      ),
                      let held = try? FakeCodex(holding: path, in: app.home)
                else {
                    a.expect(false, "the fixture could not be set up")
                    return
                }
                defer { held.letGo() }

                a.expect(app.waitUntil { app.session(id: "e2e-codex-old") != nil },
                         "yesterday's conversation is still a row")
                a.expect(app.holdsThroughTwoSweeps { app.session(id: "e2e-codex-old") != nil },
                         "and it is still there two sweeps later, not blinking")
            },

            TestCase("letting the file go takes the row with it") { a in
                let cwd = "/tmp/lampboard-e2e-codex-closing"
                guard let path = try? writeRollout(
                    in: app.home, sessionId: "e2e-codex-2", cwd: cwd,
                    lastSpoken: momentsAgo(300)
                ), let held = try? FakeCodex(holding: path, in: app.home) else {
                    a.expect(false, "the fixture could not be set up")
                    return
                }
                a.expect(app.waitUntil { app.session(id: "e2e-codex-2") != nil }, "it arrived")

                // The file stays on disk. Closing the conversation closes the
                // descriptor, and that is the only ending Codex gives us for free.
                held.letGo()
                a.expect(
                    app.waitUntil { app.session(id: "e2e-codex-2") == nil },
                    "the rollout is still there; nothing is holding it"
                )
            },

            TestCase("a subagent's rollout does not become its parent's row") { a in
                // The subagent's rollout is held open **alone** first, and that
                // ordering is the whole test. Held beside the parent's, whichever
                // file the probe happened to reach first would win, and the case
                // would pass or fail on a coin toss: with both open it passed
                // even with the rule deleted.
                //
                // Alone, there is no ambiguity. The file carries the parent's
                // `session_id`, so read as a session it is a whole conversation
                // in a folder that is the subagent's, not the parent's.
                let parent = "e2e-codex-parent"
                let subagentFolder = "/tmp/lampboard-e2e-codex-subagent"
                let parentFolder = "/tmp/lampboard-e2e-codex-parentfolder"
                guard let childPath = try? writeSubagentRollout(
                        in: app.home, parent: parent, child: "e2e-codex-child",
                        cwd: subagentFolder
                      ),
                      let holdingChild = try? FakeCodex(holding: childPath, in: app.home)
                else {
                    a.expect(false, "the fixture could not be set up")
                    return
                }
                defer { holdingChild.letGo() }

                a.expect(
                    app.holdsThroughTwoSweeps { app.session(id: parent) == nil },
                    "a subagent at work is not a conversation you can open"
                )
                a.expectNil(app.session(id: "e2e-codex-child"), "under either name")

                // Now the conversation itself. It has its own rollout, held open
                // by a process of its own, and that is the one the row is made
                // of: its folder, and its file as the thread back to its window.
                guard let parentPath = try? writeRollout(
                        in: app.home, sessionId: parent, cwd: parentFolder,
                        lastSpoken: momentsAgo(30)
                      ),
                      let holdingParent = try? FakeCodex(holding: parentPath, in: app.home)
                else {
                    a.expect(false, "the fixture could not be advanced")
                    return
                }
                defer { holdingParent.letGo() }

                a.expect(app.waitUntil { app.session(id: parent) != nil }, "the conversation arrives")
                a.expectEqual(
                    app.session(id: parent)?.workspace, "lampboard-e2e-codex-parentfolder",
                    "naming the folder its own rollout named"
                )
            },

            TestCase("installing reaches Codex too, and leaves its own hooks alone") { a in
                // Codex is configured only where it is actually present: writing a
                // hooks file into a directory nobody has ever used would leave a
                // configuration for a program that is not there.
                let codex = app.home.appendingPathComponent(".codex")
                try? FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
                let hooksFile = codex.appendingPathComponent("hooks.json")
                let foreign = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/somebody/else.sh"}]}]}}"#
                try? foreign.write(to: hooksFile, atomically: true, encoding: .utf8)

                let result = app.runCommand(["install-hooks", "--port", String(app.port)])
                a.expectEqual(result.status, 0, "exit code")

                let text = (try? String(contentsOf: hooksFile, encoding: .utf8)) ?? ""
                a.expect(text.contains("codex-hook.sh"), "ours is registered")
                a.expect(text.contains("/somebody/else.sh"), "and theirs is still there")
            },

            TestCase("uninstalling removes Codex as well, and says so per harness") { a in
                // It used to remove only Claude Code's, while reporting success:
                // Codex kept calling a script for a program that was gone, and the
                // Homebrew caveat promises a removal this command is the whole of.
                let hooksFile = app.home.appendingPathComponent(".codex/hooks.json")
                let result = app.runCommand(["uninstall-hooks"])
                a.expectEqual(result.status, 0, "exit code")
                a.expect(result.output.contains("Codex"), "the second harness is named")

                let text = (try? String(contentsOf: hooksFile, encoding: .utf8)) ?? ""
                a.expect(!text.contains("codex-hook.sh"), "ours is gone")
                a.expect(text.contains("/somebody/else.sh"),
                         "and somebody else's survived, which is the whole care here")
            },
            TestCase("a hook about a row that already exists moves its light") { a in
                // The defect this exists for, measured on a live Mac: six Codex
                // sessions in six terminals, every one of them born from the
                // rollout it holds open and every one of them idle for ever.
                // Their hooks arrived and were discarded, because the gate that
                // decides whether a folder may **have** a row was also deciding
                // whether a row already on the column may change colour. No
                // Claude Code window claims a folder somebody is working in from
                // a terminal, and Codex writes no session file naming itself.
                let cwd = "/tmp/lampboard-e2e-codex-live"
                guard let path = try? writeRollout(
                    in: app.home, sessionId: "e2e-codex-4", cwd: cwd,
                    lastSpoken: momentsAgo(300)
                ), let held = try? FakeCodex(holding: path, in: app.home) else {
                    a.expect(false, "the fixture could not be set up")
                    return
                }
                defer { held.letGo() }
                a.expect(app.waitUntil { app.session(id: "e2e-codex-4") != nil }, "the row arrived")
                a.expectEqual(app.status(of: "e2e-codex-4"), "idle", "and it starts knowing nothing")

                // The shape Codex really sends: no `transcript_path`, and the
                // harness named in a header, which is the only place it is said.
                a.expectEqual(
                    app.sendHook(
                        ["session_id": "e2e-codex-4", "hook_event_name": "UserPromptSubmit", "cwd": cwd],
                        entrypoint: nil, harness: "codex"
                    ),
                    204, "the signal is accepted"
                )
                a.expect(
                    app.waitUntil { app.status(of: "e2e-codex-4") == "working" },
                    "a turn started, and the row has to say so"
                )

                // And the row keeps what found it: the folder from the rollout,
                // not the one the hook happened to be standing in, and the file
                // the click follows back to a terminal tab.
                a.expectEqual(app.session(id: "e2e-codex-4")?.harness, "codex", "still Codex")
                a.expectEqual(
                    app.session(id: "e2e-codex-4")?.workspace, "lampboard-e2e-codex-live",
                    "still the folder the rollout named"
                )
                // Compared as the filesystem spells it: the row holds the path
                // `lsof` reported, and under a temporary home that is reached
                // through `/var`, which is a link to `/private/var` on every
                // Mac. The fixture writes one spelling and the evidence carries
                // the other, and they are one file.
                a.expect(
                    CanonicalPath.same(app.session(id: "e2e-codex-4")?.transcriptPath ?? "", path),
                    "still the rollout, which is the only thread back to its window"
                )
            },

            TestCase("a rollout nobody holds open is not a session") { a in
                // Ten rollouts on this machine, three open. The seven others are
                // conversations that happened, and a panel listing them would be a
                // column of things nobody can go to.
                let cwd = "/tmp/lampboard-e2e-codex-cold"
                guard (try? writeRollout(
                    in: app.home, sessionId: "e2e-codex-3", cwd: cwd,
                    lastSpoken: momentsAgo(300)
                )) != nil else {
                    a.expect(false, "the fixture could not be written")
                    return
                }
                Thread.sleep(forTimeInterval: 2)
                a.expect(app.session(id: "e2e-codex-3") == nil, "written, and never opened")
            },
        ])
    }
}
