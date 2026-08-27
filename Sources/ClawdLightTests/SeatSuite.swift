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
