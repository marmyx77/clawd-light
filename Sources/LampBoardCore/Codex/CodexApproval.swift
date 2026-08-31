import Foundation

/// Who answers when Codex asks for permission.
///
/// Codex publishes `PermissionRequest` for a tool call that needs approval, and
/// the event says nothing about **who** will approve it. Measured on this
/// machine: with a reviewer of `auto_review` the answer arrives on its own in a
/// few hundred milliseconds and nobody was ever waiting, while the row turned
/// amber and blinked — the one state reserved for a turn that is blocked on a
/// person. Three of those during one audit lasted 6.0 s, 6.4 s and 31.0 s,
/// because the row only goes back to yellow at `PostToolUse`, which arrives when
/// the command **finishes** rather than when the approval lands.
///
/// The reviewer is not in the event, but it is in the session's rollout, and the
/// event carries that file's path. It changes during a session — measured
/// switching from `user` to `auto_review` halfway through an audit — so it is
/// read per request rather than once.
public enum ApprovalReviewer: String, Sendable, Equatable {

    /// A person has to answer. Amber is correct: the turn is blocked.
    case person = "user"

    /// A reviewer answers by itself. Nobody is waiting, so nothing should blink.
    case automatic = "auto_review"
}

/// Reads what a Codex rollout says about who reviews approvals.
public enum CodexApproval {

    /// The key `turn_context` records carry.
    private static let field = "approvals_reviewer"

    /// The reviewer named by the **last** `turn_context` in these lines, or `nil`
    /// when the rollout does not say.
    ///
    /// `nil` is not a failure and must not be read as one: an unreadable rollout,
    /// a format that moved, a record not written yet. The caller treats it the way
    /// this project treats every absence — as the absence of information, which
    /// here means showing the request rather than hiding it. A false amber costs a
    /// glance; a swallowed one costs a turn stopped without anybody knowing.
    ///
    /// Lines are read newest first, because the value changes mid-session and the
    /// most recent one is the one in force.
    public static func reviewer(inRollout lines: [String]) -> ApprovalReviewer? {
        for line in lines.reversed() {
            guard line.contains(field) else { continue }
            guard let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            guard record["type"] as? String == "turn_context" else { continue }
            guard let payload = record["payload"] as? [String: Any],
                  let raw = payload[field] as? String
            else { continue }
            return ApprovalReviewer(rawValue: raw)
        }
        return nil
    }
}
