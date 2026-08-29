import Foundation

/// The Claude Code lifecycle events we care about.
///
/// Claude Code exposes around thirty of them; we keep only the ones that move a
/// traffic light. An unknown event is not an error — it is simply ignored, so the
/// app doesn't break when Anthropic adds new ones.
public enum HookEventKind: String, Sendable, Equatable, CaseIterable, Codable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case notification = "Notification"

    /// Codex is about to ask for an approval. Claude Code has no equivalent it
    /// exposes passively — it announces the same fact through `Notification` —
    /// so this is registered for one harness only. See `Harness.defaultHookEvents`.
    case permissionRequest = "PermissionRequest"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case sessionEnd = "SessionEnd"

    /// A subagent started inside this session's turn.
    case subagentStart = "SubagentStart"

    /// A subagent finished.
    case subagentStop = "SubagentStop"
}

/// `Notification` subtypes relevant to the state machine.
public enum NotificationKind: String, Sendable, Equatable {
    /// Claude is asking permission to run a tool: the most urgent state.
    case permissionPrompt = "permission_prompt"

    /// The session has been sitting idle waiting for input for a while.
    case idlePrompt = "idle_prompt"

    /// An agent completed its work.
    case agentCompleted = "agent_completed"

    /// An agent needs input.
    case agentNeedsInput = "agent_needs_input"

    /// An MCP server opened a dialog and is waiting for an answer: it blocks the
    /// session exactly like a permission request.
    case elicitationDialog = "elicitation_dialog"
}
