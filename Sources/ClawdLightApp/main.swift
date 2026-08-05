import AppKit
import ClawdLightCore

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
