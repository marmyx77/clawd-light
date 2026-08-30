import Foundation

/// What a Codex rollout says about itself in its first line.
///
/// The **only** place a scanner-found Codex session may take its folder from. A
/// signal arriving on the unauthenticated `/signal` route can name any `cwd` it
/// likes, and the gate that used to bound that was a Claude Code window lock,
/// which a machine running only Codex does not have. Reading the folder out of a
/// file that a live process is holding open replaces the proof rather than
/// removing it: the row exists because a file exists and a process has it open,
/// and nothing anybody sends us decides where it points.
public struct CodexSessionMeta: Sendable, Equatable {
    /// The rollout's own id, from `id`.
    ///
    /// Distinct from `sessionId`, and the distinction is not academic. On this
    /// machine, 26 rollouts came in three shapes: 19 where the two are the same
    /// string, 4 written by the command line where `session_id` is **null** and
    /// only `id` is there, and 3 where they differ because the file belongs to a
    /// subagent and `session_id` names its parent.
    public let rolloutId: String

    /// The conversation this rollout belongs to: itself, or the parent when the
    /// rollout is a subagent's.
    public let sessionId: String

    public let cwd: String

    /// Kept as written, never matched against a list. In one week this field has
    /// been seen as `codex_cli_rs`, `codex-tui`, `codex_exec` and `Codex Desktop`,
    /// inside a format its own documentation calls unstable. It is a diagnostic
    /// and a way to notice the format moving, not a decision.
    public let originator: String?

    /// Not the same word as the hooks' `SessionStart.source`, which says
    /// `startup`, `resume`, `clear` or `compact`. Here it names a surface, `cli`
    /// or `vscode`. Two vocabularies under one word, so neither is trusted to
    /// decide anything.
    ///
    /// Read only when it is a string, because it is not always one: a subagent's
    /// rollout writes an object there instead.
    public let source: String?

    /// The subagent this rollout belongs to, when it belongs to one.
    ///
    /// Measured shape: `"source": {"subagent": {"other": "guardian"}}`, beside a
    /// `session_id` naming the parent conversation.
    public let subagent: String?

    public let cliVersion: String?

    /// `true` when this file is a subagent's work rather than a conversation.
    ///
    /// Two independent signs, either of which is enough. The object under
    /// `source` is the direct one. The ids disagreeing is the safety net, for a
    /// format its own authors call unstable: whatever `source` grows into, a
    /// rollout whose `id` is not its `session_id` is not that session's rollout.
    public var isSubagent: Bool { subagent != nil || rolloutId != sessionId }

    public init(
        sessionId: String, cwd: String, rolloutId: String? = nil,
        originator: String? = nil, source: String? = nil, subagent: String? = nil,
        cliVersion: String? = nil
    ) {
        self.rolloutId = rolloutId ?? sessionId
        self.sessionId = sessionId
        self.cwd = cwd
        self.originator = originator
        self.source = source
        self.subagent = subagent
        self.cliVersion = cliVersion
    }
}

public enum CodexSessionMetaReader {

    /// How much of the head to read. The record is the first line; the cap is
    /// there because the file after it can be nine megabytes.
    public static let headLimit = 64 * 1024

    /// Reads the `session_meta` record, or refuses.
    ///
    /// Fails closed at every step. A rollout whose first record is not
    /// `session_meta`, or whose `cwd` is not an absolute path, produces nothing at
    /// all rather than a session pointing somewhere plausible. The format is
    /// declared unstable by the people who write it, so the shape being wrong is a
    /// thing that will happen, and the right answer to it is a row that never
    /// appears rather than a row that is quietly wrong.
    public static func read(head: String) -> CodexSessionMeta? {
        guard let line = head.split(separator: "\n", omittingEmptySubsequences: true).first,
              let data = line.data(using: .utf8),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              record["type"] as? String == "session_meta",
              let payload = record["payload"] as? [String: Any]
        else { return nil }

        // Two fields, and each is sometimes the only one there. `session_id` is
        // the documented name and is null in every rollout the command line
        // writes; `id` is the file's own and names the subagent when there is
        // one. Each falls back to the other, and where they disagree the
        // disagreement is kept rather than flattened — flattening it is what
        // gave a parent conversation two rollouts and let the wrong one become
        // its transcript.
        let declared = (payload["session_id"] as? String)?.nilIfEmpty
        let own = (payload["id"] as? String)?.nilIfEmpty
        guard let sessionId = declared ?? own, let rolloutId = own ?? declared,
              let cwd = payload["cwd"] as? String, cwd.hasPrefix("/")
        else { return nil }

        return CodexSessionMeta(
            sessionId: sessionId,
            cwd: PathNormalizer.normalize(cwd),
            rolloutId: rolloutId,
            originator: payload["originator"] as? String,
            source: payload["source"] as? String,
            subagent: subagentName(in: payload["source"]),
            cliVersion: payload["cli_version"] as? String
        )
    }

    /// The subagent named under `source`, when `source` is an object rather than
    /// a surface.
    ///
    /// Deliberately shallow. The one shape seen is
    /// `{"subagent": {"other": "guardian"}}`, and the key under `subagent` has no
    /// documented vocabulary, so what is taken is the presence of the marker and
    /// whatever string is beside it. When the marker is there and the name is
    /// not, the answer is still a name — an unnamed subagent is a subagent.
    private static func subagentName(in source: Any?) -> String? {
        guard let object = source as? [String: Any], let marker = object["subagent"] else {
            return nil
        }
        if let name = marker as? String { return name.nilIfEmpty ?? "subagent" }
        guard let fields = marker as? [String: Any] else { return "subagent" }
        return fields.values.compactMap { ($0 as? String)?.nilIfEmpty }.sorted().first ?? "subagent"
    }
}
