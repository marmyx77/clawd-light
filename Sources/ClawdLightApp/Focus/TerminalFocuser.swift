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

        case .tmux, .zellij:
            return .failed(.scriptFailed("selecting a tab inside \(seat.label) is not built yet"))

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
