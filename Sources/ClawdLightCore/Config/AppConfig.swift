import Foundation

/// Application configuration constants.
/// No hardcoded values scattered through the code: everything goes through here.
public enum AppConfig {
    // MARK: - Transport

    /// Listening interface. Loopback only: the server must never be reachable from the network.
    public static let listenHost = "127.0.0.1"

    /// Default port of the local HTTP server.
    public static let listenPort: UInt16 = 9877

    /// HTTP path where the Claude Code hooks post their signals.
    public static let signalPath = "/signal"

    /// Answers 200 and nothing else: the cheapest way to ask "is a panel there?".
    /// Named here because the self-test asks it too, and a route spelled out in
    /// two files drifts in one of them.
    public static let healthPath = "/health"

    /// HTTP path returning the column state as JSON. Requires the token.
    public static let sessionsPath = "/sessions"

    /// HTTP path that raises the window of the next awaiting session.
    /// Requires the token: it raises windows, it doesn't just color dots.
    public static let nextPath = "/next"

    /// HTTP path that raises the window in a given slot. The slot number is the
    /// request body. Requires the token, for the same reason as `/next`.
    public static let openPath = "/open"

    /// HTTP path that opens a new conversation in a given slot's project.
    /// Same shape as `/open`, same authentication.
    public static let newConversationPath = "/new"

    /// HTTP path that opens a slot's conversation in a chat window, without
    /// touching the editor. Same shape as `/open`, same authentication.
    public static let chatPath = "/chat"

    /// How many slots a key can address.
    ///
    /// Nine because that is how many number keys a modifier can reach without
    /// reaching, and because a set of shortcuts you have to think about is a set
    /// you stop using. The Codex Micro settles on six physical keys for the same
    /// reason: the limit is what you can address without looking, not what fits.
    public static let maxSlots = 9

    /// Maximum accepted size for an HTTP body (256 KB).
    /// `Stop` carries `last_assistant_message`, which can be long.
    public static let maxRequestBodyBytes = 256 * 1024

    // MARK: - Filesystem

    /// Name of the environment variable that relocates every path the app uses.
    public static let homeOverrideVariable = "CLAWD_LIGHT_HOME"

    /// Root from which every path the app reads and writes descends.
    ///
    /// Normally the user's home directory. `CLAWD_LIGHT_HOME` moves it elsewhere,
    /// and it exists for exactly one reason: to run the end-to-end tests against
    /// a fake home.
    ///
    /// Without this escape hatch an honest e2e test would be impossible — either
    /// it touches the user's real `~/.claude/settings.json`, or it bypasses the
    /// production code path and verifies something other than what actually ships.
    /// That is precisely the mistake that left title matching broken for an entire
    /// session with ten green tests.
    ///
    /// `homeDirectoryForCurrentUser` comes from `getpwuid` and ignores `$HOME`:
    /// rewriting `$HOME` would not be enough, and relying on it would give the
    /// illusion of an isolation that isn't there.
    public static var homeDirectory: URL {
        if let override = ProcessInfo.processInfo.environment[homeOverrideVariable],
           !override.trimmed.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// `true` when the app is running against a fake home.
    /// Guards against a test accidentally touching real system resources.
    public static var isUsingHomeOverride: Bool {
        ProcessInfo.processInfo.environment[homeOverrideVariable]?.trimmed.isEmpty == false
    }

    /// Directory where the Claude Code VS Code plugin drops one lock file per window.
    public static var ideLockDirectory: URL {
        homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("ide", isDirectory: true)
    }

    /// Directory where Claude Code drops one file per live process,
    /// named after the PID.
    public static var liveSessionsDirectory: URL {
        homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    /// How often the column is realigned against the live processes.
    /// Often enough that a row disappears right after you close a panel,
    /// rarely enough not to cost anything: one directory listing and one
    /// syscall per file.
    public static let liveSessionPollInterval: TimeInterval = 5

    /// How often an open chat window looks for new lines in its transcript.
    ///
    /// Faster than the column's realignment because you are reading it: a reply
    /// that lands five seconds late is a reply you watched not arrive. The cost is
    /// one `stat` per open window, and the reader returns immediately when the
    /// file hasn't grown.
    public static let transcriptPollInterval: TimeInterval = 1

    /// How many entries a chat window keeps in memory.
    ///
    /// A transcript reaches tens of thousands of lines and SwiftUI draws what it is
    /// given. This is the tail — the part of a conversation anybody scrolls back
    /// through — and the file stays the record of the rest.
    public static let chatHistoryLimit = 300

    /// How much of a transcript's tail a chat window reads when it opens.
    ///
    /// Enough for `chatHistoryLimit` entries several times over — a record with
    /// a big tool result runs to a hundred kilobytes — and small enough that a
    /// half-gigabyte transcript opens in the time a small one does. The head is
    /// read separately for the title.
    public static let transcriptInitialWindow = 8 * 1024 * 1024

    // MARK: - Waiting for a permission

    /// How often the app re-asks the system whether a permission has arrived.
    ///
    /// The check is a single function call, so the interval is set by how long a
    /// person is willing to look at an unchanged panel after flipping a switch —
    /// not by cost.
    public static let permissionWatchInterval: TimeInterval = 1.5

    /// How long that watch stays up before giving in.
    ///
    /// Long enough to find the pane, read the sentence and authenticate; short
    /// enough that walking away does not leave a timer running for the rest of
    /// the day. The click is not lost when it expires — it is simply made again.
    public static let permissionWatchWindow: TimeInterval = 180

    /// The app's support directory (panel position, preferences).
    public static var supportDirectory: URL {
        homeDirectory
            .appendingPathComponent(".clawd-light", isDirectory: true)
    }

    /// File holding the token for the read endpoint.
    /// Mode `0600`: its contents authorize reading workspace names.
    public static var tokenURL: URL {
        supportDirectory.appendingPathComponent("token")
    }

    /// Hook script installed at `~/.clawd-light/hook.sh` and referenced from `~/.claude/settings.json`.
    public static var hookScriptURL: URL {
        supportDirectory.appendingPathComponent("hook.sh")
    }

    /// Message listener installed at `~/.clawd-light/rewake.sh`.
    ///
    /// A separate file from `hook.sh`, and not an option inside it, because the
    /// two have opposite obligations: the traffic light hook must return in
    /// milliseconds or it delays every turn, and this one waits for minutes.
    public static var rewakeScriptURL: URL {
        supportDirectory.appendingPathComponent("rewake.sh")
    }

    /// Claude Code's global configuration file, where the hooks are registered.
    public static var claudeSettingsURL: URL {
        homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    /// Presence file read by Claude Code to suppress phone push notifications
    /// while you are sitting at the Mac (`CLAUDE_CLIENT_PRESENCE_FILE`).
    public static var presenceFileURL: URL {
        supportDirectory.appendingPathComponent("presence")
    }

    // MARK: - State semantics

    /// Entrypoints of sessions nobody is watching.
    ///
    /// This is a list of **exclusions**, not of admissions, and that difference is
    /// the whole correction: an allow-list has to be updated for every new Claude
    /// Code entrypoint, and until it is, those sessions are invisible. A deny-list,
    /// when it is wrong, shows one row too many — a mistake you can see and fix,
    /// rather than one that stays silent.
    ///
    /// `sdk` and `print` are non-interactive sessions: they run inside scripts and
    /// finish without anyone needing to answer.
    ///
    /// `sdk-cli` was added after a contract probe: it is what `claude -p` really
    /// reports, and the list had been written from the documentation rather than
    /// from an observation. It is exactly the failure the deny-list shape is meant
    /// to survive — the gap showed one row too many instead of hiding one — but a
    /// gap it was. See `Contracts/assumptions.md`, entry `entrypoint.values`.
    public static let nonInteractiveEntrypoints: Set<String> = [
        "sdk", "sdk-cli", "sdk-ts", "sdk-py", "print",
    ]

    // MARK: - Background work

    /// Entries of `background_tasks` that are **not** work the user is waiting on.
    ///
    /// Claude Code's own "active tasks" view starts from the very predicate that
    /// builds the hook payload and then removes exactly these two types — read in
    /// the binary: `.filter(bL).filter(t => t.type !== "remote_agent" && t.type
    /// !== "dream")`. `dream` is its background memory consolidation: it runs on
    /// an idle session, writes nothing to the transcript, and never wakes the
    /// session when it ends. Counting it as work held a row yellow for a day
    /// after the answer had been sitting there since one second after `Stop`.
    ///
    /// The payload carries display names, not registry names: `remote_agent` is
    /// written as `cloud session`.
    public static let backgroundTaskTypesThatAreNotWork: Set<String> = ["dream", "cloud session"]

    // MARK: - Remote hosts

    /// Hosts to read sessions from, one name per line, `#` for comments.
    ///
    /// A file and not a compiled list: the machines a person works across are
    /// theirs, not ours. Absent or empty means the feature is off, which is the
    /// default — reading another machine is an outbound connection, and this
    /// project does not start those unless asked.
    public static var remoteHostsFile: URL {
        homeDirectory.appendingPathComponent(".clawd-light/remotes")
    }

    /// How long to give ssh before giving up on a host.
    ///
    /// Short on purpose. A node that is asleep must cost one poll, not a stall:
    /// the column has to keep telling the truth about this machine even when the
    /// other one is unreachable.
    public static let remoteProbeTimeout: TimeInterval = 5

    /// Header a hook adds when it runs on another machine and reaches this one
    /// through the tunnel: the name the host was configured under. Without it a
    /// signal from the node would be indistinguishable from a local one, and its
    /// `cwd` would be looked up among local editor windows that cannot claim it.
    public static let remoteHostHeader = "X-Clawd-Host"

    /// Backoff for a tunnel that exits: the first retry after this many seconds…
    public static let remoteTunnelRetryMin: TimeInterval = 5
    /// …doubling up to this.
    public static let remoteTunnelRetryMax: TimeInterval = 60

    /// Where the hook script goes on a remote machine, relative to its home.
    public static let remoteHookScriptRelativePath = ".clawd-light/hook.sh"
    /// The far end of the tunnel on a remote machine: a loopback port **derived
    /// from the user's uid**, so two accounts on one machine never share it.
    ///
    /// A Unix socket in the user's home was tried first — owner-only by
    /// construction, immune to `GatewayPorts`. It failed on measurement: the
    /// machine at hand runs Tailscale SSH, whose daemon does the forwarding as
    /// root and created the socket `root:root 0600`, which the user cannot open.
    /// A port it is, then — verified after every connect to be bound to loopback
    /// and to nothing else (`RemoteInstallScripts.checkTunnel`).
    public static func remotePort(forUID uid: Int) -> UInt16 {
        UInt16(30_000 + max(uid, 0) % 20_000)
    }
    /// Claude Code's settings on a remote machine, relative to its home.
    public static let remoteClaudeSettingsRelativePath = ".claude/settings.json"

    /// How often the remote hosts are asked. Far slower than the local poll,
    /// because each one is a process spawn and an ssh handshake.
    public static let remotePollInterval: TimeInterval = 20

    /// Value of the `kind` field marking a session with a user in front of it.
    /// Present in the files under `~/.claude/sessions/`.
    public static let interactiveSessionKind = "interactive"

    /// A lock file older than this interval is considered orphaned.
    /// Locks are not always removed when the window closes.
    public static let ideLockMaxAge: TimeInterval = 60 * 60 * 24 * 7

    /// A session with no signals for longer than this interval is dropped from the column.
    public static let sessionStaleAfter: TimeInterval = 60 * 60 * 12

    // MARK: - Interface

    /// Maximum number of traffic lights shown at once before scrolling.
    public static let maxVisibleRows = 12

    /// Blink period for the "awaiting permission" state, in seconds.
    public static let blinkPeriod: TimeInterval = 0.7


    // MARK: - Presence and attention

    /// How many seconds without touching keyboard or mouse before you stop
    /// counting as being at the Mac.
    ///
    /// Two minutes: long enough to cover a read or a short phone call, short
    /// enough not to keep push notifications suppressed while you're elsewhere.
    public static let presenceIdleThreshold: TimeInterval = 120

    /// How often user presence is re-evaluated.
    public static let presencePollInterval: TimeInterval = 20
}
