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

    /// The last answer each remote host gave, kept between polls.
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

    /// Every remote session currently believed to exist.
    private var knownRemote: [LiveSession] {
        remoteSessions.values.flatMap { $0 }
    }

    /// Asks each configured host, on its own slow timer.
    func pollRemoteHosts() {
        let hosts = RemoteHostList.parse(
            (try? String(contentsOf: AppConfig.remoteHostsFile, encoding: .utf8)) ?? ""
        )
        guard !hosts.isEmpty else {
            guard !remoteSessions.isEmpty else { return }
            // The file was emptied: let the rows go rather than stranding them.
            remoteSessions = [:]
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
        let workspace = WorkspaceResolver.resolve(
            cwd: signal.cwd,
            in: windowReader.readWindows(),
            at: now
        )

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
        Diagnostics.log(
            "signal \(signal.event.rawValue)\(kind) "
                + "session=\(signal.sessionId.prefix(8)) "
                + "\(before) -> \(after)\(subagent)\(source)"
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
        let remote = knownRemote

        // Both sets, always. `reconcile` keeps only what it is handed, so leaving
        // the remote ids out would erase those rows on the very next pass.
        let alive = Set(live.map(\.sessionId)).union(remote.map(\.sessionId))
        apply(.reconcile(alive: alive), now: now)

        for session in live + remote {
            guard let workspace = workspace(for: session, in: windows, at: now) else {
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

    /// Where a session is running, for the column's purposes.
    ///
    /// Locally the answer has to come from an editor window: a `cwd` nobody has
    /// open is a session in a terminal somewhere, and the panel is about windows
    /// you can click. Remotely there is no window to ask about — the session lives
    /// in a tmux pane on a headless machine — so **the folder is the workspace**.
    ///
    /// Applying the local rule to a remote session is exactly what kept those rows
    /// invisible: no lock on this machine claims `/home/…`, so every one of them
    /// was dropped with "no editor window claims that folder".
    private func workspace(
        for session: LiveSession, in windows: [IDEWindow], at now: Date
    ) -> Workspace? {
        guard let host = session.host else {
            return WorkspaceResolver.resolve(cwd: session.cwd, in: windows, at: now)
        }
        return Workspace(path: session.cwd, host: host)
    }

    // MARK: - Internal

    private func apply(_ action: ReducerAction, now: Date) {
        let next = StateReducer.reduce(state, action: action, now: now)
        guard next != state else { return }
        state = next
        publishSnapshot()
    }

    /// Deposits the version readable by the HTTP server into the box.
    ///
    /// The slot and the mute flag are read from the preferences here rather than
    /// carried in `SessionState`: they are things the **user** decided about a
    /// project, not things Claude Code reported about a session, and the domain
    /// state has no business holding them.
    private func publishSnapshot() {
        guard let snapshots else { return }
        let pinned = preferences.pinnedWorkspaces
        let muted = preferences.mutedWorkspaces

        snapshots.replace(with: state.ordered.map { session in
            SessionsCodec.snapshot(
                of: session,
                muted: muted.contains(session.workspace.path),
                slot: SlotAssignment.slot(of: session.workspace.path, in: pinned)
            )
        })
    }
}
