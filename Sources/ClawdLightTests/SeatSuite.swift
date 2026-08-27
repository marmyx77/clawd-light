import ClawdLightCore
import Foundation
import TestKit

/// Where a session lives, read off its ancestry — every chain here was measured
/// on a real machine (docs/plans/terminal-sessions.md, §0).
enum SeatSuite {

    private static func process(
        _ pid: Int32, _ ppid: Int32, _ path: String, tty: String? = nil, arguments: [String] = []
    ) -> ProcessAncestor {
        ProcessAncestor(pid: pid, ppid: ppid, executablePath: path, arguments: arguments, tty: tty)
    }

    private static let terminalApp = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
    private static let codeHelper = "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"
    private static let pluginHost = "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"
    private static let code = "/Applications/Visual Studio Code.app/Contents/MacOS/Code"

    static let suite = TestSuite("Seats: where a session lives", [

        TestCase("A claude in a Terminal.app tab sits on that tab's tty") { t in
            let chain = [
                process(100, 101, "/usr/local/bin/claude", tty: "ttys003"),
                process(101, 102, "/bin/zsh", tty: "ttys003"),
                process(102, 103, "/usr/bin/login", tty: "ttys003"),
                process(103, 1, terminalApp),
            ]
            t.expectEqual(SeatClassifier.classify(chain), .terminal(.terminal, tty: "/dev/ttys003"))
        },

        TestCase("iTerm2 is recognised by its bundle, whatever the binary is called") { t in
            let chain = [
                process(100, 101, "/usr/local/bin/claude", tty: "ttys007"),
                process(101, 102, "/bin/zsh", tty: "ttys007"),
                process(102, 1, "/Applications/iTerm.app/Contents/MacOS/iTerm2"),
            ]
            t.expectEqual(SeatClassifier.classify(chain), .terminal(.iTerm, tty: "/dev/ttys007"))
        },

        TestCase("A zellij pane names its server and session; the tty is the server's, not a tab's") { t in
            let chain = [
                process(100, 101, "/usr/local/bin/claude", tty: "ttys009"),
                process(101, 2574, "/bin/zsh", tty: "ttys009"),
                process(2574, 1, "/opt/homebrew/bin/zellij",
                        arguments: ["/opt/homebrew/bin/zellij", "--server", "/var/folders/x/T/zellij-501/contract_version_1/quiet-owl"]),
            ]
            t.expectEqual(SeatClassifier.classify(chain), .zellij(serverPid: 2574, sessionName: "quiet-owl"))
        },

        TestCase("A tmux pane names its server and keeps the pane's tty") { t in
            let chain = [
                process(100, 101, "/usr/local/bin/claude", tty: "ttys011"),
                process(101, 900, "/bin/zsh", tty: "ttys011"),
                process(900, 1, "/opt/homebrew/bin/tmux"),
            ]
            t.expectEqual(SeatClassifier.classify(chain), .tmux(serverPid: 900, tty: "/dev/ttys011"))
        },

        // The pty host lives in `Code Helper.app`, the extension host in
        // `Code Helper (Plugin).app`: both are editor seats, and neither is
        // "Terminal" because it contains the word "Helper".
        TestCase("Both of VS Code's helpers are editor seats") { t in
            let panel = [
                process(100, 200, "/Users/dev/.vscode/extensions/claude/resources/native/claude"),
                process(200, 300, pluginHost),
                process(300, 1, code),
            ]
            t.expectEqual(SeatClassifier.classify(panel), .editor(.visualStudioCode), "the Claude panel")

            let integrated = [
                process(100, 150, "/usr/local/bin/claude", tty: "ttys004"),
                process(150, 250, "/bin/zsh", tty: "ttys004"),
                process(250, 300, codeHelper),
                process(300, 1, code),
            ]
            t.expectEqual(SeatClassifier.classify(integrated), .editor(.visualStudioCode), "the integrated terminal")
        },

        TestCase("An application we cannot select a tab in is still named; nothing at all is unknown") { t in
            let foo = [
                process(100, 101, "/usr/local/bin/claude", tty: "ttys005"),
                process(101, 102, "/bin/zsh", tty: "ttys005"),
                process(102, 1, "/Applications/Foo.app/Contents/MacOS/Foo"),
            ]
            t.expectEqual(SeatClassifier.classify(foo), .application(bundlePath: "/Applications/Foo.app"))

            let daemon = [
                process(100, 101, "/usr/local/bin/claude"),
                process(101, 1, "/bin/zsh"),
            ]
            t.expectEqual(SeatClassifier.classify(daemon), .unknown)
            t.expectEqual(SeatClassifier.classify([]), .unknown, "no chain")
        },

        TestCase("A terminal reached without a tty is only an application") { t in
            let chain = [
                process(100, 101, "/usr/local/bin/claude"),
                process(101, 1, terminalApp),
            ]
            t.expectEqual(
                SeatClassifier.classify(chain),
                .application(bundlePath: "/System/Applications/Utilities/Terminal.app")
            )
        },

        // The tty is the one string from the process table that reaches an
        // AppleScript source: it is matched, not escaped.
        TestCase("tty names are normalised to the device path, or refused") { t in
            t.expectEqual(TTYName.normalized("ttys003"), "/dev/ttys003")
            t.expectEqual(TTYName.normalized("/dev/ttys12"), "/dev/ttys12")
            t.expectEqual(TTYName.normalized(" ttys003 "), "/dev/ttys003", "trimmed")
            t.expectNil(TTYName.normalized("ttys003\" & do shell script \"x"), "a quote is refused")
            t.expectNil(TTYName.normalized("pts/0"), "another platform's shape")
            t.expectNil(TTYName.normalized(""), "empty")
        },

        TestCase("The scripts name the tty, refuse a bad one, and exist only for tty hosts") { t in
            let terminal = TerminalScripts.selectTab(tty: "ttys003", in: .terminal)
            t.expect(terminal?.contains("if tty of t is \"/dev/ttys003\"") == true, "Terminal walks the tabs")
            t.expect(terminal?.contains("number -1728") == true, "and errors the way a missing window does")
            let iterm = TerminalScripts.selectTab(tty: "/dev/ttys007", in: .iTerm)
            t.expect(iterm?.contains("sessions of t") == true, "iTerm2 walks sessions inside tabs")
            t.expectNil(TerminalScripts.selectTab(tty: "ttys003; rm", in: .terminal), "a bad tty makes no script")
            t.expectNil(TerminalScripts.selectTab(tty: "ttys003", in: .ghostty), "Ghostty has no tty to match")
        },

        TestCase("A zellij session name is validated before it is trusted") { t in
            t.expectEqual(SeatClassifier.zellijSessionName(in: ["zellij", "--server", "/tmp/z/quiet-owl"]), "quiet-owl")
            t.expectNil(SeatClassifier.zellijSessionName(in: ["zellij", "--server", "/tmp/z/bad name"]), "a space")
            t.expectNil(SeatClassifier.zellijSessionName(in: ["zellij", "--server"]), "no value")
            t.expectNil(SeatClassifier.zellijSessionName(in: ["zellij"]), "a client, not a server")
        },

        // macOS writes procStart as a ctime string in UTC with no zone marker;
        // parsed as local time it is off by the zone, and the guard then rejects
        // every live session or accepts a dead one's reused pid.
        TestCase("procStart is parsed as UTC on macOS and as ticks on Linux") { t in
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let expected = utc.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 17, minute: 7, second: 24))!

            t.expectEqual(ProcStart.parse("Wed Aug 26 17:07:24 2026"), .date(expected), "measured value")
            t.expectEqual(ProcStart.parse("Wed Aug  6 09:00:00 2026"),
                          .date(utc.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 9))!),
                          "ctime pads the day with a space")
            t.expectEqual(ProcStart.parse("5480393"), .ticks(5_480_393), "the Linux form")
            t.expectNil(ProcStart.parse("yesterday"), "garbage")

            let start = ProcStart.date(expected)
            t.expect(start.matches(processStartedAt: expected.addingTimeInterval(0.6)), "sub-second drift is the same process")
            t.expect(!start.matches(processStartedAt: expected.addingTimeInterval(7200)), "two hours is the zone trap, or another process")
            t.expect(ProcStart.ticks(1).matches(processStartedAt: expected), "ticks cannot be checked here and do not refuse")
        },
    ])
}

/// The two hops through a multiplexer: what tmux and `lsof` say, parsed.
enum MultiplexerSuite {
    static let suite = TestSuite("Multiplexers: tmux and zellij listings", [

        // Measured on a zellij server and its client: DEVICE is the socket's own
        // address, NAME its peer — the pairing is client peer ∈ server address.
        TestCase("A zellij client is paired with its server through lsof") { t in
            let server = LsofUnixSockets.parse("""
            COMMAND  PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
            zellij  2574 dev    5u  unix 0xf6a0224dbdf3c999      0t0      /var/folders/x/T/zellij-501/contract_version_1/quiet-owl
            zellij  2574 dev    6u  unix 0x5e075b05655b64e1      0t0      /var/folders/x/T/zellij-501/contract_version_1/quiet-owl
            zellij  2574 dev    9u  unix 0xb94472fcc137a960      0t0      ->0xc55945fff274cabe
            """)
            let clients = LsofUnixSockets.parse("""
            COMMAND  PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
            zellij  2571 dev    5u  unix 0x57b40d36d36df282      0t0      ->0x5e075b05655b64e1
            zellij  2571 dev    6u  unix 0x57b40d36d36df283      0t0      ->0x5e075b05655b64e1
            zellij  3000 dev    5u  unix 0x1111111111111111      0t0      ->0x2222222222222222
            """)
            t.expectEqual(server.count, 3, "server sockets")
            t.expectEqual(server[0].path, "/var/folders/x/T/zellij-501/contract_version_1/quiet-owl", "the bound path")
            t.expectEqual(server[2].peer, "0xc55945fff274cabe", "a peer")
            t.expectEqual(LsofUnixSockets.clientPids(of: server, among: clients), [2571], "one client, once")
            t.expect(LsofUnixSockets.parse("garbage\n\n").isEmpty, "nothing parses to nothing")
        },

        TestCase("tmux panes and clients are read with the formats we ask for") { t in
            let panes = TmuxListing.panes("/dev/ttys011\t901\tprobe:0.0\n/dev/ttys012\t902\tprobe:1.0\nbad line\n")
            t.expectEqual(panes.count, 2, "panes")
            t.expectEqual(panes[0].tty, "/dev/ttys011")
            t.expectEqual(panes[0].shellPid, 901)
            t.expectEqual(panes[1].target, "probe:1.0")
            t.expectEqual(panes[1].session, "probe")
            t.expectEqual(panes[1].window, "probe:1")

            let clients = TmuxListing.clients("/dev/ttys003\t500\tprobe\nttys004\t501\t-evil\n")
            t.expectEqual(clients.count, 1, "a name starting with a dash is refused")
            t.expectEqual(clients[0].pid, 500)
            t.expectEqual(clients[0].session, "probe")
            t.expect(TmuxListing.paneFormat.contains("#{pane_tty}"), "the format names the tty")
        },

        TestCase("The title fallback script takes only a validated fragment") { t in
            let script = TerminalScripts.selectTab(titleContaining: "quiet-owl", in: .terminal)
            t.expect(script?.contains("if name of t contains \"quiet-owl\"") == true, "Terminal")
            t.expect(TerminalScripts.selectTab(titleContaining: "quiet-owl", in: .iTerm)?.contains("sessions of t") == true, "iTerm2")
            t.expectNil(TerminalScripts.selectTab(titleContaining: "owl\" & \"x", in: .terminal), "a quote is refused")
            t.expectNil(TerminalScripts.selectTab(titleContaining: "quiet-owl", in: .ghostty), "no dictionary route")
        },
    ])
}

/// The three hosts without a tty in their dictionary: what their listings say.
enum TerminalListingSuite {
    static let suite = TestSuite("Terminal listings: WezTerm, kitty, Ghostty", [

        TestCase("WezTerm panes are keyed by tty, and the cwd is a file URL") { t in
            let json = Data("""
            [{"window_id":0,"tab_id":0,"pane_id":3,"title":"zsh","cwd":"file:///private/tmp/probe","tty_name":"/dev/ttys012","is_active":true},
             {"window_id":0,"tab_id":1,"pane_id":4,"title":"claude","cwd":"file:///Users/dev","tty_name":"/dev/ttys013"}]
            """.utf8)
            let panes = WezTermListing.parse(json)
            t.expectEqual(panes.count, 2, "panes")
            t.expectEqual(panes[0].cwd, "/private/tmp/probe", "cwd as a path")
            t.expectEqual(WezTermListing.pane(onTTY: "ttys013", in: panes)?.paneId, 4, "by tty, either shape")
            t.expectNil(WezTermListing.pane(onTTY: "ttys099", in: panes), "no pane")
            t.expect(WezTermListing.parse(Data("nope".utf8)).isEmpty, "garbage parses to nothing")
        },

        TestCase("kitty windows are found by the pid they run or front") { t in
            let json = Data("""
            [{"id":1,"tabs":[{"id":1,"title":"zsh","windows":[
               {"id":7,"pid":500,"cwd":"/tmp/a","title":"zsh","foreground_processes":[{"pid":500,"cwd":"/tmp/a","cmdline":["zsh"]}]},
               {"id":8,"pid":600,"cwd":"/Users/dev","title":"✳ Wire it","foreground_processes":[{"pid":601,"cwd":"/Users/dev","cmdline":["claude"]}]}
            ]}]}]
            """.utf8)
            let windows = KittyListing.parse(json)
            t.expectEqual(windows.count, 2, "windows across tabs")
            t.expectEqual(KittyListing.window(hostingAnyOf: [601], in: windows)?.id, 8, "the claude in the foreground")
            t.expectEqual(KittyListing.window(hostingAnyOf: [500], in: windows)?.id, 7, "the shell itself")
            t.expectNil(KittyListing.window(hostingAnyOf: [999], in: windows), "nobody")
        },

        TestCase("Ghostty terminals are matched by title first, folder second, and never by guess") { t in
            let terminals = [
                GhosttyMatcher.Terminal(id: "A", name: "✳ Other", workingDirectory: "/Users/dev"),
                GhosttyMatcher.Terminal(id: "B", name: "✳ Wire it", workingDirectory: "/Users/dev/other"),
            ]
            t.expectEqual(GhosttyMatcher.best(among: terminals, cwd: "/Users/dev", title: "Wire it")?.id, "B", "title wins")
            t.expectEqual(GhosttyMatcher.best(among: terminals, cwd: "/Users/dev/", title: nil)?.id, "A", "folder, normalised")
            t.expectNil(GhosttyMatcher.best(among: terminals, cwd: "/elsewhere", title: nil), "two marked terminals say nothing")

            // Measured: as Ghostty's own command, claude reports no working
            // directory and, before the first exchange, only Claude's mark.
            let lone = [
                GhosttyMatcher.Terminal(id: "A", name: "zsh", workingDirectory: "/Users/dev"),
                GhosttyMatcher.Terminal(id: "C", name: "✳ Claude Code", workingDirectory: ""),
            ]
            t.expectEqual(GhosttyMatcher.best(among: lone, cwd: "/tmp/probe", title: nil)?.id, "C", "the only marked one")
            t.expectNil(GhosttyMatcher.best(among: [lone[0]], cwd: "/tmp/probe", title: nil), "no mark, no match")
            t.expect(TerminalScripts.ghosttyFocus(terminalId: "surface-12")?.contains("whose id is \"surface-12\"") == true, "focus by id")
            t.expectNil(TerminalScripts.ghosttyFocus(terminalId: "x\" & \"y"), "a quote is refused")
            t.expect(TerminalScripts.ghosttyList.contains("repeat with t in terminals"), "the listing walks the application's terminals")
        },
    ])
}
