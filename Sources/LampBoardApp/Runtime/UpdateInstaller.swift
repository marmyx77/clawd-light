import AppKit
import LampBoardCore
import Foundation

/// Downloads a release and replaces this app with it — after proving it is ours.
///
/// This is the most dangerous code in the project, and it is worth saying why in
/// the file itself. macOS grants Accessibility and Automation to a **signing
/// identity**, so a replacement signed with our certificate inherits the
/// permission to drive the keyboard and the windows of this Mac without asking
/// anybody anything. An updater that installs the wrong bundle does not produce
/// a broken app; it produces a silent one with the run of the machine.
///
/// So nothing here trusts the download. Four things are proved before the
/// running app is touched, and any one of them failing stops everything:
///
/// 1. the disk image passes Gatekeeper's own assessment — signed **and**
///    notarized, the same verdict a stranger's Mac would reach;
/// 2. the app inside verifies as intact against its own signature;
/// 3. its Team ID equals the one this build was signed with, so a valid
///    Developer ID belonging to somebody else is refused;
/// 4. its bundle identifier is ours.
///
/// The comparison in (3) is against the *running* app rather than a constant in
/// the source: a hardcoded team could be edited by whoever edited the download
/// URL, and a value read from the process that is already trusted cannot.
enum UpdateInstaller {

    enum Failure: LocalizedError {
        case notInstalled
        case download(String)
        case rejected(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return """
                    This copy is running from a build folder, not from an installed \
                    application, so there is nothing to replace.

                    Download the disk image and drag the app to Applications; \
                    updates work from there.
                    """
            case .download(let reason):
                return "The download did not finish: \(reason)"
            case .rejected(let reason):
                // The wording matters: this is not "something went wrong", it is
                // "what arrived is not us", and the user should hear the difference.
                return """
                    The downloaded update was refused: \(reason)

                    Nothing has been installed. Download the release by hand from \
                    GitHub if you want to inspect it.
                    """
            case .failed(let reason):
                return "The update could not be completed: \(reason)"
            }
        }
    }

    // MARK: - The whole operation

    /// Downloads, verifies, and swaps. On success the app quits and comes back.
    static func install(from url: URL) async throws {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app",
              FileManager.default.isWritableFile(atPath: bundle.path)
        else { throw Failure.notInstalled }

        let workspace = try makeWorkspace()
        // Cleared once the swap script owns it. Deleting the workspace on the
        // way out of this function is what made every update fail: the script
        // is still waiting for this process to die, and what it is about to
        // move lives in there. See `UpdateSwap`.
        var handedOff = false
        defer { if !handedOff { try? FileManager.default.removeItem(at: workspace) } }

        let image = try await download(url, into: workspace)
        try assertGatekeeperAccepts(image)

        let mount = workspace.appendingPathComponent("mount", isDirectory: true)
        try attach(image, at: mount)
        defer { detach(mount) }

        let candidate = try onlyApplication(in: mount)
        try assertIsOurs(candidate, matching: bundle)

        // Copied out of the image before anything is replaced: from here on the
        // source is a local directory that cannot be unmounted underneath us.
        let staged = workspace.appendingPathComponent("staged.app", isDirectory: true)
        try run("/usr/bin/ditto", [candidate.path, staged.path])
        detach(mount)

        try handOff(staged: staged, replacing: bundle, cleaning: workspace)
        handedOff = true
    }

    // MARK: - Steps

    private static func makeWorkspace() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lampboard-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    private static func download(_ url: URL, into workspace: URL) async throws -> URL {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = AppConfig.updateDownloadTimeout
            let (temporary, response) = try await URLSession.shared.download(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw Failure.download("GitHub answered \(status)") }

            let image = workspace.appendingPathComponent("update.dmg")
            try FileManager.default.moveItem(at: temporary, to: image)
            return image
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.download(error.localizedDescription)
        }
    }

    /// Gatekeeper's own verdict on the image: signed by a Developer ID **and**
    /// notarized. The same question a Mac that has never seen us would ask.
    private static func assertGatekeeperAccepts(_ image: URL) throws {
        guard (try? run("/usr/sbin/spctl", [
            "--assess", "--type", "open",
            "--context", "context:primary-signature", image.path,
        ])) != nil else {
            throw Failure.rejected("macOS does not recognise it as signed and notarized")
        }
    }

    private static func attach(_ image: URL, at mount: URL) throws {
        do {
            try run("/usr/bin/hdiutil", [
                "attach", image.path, "-nobrowse", "-readonly", "-noautoopen",
                "-mountpoint", mount.path,
            ])
        } catch {
            throw Failure.failed("the disk image would not mount")
        }
    }

    private static func detach(_ mount: URL) {
        _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
    }

    /// Exactly one application, or none of them.
    ///
    /// An image carrying two is not something this project publishes, and picking
    /// the first would be choosing on the user's behalf between a thing they
    /// expected and a thing they did not.
    private static func onlyApplication(in mount: URL) throws -> URL {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: mount, includingPropertiesForKeys: nil
        )) ?? []
        let applications = contents.filter { $0.pathExtension == "app" }
        guard applications.count == 1, let app = applications.first else {
            throw Failure.rejected("the image holds \(applications.count) applications, expected one")
        }
        return app
    }

    /// Intact, ours, and the same product.
    private static func assertIsOurs(_ candidate: URL, matching running: URL) throws {
        guard (try? run("/usr/bin/codesign", [
            "--verify", "--deep", "--strict", candidate.path,
        ])) != nil else {
            throw Failure.rejected("its signature does not check out")
        }

        guard let ours = teamIdentifier(of: running) else {
            throw Failure.failed("this build carries no Team ID to compare against")
        }
        guard let theirs = teamIdentifier(of: candidate) else {
            throw Failure.rejected("it carries no Team ID")
        }
        guard ours == theirs else {
            throw Failure.rejected("it was signed by \(theirs), not by \(ours)")
        }

        let identifier = Bundle(url: candidate)?.bundleIdentifier
        guard identifier == Bundle.main.bundleIdentifier else {
            throw Failure.rejected("it is a different application (\(identifier ?? "unnamed"))")
        }

        guard (try? run("/usr/sbin/spctl", ["--assess", "--type", "exec", candidate.path])) != nil
        else {
            throw Failure.rejected("macOS would not let it run")
        }
    }

    private static func teamIdentifier(of bundle: URL) -> String? {
        guard let output = try? run("/usr/bin/codesign", [
            "-d", "--verbose=2", bundle.path,
        ]) else { return nil }

        for line in output.components(separatedBy: .newlines)
        where line.hasPrefix("TeamIdentifier=") {
            let value = String(line.dropFirst("TeamIdentifier=".count)).trimmed
            return value == "not set" ? nil : value
        }
        return nil
    }

    // MARK: - The swap

    /// Replaces the bundle after this process is gone, then starts it again.
    ///
    /// An application cannot replace the folder it is executing from and survive
    /// it, so the last step outlives us: a small script waits for this pid to
    /// disappear, moves the new bundle into place and opens it. The paths reach
    /// it as arguments rather than being written into the script, so nothing
    /// about them is ever interpreted.
    private static func handOff(staged: URL, replacing bundle: URL, cleaning workspace: URL) throws {
        // Handed to bash as an argument, not written to disk. There is then no
        // file for anybody to delete underneath a running script, and the script
        // can clean the workspace itself once it no longer needs it.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c", UpdateSwap.body, "swap",
            staged.path, bundle.path,
            String(ProcessInfo.processInfo.processIdentifier), workspace.path,
        ]
        try process.run()

        Diagnostics.log("update: handed off to the swap, quitting")
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    // MARK: - Running a tool

    /// Runs a tool and returns its output, throwing when it says no.
    ///
    /// Arguments travel as an array: no shell is involved anywhere in this file,
    /// so a path with a space or a quote in it is a path and never a command.
    ///
    /// The deadline is not a detail. Every tool called here is local and quick,
    /// but `spctl` asks Apple about a signature it has never seen, and
    /// `hdiutil attach` on a damaged image can sit there for as long as you let
    /// it — which, before this, was forever. The user had chosen "Install", and
    /// the only thing that would ever happen was nothing at all.
    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let result: Command.Result
        do {
            result = try Command.run(tool, arguments, deadline: AppConfig.updateToolTimeout)
        } catch let failure as Command.Failure {
            throw Failure.failed(failure.explanation)
        } catch {
            throw Failure.failed("\(tool) could not be run: \(error.localizedDescription)")
        }

        guard result.succeeded else {
            throw Failure.failed("\(tool) exited \(result.status): \(result.output.trimmed)")
        }
        return result.output
    }
}
