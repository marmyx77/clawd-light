import ClawdLightCore
import Foundation

/// A copy of the state readable from any queue.
///
/// The HTTP server lives on its own queue and the state lives on the main actor.
/// Crossing the boundary with `DispatchQueue.main.sync` would work right up until
/// somebody on the main queue waits for something that goes through the server's
/// queue — that is, until somebody introduces the deadlock. This box removes the
/// question: the state is deposited when it changes and collected when it is
/// needed, without the two sides ever waiting on each other.
final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SessionSnapshot] = []

    func replace(with snapshots: [SessionSnapshot]) {
        lock.lock()
        defer { lock.unlock() }
        stored = snapshots
    }

    func current() -> [SessionSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
