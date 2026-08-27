import ClawdLightCore
import Combine
import Foundation

/// The interface's source of truth.
///
/// Holds the state as an immutable value and replaces it on every action by going
/// through the reducer. All mutations happen on the main actor, so views can never
/// observe a state that is halfway through an update.
@MainActor
final class StateStore: ObservableObject {

    @Published private(set) var state: TrafficLightState = .empty

    /// Last diagnostic error, shown in the context menu.
    @Published private(set) var lastError: String?

    private let windowReader: IDEWindowReader
    private let liveSessionReader: LiveSessionReader
    private let clock: () -> Date
    private let snapshots: SnapshotBox?
    private let preferences: Preferences
    private var pollTimer: Timer?
    private var remoteTimer: Timer?

    init(
        windowReader: IDEWindowReader = IDEWindowReader(),
        liveSessionReader: LiveSessionReader = LiveSessionReader(),
        clock: @escaping () -> Date = Date.init,
        snapshots: SnapshotBox? = nil,
        preferences: Preferences = Preferences()
    ) {
        self.windowReader = windowReader
        self.liveSessionReader = liveSessionReader
        self.clock = clock
        self.snapshots = snapshots
        self.preferences = preferences
    }

    // MARK: - Other machines

    /// The last answer each remote host gave, kept between polls. A host with no
    /// entry has never answered since it was configured.
    ///
    /// Kept, and not re-read on every local pass, for two reasons. The local poll
    /// runs every few seconds and an ssh handshake does not belong on that
    /// cadence; and `reconcile` filters the column down to the sessions it is
    /// handed, so a remote row must be in that set on **every** pass or it would
    /// be erased four times a minute between remote reads.
    ///
    /// A host that fails to answer keeps its previous entry. Silence is not death
    /// — the same rule that stopped this app pruning live local sessions.
    private var remoteSessions: [String: [LiveSession]] = [:]

    /// The hosts to ask, as configured in the settings.
    private var remoteHosts: [String] { preferences.remoteHosts }

    /// Every remote session currently believed to exist.
    private var knownRemote: [LiveSession] {
        remoteSessions.values.flatMap { $0 }
    }

    /// Asks each configured host, on its own slow timer.
    func pollRemoteHosts() {
        let hosts = remoteHosts

        // A host removed from the settings takes its answers with it, so its rows
        // stop being confirmed and go on the next pass rather than lingering.
        for gone in remoteSessions.keys where !hosts.contains(gone) {
            remoteSessions.removeValue(forKey: gone)
        }

        guard !hosts.isEmpty else {
            poll()
            return
        }

        for host in hosts {
            guard let answer = RemoteSessionReader(host: host).readLiveSessions() else {
                // No answer. Keep what we had and say so once.
                Diagnostics.log("remote \(host): no answer, keeping \(remoteSessions[host]?.count ?? 0) known rows")
                continue
            }
            let usable = answer.filter(\.deservesTrafficLight)
            if usable.count != (remoteSessions[host]?.count ?? -1) {
                Diagnostics.log("remote \(host): \(usable.count) sessions")
            }
            remoteSessions[host] = usable
        }
        poll()
    }

    var sessions: [SessionState] { state.ordered }

    // MARK: - Signal intake

    /// Applies a hook signal, first resolving the workspace hosting it.
    func handle(_ signal: HookSignal) {
        let now = clock()
        let workspace: Workspace?
        if let host = signal.host {
            // Through the tunnel. No lock on this machine can claim a folder that
            // lives on another one, so the session's own folder is the workspace,
            // and the host travels with it — that is what the click will raise.
            workspace = Workspace(path: signal.cwd, host: host)
        } else {
            workspace = WorkspaceResolver.resolve(
                cwd: signal.cwd,
                in: windowReader.readWindows(),
                at: now
            )
        }

        // A signal whose `cwd` matches no editor window is discarded — there is no
        // row to put it on. That is correct, and it used to be **silent**, which is
        // not.
        //
        // The case that showed why: after restarting the Mac, a VS Code window has
        // no lock file until its Claude panel reconnects. Every hook from that
        // window is dropped in the meantime, so a turn finishes and the light never
        // goes green — with nothing anywhere saying why. From the outside it looks
        // exactly like the traffic light being broken.
        //
        // Nothing changes about the behavior. What changes is that the log now
        // names the workspace nobody claimed, so the next hour of this goes into
        // reading one line instead of bisecting the app.
        if workspace == nil {
            Diagnostics.log(
                "signal dropped: \(signal.event.rawValue) for \(signal.cwd) — "
                    + "no editor window claims that folder "
                    + "(a window that has not reconnected writes no lock)"
            )
        }

        let before = state.sessions[signal.sessionId]?.status.rawValue ?? "absent"
        apply(.signal(signal, workspace: workspace), now: now)
        let after = state.sessions[signal.sessionId]?.status.rawValue ?? "absent"

        // Every signal, and what it did to the color.
        //
        // This is the instrument the project spent three separate evenings without.
        // "The light is wrong" could only be answered by reasoning about which of
        // eight events might have arrived in what order — and reasoning is exactly
        // what produced the wrong answers, twice. One line per hook turns that into
        // reading.
        //
        // It names the **transition**, not the payload: the question is always
        // "what turned it that color", never "what were the bytes".
        let subagent = signal.isFromSubagent ? " [subagent]" : ""
        let source = signal.sessionSource.map { " source=\($0)" } ?? ""
        let kind = signal.notificationKind.map { "/\($0.rawValue)" } ?? ""
        // A `Stop` that leaves a row yellow is only readable if the line says what
        // held it. The count was not enough: one session sat yellow for a day with
        // no background shell ever launched, and the log could only say "something".
        let types = signal.inFlightBackgroundTaskTypes
        let inFlight = types.isEmpty ? "" : " inFlight=\(types.count)[\(types.joined(separator: ","))]"
        let origin = signal.host.map { " host=\($0)" } ?? ""
        Diagnostics.log(
            "signal \(signal.event.rawValue)\(kind) "
                + "session=\(signal.sessionId.prefix(8)) "
                + "\(before) -> \(after)\(subagent)\(source)\(inFlight)\(origin)"
        )
    }

    /// The user opened the session: the unread states are cleared.
    func markSeen(sessionId: String) {
        apply(.markSeen(sessionId: sessionId), now: clock())
    }

    /// Remedy for one click too many: the row goes back to "there is something to read".
    func markUnread(sessionId: String) {
        apply(.markUnread(sessionId: sessionId), now: clock())
    }

    func reset() {
        apply(.reset, now: clock())
    }

    func reportError(_ message: String) {
        lastError = message
    }

    /// Clears the last error after a successful operation, so the menu doesn't
    /// keep showing a fault that has already gone away.
    func clearError() {
        guard lastError != nil else { return }
        lastError = nil
    }

    // MARK: - Periodic realignment

    /// Starts the periodic realignment against the live Claude Code processes.
    ///
    /// It does two things the hooks cannot, because they only report what happens
    /// and never what disappeared or what was already there: it removes the rows
    /// whose process has died, and it adopts the sessions opened before the app
    /// started — which would otherwise stay invisible until you did something in
    /// that window.
    func startPolling(every interval: TimeInterval = AppConfig.liveSessionPollInterval) {
        pollTimer?.invalidate()
        poll()

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        startRemotePolling()
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        remoteTimer?.invalidate()
        remoteTimer = nil
    }

    /// Asks the other machines on their own, much slower timer.
    ///
    /// Separate from the local one because each host costs a process spawn and an
    /// ssh handshake: putting that on the local cadence would mean an ssh every
    /// five seconds for a column that changes far less often than that.
    private func startRemotePolling(
        every interval: TimeInterval = AppConfig.remotePollInterval
    ) {
        remoteTimer?.invalidate()
        // Off the first pass: the app has to show the local column immediately,
        // and an unreachable host must never be what delays it.
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task.detached { [weak self] in
                guard let self else { return }
                await self.pollRemoteHosts()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        remoteTimer = timer
    }

    /// One realignment pass.
    func poll() {
        let now = clock()
        let live = liveSessionReader.readLiveSessions().filter(\.deservesTrafficLight)
        let windows = windowReader.readWindows()

        // Remote rows are **confirmed** here, never created. A session on another
        // machine gets its row when it speaks — its hooks reach this machine
        // through the tunnel — and loses it when that machine's probe no longer
        // lists its pid. The first version adopted every session the probe found
        // as a red row, and that produced a column of things nobody had opened
        // and nothing could open: a `claude` left in a detached tmux for two days
        // is real, and it is not a window you can click.
        //
        // `reconcile` keeps only what it is handed, so every remote row that must
        // survive has to be in the set: the ones the probe confirmed, and the ones
        // on a configured host that has not answered yet — silence is not death.
        // A row on a host no longer configured is in neither and goes.
        let configured = Set(remoteHosts)
        let unconfirmed = state.sessions.values.compactMap { session -> String? in
            guard let host = session.workspace.host,
                  configured.contains(host), remoteSessions[host] == nil
            else { return nil }
            return session.id
        }
        let alive = Set(live.map(\.sessionId))
            .union(knownRemote.map(\.sessionId))
            .union(unconfirmed)
        apply(.reconcile(alive: alive), now: now)

        for session in live {
            guard let workspace = WorkspaceResolver.resolve(cwd: session.cwd, in: windows, at: now) else {
                continue
            }
            // State `idle`: the app does not know what a session it has never seen
            // is doing, and this is where it says so.
            //
            // It was briefly inferred instead — "the transcript moved in the last
            // forty-five seconds, therefore a turn is in flight" — and that was
            // wrong in a way worth recording. A transcript is appended on plenty of
            // things that are not a turn, **resuming a session among them**. So
            // after a reboot, when Claude Code resumes everything at once, every
            // file moved at once and the whole column went yellow: twelve sessions
            // claiming to be working while none of them were.
            //
            // A column that is uniformly wrong is worse than one that is
            // uniformly cautious, because the panel exists to make the one session
            // that needs you stand out. `idle` here is not a guess dressed up as a
            // fact; it is the absence of information, and the first hook replaces it.
            //
            // The timestamp, by contrast, IS evidence and is kept: it comes from
            // the transcript, which is the only file that moves when a session
            // does something.
            apply(
                .adopt(
                    SessionState(
                        id: session.sessionId,
                        status: .idle,
                        workspace: workspace,
                        updatedAt: session.modifiedAt,
                        statusSince: session.modifiedAt
                    )
                ),
                now: now
            )
        }

        // The same set `reconcile` used. Without it, pruning removes sessions we
        // have just proved are running.
        apply(.prune(alive: alive), now: now)
    }

    // MARK: - Internal

    private func apply(_ action: ReducerAction, now: Date) {
        let next = StateReducer.reduce(state, action: action, now: now)
        guard next != state else { return }
        givePlaces(to: next)
        state = next
        publishSnapshot()
    }

    /// Every project in the state gets a place in the column's order, **before**
    /// the state is published: the first render that shows a project already
    /// knows where it goes, and a known project never moves (D23).
    ///
    /// Here and not in the panel, because the panel is one reader of the order
    /// among three — the extended window and `/sessions` are the others — and
    /// headless mode has no panel at all. An order that only the panel maintains
    /// is an order the CLI disagrees with.
    private func givePlaces(to next: TrafficLightState) {
        let order = preferences.rowOrder
        let merged = RowOrder.absorbing(next.sessions.values.map(\.workspace.path), into: order)
        if merged != order { preferences.rowOrder = merged }
    }

    /// Deposits the version readable by the HTTP server into the box.
    ///
    /// The slot and the mute flag are read from the preferences here rather than
    /// carried in `SessionState`: they are things the **user** decided about a
    /// project, not things Claude Code reported about a session, and the domain
    /// state has no business holding them.
    private func publishSnapshot() {
        guard let snapshots else { return }
        let order = preferences.rowOrder
        let muted = preferences.mutedWorkspaces

        snapshots.replace(with: state.ordered.map { session in
            SessionsCodec.snapshot(
                of: session,
                muted: muted.contains(session.workspace.path),
                slot: RowOrder.slot(of: session.workspace.path, in: order, limit: AppConfig.maxSlots)
            )
        })
    }
}
