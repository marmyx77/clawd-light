import Foundation

/// What a blocked session is actually asking for.
///
/// The amber dot says a session needs you. In a twelve-session day the next
/// question is always the same — *is this the approval I grant without reading,
/// or the one I have to look at* — and walking to the window to find out is the
/// walk the panel exists to save.
///
/// This exists for Codex and not for Claude Code, and the asymmetry is a finding
/// rather than an omission. Claude Code's `Notification` payload was read out of
/// the shipped binary while this was written: it builds the message as
/// `Claude needs your permission to use ${tool}` and carries no `tool_input` at
/// all, so the most that side can produce is the amber dot spelled out in
/// English. The command itself lives only in `PermissionRequest`, a decision
/// hook this project declines to register there. Codex publishes `tool_name` and
/// `tool_input` on its own `PermissionRequest`, which it must be registered for
/// anyway — it has no other way to say a session is blocked.
///
/// So the rule is not "show the ask when we can be bothered": it is that the
/// panel says exactly as much as the harness will tell it, and no more.
public struct PendingAsk: Sendable, Equatable {

    /// The tool being asked about, in the harness's own vocabulary: `Bash`,
    /// `apply_patch`, `mcp__server__tool`.
    public let tool: String

    /// The one argument worth showing, already chosen and trimmed. `nil` when the
    /// tool carries nothing safe to show, which is normal rather than a failure.
    public let detail: String?

    public init(tool: String, detail: String?) {
        self.tool = tool
        self.detail = detail
    }

    /// The line a row shows: `Bash: git push origin main`.
    public var sentence: String {
        guard let detail, !detail.isEmpty else { return tool }
        return "\(tool): \(detail)"
    }

    /// The longest a detail may be before it is cut.
    ///
    /// A cut is announced with an ellipsis rather than left to look like the end
    /// of the command, because a `rm -rf` truncated after `rm -rf /Users/dev` and
    /// a `rm -rf /Users/dev` are the same string on screen and very different
    /// things to approve.
    public static let detailLimit = 120

    /// Reads the ask out of a hook payload's tool fields.
    ///
    /// The allow-list is the whole design. `tool_input` is a free-form JSON value
    /// whose shape belongs to whichever tool is being called: an `apply_patch`
    /// carries the **contents of the file being written**, and an MCP tool carries
    /// whatever its author decided. Rendering that blind would put source code,
    /// and anything a person happened to paste into a prompt, onto a floating
    /// panel that sits on top of a screen being shared.
    ///
    /// So only these keys are ever shown, and only as strings:
    ///
    /// - `command` — the shell line, which is the whole point
    /// - `file_path`, `path` — *which* file, never its contents
    /// - `url` — where a fetch is going
    /// - `description` — the human-readable reason, when Codex supplies one
    ///
    /// Everything else is dropped and the row shows the tool name alone, which is
    /// still more than a bare dot. Adding a key here is a decision about what may
    /// appear on a screen, not a formatting tweak.
    public static func from(toolName: String?, toolInput: Any?) -> PendingAsk? {
        guard let tool = toolName?.trimmed, !tool.isEmpty else { return nil }
        return PendingAsk(tool: tool, detail: detail(from: toolInput))
    }

    private static let shownKeys = ["command", "file_path", "path", "url", "description"]

    private static func detail(from toolInput: Any?) -> String? {
        // A tool whose whole input is one string — some MCP servers do this — is
        // still an argument, not a document; the same cap applies.
        if let text = toolInput as? String { return clipped(text) }
        guard let object = toolInput as? [String: Any] else { return nil }
        for key in shownKeys {
            if let text = (object[key] as? String)?.trimmed, !text.isEmpty {
                return clipped(text)
            }
        }
        return nil
    }

    private static func clipped(_ raw: String) -> String? {
        // Newlines become spaces before anything else: a multi-line heredoc drawn
        // into a single-line row would otherwise take the row's height with it.
        let flat = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        guard flat.count > detailLimit else { return flat }
        return String(flat.prefix(detailLimit)) + "…"
    }
}
