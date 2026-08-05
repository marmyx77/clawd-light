import Foundation

/// A session as seen by whoever queries the read endpoint.
///
/// Deliberately a separate type from `SessionState`: the format leaving the app
/// is a contract with the outside world, and tying it to the internal structure
/// would turn every refactor into a breaking change for its consumers.
public struct SessionSnapshot: Sendable, Equatable, Codable {
    public let id: String
    public let status: String
    public let workspace: String
    public let path: String
    public let updatedAt: Date
    public let statusSince: Date
    public let activeSubagents: Int
    public let failureReason: String?
    public let lastMessage: String?
    public let muted: Bool
    public let pinned: Bool

    /// The keyboard slot this project is bound to, 1-based, or `nil`.
    ///
    /// Part of the read contract because it answers a question no consumer can
    /// work out on its own: the column's order is urgency, and the slot is not.
    public let slot: Int?

    /// Absolute path of the session's JSONL transcript, when one is known.
    ///
    /// Published because it is the one field that turns this endpoint from a
    /// status feed into something you can build a reader on: everything else says
    /// how a session **is**, this says where to find what was **said**.
    public let transcriptPath: String?

    public init(
        id: String,
        status: String,
        workspace: String,
        path: String,
        updatedAt: Date,
        statusSince: Date,
        activeSubagents: Int = 0,
        failureReason: String? = nil,
        lastMessage: String? = nil,
        muted: Bool = false,
        pinned: Bool = false,
        slot: Int? = nil,
        transcriptPath: String? = nil
    ) {
        self.id = id
        self.status = status
        self.workspace = workspace
        self.path = path
        self.updatedAt = updatedAt
        self.statusSince = statusSince
        self.activeSubagents = activeSubagents
        self.failureReason = failureReason
        self.lastMessage = lastMessage
        self.muted = muted
        self.pinned = pinned
        self.slot = slot
        self.transcriptPath = transcriptPath
    }
}

/// Body of the `GET /sessions` response.
public struct SessionsResponse: Sendable, Equatable, Codable {
    public let generatedAt: Date
    public let sessions: [SessionSnapshot]

    public init(generatedAt: Date, sessions: [SessionSnapshot]) {
        self.generatedAt = generatedAt
        self.sessions = sessions
    }
}

/// Serializes and deserializes the body of the read endpoint.
///
/// Dates travel as ISO 8601: a numeric timestamp would force every consumer to
/// guess the unit, and one that guesses wrong doesn't find out until it looks at
/// a time that is fifty years off.
public enum SessionsCodec {

    public static func encode(_ response: SessionsResponse) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Sorted keys: makes comparing two responses a readable diff instead of a
        // random reshuffle.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(response)
    }

    public static func decode(_ data: Data) throws -> SessionsResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionsResponse.self, from: data)
    }

    /// Builds the snapshot of a session.
    ///
    /// - Parameter slot: the keyboard slot of the session's project. Passing it
    ///   also settles `pinned`, because having a slot is what being pinned means —
    ///   two parameters that can disagree is two parameters too many.
    public static func snapshot(
        of session: SessionState,
        muted: Bool = false,
        slot: Int? = nil
    ) -> SessionSnapshot {
        SessionSnapshot(
            id: session.id,
            status: session.status.rawValue,
            workspace: session.workspace.name,
            path: session.workspace.path,
            updatedAt: session.updatedAt,
            statusSince: session.statusSince,
            activeSubagents: session.activeSubagents,
            failureReason: session.failureReason?.rawValue,
            lastMessage: session.lastMessage,
            muted: muted,
            pinned: slot != nil,
            slot: slot,
            transcriptPath: session.transcriptPath
        )
    }
}
