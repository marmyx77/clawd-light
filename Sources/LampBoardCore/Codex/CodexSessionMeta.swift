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
    public let source: String?

    public let cliVersion: String?

    public init(
        sessionId: String, cwd: String,
        originator: String? = nil, source: String? = nil, cliVersion: String? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.originator = originator
        self.source = source
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

        // `session_id` is the documented name and `id` has been seen beside it.
        let id = (payload["session_id"] as? String) ?? (payload["id"] as? String)
        guard let id, !id.isEmpty,
              let cwd = payload["cwd"] as? String, cwd.hasPrefix("/")
        else { return nil }

        return CodexSessionMeta(
            sessionId: id,
            cwd: PathNormalizer.normalize(cwd),
            originator: payload["originator"] as? String,
            source: payload["source"] as? String,
            cliVersion: payload["cli_version"] as? String
        )
    }
}
