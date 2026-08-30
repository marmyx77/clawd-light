import LampBoardCore
import Foundation

/// A Codex session proven to exist right now.
struct CodexEvidence: Sendable, Equatable {
    /// The rollout the process holds open.
    let rolloutPath: String
    let pid: Int32
    /// The binary behind the pid, which is what names the surface.
    let executable: String
    let surface: CodexSurface
}

/// What the scanner learned, and whether it learned anything at all.
///
/// The distinction is the point of the type. A probe that answered and saw no
/// open rollout is evidence that the sessions are over; a probe that could not
/// run, or ran out of time, is **absence of evidence**, and treating the two the
/// same would delete every Codex row the first time a network mount made `lsof`
/// pause. The store already draws this line for a remote host that has gone
/// quiet, and it draws it here for the same reason.
enum CodexScanResult: Sendable, Equatable {
    case observed([CodexEvidence])
    case unavailable(String)
}

/// Finds the Codex sessions running on this machine, without being told.
///
/// Codex inside the ChatGPT app registers our hooks, marks them trusted, runs a
/// full session, writes every event to its rollout, and sends no signal at all.
/// Measured, not assumed: eight events configured with trusted hashes, a rollout
/// updated at the second a message was answered, and not one line in the log.
/// Anything built on hooks alone is blind to it.
///
/// So the evidence runs the other way. A live `codex` process holds its rollout
/// open; the file says which session and which folder; the binary says which
/// surface. Nothing has to be sent to us, and nothing unauthenticated is believed.
enum CodexProcessScanner {

    /// One pass. Cheap enough for a poll: one process enumeration and one `lsof`,
    /// both bounded.
    static func scan(
        sessionsRoot: URL = AppConfig.codexSessionsDirectory,
        deadline: TimeInterval = AppConfig.focusProbeTimeout
    ) -> CodexScanResult {
        let pids = ProcessTree.pids(named: "codex")
        guard !pids.isEmpty else { return .observed([]) }

        guard let lsof = ["/usr/sbin/lsof", "/usr/bin/lsof"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return .unavailable("lsof is not on this machine") }

        let result: Command.Result
        do {
            result = try Command.run(
                lsof,
                // Field output, and only the pids we already found. Asking `lsof`
                // for everything is what makes it stat a network mount and pause.
                ["-nP", "-F", "pcftn", "-p", pids.map(String.init).joined(separator: ",")],
                deadline: deadline,
                capturingStandardError: false
            )
        } catch {
            return .unavailable((error as? Command.Failure)?.explanation ?? "\(error)")
        }

        // `lsof` exits 1 when some of the pids are gone, which is normal here: a
        // session can end between enumerating and asking. What it printed is still
        // good, so the status is not a failure by itself.
        let open = LsofOpenFiles.under(sessionsRoot.path, in: LsofOpenFiles.parse(result.output))
        guard !open.isEmpty else {
            return result.output.isEmpty && !result.succeeded
                ? .unavailable("lsof said nothing and exited \(result.status)")
                : .observed([])
        }

        return .observed(open.compactMap { file in
            guard file.path.hasSuffix(".jsonl") else { return nil }
            let executable = ProcessTree.path(of: file.pid)
            return CodexEvidence(
                rolloutPath: file.path,
                pid: file.pid,
                executable: executable,
                surface: CodexSurface.of(executable: executable)
            )
        })
    }
}
