import ClawdLightCore
import Foundation

/// File-based diagnostic log.
///
/// An app with no Dock icon and no main window has nowhere to show what it is
/// doing, and `NSLog` from a process launched via `open` is hard to recover. A
/// file in a known place solves both problems when the panel behaves unexpectedly.
enum Diagnostics {

    /// Only active when the environment variable is set, so normal use doesn't
    /// write to disk on every event.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["CLAWD_LIGHT_DEBUG"] != nil
    }

    static var logURL: URL {
        AppConfig.supportDirectory.appendingPathComponent("debug.log")
    }

    /// Truncates the file at startup: it is always the latest run that matters.
    static func startSession() {
        guard isEnabled else { return }
        try? FileManager.default.createDirectory(
            at: AppConfig.supportDirectory, withIntermediateDirectories: true
        )
        // Created with the permissions it needs, not repaired afterwards: the
        // log carries workspace paths, window titles and remote host names —
        // the same information the token on `GET /sessions` exists to protect —
        // and until this line it was born 0644 and readable by every other
        // account on the machine.
        try? FileManager.default.removeItem(at: logURL)
        _ = FileManager.default.createFile(
            atPath: logURL.path, contents: Data(),
            attributes: [.posixPermissions: 0o600]
        )
        log("session started")
    }

    /// One writer at a time. Lines now come from the main actor and from the
    /// tasks that talk to other machines; two appends racing on the same file
    /// would interleave, and a log that has to be second-guessed is no instrument.
    private static let writer = DispatchQueue(label: "clawd-light.diagnostics")

    static func log(_ message: String) {
        guard isEnabled else { return }

        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        // A diagnostic log that brings the app down would be worse than the
        // problem it exists to diagnose: every write error is swallowed here.
        writer.sync {
            do {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                try? data.write(to: logURL)
            }
        }
    }
}
