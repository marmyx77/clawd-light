import LampBoardCore
import Foundation

enum SeatError: Error, Equatable {
    /// No live session file names the session: it has ended, or is ending.
    case noSession
    /// The file names a pid that no longer exists.
    case processGone
    /// The pid exists but started at another time: it is somebody else now.
    case pidReused
    /// Nothing on this Mac holds the session's transcript open any more.
    case transcriptClosed
    /// The probe that would have answered could not run. Absence of evidence,
    /// which is a different thing from a session that has ended.
    case cannotAsk(String)

    var short: String {
        switch self {
        case .noSession: return "its session file is gone: the session has ended"
        case .processGone: return "its process is gone"
        case .pidReused: return "its pid now belongs to another process"
        case .transcriptClosed: return "nothing holds its transcript open: the conversation is closed"
        case .cannotAsk(let why): return "its place could not be read (\(why))"
        }
    }
}

/// From a session to the place its process lives in, at click time.
///
/// Nothing is cached: hours can pass between a signal and a click, and in
/// between the same pid can die and be handed to something else. The session
/// file's `procStart` against the kernel's start time is what catches that.
enum SeatResolver {
    struct Resolution {
        let seat: Seat
        /// The session's ancestry, `claude` first: the pids a listing can be
        /// matched against when the seat has no tty to offer.
        let chain: [ProcessAncestor]
    }

    /// The seat of a session, by whichever evidence that harness leaves.
    static func resolve(session: SessionState) -> Result<Resolution, SeatError> {
        guard session.harness == .codex else { return resolve(sessionId: session.id) }
        return resolveCodex(transcriptPath: session.transcriptPath)
    }

    /// A Codex session, found through the file it is holding open.
    ///
    /// There is no session file to read: Codex writes a rollout and nothing
    /// else, and the row for one exists precisely because a live process holds
    /// that rollout open. The same fact answers this question, so the click asks
    /// it again rather than remembering a pid — for the reason the whole type
    /// exists, that hours can pass between a signal and a click and a pid can be
    /// handed to somebody else in between. A descriptor cannot be stale about
    /// who is holding it, which is also why there is no `procStart` check here:
    /// the process holding the file **is** the process.
    private static func resolveCodex(transcriptPath: String?) -> Result<Resolution, SeatError> {
        guard let path = transcriptPath?.trimmed.nilIfEmpty else { return .failure(.transcriptClosed) }
        guard let lsof = ["/usr/sbin/lsof", "/usr/bin/lsof"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return .failure(.cannotAsk("lsof is not on this machine")) }

        let output: String
        do {
            // `--` before the path: a rollout name is generated, but the flag
            // that stops it being read as one costs nothing.
            output = try Command.run(
                lsof, ["-nP", "-F", "pcftn", "--", path],
                deadline: AppConfig.focusProbeTimeout, capturingStandardError: false
            ).output
        } catch let failure as Command.Failure {
            return .failure(.cannotAsk(failure.explanation))
        } catch {
            return .failure(.cannotAsk(error.localizedDescription))
        }

        // `lsof` exits 1 when the file is open nowhere, which is not an error
        // here: it is the answer. What it printed is what decides.
        guard let holder = CodexHolders.first(holding: path, in: LsofOpenFiles.parse(output)) else {
            return .failure(.transcriptClosed)
        }
        guard ProcessTree.info(of: holder) != nil else { return .failure(.processGone) }
        let chain = ProcessTree.ancestry(of: holder)
        return .success(Resolution(seat: SeatClassifier.classify(chain), chain: chain))
    }

    static func resolve(sessionId: String) -> Result<Resolution, SeatError> {
        guard let file = LiveSessionReader().readLiveSessions().first(where: { $0.sessionId == sessionId })
        else { return .failure(.noSession) }
        guard file.pid > 0, let info = ProcessTree.info(of: pid_t(file.pid)) else { return .failure(.processGone) }
        if let raw = file.procStart, let start = ProcStart.parse(raw), !start.matches(processStartedAt: info.startedAt) {
            return .failure(.pidReused)
        }
        let chain = ProcessTree.ancestry(of: pid_t(file.pid))
        return .success(Resolution(seat: SeatClassifier.classify(chain), chain: chain))
    }
}
