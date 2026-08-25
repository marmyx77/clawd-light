import Foundation

/// The five states of a traffic light.
///
/// The semantics are deliberate: green does not mean "all good", it means
/// "there is an answer you haven't read yet".
public enum SessionStatus: String, Sendable, Equatable, CaseIterable, Codable {
    /// Session at rest: no work in progress, nothing to read. Dim red.
    case idle

    /// Claude is thinking or running tools. Yellow.
    case working

    /// Claude is blocked waiting for a decision from you. Blinking amber.
    case awaiting

    /// The turn has finished: there is an answer to read. Green.
    case ready

    /// The turn stopped without producing an answer: quota limit, overload,
    /// authentication error. Solid red.
    ///
    /// Kept distinct from `ready` because there something is waiting to be read
    /// and here nothing is: showing them in the same color makes "it finished"
    /// indistinguishable from "it died halfway".
    case failed

    /// Sort priority: the states that demand attention rise to the top.
    /// Lower = more urgent.
    ///
    /// `failed` sits below `ready` on purpose: a ready answer is consumed right
    /// away, whereas there is nothing you can do about a rate limit until it expires.
    public var urgencyRank: Int {
        switch self {
        case .awaiting: return 0
        case .ready: return 1
        case .failed: return 2
        case .working: return 3
        case .idle: return 4
        }
    }

    /// Only `awaiting` blinks: blinking is a scarce signal and should be spent on
    /// the one state that genuinely blocks the work.
    public var shouldBlink: Bool {
        self == .awaiting
    }

    /// States representing something the user has not seen yet, and which
    /// therefore fall back to `idle` when they open the session.
    public var clearsOnFocus: Bool {
        switch self {
        case .ready, .awaiting, .failed: return true
        case .idle, .working: return false
        }
    }

    /// States that a trailing signal must not be allowed to downgrade to `working`.
    ///
    /// Distinct from `clearsOnFocus`: `failed` should be cleared by a click like
    /// the others, but it must **not** survive a restart — if the turn resumes
    /// after an error, yellow is the correct information and red would be a leftover.
    public var blocksDowngrade: Bool {
        switch self {
        case .ready, .awaiting: return true
        case .idle, .working, .failed: return false
        }
    }
}
