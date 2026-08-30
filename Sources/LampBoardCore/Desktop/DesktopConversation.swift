import Foundation

/// The two judgements a Claude Desktop row rests on, kept away from the disk so
/// they can be argued with.
///
/// The scanner's job is to walk directories and read files. Everything it then
/// **decides** is here: whether what it found is a row at all, and what colour
/// that row may honestly be. Both were wrong in the first version, and neither
/// mistake was visible in a test, because both lived inside a function that only
/// ran against a real home.
public enum DesktopConversation {

    /// Whether the panel may show a row for this conversation.
    ///
    /// Three gates, and each is the application's own answer rather than an
    /// inference of ours:
    ///
    /// - it must have a folder the application **resolved as local**, which is
    ///   the one field separating a session running on this Mac from one running
    ///   on Anthropic's servers, where nothing is readable at all;
    /// - it must not be archived, which is the person saying they are done
    ///   with it;
    /// - it must have been active since `horizon`, without which every
    ///   conversation ever held would be a row. Fifty-one of them are on the
    ///   machine this was written on, going back to April.
    ///
    /// A conversation with no transcript id is not refused here: the id is what
    /// the row is keyed by, so the caller cannot even name it, and that is a
    /// stronger statement than this function should make.
    public static func deservesRow(_ index: DesktopSessionIndex, since horizon: Date) -> Bool {
        guard index.hasLocalFolder, !index.isArchived else { return false }
        guard let recorded = index.lastActivityAt else { return false }
        return recorded >= horizon
    }

    /// A colour, and the moment its evidence is dated.
    public struct Derivation: Sendable, Equatable {
        public let status: SessionStatus
        /// When what was seen was true.
        ///
        /// Carried because this colour is re-read on a timer rather than
        /// reported once, so the state machine needs to know whether it is news
        /// or the same thing said again. See `ReducerAction.derive`.
        public let moment: Date

        public init(status: SessionStatus, moment: Date) {
            self.status = status
            self.moment = moment
        }
    }

    /// The colour the evidence supports, and nothing beyond it.
    ///
    /// Two kinds of evidence, dated two different ways, and the difference is
    /// the whole of this function.
    ///
    /// A colour read off the **transcript** is dated by the transcript. It is a
    /// record of something that happened, so it is news only until the row has
    /// moved past it: without that, clearing a green row would set it seen and
    /// the next sweep would light it up again for the same answer, five seconds
    /// later, for ever.
    ///
    /// A colour read off a **live process** holding the conversation's session
    /// file is dated **now**. It is not a record of anything; it is a thing that
    /// is true at the moment of looking. Dating it by the transcript is what
    /// broke the first version of this rule: a turn that has just started has
    /// written nothing yet, so the transcript still ends in the previous answer,
    /// and a row cleared a moment ago could never go yellow again until the
    /// model happened to write a line.
    ///
    /// A live process also outranks the transcript, for the same reason: the
    /// transcript is what has been written so far, and a model that has just
    /// been asked a question has written nothing.
    ///
    /// `idle` when the transcript says nothing readable. That is the absence of
    /// information, spelled as the absence of information — never a colour
    /// invented to fill the gap.
    public static func derivation(
        isAnswering: Bool, phase: TranscriptTurn.Phase?, lastActivity: Date, observedAt: Date
    ) -> Derivation {
        if isAnswering { return Derivation(status: .working, moment: observedAt) }
        switch phase {
        case .running: return Derivation(status: .working, moment: lastActivity)
        case .answered: return Derivation(status: .ready, moment: lastActivity)
        case nil: return Derivation(status: .idle, moment: lastActivity)
        }
    }
}
