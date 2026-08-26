import Foundation

/// State of a single Claude Code session — that is, of one traffic light.
///
/// The type is immutable: every transition produces a new instance through the
/// `with…` methods, so there is no path along which a state can change under
/// the feet of whoever is reading it.
public struct SessionState: Sendable, Equatable, Identifiable {
    /// Claude Code session id.
    public let id: String

    /// The state the hooks declared for the main turn.
    ///
    /// It does not always match what is displayed: see `status`.
    public let baseStatus: SessionStatus

    /// VS Code workspace the session belongs to.
    public let workspace: Workspace

    /// Preview of the last answer, shown as a tooltip.
    public let lastMessage: String?

    /// Timestamp of the last signal received. Used for ordering and for
    /// dropping sessions that have been quiet for too long.
    public let updatedAt: Date

    /// Timestamp at which the session entered its current state.
    /// Lets the row show "how long it has been working".
    public let statusSince: Date

    /// Why the turn stopped. Only populated in the `failed` state.
    public let failureReason: StopFailureReason?

    /// How many subagents are running inside this session's turn.
    ///
    /// A subagent has no traffic light of its own, but its existence **proves**
    /// the session is working: without this counter a forty-five minute
    /// background workflow leaves the light frozen, because `Stop` only fires
    /// when the turn closes and nothing arrives in between.
    public let activeSubagents: Int

    /// What the session is waiting on, when it is `waiting`: the types Claude Code
    /// listed in flight at the last `Stop`, in its order — `monitor`, `shell`,
    /// `subagent`. Empty otherwise.
    ///
    /// Kept so the row can say *why* it is blue. A wait that lasts a day is only a
    /// defect if you cannot tell what is holding it; naming the shell makes the
    /// honest question — is that a dev server nobody will stop? — askable.
    public let waitingOn: [String]

    /// Where this session's transcript lives, when a hook has told us.
    ///
    /// Optional and it stays optional: a session adopted from the filesystem has
    /// no transcript path until the first hook arrives, and a chat window that
    /// cannot open is a better outcome than one that opens the wrong file.
    public let transcriptPath: String?

    public init(
        id: String,
        status: SessionStatus,
        workspace: Workspace,
        lastMessage: String? = nil,
        updatedAt: Date,
        statusSince: Date,
        failureReason: StopFailureReason? = nil,
        activeSubagents: Int = 0,
        transcriptPath: String? = nil,
        waitingOn: [String] = []
    ) {
        self.waitingOn = waitingOn
        self.id = id
        self.baseStatus = status
        self.workspace = workspace
        self.lastMessage = lastMessage
        self.updatedAt = updatedAt
        self.statusSince = statusSince
        self.failureReason = failureReason
        self.activeSubagents = max(0, activeSubagents)
        self.transcriptPath = transcriptPath
    }

    /// The state the traffic light actually shows.
    ///
    /// As long as a subagent is alive the session **is working**, whatever the
    /// last hook of the main turn may have said. This is not a refinement: with
    /// background agents, `Stop` fires when the parent turn returns control while
    /// the agents keep going for tens of minutes. Taking that `Stop` literally
    /// paints green — "there is an answer to read" — onto a session that is still
    /// working, and that is the most expensive lie the column can tell.
    ///
    /// Deriving it rather than storing it also solves the way back on its own:
    /// when the last subagent finishes, the green that was set aside reappears
    /// without anyone having to remember it.
    ///
    /// The one exception is waiting for a permission, which always wins: it blocks
    /// everything, subagents included, and it needs you now.
    ///
    /// What a live subagent paints depends on whether the parent is still in its
    /// turn. While it is (`working`), the row is working. After the parent's
    /// `Stop`, a subagent still alive is a session **waiting** to be woken by it —
    /// not one working. It used to paint yellow over any state, and yellow over a
    /// session that has stopped is the half-truth D22 exists to remove.
    public var status: SessionStatus {
        guard activeSubagents > 0 else { return baseStatus }
        switch baseStatus {
        case .awaiting: return .awaiting
        case .working: return .working
        case .ready, .idle, .waiting, .failed: return .waiting
        }
    }

    // MARK: - Copies

    /// Copy with a new state. `statusSince` only advances when the state really
    /// changes, so a burst of `PreToolUse` events doesn't reset the stopwatch.
    public func with(status newStatus: SessionStatus, at now: Date) -> SessionState {
        replacing(
            status: newStatus,
            updatedAt: now,
            statusSince: newStatus == baseStatus ? statusSince : now
        )
    }

    /// Copy with a new failure cause.
    /// Passing `nil` clears it: a session that restarts does not carry the
    /// previous turn's error with it.
    public func with(failureReason newReason: StopFailureReason?) -> SessionState {
        replacing(failureReason: .some(newReason))
    }

    /// Copy marked as seen by the user.
    ///
    /// Unlike `with(status:at:)` this does **not** touch `updatedAt`: that field
    /// records Claude's last activity, and it is what the row label displays. A
    /// click is not session activity, and jumping a three-day-old session to "now"
    /// would erase the only useful information it carries.
    public func markedSeen(at now: Date) -> SessionState {
        replacing(status: .idle, statusSince: now, failureReason: .some(nil))
    }

    /// Copy restored to "there is something to read".
    ///
    /// This is the remedy for one click too many: `markedSeen` is irreversible by
    /// construction, and without this escape hatch an accidentally consumed answer
    /// is lost. It leaves `updatedAt` alone for the same reason.
    public func markedUnread(at now: Date) -> SessionState {
        guard baseStatus == .idle else { return self }
        return replacing(status: .ready, statusSince: now)
    }

    /// Copy that records — or forgets — what the session is waiting on.
    public func with(waitingOn types: [String]) -> SessionState {
        guard types != waitingOn else { return self }
        return replacing(waitingOn: types)
    }

    /// Copy with a new preview message.
    public func with(lastMessage newMessage: String?) -> SessionState {
        replacing(lastMessage: .some(newMessage ?? lastMessage))
    }

    /// Copy with an updated workspace: a session can change `cwd` and end up in
    /// a different workspace.
    public func with(workspace newWorkspace: Workspace) -> SessionState {
        replacing(workspace: newWorkspace)
    }

    /// Copy that remembers where the transcript is.
    ///
    /// A `nil` argument leaves the known path alone instead of clearing it. The
    /// path is a fact about the session that does not stop being true because one
    /// signal failed to carry it, and forgetting it would close the chat window
    /// of a session that is merely between events.
    public func with(transcriptPath newPath: String?) -> SessionState {
        guard let newPath, newPath != transcriptPath else { return self }
        return replacing(transcriptPath: .some(newPath))
    }

    /// Copy with the subagent counter shifted by `delta`, never below zero.
    ///
    /// The floor at zero is not pedantry: `SubagentStop` can arrive without its
    /// matching `SubagentStart` — the app may have started mid-turn — and a
    /// negative counter would hold the row yellow forever.
    public func withSubagents(delta: Int, at now: Date) -> SessionState {
        replacing(updatedAt: now, activeSubagents: max(0, activeSubagents + delta))
    }

    /// Copy with the counter zeroed.
    ///
    /// The reset point is the **user's prompt**, not the end of the turn: with
    /// background agents the turn finishes while they are still working, and
    /// resetting there would restore green at the worst possible moment. A new
    /// prompt, by contrast, is a certain boundary, and it doubles as a safety net —
    /// if a `SubagentStop` gets lost along the way, the stuck counter clears on the
    /// next question instead of holding the row yellow until pruning.
    public func withoutSubagents() -> SessionState {
        guard activeSubagents != 0 else { return self }
        return replacing(activeSubagents: 0)
    }

    // MARK: - Queries

    /// Duration of the current state relative to `now`.
    public func statusDuration(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(statusSince))
    }

    /// `true` when the session has subagents in flight.
    public var hasActiveSubagents: Bool { activeSubagents > 0 }

    // MARK: - Internal

    /// Copy with only the given fields replaced.
    ///
    /// Fields that can hold `nil` arrive as a double optional: `nil` means "leave
    /// it alone", `.some(nil)` means "clear it". Without that distinction there
    /// would be no way to erase `failureReason`, which is exactly what is needed
    /// when a session restarts after an error.
    private func replacing(
        status: SessionStatus? = nil,
        workspace: Workspace? = nil,
        lastMessage: String?? = nil,
        updatedAt: Date? = nil,
        statusSince: Date? = nil,
        failureReason: StopFailureReason?? = nil,
        activeSubagents: Int? = nil,
        transcriptPath: String?? = nil,
        waitingOn: [String]? = nil
    ) -> SessionState {
        SessionState(
            id: id,
            status: status ?? baseStatus,
            workspace: workspace ?? self.workspace,
            lastMessage: lastMessage ?? self.lastMessage,
            updatedAt: updatedAt ?? self.updatedAt,
            statusSince: statusSince ?? self.statusSince,
            failureReason: failureReason ?? self.failureReason,
            activeSubagents: activeSubagents ?? self.activeSubagents,
            transcriptPath: transcriptPath ?? self.transcriptPath,
            waitingOn: waitingOn ?? self.waitingOn
        )
    }
}
