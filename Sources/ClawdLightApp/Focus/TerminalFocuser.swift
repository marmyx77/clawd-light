import AppKit
import ClawdLightCore
import Foundation

/// Brings the terminal tab hosting a session to the front.
///
/// One strategy per kind of seat, and the same three-way answer the editor path
/// gives: raised exactly, only activated, or nothing at all — each deserves a
/// different reaction, and flattening them has already produced two bugs.
enum TerminalFocuser {
    /// What the session knows about itself, for the hosts whose dictionary or
    /// CLI has no tty to match: its folder, its conversation title, the pids
    /// on its chain.
    struct Context {
        let cwd: String
        let title: String?
        let pids: Set<Int32>
    }

    static func focus(seat: Seat, context: Context = Context(cwd: "", title: nil, pids: [])) -> VSCodeFocuser.FocusResult {
        switch seat {
        case .terminal(let kind, let tty):
            return raise(kind: kind, tty: tty, context: context)

        case .application(let bundlePath):
            // A place we cannot select a tab in. The application can still come
            // to the front, and the menu says why it stopped there.
            if let error = activate(bundlePath: bundlePath) { return .failed(error) }
            return .activatedOnly(reason: .windowNotFound((bundlePath as NSString).lastPathComponent))

        case .editor:
            // The caller raises editor seats the way it raises editor rows.
            return .failed(.scriptFailed("an editor seat is not this focuser's to raise"))

        case .tmux(_, let tty):
            return raiseTmux(paneTTY: tty)

        case .zellij(let serverPid, let sessionName):
            return raiseZellij(serverPid: serverPid, sessionName: sessionName)

        case .unknown:
            return .failed(.windowNotFound("that process"))
        }
    }

    // MARK: - By tty

    private static func raise(
        kind: TerminalKind, tty: String, context: Context = Context(cwd: "", title: nil, pids: [])
    ) -> VSCodeFocuser.FocusResult {
        guard isRunning(kind) else { return .failed(.scriptFailed("\(kind.applicationName) is not running")) }
        switch kind.raising {
        case .appleScriptTTY:
            guard let script = TerminalScripts.selectTab(tty: tty, in: kind) else {
                return .failed(.scriptFailed("no script for \(kind.applicationName)"))
            }
            switch VSCodeFocuser.runAppleScript(script, app: kind.applicationName) {
            case .success:
                Diagnostics.log("seat: \(kind.applicationName) \(tty) raised")
                return .raised
            case .failure(let error):
                Diagnostics.log("seat: \(kind.applicationName) \(tty) not raised — \(error.shortDescription)")
                if case .scriptFailed(let reason) = error, reason.contains("-1728") {
                    return .failed(.windowNotFound("a tab on \(tty)"))
                }
                return .failed(error)
            }
        case .appleScriptTitle:
            return raiseGhostty(context: context)
        case .wezterm:
            return raiseWezTerm(tty: tty)
        case .kitty:
            return raiseKitty(context: context)
        }
    }

    // MARK: - Ghostty, by title or folder

    /// The listing comes back as a list of `{id, name, working directory}`
    /// triples; the match happens in Swift and only the chosen id goes back.
    private static func raiseGhostty(context: Context) -> VSCodeFocuser.FocusResult {
        let app = TerminalKind.ghostty.applicationName
        let listing: NSAppleEventDescriptor
        switch VSCodeFocuser.runAppleScript(TerminalScripts.ghosttyList, app: app) {
        case .failure(let error):
            Diagnostics.log("seat: Ghostty listing failed — \(error.shortDescription)")
            return .failed(error)
        case .success(let found): listing = found
        }
        var terminals: [GhosttyMatcher.Terminal] = []
        if listing.numberOfItems > 0 {
            for index in 1...listing.numberOfItems {
                guard let triple = listing.atIndex(index), triple.numberOfItems >= 3,
                      let id = triple.atIndex(1)?.stringValue else { continue }
                terminals.append(GhosttyMatcher.Terminal(
                    id: id, name: triple.atIndex(2)?.stringValue ?? "",
                    workingDirectory: triple.atIndex(3)?.stringValue ?? ""
                ))
            }
        }
        for terminal in terminals {
            Diagnostics.log("seat: Ghostty terminal \(terminal.id): name “\(terminal.name)”, cwd \(terminal.workingDirectory)")
        }
        guard let chosen = GhosttyMatcher.best(among: terminals, cwd: context.cwd, title: context.title),
              let script = TerminalScripts.ghosttyFocus(terminalId: chosen.id)
        else {
            Diagnostics.log("seat: Ghostty lists \(terminals.count) terminals, none in \(context.cwd) or titled \(context.title ?? "-")")
            if let error = activate(bundleIdentifier: TerminalKind.ghostty.bundleIdentifier) { return .failed(error) }
            return .activatedOnly(reason: .windowNotFound("a Ghostty terminal in \(context.cwd)"))
        }
        switch VSCodeFocuser.runAppleScript(script, app: app) {
        case .success:
            Diagnostics.log("seat: Ghostty terminal \(chosen.id) (\(chosen.name)) raised")
            return .raised
        case .failure(let error):
            Diagnostics.log("seat: Ghostty terminal \(chosen.id) not raised — \(error.shortDescription)")
            return .failed(error)
        }
    }

    // MARK: - WezTerm, by tty

    private static func raiseWezTerm(tty: String) -> VSCodeFocuser.FocusResult {
        let wezterm = "/Applications/WezTerm.app/Contents/MacOS/wezterm"
        guard FileManager.default.isExecutableFile(atPath: wezterm) else {
            return .failed(.scriptFailed("wezterm CLI not found in the application bundle"))
        }
        let panes = WezTermListing.parse(Data(output(of: wezterm, ["cli", "list", "--format", "json"]).utf8))
        guard let pane = WezTermListing.pane(onTTY: tty, in: panes) else {
            return .failed(.windowNotFound("a WezTerm pane on \(tty)"))
        }
        _ = output(of: wezterm, ["cli", "activate-pane", "--pane-id", String(pane.paneId)])
        if let error = activate(bundleIdentifier: TerminalKind.wezterm.bundleIdentifier) { return .failed(error) }
        Diagnostics.log("seat: WezTerm pane \(pane.paneId) on \(tty) raised")
        return .raised
    }

    // MARK: - kitty, by pid, over its socket

    /// Remote control has to be on (`allow_remote_control`, `listen_on`); the
    /// socket is `/tmp/kitty` or `/tmp/kitty-<pid>` depending on how it was
    /// configured, so every kitty pid is tried. Without a socket the
    /// application is activated and the menu says why it stopped there.
    private static func raiseKitty(context: Context) -> VSCodeFocuser.FocusResult {
        let kitten = "/Applications/kitty.app/Contents/MacOS/kitten"
        guard FileManager.default.isExecutableFile(atPath: kitten) else {
            return .failed(.scriptFailed("kitten CLI not found in the application bundle"))
        }
        let candidates = ["/tmp/kitty"] + ProcessTree.pids(named: "kitty").map { "/tmp/kitty-\($0)" }
        for socket in candidates where FileManager.default.fileExists(atPath: socket) {
            let to = "unix:\(socket)"
            let windows = KittyListing.parse(Data(output(of: kitten, ["@", "--to", to, "ls"]).utf8))
            guard let window = KittyListing.window(hostingAnyOf: context.pids, in: windows) else { continue }
            _ = output(of: kitten, ["@", "--to", to, "focus-window", "--match", "id:\(window.id)"])
            if let error = activate(bundleIdentifier: TerminalKind.kitty.bundleIdentifier) { return .failed(error) }
            Diagnostics.log("seat: kitty window \(window.id) raised through \(socket)")
            return .raised
        }
        if let error = activate(bundleIdentifier: TerminalKind.kitty.bundleIdentifier) { return .failed(error) }
        return .activatedOnly(reason: .scriptFailed(
            "kitty's remote control is off or its window was not found — allow_remote_control and listen_on unix:/tmp/kitty in kitty.conf"
        ))
    }

    // MARK: - Through tmux

    /// Two hops: the pane on the session's tty is selected inside tmux, then the
    /// client attached to that pane's session is a process like any other — its
    /// chain ends in a terminal tab, raised the usual way.
    private static func raiseTmux(paneTTY: String) -> VSCodeFocuser.FocusResult {
        guard let tmux = executable(named: "tmux") else { return .failed(.scriptFailed("tmux not found")) }
        let panes = TmuxListing.panes(output(of: tmux, ["list-panes", "-a", "-F", TmuxListing.paneFormat]))
        guard let pane = panes.first(where: { $0.tty == paneTTY }) else {
            return .failed(.windowNotFound("a tmux pane on \(paneTTY)"))
        }
        _ = output(of: tmux, ["select-window", "-t", pane.window])
        _ = output(of: tmux, ["select-pane", "-t", pane.target])

        let clients = TmuxListing.clients(output(of: tmux, ["list-clients", "-F", TmuxListing.clientFormat]))
        guard let client = clients.first(where: { $0.session == pane.session }) ?? clients.first else {
            return .failed(.windowNotFound("a terminal attached to tmux session \(pane.session)"))
        }
        Diagnostics.log("seat: tmux pane \(pane.target) selected; client \(client.pid) on \(client.tty)")
        return raiseHost(ofClient: client.pid, fallbackTitle: nil)
    }

    // MARK: - Through zellij

    /// The client is paired with its server through their Unix sockets (`lsof`:
    /// the client's peer address is one of the server's own); with one client
    /// there is nothing to pair. The client's chain ends in a terminal tab. When
    /// no client can be paired, the tab whose title carries the session name —
    /// zellij writes it there — is the fallback.
    private static func raiseZellij(serverPid: Int32, sessionName: String) -> VSCodeFocuser.FocusResult {
        let clients = ProcessTree.pids(named: "zellij").filter { $0 != serverPid && ProcessTree.info(of: $0)?.tty != nil }
        var chosen: pid_t?
        if clients.count == 1 {
            chosen = clients[0]
        } else if !clients.isEmpty, let lsof = executable(named: "lsof") {
            let server = LsofUnixSockets.parse(output(of: lsof, ["-nP", "-U", "-a", "-p", String(serverPid)]))
            let all = LsofUnixSockets.parse(output(of: lsof, ["-nP", "-U", "-a", "-p", clients.map(String.init).joined(separator: ",")]))
            chosen = LsofUnixSockets.clientPids(of: server, among: all).first
        }
        if let chosen {
            Diagnostics.log("seat: zellij session \(sessionName) has client \(chosen)")
            return raiseHost(ofClient: chosen, fallbackTitle: sessionName)
        }
        return raiseByTitle(sessionName)
    }

    /// The terminal tab a multiplexer client runs in.
    private static func raiseHost(ofClient pid: pid_t, fallbackTitle: String?) -> VSCodeFocuser.FocusResult {
        let seat = SeatClassifier.classify(ProcessTree.ancestry(of: pid))
        switch seat {
        case .terminal(let kind, let tty):
            return raise(kind: kind, tty: tty)
        case .tmux, .zellij, .editor, .application, .unknown:
            if let fallbackTitle { return raiseByTitle(fallbackTitle) }
            return focus(seat: seat)
        }
    }

    /// The tab whose title carries a fragment, in whichever tty host is running.
    private static func raiseByTitle(_ fragment: String) -> VSCodeFocuser.FocusResult {
        for kind in [TerminalKind.terminal, .iTerm] where isRunning(kind) {
            guard let script = TerminalScripts.selectTab(titleContaining: fragment, in: kind) else { continue }
            switch VSCodeFocuser.runAppleScript(script, app: kind.applicationName) {
            case .success:
                Diagnostics.log("seat: \(kind.applicationName) tab titled \(fragment) raised")
                return .raised
            case .failure(let error):
                if case .scriptFailed(let reason) = error, reason.contains("-1728") { continue }
                return .failed(error)
            }
        }
        return .failed(.windowNotFound("a tab titled \(fragment)"))
    }

    // MARK: - Running a CLI

    private static func executable(named name: String) -> String? {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            .map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs a CLI with an argument list — never a shell — and returns its stdout.
    private static func output(of executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Diagnostics.log("seat: \(executable) could not run: \(error.localizedDescription)")
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Activation

    private static func isRunning(_ kind: TerminalKind) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: kind.bundleIdentifier).isEmpty
    }

    /// `open -b`, for the same reason the editor path uses it: an accessory app
    /// that is not frontmost cannot activate another one itself, and `open` can.
    private static func activate(bundleIdentifier: String) -> FocusError? {
        run(["-b", bundleIdentifier])
    }

    private static func activate(bundlePath: String) -> FocusError? {
        run(["-a", bundlePath])
    }

    private static func run(_ arguments: [String]) -> FocusError? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? nil : .activationFailed("open returned \(process.terminationStatus)")
        } catch {
            return .activationFailed(error.localizedDescription)
        }
    }
}
