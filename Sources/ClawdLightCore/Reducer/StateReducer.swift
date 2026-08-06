import Foundation

/// The actions that can change the traffic light column.
public enum ReducerAction: Sendable, Equatable {
    /// A hook signal, already matched to its workspace (`nil` when it doesn't belong to VS Code).
    case signal(HookSignal, workspace: Workspace?)

    /// The user has seen the session: the "unread" states go back to red.
    case markSeen(sessionId: String)

    /// Remedy for one click too many: a cleared row goes back to "there is something to read".
    case markUnread(sessionId: String)

    /// Removes sessions that have been quiet for too long.
    ///
    /// `alive` are the ones whose process is confirmed running; they are kept
    /// whatever their timestamp says. Silence is not death when you can see the
    /// process.
    case prune(alive: Set<String> = [])

    /// Aligns the column with the Claude Code processes that are actually alive.
    /// An empty set is ignored: it almost always means the filesystem read failed,
    /// not that every session disappeared.
    case reconcile(alive: Set<String>)

    /// Inserts a session discovered from the filesystem, without overwriting one
    /// already known: what the hooks know is always more precise than a deduction.
    case adopt(SessionState)

    /// Replaces the whole state (used when the app restarts).
    case reset
}

/// A pure state machine: `(state, action) -> new state`.
///
/// No dependency on the clock, the filesystem or the network — `now` is a parameter.
/// All the traffic light logic lives here, and it is entirely under test.
public enum StateReducer {
    public static func reduce(
        _ state: TrafficLightState,
        action: ReducerAction,
        now: Date
    ) -> TrafficLightState {
        switch action {
        case .reset:
            return .empty

        case .prune(let alive):
            return state.pruning(
                olderThan: AppConfig.sessionStaleAfter, at: now, keepingAlive: alive
            )

        case .reconcile(let alive):
            guard !alive.isEmpty else { return state }
            return TrafficLightState(sessions: state.sessions.filter { alive.contains($0.key) })

        case .adopt(let session):
            guard state.sessions[session.id] == nil else { return state }
            return state.upserting(session)

        case .markSeen(let sessionId):
            guard let session = state.sessions[sessionId], session.status.clearsOnFocus else {
                return state
            }
            return state.upserting(session.markedSeen(at: now))

        case .markUnread(let sessionId):
            guard let session = state.sessions[sessionId] else { return state }
            return state.upserting(session.markedUnread(at: now))

        case .signal(let signal, let workspace):
            let next = apply(signal: signal, workspace: workspace, to: state, now: now)
            return remembering(transcriptOf: signal, in: next)
        }
    }

    /// Records where the session's transcript lives, whatever else the signal did.
    ///
    /// It sits here, once, rather than on each of the seven paths through `apply`:
    /// the path is orthogonal to the traffic light — it does not depend on the
    /// event, the state or the ordering — and threading it through every branch
    /// would mean seven chances to forget it and no test that notices six.
    ///
    /// A session `apply` removed or refused is simply not there, and this does
    /// nothing. That is the correct outcome, not a special case.
    private static func remembering(
        transcriptOf signal: HookSignal,
        in state: TrafficLightState
    ) -> TrafficLightState {
        guard let path = signal.transcriptPath,
              let session = state.sessions[signal.sessionId]
        else { return state }
        return state.upserting(session.with(transcriptPath: path))
    }

    // MARK: - Applying a signal

    private static func apply(
        signal: HookSignal,
        workspace: Workspace?,
        to state: TrafficLightState,
        now: Date
    ) -> TrafficLightState {
        // Only sessions that deserve a row, and only inside a known workspace.
        guard signal.deservesTrafficLight, let workspace else { return state }

        // The birth and death of a subagent must be read **before** the rule that
        // discards subagent signals: they carry `agent_id` like all the others,
        // but they speak about the parent's turn, not the child's.
        if let delta = signal.subagentDelta {
            return applySubagent(delta: delta, signal: signal, workspace: workspace, to: state, now: now)
        }

        // A subagent works inside the parent's turn: it has no traffic light of its own.
        guard !signal.isFromSubagent else { return state }

        if signal.event == .sessionEnd {
            return state.removing(sessionId: signal.sessionId)
        }

        guard let newStatus = status(for: signal) else {
            return discovering(signal: signal, workspace: workspace, in: state, now: now)
        }

        let existing = state.sessions[signal.sessionId]

        // An answer that is already waiting is not downgraded to "working" by a
        // trailing signal that arrived out of order.
        //
        // The comparison is against `baseStatus`, not the displayed state: a
        // session with green set aside and subagents in flight *appears* yellow,
        // and using the appearance here would make the very downgrade this rule
        // exists to prevent look legitimate — erasing precisely the answer that
        // is waiting to be read.
        if let existing,
           shouldKeep(current: existing.baseStatus, over: newStatus, event: signal.event) {
            return state.upserting(
                existing
                    .with(workspace: workspace)
                    .with(lastMessage: preview(of: signal.lastAssistantMessage))
            )
        }

        let base = existing?
            .with(workspace: workspace)
            ?? SessionState(
                id: signal.sessionId,
                status: newStatus,
                workspace: workspace,
                updatedAt: now,
                statusSince: now
            )

        let updated = base
            .with(status: newStatus, at: now)
            .with(lastMessage: preview(of: signal.lastAssistantMessage))
            .with(failureReason: newStatus == .failed ? (signal.failureReason ?? .unknown) : nil)

        // A new question opens a new turn: the previous turn's subagents no longer
        // count, and if some `SubagentStop` got lost along the way this is where
        // the stuck counter clears.
        return state.upserting(
            signal.event == .userPromptSubmit ? updated.withoutSubagents() : updated
        )
    }

    /// Moves a session's subagent counter.
    ///
    /// A start creates the row if it isn't there: a subagent starting **proves** a
    /// session is working, and that is stronger evidence than what the app already
    /// trusts when discovering new sessions.
    ///
    /// A stop, by contrast, creates nothing. There is nothing to decrement in a
    /// session never seen before, and materializing a row from a closing event
    /// would mean inventing a state out of its own conclusion.
    private static func applySubagent(
        delta: Int,
        signal: HookSignal,
        workspace: Workspace,
        to state: TrafficLightState,
        now: Date
    ) -> TrafficLightState {
        guard let existing = state.sessions[signal.sessionId] else {
            guard delta > 0 else { return state }
            return state.upserting(
                SessionState(
                    id: signal.sessionId,
                    status: .working,
                    workspace: workspace,
                    updatedAt: now,
                    statusSince: now,
                    activeSubagents: delta
                )
            )
        }

        return state.upserting(
            existing
                .with(workspace: workspace)
                .withSubagents(delta: delta, at: now)
        )
    }

    /// Maps event → traffic light state. `nil` means "change nothing".
    private static func status(for signal: HookSignal) -> SessionStatus? {
        switch signal.event {
        case .sessionStart:
            // Context compaction fires mid-turn: treating it as the start of a
            // session would clear the yellow of a session that is working, and
            // sink it to the bottom of the column into the bargain.
            return signal.isContextCompaction ? nil : .idle

        case .userPromptSubmit, .preToolUse, .postToolUse:
            return .working

        case .stop:
            // A turn that ends with shells still running has **not** finished the
            // work, and green means two things at once: there is something to read,
            // and nothing more is coming. The second half is false here.
            //
            // This was examined on the first day and deliberately left alone, on
            // the reasoning that the turn had genuinely ended and an answer
            // genuinely existed. Use overruled it: the session writes a recap, the
            // light goes green, and the actual work carries on for minutes —
            // exactly the lie the subagent correction exists to prevent, arriving
            // by a different door.
            //
            // Green comes back on its own. The task finishes, wakes the session
            // with a notification, and that turn ends with nothing running.
            return signal.runningBackgroundTasks > 0 ? .working : .ready

        case .stopFailure:
            // A turn that was cut down produced nothing to read: showing it green
            // like a completed turn is the most expensive lie in the column. The
            // one exception is truncation at maximum length, where the text exists
            // and is merely incomplete.
            return signal.failureReason?.hasUsableOutput == true ? .ready : .failed

        case .notification:
            switch signal.notificationKind {
            case .permissionPrompt, .agentNeedsInput, .elicitationDialog:
                return .awaiting

            case .agentCompleted:
                return .ready

            // `idle_prompt` is an inactivity timer, not an answer: it reports that
            // the session has been quiet for a while, which the traffic light
            // already knows. Mapping it to green invented answers that never arrived.
            case .idlePrompt:
                return nil

            case .none:
                return nil
            }

        case .sessionEnd:
            return nil

        // Handled earlier by `applySubagent`: they never reach this point.
        case .subagentStart, .subagentStop:
            return nil
        }
    }

    /// Some events do not move the state of an existing row, but they do reveal
    /// the existence of a session the app had not yet seen — typically because it
    /// was started mid-session.
    ///
    /// This applies only to the inactivity timer, which *proves* a session is idle.
    /// Context compaction, by contrast, creates nothing: inventing an `idle` row
    /// for a session that is demonstrably working would be exactly the lie this
    /// correction removes.
    private static func discovering(
        signal: HookSignal,
        workspace: Workspace,
        in state: TrafficLightState,
        now: Date
    ) -> TrafficLightState {
        guard state.sessions[signal.sessionId] == nil,
              signal.notificationKind == .idlePrompt
        else {
            return state
        }

        return state.upserting(
            SessionState(
                id: signal.sessionId,
                status: .idle,
                workspace: workspace,
                updatedAt: now,
                statusSince: now
            )
        )
    }

    /// Protects the "unread" states from signals that would downgrade them.
    ///
    /// The real case: after `Stop` (green), a `PostToolUse` from the turn that just
    /// closed can arrive late. Without this rule the light would go back to yellow
    /// and the waiting answer would go unnoticed.
    private static func shouldKeep(
        current: SessionStatus,
        over incoming: SessionStatus,
        event: HookEventKind
    ) -> Bool {
        // `failed` needs the same protection as `ready` and `awaiting`, but for a
        // different reason, and that is why it isn't in `blocksDowngrade`.
        //
        // That flag answers the question "does this state survive a restart?", and
        // for `failed` the answer is no: if the turn really does resume, yellow is
        // the correct information and red is a leftover. But a late `PostToolUse`
        // **is not a restart** — it is the tail of the turn that just got cut down,
        // the same phenomenon this rule exists to neutralize on `ready`. Without
        // this addition, a trailing signal erased the cause of the error and
        // painted a session yellow when it wasn't working at all.
        let resists = current.blocksDowngrade || current == .failed
        guard resists, incoming == .working else { return false }

        // A new user prompt, on the other hand, is a legitimate transition:
        // it means they read it and started again.
        return event != .userPromptSubmit
    }

    /// Reduces the message to a one-line preview for the tooltip.
    private static func preview(of message: String?) -> String? {
        guard let message = message?.trimmed, !message.isEmpty else { return nil }
        let singleLine = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        let limit = 140
        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit)) + "…"
    }
}
