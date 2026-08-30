import LampBoardCore
import Foundation

enum SeatError: Error, Equatable {
    /// No live session file names the session: it has ended, or is ending.
    case noSession
    /// The file names a pid that no longer exists.
    case processGone
    /// The pid exists but started at another time: it is somebody else now.
    case pidReused

    var short: String {
        switch self {
        case .noSession: return "its session file is gone: the session has ended"
        case .processGone: return "its process is gone"
        case .pidReused: return "its pid now belongs to another process"
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
