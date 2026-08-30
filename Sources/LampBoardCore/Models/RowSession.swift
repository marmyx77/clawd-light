import Foundation

/// One conversation inside a row, told apart from the others.
///
/// A row is a project (D4, D23), and a project can hold several conversations at
/// once. Until this type existed the column could only say **how many**: three
/// Claude sessions in one folder are identical in every field the panel draws,
/// same window label, same entrypoint, same folder, same slot, and differ only by
/// a UUID nobody sees. That is a count, not an answer to "which one".
public struct RowSession: Sendable, Equatable, Identifiable {

    /// The session's own id: what a click on this line has to open.
    public let id: String

    /// Its place in the row, 1-based, along the order the conversations were
    /// opened. Also its name while it has none of its own.
    public let ordinal: Int

    /// What to call it: its title, or its position until a title exists.
    public let name: String

    /// Everything else about it: state, context, subagents, how long.
    public let session: SessionState

    public init(id: String, ordinal: Int, name: String, session: SessionState) {
        self.id = id
        self.ordinal = ordinal
        self.name = name
        self.session = session
    }
}

extension RowSession {

    /// The conversations of one row, in the order they were opened.
    ///
    /// Deliberately **not** the order of `sessions`, which is most urgent first.
    /// The column does not reorder itself (D23) and neither may the list inside a
    /// row: a line that jumps because a turn finished is the same defect one
    /// level down, and worse there, because the lines sit closer together and a
    /// misclick opens the wrong conversation.
    ///
    /// Ties are broken by id rather than left to the sort. Sessions adopted from
    /// the filesystem in one pass share a timestamp, and an unstable order would
    /// renumber the list between two otherwise identical renders.
    static func list(
        of sessions: [SessionState], in names: [String: String], order: [String] = []
    ) -> [RowSession] {
        // The order the user put them in first, then the order they were opened.
        // A conversation nobody has moved sorts after the ones somebody did, which
        // is what makes a new one arrive at the end instead of in the middle of a
        // list somebody arranged.
        let placed = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let ordered = sessions.sorted { left, right in
            switch (placed[left.id], placed[right.id]) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                return left.firstSeenAt == right.firstSeenAt
                    ? left.id < right.id
                    : left.firstSeenAt < right.firstSeenAt
            }
        }

        // How many in this row share each lane, so a lane's name is only numbered
        // when the number is the thing telling two lines apart.
        var laneSize: [Harness: Int] = [:]
        for session in ordered { laneSize[session.harness, default: 0] += 1 }
        var laneSeen: [Harness: Int] = [:]

        return ordered.enumerated().map { index, session in
            let ordinal = index + 1
            laneSeen[session.harness, default: 0] += 1
            return RowSession(
                id: session.id,
                ordinal: ordinal,
                name: name(
                    of: session,
                    ordinal: ordinal,
                    inLane: laneSeen[session.harness] ?? 1,
                    laneSize: laneSize[session.harness] ?? 1,
                    names: names
                ),
                session: session
            )
        }
    }

    /// What to call one conversation, in order of how much it was chosen.
    ///
    /// The name you gave **this** conversation first: it is the most specific
    /// thing anybody said about it. Then its own title, which the transcript
    /// writes after the first exchange. Then the name given to this agent's lane
    /// in this project, numbered when the lane holds more than one, so naming the
    /// Codex lane "migration" gives a fresh session "migration #2" rather than
    /// "#2". Then its position, which is all there is in the first seconds of a
    /// conversation that has not spoken yet.
    private static func name(
        of session: SessionState,
        ordinal: Int,
        inLane place: Int,
        laneSize: Int,
        names: [String: String]
    ) -> String {
        if let own = RowNames.name(ofSession: session.id, in: names) { return own }
        if let title = session.title { return title }
        if let lane = RowNames.name(of: session.workspace.key, harness: session.harness, in: names),
           lane != RowNames.name(of: session.workspace.key, in: names) {
            return laneSize > 1 ? "\(lane) #\(place)" : lane
        }
        return "#\(ordinal)"
    }
}
