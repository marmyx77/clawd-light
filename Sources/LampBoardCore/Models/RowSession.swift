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
    static func list(of sessions: [SessionState], in names: [String: String]) -> [RowSession] {
        let ordered = sessions.sorted {
            $0.firstSeenAt == $1.firstSeenAt
                ? $0.id < $1.id
                : $0.firstSeenAt < $1.firstSeenAt
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
        if let lane = RowNames.name(of: session.workspace.path, harness: session.harness, in: names),
           lane != RowNames.name(of: session.workspace.path, in: names) {
            return laneSize > 1 ? "\(lane) #\(place)" : lane
        }
        return "#\(ordinal)"
    }
}
