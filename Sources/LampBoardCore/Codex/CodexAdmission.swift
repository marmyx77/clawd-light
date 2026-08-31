import Foundation

/// What the panel should hold after a Codex probe, given what it already holds.
///
/// One line of the store used to carry this whole rule:
///
/// ```swift
/// guard case .observed(let evidence) = result else { return }
/// ```
///
/// It is the right rule — a probe that could not answer is not a session that
/// ended — and nothing was watching it. Deleting that line left the suite green,
/// because producing an unavailable probe in a test would mean making `lsof`
/// genuinely hang. So the decision moved here, where it is a value handed to a
/// function, and the case that covers it can simply say `.unavailable`.
public enum CodexAdmission {

    /// What a scan says about the column.
    public struct Verdict: Sendable, Equatable {
        /// Sessions the panel does not know yet. Everything else it already has,
        /// and adoption never overwrites what is known.
        public let arriving: [CodexEvidence]
        /// Every Codex id that must survive the sweep. What is not here has had
        /// its rollout closed, which is the one ending Codex gives for free.
        public let alive: Set<String>

        public init(arriving: [CodexEvidence], alive: Set<String>) {
            self.arriving = arriving
            self.alive = alive
        }
    }

    /// The verdict, or `nil` when the probe could not answer.
    ///
    /// `nil` is not "nothing is running". It is "we did not get to look", and the
    /// caller must do nothing at all with it: add no rows, remove no rows, and
    /// leave the set of confirmed ids exactly as it was. The empty observation —
    /// `.observed([])` — is the opposite and does mean the conversations are
    /// over, because the probe ran and saw no open rollout.
    public static func verdict(
        on result: CodexScanResult, holding known: Set<String>
    ) -> Verdict? {
        guard case .observed(let evidence) = result else { return nil }
        return Verdict(
            arriving: evidence.filter { !known.contains($0.meta.sessionId) },
            alive: Set(evidence.map(\.meta.sessionId))
        )
    }
}
