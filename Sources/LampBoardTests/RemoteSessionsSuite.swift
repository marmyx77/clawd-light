import LampBoardCore
import Foundation
import TestKit

/// Sessions that run on another machine.
///
/// lampboard was built as a single-machine tool and said so by construction:
/// the hook posts to `127.0.0.1`, the server binds `127.0.0.1`, and a row exists
/// only if a local VS Code lock claims its folder. A session running over ssh on
/// the always-on node therefore never appeared — four independent barriers, all
/// measured.
///
/// The way in is not to open the local port. `POST /signal` carries no token, so
/// exposing it on the tailnet would put unauthenticated state injection on the
/// network. Instead the node is **read**: it already answers over ssh, and it is
/// the only place where the two checks that matter can be made — `kill(pid, 0)`
/// and the transcript's timestamp.
enum RemoteSessionsSuite {

    private static let host = "node"

    /// `true` when the local python3 can parse `script`. Parsing only: nothing runs.
    private static func pythonParses(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", "import ast, sys; ast.parse(sys.stdin.read())"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        input.fileHandleForWriting.write(Data(script.utf8))
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func decode(_ json: String) -> [LiveSession] {
        (try? RemoteSessionsDecoder.decode(
            Data(json.utf8), host: host
        )) ?? []
    }

    static let suite = TestSuite("Remote sessions", [

        // The shape the node actually emits, taken from a live probe.
        TestCase("A real payload decodes") { t in
            let sessions = decode("""
            [{"pid":1838232,"sessionId":"9c93b73b-1111-2222-3333-444455556666",
              "cwd":"/home/dev/.notes","entrypoint":"cli","name":"notes",
              "kind":"interactive","activityEpoch":1787223193}]
            """)
            t.expectEqual(sessions.count, 1, "sessions")
            t.expectEqual(sessions.first?.pid, 1838232, "pid")
            t.expectEqual(sessions.first?.cwd, "/home/dev/.notes", "cwd")
            t.expectEqual(sessions.first?.entrypoint, "cli", "entrypoint")
            t.expectEqual(
                sessions.first?.modifiedAt,
                Date(timeIntervalSince1970: 1787223193),
                "activity comes from the node, not from this machine's clock"
            )
        },

        TestCase("Several sessions on the same host all arrive") { t in
            let sessions = decode("""
            [{"pid":1,"sessionId":"aaaaaaaa-1111","cwd":"/home/dev/.notes",
              "entrypoint":"cli","kind":"interactive","activityEpoch":100},
             {"pid":2,"sessionId":"bbbbbbbb-2222","cwd":"/home/dev/Development/x",
              "entrypoint":"cli","kind":"interactive","activityEpoch":200}]
            """)
            t.expectEqual(sessions.count, 2, "sessions")
        },

        // A malformed entry must not take the whole read down with it: the node is
        // a machine we do not control the output of, and one bad record is not a
        // reason to lose the other two.
        TestCase("One broken record does not lose the others") { t in
            let sessions = decode("""
            [{"pid":1,"sessionId":"aaaaaaaa-1111","cwd":"/home/dev/a",
              "entrypoint":"cli","activityEpoch":100},
             {"nonsense":true},
             {"pid":3,"sessionId":"cccccccc-3333","cwd":"/home/dev/c",
              "entrypoint":"cli","activityEpoch":300}]
            """)
            t.expectEqual(sessions.map(\.pid), [1, 3], "the survivors")
        },

        TestCase("A record without a session id is dropped") { t in
            t.expectEqual(
                decode(#"[{"pid":1,"cwd":"/home/dev/a","activityEpoch":1}]"#).count,
                0, "sessions"
            )
        },

        TestCase("A relative cwd is dropped rather than resolved") { t in
            t.expectEqual(
                decode(#"[{"pid":1,"sessionId":"aaaaaaaa-1111","cwd":"marco/a","activityEpoch":1}]"#).count,
                0, "a relative path here would mean guessing whose root it is"
            )
        },

        TestCase("Rubbish in gives nothing out, and does not crash") { t in
            t.expectEqual(decode("not json at all").count, 0, "sessions")
            t.expectEqual(decode("{}").count, 0, "an object is not a list")
            t.expectEqual(decode("[]").count, 0, "empty is fine")
        },

        // MARK: The workspace of a remote session

        // Locally a row exists only if a VS Code window claims the folder. That
        // criterion is meaningless for a session in a tmux pane on a headless
        // node, and applying it there is exactly what kept these rows invisible.
        TestCase("A remote session's workspace is its own folder") { t in
            let w = Workspace(path: "/home/dev/.notes", host: host)
            t.expectEqual(w.name, ".notes", "name")
            t.expectEqual(w.host, host, "host")
            t.expect(w.isRemote, "it must know it is not here")
        },

        TestCase("A local workspace stays local") { t in
            let w = Workspace(path: "/Users/dev/project")
            t.expectNil(w.host, "host")
            t.expect(!w.isRemote, "no host means this machine")
        },

        // Two folders with the same name on two machines are two rows, not one.
        TestCase("The same path on two hosts is two workspaces") { t in
            let here = Workspace(path: "/w/project")
            let there = Workspace(path: "/w/project", host: host)
            t.expect(here != there, "they must not collapse into one row")
        },

        TestCase("The label says where it is, the name does not") { t in
            let w = Workspace(path: "/home/dev/.notes", host: host)
            t.expectEqual(w.label, ".notes @node", "label")
            t.expectEqual(w.name, ".notes", "the name stays the folder")
        },

        // MARK: Which hosts to ask

        TestCase("Absent or empty means the feature is off") { t in
            t.expectEqual(RemoteHostList.parse("").count, 0, "empty")
            t.expectEqual(RemoteHostList.parse("\n\n  \n").count, 0, "blank lines only")
            t.expectEqual(RemoteHostList.parse("# just a comment\n").count, 0, "comments only")
        },

        TestCase("One name per line, comments and duplicates removed") { t in
            t.expectEqual(
                RemoteHostList.parse("""
                # the always-on box
                node   # via the VPN
                mac-mini
                node
                """),
                ["node", "mac-mini"],
                "hosts"
            )
        },

        // The name becomes an argument to ssh. It never reaches a shell, but a
        // name starting with a dash would be read by ssh as *options*, and one
        // with a space would split into two arguments.
        TestCase("A name ssh would misread is refused") { t in
            t.expect(RemoteHostList.isUsable("node"), "plain")
            t.expect(RemoteHostList.isUsable("dev@192.0.2.10"), "user@host")
            t.expect(!RemoteHostList.isUsable("-oProxyCommand=curl evil"), "leading dash")
            t.expect(!RemoteHostList.isUsable("host with space"), "space")
            t.expect(!RemoteHostList.isUsable("host;rm -rf /"), "separator")
            t.expect(!RemoteHostList.isUsable(""), "empty")
        },

        TestCase("A refused name does not take the good ones with it") { t in
            t.expectEqual(
                RemoteHostList.parse("node\n-oProxyCommand=x\nmac-mini"),
                ["node", "mac-mini"],
                "hosts"
            )
        },

        // MARK: The script that runs there

        // It is a promise made to another machine: the shape it prints is what the
        // decoder above parses, and the two must not drift apart.
        TestCase("The probe emits the fields the decoder reads") { t in
            for field in ["sessionId", "cwd", "entrypoint", "name", "kind", "activityEpoch", "pid"] {
                t.expect(
                    RemoteProbeScript.script.contains("\"\(field)\""),
                    "the probe must emit \(field)"
                )
            }
        },

        // The same encoding rule as TranscriptLocator, expressed once more because
        // it has to run on the other machine. If these two ever disagree, activity
        // silently falls back to the session file — which is the frozen one.
        TestCase("The probe reads activity from the transcript, not the session file") { t in
            t.expect(RemoteProbeScript.script.contains("*.jsonl"), "it must stat transcripts")
            t.expect(
                RemoteProbeScript.script.contains("[^a-zA-Z0-9]"),
                "and encode the folder the way TranscriptLocator does"
            )
        },

        // MARK: What deserves a row

        // Found by building the remote path, and it was never about remote. An SDK
        // session that declares itself `interactive` slipped through, because the
        // check returned on `kind` and never reached the entrypoint. Locally it
        // stayed invisible for the wrong reason — no editor window claimed its
        // folder — so removing that accidental filter is what exposed it.
        //
        // Real shape, from the node: claude-mem's observer.
        TestCase("An SDK session calling itself interactive is still not a row") { t in
            let observer = LiveSession(
                pid: 1, sessionId: "aaaaaaaa-1111",
                cwd: "/home/dev/.claude-mem/observer-sessions",
                entrypoint: "sdk-cli", name: "observer-sessions-c7",
                kind: "interactive", modifiedAt: Date(), host: host
            )
            t.expect(!observer.deservesTrafficLight, "an SDK session has nobody in front of it")
        },

        TestCase("A real interactive session still gets its row") { t in
            let interactive = LiveSession(
                pid: 2, sessionId: "bbbbbbbb-2222", cwd: "/home/dev/.notes",
                entrypoint: "cli", name: "notes-32", kind: "interactive",
                modifiedAt: Date(), host: host
            )
            t.expect(interactive.deservesTrafficLight, "cli + interactive is exactly the case")
        },

        TestCase("A non-interactive kind is refused whatever started it") { t in
            let batch = LiveSession(
                pid: 3, sessionId: "cccccccc-3333", cwd: "/home/dev/x",
                entrypoint: "cli", name: nil, kind: "batch",
                modifiedAt: Date(), host: host
            )
            t.expect(!batch.deservesTrafficLight, "kind still decides when it disagrees")
        },

        TestCase("The probe checks liveness where the processes are") { t in
            t.expect(RemoteProbeScript.script.contains("os.kill(pid, 0)"), "kill(pid, 0)")
            t.expect(
                RemoteProbeScript.script.contains("PermissionError"),
                "a process owned by somebody else is still alive"
            )
        },

        // A pid outlives its process: after a reboot the same number names
        // something else, and kill(pid, 0) would keep a dead session's row alive.
        // A script that does not parse is a promise nobody can keep, and no
        // `contains` check sees it: two literals joined without a newline once
        // produced `return Nonedef bound_addresses` and a tunnel that retried
        // forever. python3 is on every Mac; let it read what the node will read.
        TestCase("Every script sent to another machine is valid Python") { t in
            for (name, script) in [
                ("probe", RemoteProbeScript.script),
                ("inspect", RemoteInstallScripts.inspect),
                ("apply", RemoteInstallScripts.apply(payloadBase64: "e30=")),
                ("prepareTunnel", RemoteInstallScripts.prepareTunnel),
                ("checkTunnel", RemoteInstallScripts.checkTunnel(port: 31000)),
            ] {
                t.expect(pythonParses(script), "\(name) does not parse")
            }
        },

        // What runs on the node to install the hooks, and the promises it keeps.
        TestCase("The install scripts check the directory, compare before writing, and keep the mode") { t in
            let apply = RemoteInstallScripts.apply(payloadBase64: "e30=")
            t.expect(apply.contains("expectedSha256"), "compare-and-swap on the settings")
            t.expect(apply.contains("shutil.copy2"), "the backup keeps the file's mode")
            t.expect(apply.contains("os.chmod(tmp, mode)") && apply.contains("os.replace(tmp, settings_path)"), "atomic write, same mode")
            t.expect(apply.contains("S_ISLNK") && apply.contains("st_uid != os.getuid()"), "a symlinked or foreign ~/.lampboard is refused")
            t.expect(RemoteInstallScripts.inspect.contains("settingsSha256"), "the inspection hands back what to compare")
            // The bind is a request; whether it was honoured is read where it is a fact.
            t.expect(RemoteInstallScripts.prepareTunnel.contains("/proc/net/tcp"), "a taken port is seen before the tunnel asks for it")
            t.expect(RemoteInstallScripts.checkTunnel(port: 31000).contains("bound_addresses(31000)"), "the tunnel check reports where the port is bound")
        },

        TestCase("The probe refuses a pid that has been reused") { t in
            t.expect(RemoteProbeScript.script.contains("/proc/%d/stat"), "reads the start time where it is")
            t.expect(
                RemoteProbeScript.script.contains("record.get(\"procStart\")"),
                "compares it with what the session file remembers"
            )
        },
    ])
}
