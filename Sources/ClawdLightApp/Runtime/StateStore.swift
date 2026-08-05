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
        // Nothing changes about the behaviour. What changes is that the log now
        // names the workspace nobody claimed, so the next hour of this goes into
        // reading one line instead of bisecting the app.
        if workspace == nil {
            Diagnostics.log(
                "signal dropped: \(signal.event.rawValue) for \(signal.cwd) — "
                    + "no editor window claims that folder "
                    + "(a window that has not reconnected writes no lock)"
            )
        }

        apply(.signal(signal, workspace: workspace), now: now)
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
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// One realignment pass.
    func poll() {
        let now = clock()
        let live = liveSessionReader.readLiveSessions().filter(\.deservesTrafficLight)
        let windows = windowReader.readWindows()

        apply(.reconcile(alive: Set(live.map(\.sessionId))), now: now)

        for session in live {
            guard let workspace = WorkspaceResolver.resolve(
                cwd: session.cwd, in: windows, at: now
            ) else {
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
        apply(.prune(alive: Set(live.map(\.sessionId))), now: now)
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
