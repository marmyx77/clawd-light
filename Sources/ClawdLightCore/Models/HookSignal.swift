import Foundation

/// A validated signal coming from a Claude Code hook.
///
/// This is the type that crosses the system boundary: it is only ever built by
/// `HookPayloadDecoder`, which rejects malformed payloads. From here on the rest
/// of the code may assume the fields make sense.
public struct HookSignal: Sendable, Equatable {
    /// Claude Code session identifier.
    public let sessionId: String

    /// Event that produced the signal.
    public let event: HookEventKind

    /// Working directory of the session. Absolute and normalised.
    public let cwd: String

    /// Subtype, only populated for `Notification`.
    public let notificationKind: NotificationKind?

    /// Present only when the signal comes from a subagent. In that case it must be
    /// ignored: subagents work inside the parent's turn and must not move the light.
    public let agentId: String?

    /// Claude Code entrypoint (`claude-vscode`, `cli`, …), read from the environment
    /// by the hook script. Used to discard sessions not hosted by VS Code.
    public let entrypoint: String?

    /// Text of the assistant's last message, present on `Stop`.
    /// Used as the row tooltip. On `StopFailure` it holds the error text.
    public let lastAssistantMessage: String?

    /// Reason for the start, only populated for `SessionStart`:
    /// `startup`, `resume`, `clear`, `compact`, `fork`.
    ///
    /// Needed to tell opening a session apart from compacting the context, which
    /// fires **mid-turn** and must not reset the row.
    public let sessionSource: String?

    /// Cause of the interruption, only populated for `StopFailure`.
    public let failureReason: StopFailureReason?

    /// Absolute path of the session's JSONL transcript.
    ///
    /// Present on **every** event. It is the only way to reach what was actually
    /// said in a session — the hooks describe state, this file holds content —
    /// and it is what the chat window reads.
    public let transcriptPath: String?

    public init(
        sessionId: String,
        event: HookEventKind,
        cwd: String,
        notificationKind: NotificationKind? = nil,
        agentId: String? = nil,
        entrypoint: String? = nil,
        lastAssistantMessage: String? = nil,
        sessionSource: String? = nil,
        failureReason: StopFailureReason? = nil,
        transcriptPath: String? = nil
    ) {
        self.sessionId = sessionId
        self.event = event
        self.cwd = cwd
        self.notificationKind = notificationKind
        self.agentId = agentId
        self.entrypoint = entrypoint
        self.lastAssistantMessage = lastAssistantMessage
        self.sessionSource = sessionSource
        self.failureReason = failureReason
        self.transcriptPath = transcriptPath
    }

    /// `true` when the event is a context compaction: not the start of a session,
    /// but a technical interruption inside a turn already in progress.
    public var isContextCompaction: Bool {
        event == .sessionStart && sessionSource == "compact"
    }

    /// A signal emitted by a subagent does not represent the user session's state.
    public var isFromSubagent: Bool {
        guard let agentId else { return false }
        return !agentId.isEmpty
    }

    /// How far this signal moves the subagent counter, if at all.
    ///
    /// `SubagentStart` and `SubagentStop` carry `agent_id` like any other event
    /// generated inside a subagent, but they are not the same thing: the others
    /// describe the subagent's *work*, these two describe that the subagent
    /// **exists**, which is a fact about the parent's turn. The rule that discards
    /// subagent signals still stands — it just has to be applied afterwards.
    public var subagentDelta: Int? {
        switch event {
        case .subagentStart: return 1
        case .subagentStop: return -1
        default: return nil
        }
    }

    /// `true` when the signal deserves a row in the column.
    ///
    /// The criterion is **not** the entrypoint. Filtering on `claude-vscode`
    /// discarded every session started with `claude` from VS Code's *integrated*
    /// terminal: same window, same project, same click that would bring it to the
    /// front, and yet no traffic light. And it was an invisible defect — a missing
    /// row doesn't complain.
    ///
    /// Widening the entrypoint list was not the right fix: future entrypoints are
    /// unknown, and an allow-list punctures itself with every Claude Code release.
    /// The correct criterion is *where* the session runs, and the workspace resolver
    /// already answers that: if the `cwd` sits inside a folder an IDE has open, the
    /// session is in that window, however it was started.
    ///
    /// What remains here is only the exclusion of what isn't interactive — no user
    /// is waiting in front of an automated session.
    public var deservesTrafficLight: Bool {
        guard let entrypoint, !entrypoint.isEmpty else { return true }
        return !AppConfig.nonInteractiveEntrypoints.contains(entrypoint)
    }
}
