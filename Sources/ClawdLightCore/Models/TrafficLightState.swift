import Foundation

/// The complete state of the traffic light column.
///
/// An immutable structure: the reducer always produces a new version of it.
/// The ordering of the sessions is a derived property, not mutable state.
public struct TrafficLightState: Sendable, Equatable {
    /// Sessions indexed by session id.
    public let sessions: [String: SessionState]

    public init(sessions: [String: SessionState] = [:]) {
        self.sessions = sessions
    }

    public static let empty = TrafficLightState()

    /// Sessions ordered the way they should be drawn in the column.
    ///
    /// State urgency first; then, for equal states, whoever has been waiting
    /// longest. The alphabetical criterion used previously gave precedence to
    /// the luckiest name: between two sessions asking for a permission, the one
    /// stuck for six minutes belongs above the one stuck for ten seconds.
    /// The name stays as a tie-break, so the order doesn't jitter between refreshes.
    public var ordered: [SessionState] {
        sessions.values.sorted { lhs, rhs in
            if lhs.status.urgencyRank != rhs.status.urgencyRank {
                return lhs.status.urgencyRank < rhs.status.urgencyRank
            }
            if lhs.statusSince != rhs.statusSince {
                return lhs.statusSince < rhs.statusSince
            }
            if lhs.workspace.name != rhs.workspace.name {
                return lhs.workspace.name.localizedStandardCompare(rhs.workspace.name) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    /// Number of sessions currently waiting on the user.
    public var unseenCount: Int {
        sessions.values.filter { $0.status.clearsOnFocus }.count
    }

    /// Most urgent state present in the column, if there is at least one.
    public var mostUrgentStatus: SessionStatus? {
        sessions.values.map(\.status).min { $0.urgencyRank < $1.urgencyRank }
    }

    /// Copy with a session inserted or replaced.
    public func upserting(_ session: SessionState) -> TrafficLightState {
        var next = sessions
        next[session.id] = session
        return TrafficLightState(sessions: next)
    }

    /// Copy without the given session.
    public func removing(sessionId: String) -> TrafficLightState {
        var next = sessions
        next.removeValue(forKey: sessionId)
        return TrafficLightState(sessions: next)
    }

    /// Copy without the sessions that have shown no sign of life for longer than `maxAge`.
    ///
    /// The threshold applies to **every** state, `working` included. The exemption
    /// that used to be here — "a long turn is not a dead session" — made yellows
    /// immortal, and the case where that happens is not rare: `Stop` does not fire
    /// when you interrupt a turn with Esc, and no other hook covers it. Every
    /// interruption left a yellow row behind forever.
    ///
    /// If the threshold gets it wrong the damage is bounded: on the next signal the
    /// reducer recreates the row, so at worst you temporarily lose a clickable
    /// target, not an event.
    /// - Parameter alive: sessions whose process is confirmed running. These are
    ///   **never** pruned, however old their last signal looks.
    ///
    ///   Pruning exists to drop rows we can no longer account for. A live pid is
    ///   accounting for one, and dropping it anyway was a real defect: a session
    ///   open for a week and working right now vanished from the column, because
    ///   the file its age was read from is written once at startup and never
    ///   touched again. The traffic light went dark on exactly the session it
    ///   existed to show.
    public func pruning(
        olderThan maxAge: TimeInterval, at now: Date, keepingAlive alive: Set<String> = []
    ) -> TrafficLightState {
        let survivors = sessions.filter { id, session in
            alive.contains(id) || now.timeIntervalSince(session.updatedAt) <= maxAge
        }
        return TrafficLightState(sessions: survivors)
    }
}
