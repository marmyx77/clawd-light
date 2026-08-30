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

extension ColumnRow {

    /// The row's conversations, in the order they were opened.
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
    public var members: [RowSession] {
        sessions
            .sorted {
                $0.firstSeenAt == $1.firstSeenAt
                    ? $0.id < $1.id
                    : $0.firstSeenAt < $1.firstSeenAt
            }
            .enumerated()
            .map { index, session in
                let ordinal = index + 1
                return RowSession(
                    id: session.id,
                    ordinal: ordinal,
                    // A title appears after the first exchange, not before. An
                    // empty name in those first seconds would leave two fresh
                    // conversations indistinguishable at exactly the moment
                    // somebody opened the second one and is looking for it.
                    name: session.title ?? "#\(ordinal)",
                    session: session
                )
            }
    }
}
