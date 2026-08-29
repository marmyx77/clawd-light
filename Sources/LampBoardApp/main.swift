import AppKit
import LampBoardCore

// Entry point. The configuration commands run without an interface and exit;
// only `run` starts the AppKit event loop.

let command = CommandLineInterface.parse(CommandLine.arguments)

if let exitCode = CommandLineInterface.execute(command) {
    exit(exitCode)
}

guard case .run(let port, let skipSetupPrompt, let headless) = command else {
    exit(0)
}

// `NSApplication.delegate` is a weak reference: without this variable the
// delegate would be deallocated as soon as the block ended, and the app would
// start up mute.
var retainedDelegate: AppDelegate?

/// The same, for the signal sources: a source nobody holds stops firing.
var retainedSignals: [DispatchSourceSignal] = []

/// Makes `pkill` a graceful quit instead of a sudden death.
///
/// WHY THIS EXISTS
/// `applicationWillTerminate` stops the polling, the server, the presence file
/// and — the one that hurt — the ssh tunnels. None of it runs when the process
/// is killed with a signal: a Cocoa app takes SIGTERM's default disposition and
/// simply stops, children and all state left where they fell.
///
/// That would be a footnote if the app were quit from the menu. It is not:
/// `pkill -x lampboard; open LampBoard.app` is what this project's own build
/// script prints as the way to restart, so every restart orphaned an
/// `ssh -N -R` that kept holding the tunnel's port. The next instance asked for
/// the same port, was refused, and reported the refusal against the remote
/// machine — which had done nothing. Measured once: two hours of "retrying in
/// 60 s" with the cause sitting in the local process table.
///
/// `SIG_IGN` first, because the default disposition would win the race before
/// the source ever fires.
func quitGracefullyOnSignal(_ number: Int32) {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler {
        // Through NSApp rather than exit(): the whole point is the cleanup that
        // hangs off applicationWillTerminate.
        MainActor.assumeIsolated { NSApp.terminate(nil) }
    }
    source.resume()
    retainedSignals.append(source)
}

// SIGINT as well as SIGTERM: a run started from a terminal is stopped with ^C,
// and it leaves exactly the same debris behind.
quitGracefullyOnSignal(SIGTERM)
quitGracefullyOnSignal(SIGINT)

// Top-level code in main.swift is not isolated to the main actor, but here we are
// on it by definition: this is the main thread, before anything else starts.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate(
        port: port, skipSetupPrompt: skipSetupPrompt, headless: headless
    )
    retainedDelegate = delegate
    application.delegate = delegate
    application.run()
}
