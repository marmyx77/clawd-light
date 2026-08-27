# Terminal sessions — review of the plan (2026-08-27)

Adversarial review of `terminal-sessions.md`, first version: three lenses (architectural fit,
platform facts, gaps) followed by one refuter per finding. 37 findings; 21 judged — 8 confirmed,
13 refuted; 16 refuters did not run (spend limit) and their findings are listed as **unjudged**,
each with the author's own verification where one was possible. The plan was revised from this list.

## Confirmed

### [blocking] No stored fact says "this row is a terminal row" — label, glyph, menu and click policy all need one

*Where:* Plan §1 (Label), §2 (SessionState / ColumnRow.displayName / TrafficLightRow / PanelController.activate); Sources/ClawdLightCore/Models/Workspace.swift:9-30; Sources/ClawdLightCore/Models/SessionState.swift:8-56

Four plan features branch on whether a row is a terminal row: "A row holding **one** terminal session with a known conversation title is labelled by that title" (§1), "A small terminal glyph precedes the name" (§1), "'New conversation here' hidden for terminal rows" (§2), and the click path (§2). Nothing in the state carries that fact. `Workspace` has only `path` and `host` (Workspace.swift:11-19); `SessionState` has no origin field (SessionState.swift:8-56); `ColumnLayout.render` is pure and sees no windows (ColumnLayout.swift:177-180); and the plan says `Seat` is computed "at click time only; nothing is cached" (§2), so it cannot drive the label either. `entrypoint == "cli"` is not a proxy: §1 keeps a `cli` session inside an open folder attributed to the editor window ("however it was started"), and the E2E at CoverageSuite.swift:20-33 encodes that; for such a session 'New conversation here' is meaningful and the label should stay the folder. The plan's claim that "what is new is *who* produces the workspace (StateStore), not the state machine" (§2) is therefore false: the state must record that the workspace was the cwd fallback, exactly as `Workspace.host` records the remote case (Workspace.swift:13-19, "Part of the identity, not decoration").

**Fix:** Add an explicit origin to the domain state, set by `StateStore` when it produces `Workspace(path: cwd)`: either `Workspace.kind: .editor | .terminal` (mirroring `host`) or `SessionState.origin`. Define it in §2 under Core, make `ColumnRow.displayName`, the glyph, the menu and `PanelController.activate` read it, and note that `ColumnLayout.group` keys on `workspace.path` (ColumnLayout.swift:207-210) so a terminal row and an editor row on the same path still merge. Then `SeatResolver` runs only for rows whose origin is terminal.

### [important] §1 and §2 disagree about the click on a Terminal.app-hosted `cli` session inside an open folder

*Where:* Plan §1 "What changes for everyone" vs §2 "PanelController.activate"; Sources/ClawdLightApp/Focus/VSCodeFocuser.swift:106-110

§1: "For a `cli` session in an editor window the click raises the window and stops there." §2: "`PanelController.activate`: local session → `SeatResolver`; `.editor` → today's path …; a terminal seat → `TerminalFocuser`". By §0's own chain table, `claude` started in a Terminal.app tab whose cwd is inside an open VS Code folder classifies as `.terminal(Terminal, tty:)`, so §2 raises the Terminal tab while §1 raises the VS Code window. §5 ("VS Code's integrated terminal stays a window-level target") covers only the integrated-terminal chain, not this one. A second ambiguity: today the editor is chosen from the locks at click time (`VSCodeFocuser.kind(hosting:)`, VSCodeFocuser.swift:106-110), while `Seat.editor(IDEKind)` would come from the process tree; a `cli` session in Cursor's terminal with the folder also open in VS Code gets two different answers and the plan does not say which wins.

**Fix:** Pick one rule and write it in D25. Recommended: the row's origin (finding 1) decides — editor-attributed rows take today's path unchanged (no process walk, no second source for the IDE kind); terminal rows go through `SeatResolver`. If instead "seat always wins" is intended, rewrite §1 and §5 accordingly and state that the process-tree IDE kind overrides the lock-derived one.

### [important] `procStart` on macOS is a date string, not clock ticks, and `LiveSession` does not read it

*Where:* Plan §2 (ProcessTree, "Pid reuse guard"), §5 ("Pid reuse"); Sources/ClawdLightCore/Workspace/LiveSession.swift:9-35, 119-127; Contracts/assumptions.md:591-597

The plan says the guard compares "the session file's `procStart` against `p_starttime`, the same idea as the remote probe's field 22". Measured on this machine, every session file carries `procStart` as a ctime-style local string (`'Wed Aug 26 17:07:24 2026'`), with second resolution and no zone; the Contracts entry `remote.sessions` (assumptions.md:595-597) describes clock ticks, which is the Linux representation the probe compares as a string. On macOS `kinfo_proc.kp_proc.p_starttime` is a `timeval`, so the guard needs a parser and a tolerance, and that is a domain decision that belongs in Core under test — the plan lists no such piece. Moreover `LiveSession` has no `procStart` field and `LiveSessionParser.parse` never reads it (LiveSession.swift:119-127), while the plan's Core list adds nothing to `LiveSession`; `SeatResolver` ("session id → pid (`LiveSessionReader`)") also has no by-id lookup to call (LiveSessionReader.swift:25-38) and `PanelController` holds no reader (PanelController.swift:13-16).

**Fix:** Add to §2 Core: `LiveSession.procStart: String?` parsed by `LiveSessionParser`, and a pure `ProcStartMatcher.matches(fileValue:, startTime:)` parsing `EEE MMM d HH:mm:ss yyyy` in the local zone with ±1 s tolerance, tested with fixtures. Add a Contracts entry `sessions.file.procStart` recording the macOS format next to the Linux one. State how `SeatResolver` obtains a `LiveSession` for a session id (inject a reader into `PanelController`, or have `StateStore` expose it).

### [important] The unknown-host branch would now mint a local row for a foreign path

*Where:* Plan §2 (StateStore.handle rule); Sources/ClawdLightApp/Runtime/StateStore.swift:154-165, 322-323; Sources/ClawdLightE2E/CoverageSuite.swift:94-98

A signal whose `X-Clawd-Host` names a host the app was not told about is "treated as local" and reaches the resolver (StateStore.swift:155-165), which drops it today; the E2E asserts "unknown host, no row" (CoverageSuite.swift:94-98) and D24 calls that header "a header anyone on loopback could have written". The plan's rule — "resolver returns `nil`, toggle on, `signal.deservesTrafficLight` → `Workspace(path: cwd)`" — does not require `signal.host == nil`, so with the toggle on the forged signal gets a local row for `/home/…` until the next `reconcile` erases it because no local pid confirms it (StateStore.swift:322-323): a five-second phantom row, and a regression of an E2E the plan does not list.

**Fix:** Add `signal.host == nil` to the fallback condition in §2, and add to Phase B's E2E list: `terminal on`, hook with unknown host → still absent.

### [important] The label rule is scoped to `ColumnRow.displayName`, but fifteen surfaces read `workspace.name`/`label`, including the notification title

*Where:* Plan §2 ("`ColumnRow.displayName` implements the label rule"), §5 "Home-folder rows"; Sources/ClawdLightApp/Runtime/SessionNotifier.swift:156; Sources/ClawdLightApp/UI/PanelController.swift:83,364,379,396,403; Sources/ClawdLightApp/UI/TrafficLightRow.swift:79,261; Sources/ClawdLightApp/UI/TrafficLightColumn.swift:245

The plan's reason for the title is that "the folder name of `~` is a username and says nothing" (§1), yet it places the rule in one computed property. `content.title = session.workspace.name` (SessionNotifier.swift:156) would notify "marcoarmellino" for every home-folder terminal session; `open <n>`/`next` answer with `row.workspace.name` (PanelController.swift:83, 364, 379), `slotAssignments` lists it (403), the tooltip uses `label` (TrafficLightRow.swift:261), the hidden summary uses `HiddenSummary.workspaceNames` (ColumnLayout.swift:282; TrafficLightColumn.swift:245), the roster header uses `name` (ChatShellView.swift:137). Meanwhile `Workspace.name` must stay the folder because it is the key matched against window titles (Workspace.swift:32-36). Two engineers would pick different subsets.

**Fix:** Enumerate in §2 which surfaces show the display name (row, tooltip, `open`/`next` answers, notification title, hidden summary) and which must keep `workspace.name` (window matching, `/sessions.workspace`). Put the rule on `SessionState`/`ColumnRow` in Core and route every listed App site through it; add the notification case to Phase B's tests.

### [important] No reducer action can attach a title to an existing session

*Where:* Plan §2 ("`SessionTitleReader` — reads the title once on adoption or first hook, again on `Stop`"), Phase A ("reducer keeps the entrypoint across transitions"); Sources/ClawdLightCore/Reducer/StateReducer.swift:4-32, 57-59, 86-94, 146-152, 189-196, 326-331

`ReducerAction` has `.signal`, `.adopt`, `.markSeen`, `.markUnread`, `.prune`, `.reconcile`, `.reset` (StateReducer.swift:4-32). `.adopt` refuses to overwrite a known session (57-59) and `.signal` carries only a `HookSignal`, which has no title. So a title learned "again on `Stop` while it is still unknown" has no path into the state, and `/sessions` cannot show it. Likewise `entrypoint`: the reducer constructs fresh `SessionState`s in three places (146-152, 189-196, 326-331) and rebuilds existing ones through `.with(...)`; the plan's Phase A test "reducer keeps the entrypoint across transitions" will be implemented three times unless it goes through the single `remembering(transcriptOf:)` hook (86-94) that exists for exactly this class of orthogonal fact.

**Fix:** Add to §2 Core: a `ReducerAction.remember(sessionId:, title:)` (or a general `.annotate`) handled like `remembering`, and extend `remembering` to carry `signal.entrypoint` alongside `transcriptPath`. Name these as the only two places the fields are written.

### [minor] `TranscriptTitleScanner`/`SessionTitleReader` duplicate a title extraction that already exists, with a different rule

*Where:* Plan §2 ("`TranscriptTitleScanner.title(in:)` — the first `ai-title` line within the first 512 KB"), Phase B tests ("first line wins"); Sources/ClawdLightCore/Transcript/TranscriptTail.swift:19-46; Sources/ClawdLightApp/UI/ChatView.swift:60

`TranscriptTail.consume` already extracts the title from any chunk (TranscriptTail.swift:38-43) and the chat header already renders `conversation.title ?? workspace.name` (ChatView.swift:60). The plan's scanner says "first line wins" while `TranscriptTail` keeps the last one seen (line 40-42), so the column and the chat window would read the same file under two rules. Measured on the 400 most recent transcripts: the `ai-title` record is repeated (909, 539, 17 and 2 times per file), always identical, first occurrence at most 119 KB in — so 512 KB is safe, and the two rules agree today only by accident.

**Fix:** Define `TranscriptTitleScanner.title(in:)` as `TranscriptTail().consume(headSlice).title` and adopt last-wins as the single documented rule; drop the "first line wins" test in favour of "repeated identical records yield one title".

### [minor] `FocusError`/`FocusResult` are VS Code-shaped; `automationDenied(app:)` is a change to an existing case, not a new one

*Where:* Plan §2 ("`TerminalFocuser` … returning the existing `FocusResult`. New `FocusError.automationDenied(app:)`"); Sources/ClawdLightApp/Focus/VSCodeFocuser.swift:10-31, 47-54, 71, 118-128, 364, 405

`FocusError.automationDenied` exists without payload (VSCodeFocuser.swift:16) with a message hard-wired to System Events (47-54) and is produced inside `runAppleScript` (405), so adding `app:` changes that mapping for the VS Code path too. `FocusResult` is nested in `VSCodeFocuser` (118-128); `FocusError` carries `.vsCodeNotRunning` (18) and an `activationFailed` text reading "Cannot bring VS Code to the front" (71); `windowTitles(of:)` is typed on `IDEKind` (364), which the kitty/zellij title fallback (§0 table) cannot call. Reusing these as written makes a terminal failure say "VS Code".

**Fix:** Say in §2 that `FocusResult`/`FocusError` move to a shared `Focus/FocusResult.swift`, that `automationDenied` gains `app: String` (defaulting to "System Events" at the existing call site), that `activationFailed`'s text becomes app-neutral, and that `windowTitles` takes a process name.

### [minor] §0 cites a README caveat that does not exist there; the trap named is a different, already-fixed bug

*Where:* Plan §0 ("README, *Two tabs instead of one*"), Phase A ("Docs: README caveat rewritten"); docs/07-traps.md:1201-1212; README.md:430-437; Sources/ClawdLightApp/Runtime/Preferences.swift:68-72

"Two tabs instead of one" is a heading in docs/07-traps.md:1201, and it describes 'New conversation here' opening two tabs — fixed by the `opensTab` parameter (PanelController.swift:287-290, 351). The fact the plan means — the deep link creates a new tab for integrated-terminal sessions — is recorded in `Preferences.opensSessionTab`'s comment (Preferences.swift:68-72), and README.md:430-437 ("It doesn't matter how you started the session") has no such caveat. Phase A's "README caveat rewritten" points at nothing.

**Fix:** Cite Preferences.swift `opensSessionTab` point 2 and D5 in §0; in Phase A, write the caveat into README's "It doesn't matter how you started" paragraph and update the `opensSessionTab` comment to say the link is now gated by entrypoint.

### [minor] "It leaves when the process is gone" does not hold for the last row in the column

*Where:* Plan §1 ("It leaves when the process is gone."); Sources/ClawdLightCore/Reducer/StateReducer.swift:53-55; Sources/ClawdLightApp/Runtime/StateStore.swift:296, 322-323; Sources/ClawdLightCore/Config/AppConfig.swift:255

`.reconcile(alive:)` ignores an empty set (StateReducer.swift:53-55) and `confirmed` is built from local live pids plus remote (StateStore.swift:322). A single terminal session in `~` that dies without `SessionEnd` (terminal window closed, `kill -9`) leaves an empty `alive` set, so its row stays until the twelve-hour prune (AppConfig.swift:255). Pre-existing for editor rows, but a lone home-folder terminal row is the common shape this feature adds.

**Fix:** Either state the limit in D25, or have `LiveSessionReader.readLiveSessions()` return `nil` on a failed directory read and `[]` on an honest empty read (the `RemoteSessionReader` distinction, RemoteSessionReader.swift:25-32) and let `poll()` reconcile to empty when the read succeeded.

### [minor] In-code statements that become false are not in the plan's documentation list

*Where:* Plan Phase B/F ("Docs: D25, 01-architecture, README, Contracts"); Sources/ClawdLightCore/Reducer/StateReducer.swift:5; Sources/ClawdLightCore/Workspace/WorkspaceResolver.swift:3-7; Sources/ClawdLightCore/Workspace/LiveSession.swift:16; Sources/ClawdLightCore/Models/HookSignal.swift:25-26

`ReducerAction.signal` is documented as "`nil` when it doesn't belong to VS Code" (StateReducer.swift:5); `WorkspaceResolver` says a session with no window "is running in a terminal and is ignored" (WorkspaceResolver.swift:5-7); `LiveSession.entrypoint` says "Used to exclude terminal sessions" (LiveSession.swift:16) and `HookSignal.entrypoint` "Used to discard sessions not hosted by VS Code" (HookSignal.swift:25-26). `check-docs.sh` checks figures and links, not these sentences, so they will survive Phase F as written.

**Fix:** Add these four comments to Phase B's documentation step.

### [important] `wezterm cli list --format json` has no `pid` field

*Where:* §0 "What each host exposes" table, WezTerm row; §3 phase E

The row says panes come with `tty_name`, `pid`, `tab_id`, `window_id`. `wezterm cli list --help` (20240203-110809) confirms `--format json`, and `strings` of `/Applications/WezTerm.app/Contents/MacOS/wezterm` contains the serialised struct field blob `window_id workspace cursor_shape cursor_visibility top_row tab_title window_title is_active is_zoomed` alongside `tty_name`, `pane_id`, `tab_id`, `cwd`, `cursor_x`, `cursor_y`, `left_col`; there is no `pid` field (the list item mirrors wezterm's `CliListResultItem`, which carries no process id). A live listing could not be taken: `wezterm cli --no-auto-start list --format json` fails with `failed to connect to Socket(~/.local/share/wezterm/sock)` because no wezterm is running. Also `tty_name` is the full `/dev/ttysNNN` path, whereas `devname()` yields `ttysNNN`.

**Fix:** Drop `pid` from the WezTerm row and from `WezTermListing`; match panes by `tty_name` only, comparing basenames. Pass `--no-auto-start` so a click never spawns a headless mux server from the menubar app.

### [important] kitty remote control from outside a kitty window needs `--to`, and `listen_on unix:/tmp/kitty` becomes `/tmp/kitty-<pid>`

*Where:* §0 kitty row; §3 phase E (`allow_remote_control socket-only`, `listen_on unix:/tmp/kitty`)

The plan names `kitten @ ls` and `kitten @ focus-window --match pid:<shell pid>` (both confirmed by `kitten @ ls --help` / `kitten @ focus-window --help`, kitty 0.48.2; `--match` fields include `pid`; `Window.as_dict` keys include `pid` and `foreground_processes`). But `kitten @ --help` states: "--to … If not specified, the environment variable KITTY_LISTEN_ON is checked. If that is also not found, messages are sent to the controlling terminal for this process, i.e. they will only work if this process is run within a kitty window." clawd-light is not inside a kitty window, so every `kitten @` call needs `--to`. And the bundled `listen_on` documentation (`kitty +runpy`, options definition) says: "If {kitty_pid} is present, then it is replaced by the PID of the kitty process, otherwise the PID of the kitty process is appended to the value, with a hyphen" — so the phase-E config `listen_on unix:/tmp/kitty` produces `/tmp/kitty-<pid>`, and `--to unix:/tmp/kitty` would not connect. `allow_remote_control socket-only` is a valid value (choices: password, socket-only, socket, no, yes).

**Fix:** Add `--to unix:<socket>` to both kitten calls. Derive the socket from the kitty ancestor's pid found in the process chain (`/tmp/kitty-<kittypid>` for the test config, or `{kitty_pid}` substitution for a user's `listen_on`), or document that the user must set `listen_on` with a path clawd-light can compute. State in the kitty row that without a reachable socket the route is unavailable even when `allow_remote_control` is on.

### [important] `lsof` does pair a zellij client with its server on macOS

*Where:* §0 paragraph after the hosts table ("`lsof` cannot pair a zellij client with its server…")

The plan says both sides print only peer addresses (`->0x…`) so the sets never intersect. Measured with `lsof -nP -U -a -p 2574` (server) and `-p 2571` (client): the server's fds 6u and 7u have DEVICE `0x5e075b05655b64e1` with NAME `/var/folders/…/T/zellij-501/contract_version_1/erudite-pigeon`; the client's fds 5u and 6u have NAME `->0x5e075b05655b64e1`. The DEVICE column is the socket's own kernel address and NAME's `->0x…` is the peer, so client-peer ∈ server-DEVICE holds and the matching server fd also carries the session-named socket path. The pairing the plan rules out is available.

**Fix:** Rewrite the paragraph. Either adopt `lsof -U` pairing (client pid → peer address → server pid/socket path → session name → and the client's tty from its own chain) as the zellij route with the title match as fallback, or keep the title route but state the real reason (cost/latency of lsof, or a preference to avoid shelling out), not an incorrect fact.

### [important] macOS `procStart` is a UTC ctime string, not a tick count — and not local time

*Where:* §2 ProcessTree paragraph (pid-reuse guard); §5 "Pid reuse"; Contracts/assumptions.md:595–610

The plan compares the session file's `procStart` with `p_starttime` "the same idea as the remote probe's field 22", and the Contract documents only the Linux form (`"procStart":"5480393"` clock ticks). On this Mac the files read `"procStart":"Wed Aug 26 17:07:24 2026"` (pid 32647) and `"Wed Aug 26 16:34:07 2026"` (pid 95193), while `ps -o lstart= -p` prints `Wed Aug 26 19:07:24 2026` and `Wed Aug 26 18:34:07 2026`, and `startedAt` 1787764046576 → `date -u -r` = 17:07:26 UTC / 19:07:26 CEST. So the darwin value is a ctime-format string in UTC with no zone marker and second resolution. `p_starttime` (`struct timeval __p_starttime`, macro `p_starttime` in sys/proc.h:98–102, confirmed) is epoch-based; a guard that formats it in local time, or parses the string as local time, is off by the zone offset and rejects every live session (or, reversed, accepts a reused pid).

**Fix:** Parse `procStart` with `%a %b %e %H:%M:%S %Y` in UTC, compare against `p_starttime.tv_sec` truncated to seconds with a ±1 s tolerance, and add a Contracts entry for the darwin format next to the Linux one, with the two measured values as the fixture.

### [minor] zellij socket path: the middle component is `contract_version_1`, not the version

*Where:* §0 Process chains table, zellij row (`…/zellij-<uid>/<version>/<session>`)

`ps -axo args` shows the server as `/opt/homebrew/bin/zellij --server /var/folders/2t/…/T/zellij-501/contract_version_1/erudite-pigeon` (zellij 0.45.0). The middle component is the IPC contract version, not the zellij version; only the last component is the session name, which the plan's `ZellijSocketName` parser already relies on.

**Fix:** Write `…/zellij-<uid>/contract_version_<n>/<session>` in the table so the fixture and the contract entry `zellij.socket` describe the real path.

### [minor] The home-folder `claude` is not "driven through a python wrapper"

*Where:* §0 "Noise, measured"; §5 "Sessions started by tools"

The plan reads the Terminal title `python ◂ claude` as a python wrapper running claude. The process tree says otherwise: claude 95193 (cwd `/Users/you`, `entrypoint: cli`) is a direct child of `-zsh` 88236 on ttys000 (login 88233 → Terminal 88200); the Python processes 95354, 95356, 95500 (and `uv` 95383, `node` 95355) are its children — MCP servers — not its ancestors. Terminal.app's title shows the newest process on the tty before the `◂` and the command that started the tab after it. The second session (32647, inside zellij, ttys009) likewise has no python ancestor.

**Fix:** Reword the noise paragraph ("two plain `claude` sessions in `~`, one in a Terminal tab, one inside zellij") and drop the wrapper example from the risks, or keep the risk as hypothetical without citing this measurement.

### [minor] tty strings come in two shapes and must be normalised before matching

*Where:* §0 hosts table (Terminal, iTerm2, WezTerm, tmux rows); §2 ProcessTree (`e_tdev → devname`)

`devname(e_tdev, S_IFCHR)` and `ps -o tty` return `ttys003`; tmux `pane_tty`/`client_tty` (man tmux 3.7c: "Pseudo terminal of pane/client"), wezterm `tty_name`, Terminal's `tty of tab` and iTerm2's `tty of session` return the `/dev/ttys003` path. The AppleScript forms were not exercised here (no Apple Events sent) and neither tmux nor wezterm was running, so those four are from documented behaviour rather than live output; the `devname` form is from the man page. The plan compares them as if they were one string. Also `e_tdev` is `NODEV` (`(dev_t)(-1)`, sys/param.h:141) for a process without a controlling tty, where `devname` returns NULL — the `ttyName: nil` case.

**Fix:** State in the ProcessTree paragraph that `ttyName` is the basename and that every listing parser strips a leading `/dev/` before comparison; add one test per parser with the `/dev/`-prefixed input; handle `NODEV` explicitly.

### [minor] The cited README caveat does not exist and the traps entry describes a different bug

*Where:* §0 "Inside a workspace it already works, with one wart" ("README, *Two tabs instead of one*")

`grep -in 'two tabs' README.md` finds nothing. The heading exists only at docs/07-traps.md:1201, and it records a different defect: "New conversation here" opened two tabs because the path passed `sessionId` and then opened a new tab, fixed with a skip parameter. The behaviour the plan describes — the extension deep link opening a new tab for a `cli` session that has no tab — is a new observation, not that trap.

**Fix:** Cite docs/07-traps.md only if the mechanism is the same; otherwise describe the `cli` deep-link behaviour as measured in §0 and leave the trap out, so phase A's "README caveat rewritten" targets text that exists.

## Unjudged (refuter did not run)

### [blocking] Folder rows anchored on the hook's cwd will move every time Claude `cd`s

*Where:* §1 D25 ("the folder as its workspace"), §2 `StateStore.handle` → `Workspace(path: cwd)`, phase B

The hook's `cwd` is the session's tracked working directory, not its launch folder, and it changes when the Bash tool changes directory. Measured on this machine's transcripts (same tracked value the hooks carry): 5 of the 60 most recent files hold more than one cwd — the home-folder cli session `e478c096` has `/Users/<you>` ×476 and `/Users/<you>/Development` ×100; `7a7ced12` has 10 distinct cwds under its project. Today the resolver folds every subfolder onto the window's root, so nobody noticed. For an unclaimed folder there is no root: `StateReducer.apply` does `existing.with(workspace: workspace)` on every signal, `ColumnLayout.group` keys rows by `workspace.path`, `StateStore.givePlaces`/`RowOrder.absorbing` append every new path, and `TranscriptLocator.candidateURL` derives the transcript folder from the path. So the `~` row becomes a `Development` row appended at the bottom (new slot, old path left as an empty slot), comes back on the next `cd`, and while drifted the chat window and the preview look for the transcript in the wrong `projects/` folder (the real file sits under `-Users-<you>/` even for the records whose cwd was `/Users/<you>/Development`). This is exactly the row-that-moves D23 exists to prevent.

**Fix:** Anchor a folder-attributed row on the **session file's `cwd`** (written once at launch, which is also what Claude Code derives the transcript folder from): in `StateStore.handle`, when the resolver returns nil and the toggle is on, look the session id up in `liveSessionReader.readLiveSessions()` and use that file's cwd; if the file is not there yet, use the hook cwd and let the next `poll()` correct it through a new `.reattribute(sessionId, workspace)` action (adopt must not stay the only path, since it never overwrites). Alternatively make existing folder rows claimants in the resolver (ancestor match), which also folds `~/Development` back into `~` for a hook-born row. Add the domain test "a later signal from a subfolder does not move a folder-attributed row" and an E2E: hook with cwd `/x`, then hook with cwd `/x/sub`, `path` stays `/x`. Confirm with one recorded hook after a `cd` before building, per the plan's own measure-first rule.

### [blocking] Turning the toggle off leaves every terminal row in place; the E2E `terminal off → absent` fails as written

*Where:* §1 D25, §2 `StateStore.handle`/`poll()`, phase B tests

Nothing in the current pipeline removes a row because its folder is unclaimed. `poll()` builds `confirmed` from every live session file (`live.map(\.sessionId)`), `reconcile` keeps all of them, `adopt` skips existing ids, `prune(alive: confirmed)` exempts them. `handle()` with the toggle off resolves nil and applies `.signal(signal, workspace: nil)`, and `StateReducer.apply` returns the state untouched on `guard signal.deservesTrafficLight, let workspace else { return state }` — so the existing row is not even downgraded. A terminal row therefore survives the toggle until its process dies or twelve hours pass. The plan also gives `poll()` no way to tell a terminal row from an editor row whose lock has vanished (the post-reboot case documented in `StateStore.handle`'s comment, whose rows must survive): `SessionState` records the workspace, not how it was attributed.

**Fix:** Add `attribution: .editor | .folder` (or `claimedByEditor: Bool`) to `SessionState` and `SessionSnapshot`. When the toggle is off, `poll()` applies a new `.evict(ids)` (or hands `reconcile` a set without the `.folder` local rows) so they leave at the next pass; the E2E waits with `waitUntil` for `absent` after `terminal off` and for the row after `terminal on` (≤5 s, not immediate). Use the same field for the glyph rule (`attribution == .folder && entrypoint != "claude-vscode"`) so a `claude-vscode` session that briefly has no lock does not wear a terminal glyph. State in D25 that the rows leave on the next poll, not instantly.

### [blocking] The click path does not consult the toggle, so the Terminal Automation prompt appears with the feature off

*Where:* §2 `PanelController.activate` ("local session → SeatResolver; … a terminal seat → TerminalFocuser"), §1 "What does not change", §5 first risk

A `claude` started in Terminal.app inside a folder VS Code has open already gets a row today (E2E "a terminal-started session inside a workspace counts"). With the plan as written, clicking it runs `SeatResolver` regardless of the toggle, finds a `.terminal(Terminal.app, tty)` seat and runs `tell application "Terminal"` — the very Automation prompt D8 says must not appear unasked, and it appears while "Show terminal sessions" is off. The plan is also internally inconsistent: §1 says such a session is "still attributed to that editor window" and that the click "follows the process, not the folder"; both cannot decide the click for this session, and the reader cannot tell which wins.

**Fix:** Write the click rule as a pure table (`ClickPolicy(toggle, attribution, seat) → target`) in Core with tests: toggle off → today's path unchanged for every row (no `SeatResolver`, no terminal Apple Event ever); toggle on → seat decides, and say in D25 that an editor-attributed row hosting a Terminal.app `claude` raises the terminal tab (or that it raises the editor — pick one, record it). Add the log line naming the branch taken (`click: toggle=off, editor path`) so the next Automation prompt can be traced.

### [important] The pid-reuse guard is specified against the wrong `procStart` format

*Where:* §2 `ProcessTree` ("procStart against p_starttime, the same idea as the remote probe's field 22"), phase C tests, Contracts `remote.sessions`

On macOS `procStart` is a ctime string in **UTC**, not ticks: session 14830's file says `"procStart":"Mon Aug 24 11:06:04 2026"` while `ps -o lstart` for the same pid prints `Mon Aug 24 13:06:04 2026` (CEST). `Contracts/assumptions.md` (`remote.sessions`) describes the field as "the process start time in clock ticks", which is only true on the Linux node. A guard that parses the string in local time is off by the UTC offset and declares every live session dead; a guard that ignores the format compiles and never matches. The file also carries `startedAt: 1787569565614` (epoch ms → 13:06:05 CEST), one second after `p_starttime`.

**Fix:** Compare `startedAt/1000` with `p_starttime.tv_sec` under a ±5 s tolerance (timezone-free), and parse `procStart` as UTC only as a secondary check; on mismatch fall back to the title route, not to "dead". Record both platform formats in a `sessions.file.procStart` contract entry and correct `remote.sessions`. Unit test with the three real values above.

### [important] When the cwd is later opened in an editor, hook-born and file-born rows diverge and the row changes identity

*Where:* §1 "What does not change", §2 `poll()`, phase B

A folder row exists at `Workspace(path: launchCwd)`. When a lock appears for an ancestor folder, the next hook resolves to the editor window and `existing.with(workspace:)` moves the session to `Workspace(path: lockFolder)`: if the launch cwd was a subfolder the row id changes, the new path is appended to `rowOrder` (new slot, bottom of the column), the old path lingers as an empty slot, and `hiddenWorkspaces`/`mutedWorkspaces`/`calmBlinkWorkspaces` keyed on the old path stop applying. A row adopted from the file, by contrast, never moves because `adopt` never overwrites — so two identical sessions end up in different rows depending on whether they spoke since the window opened. The reverse (window closed, toggle on) has the same shape.

**Fix:** Re-resolve `.folder`-attributed local rows on every `poll()` against the current windows and move them with the `.reattribute` action from finding 1, so both birth paths agree within one pass; when the path changes, decide explicitly whether the per-path flags follow (recommend: yes for hide/mute/calm, no for order) and test it. Document the transition in D25.

### [important] `/sessions`, the CLI listings and the slot descriptions cannot tell a folder row from an editor row

*Where:* §2 `SessionSnapshot` ("gains entrypoint and title"), phase A/B docs (`SessionsPayloadSuite`, Contracts)

`entrypoint` is `cli` both for a session in VS Code's integrated terminal (editor row, click raises a window) and for a folder row (click raises a tab), so a consumer that today does `open -b com.microsoft.VSCode <path>` on `path` would open a new VS Code window on `~`. `workspace` for a `~` row is the username, and every text surface uses it: `CommandLineInterface.listSlots`/`runSessions` print `session.workspace`, `PanelController.activateSlot`/`openChatInSlot`/`activateNextWaiting` return `row.workspace.name`, `SessionNotifier.deliver` sets `content.title = session.workspace.name`. The plan's label rule lives only in `ColumnRow.displayName`.

**Fix:** Publish `attribution` (from finding 2) alongside `entrypoint` and `title`; move the label rule onto a Core function (`SessionLabel.displayName(session/row)`) and use it in the row, the chat sidebar, the tooltip, the notification title, the slot-command return values and the CLI listings; add the three fields to `SessionsPayloadSuite` and the README's read-endpoint paragraph.

### [important] `clawd-light new <n>` / `POST /new` on a terminal slot still opens a VS Code tab

*Where:* §2 `TrafficLightRow` ("New conversation here hidden for terminal rows"), `PanelController.newConversationInSlot`

Hiding the menu entry is only one of three entry points. `newConversationInSlot` → `newConversation(in:)` → `activate(row, opensTab: false)` then `VSCodeFocuser.openNewConversation`, which fires the `vscode://Anthropic.claude-code/open` deep link into whichever VS Code window has focus — for a slot that holds a `~` terminal row, that creates a Claude tab in an unrelated project. Bound to a key, it is the wrong-target failure the slot design calls the worst one.

**Fix:** Make `newConversation(in:)` refuse `.folder`-attributed rows (return nil → CLI prints "slot n is a terminal session", exit 1) and add the case to the `ClickPolicy` table. Note in the plan that this cannot be E2E-tested (headless has no `panelController`, so `/new` already answers empty) and cover it with a domain test on the policy.

### [important] Phase B's E2E cases leak state into the other suites and lack a transcript fixture

*Where:* §3 phase B E2E list; `Sources/ClawdLightE2E/main.swift` suite order; `AppUnderTest`

Three concrete hazards. (1) `runCommand(["terminal","on"])` writes the shared `UserDefaults` suite the running app reads on every poll; if a case does not turn it off, LifecycleSuite's "an unknown session does not appear out of nowhere", CoverageSuite's "stays excluded" and the remote test's "no host, no row" — all asserting `absent` for unclaimed cwds — start failing, and with finding 2 the rows survive `terminal off` anyway. (2) `writeLiveSession(entrypoint: "cli")` uses the runner's own pid, so the file stays alive for the whole run; a non-empty `live` set makes `reconcile` erase every hook-only row of every other suite at the next poll (ScaleSuite already has to call `removeLiveSessions()` for this reason). (3) "`/sessions` shows `title`" needs an `ai-title` line under `<home>/.claude/projects/<encoded cwd>/<id>.jsonl`; `AppUnderTest` has no transcript helper and the hooks' `transcript_path` fixture is `/tmp/<id>.jsonl` (HookPayloads.swift:102), which does not exist.

**Fix:** Put the terminal cases in their own suite, registered before ScaleSuite, with `defer { runCommand(["terminal","off"]); removeLiveSessions() }` in every case and an explicit `waitUntil(absent)` after the off; add `writeTranscript(sessionId:cwd:lines:)` to `AppUnderTest` (and use it in the title case with a real `{"type":"ai-title","aiTitle":…}` line); assert the pre-existing `absent` cases still pass with the toggle on and off.

### [important] The label rule renames rows under the user's eyes, and the no-title case is the common one

*Where:* §1 "Label", §5 "Home-folder rows", §2 `ColumnRow.displayName`

Measured: 55 of the 60 most recent transcripts contain no `ai-title` record at all, and where one exists it first appears at line 16–23 / 60–120 KB — after the first exchange. So a terminal row is born labelled by folder and renames itself a turn later, and a grouped folder row flips title → folder → title as a second session starts and ends (`count == 1` condition). For `~` the fallback is the username in the majority case, which the plan treats as the exception. The titles themselves are stable (every multi-record file has exactly one distinct title; they are re-emitted on resume), so "first line wins" is safe.

**Fix:** Choose a stable fallback for a titleless folder row — the session file's `name` (`marcoarmellino-a1`) or `folder · tty`/host app — and decide whether the later title replaces it; keep `ColumnRow.id` = path so SwiftUI does not rebuild; apply the rule through the single Core function from finding 6 so the panel, sidebar and notifications agree; add "title arrives after the row" and "second session joins the folder" to the label tests.

### [important] Terminal cwds make `rowOrder` and the nine slots grow without bound

*Where:* §1 "Slots, order … all unchanged", `StateStore.givePlaces`, `RowOrder.absorbing` (RowOrder.swift:22)

`absorbing` only appends and nothing ever removes a path; slots are positions 1–9 of that list and "a project with no live session keeps its place". Editor folders are bounded by what a person opens; terminal cwds are not — one `claude` in `~/Downloads`, one in `/tmp/x`, one in a worktree each take a permanent place, and the first nine fill with dead folders holding empty slots while real projects land below slot 9. With finding 1 unfixed, every `cd` adds another.

**Fix:** Do not give `.folder`-attributed rows a place in `rowOrder`: draw them after the placed rows (ordered by name) without a slot, or give them a place that is removed when their last session ends. Record the choice in D25 and in the README slot section; test `givePlaces` ignores folder rows.

### [important] Title reads are synchronous main-actor I/O and the reducer has no action to carry a late title

*Where:* §2 `SessionTitleReader`, `TrafficLightState`/reducer bullet ("nothing new in the state machine"), `TranscriptTitleScanner`

`poll()` and `handle()` run on the main actor; reading up to 512 KB per session on adoption means up to ~12 MB synchronously at startup with the two dozen sessions the project designs for, and "again on Stop while it is still unknown" re-reads 512 KB on every Stop for the life of every titleless session — which is 55 of 60 sessions measured. Separately, a title that arrives after the row exists needs a reducer path: `.adopt` never overwrites and `.signal` does not carry a title, so the plan's claim that the state machine needs nothing new is false for this field.

**Fix:** Read titles off the main actor (`Task.detached`, like the remote probe) and apply a `.retitle(sessionId, title)` action; cap retries (e.g. stop after the third titleless Stop, retry on `SessionStart(resume)`); test the reducer action and that `.adopt` still does not touch a known title.

### [minor] The title-match fallbacks inherit the locked-screen lie without the existing distinction

*Where:* §2 `PanelController.activate` ("pid gone → title match across running terminal apps"), phase E kitty/unknown-host fallback, `FocusError.automationDenied(app:)`

Every title route that goes through System Events (kitty without remote control, the unknown host, the pid-gone search) gets zero windows while the screen is locked (07-traps "The locked screen", `FocusError.noWindowsVisible`), and `open <n>`/`next` can be triggered from Shortcuts while locked or in the second after unlocking. The plan adds only `automationDenied(app:)`, so the outcome reads as "not found" — the wrong remedy, again.

**Fix:** Check `CGSSessionScreenIsLocked` (already implemented in `PresenceFile.isScreenLocked`, hoist it) before any title route and return `noWindowsVisible`; make `TerminalFocuser` return the existing `FocusResult` with the same three outcomes and log `seat: <host> screen locked`.

### [minor] State the string-to-script trust boundary and test it, including the two new attacker-influenced inputs

*Where:* §2 `TerminalScripts` ("through AppleScriptString.escaped"), §5

Three values reach scripts that did not before: the conversation title (model-generated from content the session read, so prompt-injectable) into `whose name contains "…"`; the zellij session name from another process's `KERN_PROCARGS2`; and, if the hook cwd is used (finding 1), a `cwd` from the unauthenticated `POST /signal` into Ghostty's `working directory`. `AppleScriptString.escaped` covers `"` and `\` and is sufficient for AppleScript literals, but nothing in the plan forbids regex-typed matchers (`kitten @ focus-window --match title:`) or a `sh -c` for tmux/wezterm, and no test pins the rule. `~/.claude/sessions/<pid>.json` is user-writable, so a same-user process can point the click at any pid — the mailbox's trust model, unstated here.

**Fix:** One rule in `TerminalScripts`: every dynamic value passes `escaped`, every CLI is a `Process` argument array, matchers are pid/tty/id only (never title regex); a builder test with the title `x" \ ; do shell script "say hi"` asserting the literal is escaped in every script; use the session-file cwd, never the hook cwd, for anything that reaches a script; add the same-user caveat to §5.

### [minor] Chat window, rewake and session-file facts for a session with no editor

*Where:* §2 `TrafficLightRow` ("Read here… stays"), §0 "Session files"

Message delivery works by construction (the rewake `Stop` hook is global), but `ChatView` labels the raise button `.help("Open this session in VS Code")` (ChatView.swift:277), and `ChatSession`/`ChatShell.preview` derive the transcript from `workspace.path`, which is only right with the launch-cwd anchor of finding 1. §0's field list also misses what every 2.1.241 file carries — `startedAt`, `version`, `peerProtocol`, `peerFeatures: ["notify_idle"]`, `messagingSocketPath: /tmp/cc-socks/<pid>.sock` — so the promised `sessions.file.pid` contract entry would be written from an incomplete measurement, and a per-session messaging socket is a fact worth recording next to D15 even if unused.

**Fix:** Make the button text follow the seat ("Open in Terminal"/"Open in VS Code"); write the contract entry from a real file with all fields and formats; add one line to D25/D15 noting `messagingSocketPath` exists and is not used.

### [minor] `status` and `selftest` will contradict the column once the toggle is on

*Where:* §3 phase B/F deliverables; `CommandLineInterface.runStatus`, `SelfTest`

`runStatus` prints "of which with a recognized workspace: N ← rows in the column" and "The others have a cwd that no lock contains"; `selftest` says "normal if you are running the command from an external terminal" when the cwd resolves to nothing. Neither is in the phase lists, so with terminal sessions on both understate the column and send the reader to the wrong explanation — the diagnostic surfaces this project leans on hardest.

**Fix:** Add to phase B: `status` prints the toggle and the count of unclaimed interactive sessions that get rows; `selftest`'s workspace step says "would be a terminal row" when the toggle is on; both listed in the README's "When something's wrong".

### [minor] `DeepLinkPolicy` must define the nil entrypoint and how a row acquires one

*Where:* §3 phase A

`hook.sh` sends `X-Claude-Entrypoint:` empty when `CLAUDE_CODE_ENTRYPOINT` is unset, so `HookSignal.entrypoint` is nil; `.adopt` never overwrites, so a hook-born row never learns the file's value unless the reducer fills the field in. `opensTab(entrypoint:)` therefore meets nil in practice and the plan does not say what it does.

**Fix:** nil → no tab (the two-tabs defect is the costlier error and the tab is a bonus); in the `.signal` path set `entrypoint` on creation and fill it when nil without overwriting a known value; test both.

## Refuted

- **Terminal rows pollute the persisted order and consume keyboard slots — §1 says order and slots are unchanged** — The mechanics the reviewer cites are real (givePlaces absorbs every session's workspace.path, StateStore.swift:387-391; nothing prunes rowOrder — its only writers are absorbing/moving/placing/normalized; a slot is a position in the full list, RowOrder.swift:76-79; the reducer re-applies with(workspace:) on every signal, StateReducer.swift:139/145/220). But the finding fails on the two things that matter.

1. The claimed fact — that this is "the interaction D23 was written to avoid ... arriving by a new door" — is false. D23 forbids known rows moving; absorbing a newcomer appends at the bottom and moves nothing ("appending is the one arrangement that moves nothing the user has already learned", RowOrder.swift:17-20). "After nine, every new editor project lands beyond slot 9" is already today's behaviour for every editor folder ever opened once, and is D23's stated rule, not a regression the plan introduces. The door is not new either: D24 remote rows already use the raw cwd as workspace (StateStore.swift:153, `Workspace(path: signal.cwd, host: host)`) and go through the same givePlaces, leaving entries behind when the remote pid dies; the plan says D25 is "the same rule D24 adopted for other machines, brought home" (plan line 80-81). §1's "Slots, order ... unchanged" is accurate as written: the mechanism is unchanged and a new class of row enters it the same way remote rows already do. Unwanted rows have `hide` (plan §5) and the feature is off by default (D8).

2. Both proposed fixes contradict D23 without saying so. Option A (terminal paths not absorbed, sorted via position == Int.max, slot only when dragged) contradicts "Every project has a place — the one it got when first seen" and "Slots are positions: the first nine rows are keys 1 to 9" (04-decisions.md D23, lines 708-712, 744-751; RowOrder.swift:5-9): a terminal row drawn third with no slot breaks position = slot, StateStore's "newcomer gets a place before publishing so headless and CLI agree" (D23 "Where the order lives") is bypassed, and the Int.max path is documented as a one-render transient, not a home (ColumnLayout.swift:247-248). Option B (prune when the last session leaves) contradicts D23's "keeps it whatever its state does" and "The list may name projects with no live session: their slot is empty" (README lines 180-181; SlotSuite.swift:135 tests exactly this invariant), and reintroduces rows shifting up when a session ends — the mechanism D23 removed (07-traps, "The click that only knocked"). The fix says "decide and record in D25" but never states that either option carves an exception into D23.

- **VS Code integrated-terminal shells hang off `Code Helper`, not `Code Helper (Plugin)`** — The plan already handles it. Row 39 of /Users/you/Development/clawd-light/docs/plans/terminal-sessions.md reads, on disk today: "| VS Code, integrated terminal | `claude → zsh → Code Helper → Code` — the pty host lives in `Code Helper.app`, the extension host in `Code Helper (Plugin).app`; the classifier must tell the two apart by the bundle name, not the word \"Helper\" | the tab's pty, e.g. `ttys004` |". That is the reviewer's proposed row, word for word, plus the discrimination rule. §2 already states that `SeatClassifier.classify` is "tested against fixtures of every chain in §0", and both VS Code chains (panel and integrated terminal) are in the §0 table, so both are fixtures by construction; `ProcessAncestor` already carries `executablePath`, which is what a bundle-name check reads.

The reviewer's measurement itself is correct and I reproduced it read-only (`ps -axo pid,ppid,tty,comm`): the eight integrated-terminal shells on ttys001-006/013/014 have ppid 3893 = `/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper`, whose parent 3811 is `/Applications/Visual Studio Code.app/Contents/MacOS/Code`; the panel chain `claude 66419 → 66293 Code Helper (Plugin) → 3811 Code` also holds. But the plan states exactly this, so the finding is not a discrepancy with the plan.

One caveat for the orchestrator: the fix lives in the working tree only. `git status` shows the plan as `AM` (staged new file, unstaged modification), and the unstaged diff is precisely row 39 — the staged copy still says "`claude → zsh → Code Helper (Plugin) → Code` (expected; to be measured in phase C) | a pty of the plugin host". So the reviewer read the staged text; the on-disk plan has since been corrected and needs `git add` to carry the correction into the commit.

A second reason the proposed fix should not be adopted as written: keying the classifier on the literal path prefix `/Applications/Visual Studio Code.app/Contents/` is narrower than the plan's "by the bundle name". It would not recognise Cursor (docs/04-decisions.md N3 includes Cursor as a VS Code fork with its own bundle, `com.todesktop.230313mzl4w4u92`), VS Code Insiders (Sources/ClawdLightTests/IDEKindSuite.swift already tests "Visual Studio Code - Insiders" as `.visualStudioCode`), or an install outside /Applications. Adopting it would silently drop Cursor coverage, contradicting N3 without saying so. The plan's bundle-name rule, mapped through `IDEKind`'s bundle table, already covers those cases.
