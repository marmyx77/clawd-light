import LampBoardCore
import Foundation
import TestKit

/// The swap that finishes an update, run for real against two fake bundles.
///
/// This is the one part of updating that cannot be exercised from inside the
/// running application, because it begins by waiting for that application to
/// die. Nothing tested it, and what was shipped could not work: `install()`
/// deleted the temporary directory the moment it returned, while the script was
/// still in its wait loop, so the thing it was about to move had already been
/// erased. The application quit, the swap rolled back, and nothing changed.
///
/// Here the script is given a process to wait for, two directories standing in
/// for the bundles, and a workspace of its own — and every ending is checked:
/// the one that succeeds, the one that finds nothing to install, and the one
/// where the destination cannot be moved aside.
enum UpdateSwapSuite {

    /// One run of the real script text, with a live process to wait for.
    private struct Swap {
        let status: Int32

        init(new: String, old: String, workspace: String, waitingFor pid: Int32) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [
                "-c", UpdateSwap.body, "swap", new, old, String(pid), workspace,
            ]
            // The relaunch at the end would raise a window on whoever is
            // running the suite. The swap has already happened by then, and
            // what is being tested is the filesystem.
            var environment = ProcessInfo.processInfo.environment
            environment["LAMPBOARD_UPDATE_OPEN"] = "/usr/bin/true"
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            status = process.terminationStatus
        }
    }

    /// A process that is alive until it is told not to be, so the wait loop has
    /// something real to wait for.
    private static func sleeper() -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try? process.run()
        return process
    }

    private static func stage(_ name: String) -> (root: URL, new: URL, old: URL, workspace: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lampboard-swap-\(name)-\(UUID().uuidString)", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let new = workspace.appendingPathComponent("staged.app", isDirectory: true)
        let old = root.appendingPathComponent("LampBoard.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try? "new".write(to: new.appendingPathComponent("which"), atomically: true, encoding: .utf8)
        try? "old".write(to: old.appendingPathComponent("which"), atomically: true, encoding: .utf8)
        return (root, new, old, workspace)
    }

    private static func marker(in bundle: URL) -> String {
        (try? String(contentsOf: bundle.appendingPathComponent("which"), encoding: .utf8)) ?? "gone"
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func suite() -> TestSuite {
        TestSuite("E2E · the swap that finishes an update", [

            TestCase("it waits for the application to go, then replaces it") { a in
                let places = stage("ok")
                defer { try? FileManager.default.removeItem(at: places.root) }

                let waiting = sleeper()
                // Killed a moment after the script starts, which is the shape of
                // the real thing: the application is quitting while the script
                // is already waiting.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { waiting.terminate() }

                let swap = Swap(
                    new: places.new.path, old: places.old.path,
                    workspace: places.workspace.path, waitingFor: waiting.processIdentifier
                )
                a.expectEqual(swap.status, 0, "the swap reports success")
                a.expectEqual(marker(in: places.old), "new", "the new application is in place")
                a.expect(!exists(places.old.appendingPathExtension("replaced")),
                         "and the backup is gone, because the new one arrived")
                a.expect(!exists(places.workspace),
                         "and so is the workspace, which nothing else will clean")
            },

            TestCase("finding nothing to install puts the old one back") { a in
                // Exactly the defect that shipped: the staged application is not
                // there when the move comes. Whatever the cause, the machine
                // must end with an application rather than with nothing.
                let places = stage("rollback")
                defer { try? FileManager.default.removeItem(at: places.root) }
                try? FileManager.default.removeItem(at: places.new)

                let waiting = sleeper()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { waiting.terminate() }

                let swap = Swap(
                    new: places.new.path, old: places.old.path,
                    workspace: places.workspace.path, waitingFor: waiting.processIdentifier
                )
                a.expectEqual(swap.status, 1, "it says it failed rather than pretending")
                a.expectEqual(marker(in: places.old), "old", "the old application is back")
                a.expect(!exists(places.old.appendingPathExtension("replaced")),
                         "with nothing left beside it")
                a.expect(!exists(places.workspace), "and the workspace cleaned up after itself")
            },

            TestCase("a destination it cannot move aside is refused, not emptied") { a in
                // The first move is the dangerous one: it is the only moment
                // where the installed application is not where it belongs. If
                // that fails there is nothing to undo, and nothing may be
                // deleted on the way out.
                let places = stage("locked")
                defer {
                    _ = try? FileManager.default.setAttributes(
                        [.posixPermissions: 0o755], ofItemAtPath: places.root.path
                    )
                    try? FileManager.default.removeItem(at: places.root)
                }
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o500], ofItemAtPath: places.root.path
                )

                let waiting = sleeper()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { waiting.terminate() }

                let swap = Swap(
                    new: places.new.path, old: places.old.path,
                    workspace: places.workspace.path, waitingFor: waiting.processIdentifier
                )
                a.expectEqual(swap.status, 1, "it refuses")
                a.expectEqual(marker(in: places.old), "old", "and the application is untouched")
            },
        ])
    }
}
