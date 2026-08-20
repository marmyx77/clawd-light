import Foundation

/// One line in a chat window.
///
/// A transcript record and a chat entry are **not** the same thing. A single
/// assistant record can hold an answer *and* six tool calls, which read as two
/// different things on screen; and the overwhelming majority of `user` records
/// are tool results that no human ever typed. This type is what survives that
/// translation — the part a person would recognise as conversation.
public struct TranscriptEntry: Sendable, Equatable, Identifiable {

    /// What the entry is, which is also how it is drawn.
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        /// Typed by the user. The only kind we can prove: see `origin.kind`.
        case human
        /// Claude's visible answer.
        case assistant
        /// Tool calls, collapsed into one line. Not conversation, but leaving
        /// them out makes a long working turn look like silence.
        case activity
        /// A boundary or a system fact: context compacted, a background task
        /// reporting in. Drawn small and centred, never as a bubble.
        case note
    }

    public let id: String
    public let kind: Kind
    public let text: String
    public let timestamp: Date

    public init(id: String, kind: Kind, text: String, timestamp: Date) {
        self.id = id
        self.kind = kind
        self.text = text
        self.timestamp = timestamp
    }

    /// `true` for the kinds that count as somebody speaking.
    ///
    /// Used by the unread counter: a badge that went up because Claude ran a
    /// `Read` would be a badge nobody could act on.
    public var isConversation: Bool {
        kind == .human || kind == .assistant
    }
}

/// A whole conversation, ready to render.
public struct Conversation: Sendable, Equatable {
    /// Claude Code session id — the same one the traffic light uses.
    public let sessionId: String

    /// The title Claude gave the conversation, when it gave one.
    ///
    /// This is `ai-title` in the transcript. It is what makes the chat window a
    /// contact and not a file path, so when it is missing the caller falls back
    /// to the folder name rather than showing nothing.
    public let title: String?

    public let entries: [TranscriptEntry]

    /// How many entries were dropped off the front to keep the window bounded.
    ///
    /// Kept so the window can say so. A conversation that silently begins in the
    /// middle is a dropped message the reader has no way of seeing — and tmux, which
    /// has to do the same thing to control clients that fall behind, never does it
    /// quietly: it sends `%pause` on the wire, or disconnects the client with "too
    /// far behind". The consumer always learns what it stopped getting.
    public let omittedEntries: Int

    public init(
        sessionId: String,
        title: String? = nil,
        entries: [TranscriptEntry] = [],
        omittedEntries: Int = 0
    ) {
        self.sessionId = sessionId
        self.title = title
        self.entries = entries
        self.omittedEntries = max(0, omittedEntries)
    }

    /// The last thing said, for the line under the name in the roster.
    public var lastSpoken: TranscriptEntry? {
        entries.last { $0.isConversation }
    }

    /// How many answers arrived since the user last looked.
    ///
    /// Counts **assistant** entries only. A message you wrote yourself is not
    /// unread, and an activity line is not something you can be behind on.
    ///
    /// `nil` for `since` means never opened, which counts everything: opening a
    /// three-day-old conversation for the first time should say so.
    public func unreadCount(since: Date?) -> Int {
        entries.lazy
            .filter { $0.kind == .assistant }
            .filter { since == nil || $0.timestamp > since! }
            .count
    }

    /// Copy with `more` appended.
    ///
    /// Appending rather than re-reading is the whole point of tailing the file:
    /// a transcript reaches tens of thousands of lines, and re-parsing it on
    /// every hook would turn a chat window into a space heater.
    public func appending(_ more: [TranscriptEntry], title newTitle: String? = nil) -> Conversation {
        Conversation(
            sessionId: sessionId,
            title: newTitle ?? title,
            entries: entries + more,
            omittedEntries: omittedEntries
        )
    }

    /// Copy holding at most the last `limit` entries, remembering how many it let go.
    ///
    /// The count **accumulates**, because this runs on every poll over an already
    /// trimmed conversation: a figure that started from zero each time would settle
    /// on the size of one poll's overflow and stay there while the real number
    /// climbed into the hundreds.
    public func trimmed(to limit: Int) -> Conversation {
        guard entries.count > limit else { return self }
        return Conversation(
            sessionId: sessionId,
            title: title,
            entries: Array(entries.suffix(limit)),
            omittedEntries: omittedEntries + (entries.count - limit)
        )
    }
}
