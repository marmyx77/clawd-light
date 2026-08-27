import AppKit
import ClawdLightCore
import Foundation

/// Brings the terminal tab hosting a session to the front.
///
/// One strategy per kind of seat, and the same three-way answer the editor path
/// gives: raised exactly, only activated, or nothing at all — each deserves a
/// different reaction, and flattening them has already produced two bugs.
enum TerminalFocuser {
    static func focus(seat: Seat) -> VSCodeFocuser.FocusResult {
        switch seat {
        case .terminal(let kind, let tty):
            return raise(kind: kind, tty: tty)

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

    private static func raise(kind: TerminalKind, tty: String) -> VSCodeFocuser.FocusResult {
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
        case .appleScriptTitle, .kitty, .wezterm:
            // Phase E of docs/plans/terminal-sessions.md.
            if let error = activate(bundleIdentifier: kind.bundleIdentifier) { return .failed(error) }
            return .activatedOnly(reason: .scriptFailed("tab selection in \(kind.applicationName) is not built yet"))
        }
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
