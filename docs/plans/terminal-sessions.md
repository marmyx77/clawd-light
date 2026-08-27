# Terminal sessions — implementation plan

**Status:** in progress. Planned 2026-08-27, revised the same day from an adversarial
review ([terminal-sessions-review.md](terminal-sessions-review.md)); phases A, B and
C built and verified the same day — see each phase for what was found on the way.
**Scope:** a `claude` started in a terminal — Terminal.app, iTerm2, Ghostty, kitty,
WezTerm, inside tmux or zellij, or in VS Code's integrated terminal — gets a row
when it runs in a folder no editor window claims, and a click raises the
terminal **tab** that hosts it. For zellij the click reaches the tab hosting the
zellij client, not the pane inside it; that limit is accepted.

The plan follows the shape the remote work took (D24): measure first, decide,
then build in phases each of which is complete, tested and documented on its own.

---

## 0 · What is true today (measured on 2026-08-27)

**Hooks already arrive.** The hooks are global in `~/.claude/settings.json`, so a
terminal session posts to `/signal` like any other. The signal is then dropped
by `StateStore.handle` because `WorkspaceResolver` finds no editor window whose
folder contains the `cwd`; the log says so:
`signal dropped: Notification for /Users/you — no editor window claims that folder`.

**Inside a workspace it already works, with one wart.** A `cli` session whose
`cwd` is inside an open folder is attributed to that window (E2E: *a terminal-
started session inside a workspace counts*). With "Click also opens the tab" on,
the click follows with the extension's deep link; the extension resolves it in
the focused window and, finding no tab for that session, **opens a new one**.
Observed, and written down nowhere until now — the traps entry *Two tabs instead
of one* is a different, fixed bug. The entrypoint is known at signal time
(`X-Claude-Entrypoint: cli`) and in the session file, so this is a policy line.

**The hook's `cwd` follows `cd`.** Claude Code moves its process directory with
the Bash tool's persistent `cd`, and the hook payload carries that directory. This
session's transcript has 16,170 records at the project root and 29 under `docs/`,
from one `cd docs`. Editor rows never noticed: a subfolder still resolves to the
window's folder. A row anchored on the hook's `cwd` would move on every `cd`. The
session file's `cwd` (`~/.claude/sessions/<pid>.json`) is written once at startup
and never touched again (Contracts, `sessions.file.mtime`) — that is the anchor.

**Process chains**, read with `ps -o pid,ppid,tty,comm` on live sessions:

| Started from | Chain from `claude` upwards | tty of `claude` |
|---|---|---|
| Terminal.app tab | `claude → -zsh → login → Terminal` | the tab's, e.g. `ttys003` |
| zellij inside a Terminal tab | `claude → zsh → zellij --server …/zellij-<uid>/contract_version_1/<session>` (ppid 1) | a pty of the server's, **not** the tab's |
| the zellij client | `zellij → -zsh → login → Terminal`, on the tab's tty | — |
| VS Code, Claude panel | `claude → Code Helper (Plugin) → Code` | none |
| VS Code, integrated terminal | `claude → zsh → Code Helper → Code` — the pty host lives in `Code Helper.app`, the extension host in `Code Helper (Plugin).app`; the classifier must tell the two apart by the bundle name, not the word "Helper" | the tab's pty, e.g. `ttys004` |

tty names come in two shapes — `ttys003` from `ps`/`kinfo_proc`, `/dev/ttys003`
from `Terminal.sdef` and tmux — and are normalised to the device path before any
comparison.

**Titles.** Claude Code sets the terminal title to `✳ <conversation title>` (the
`ai-title` record of the transcript, e.g. `✳ Wire the release script`). Terminal.app
shows it as `you — ✳ Wire the release script — python ◂ claude — 80×45` (the
`python ◂ claude` part is Terminal's own display of the tab's process); inside
zellij the session name comes first: `you — quiet-owl | ✳ Wire the release script — zellij — 121×51`.

**What each host exposes**, read from the bundles and CLIs, no permission needed:

| Host | How a tab can be found | How it is raised | Source |
|---|---|---|---|
| Terminal.app | `tty of tab` (`Terminal.sdef`, property `tty`, read-only) | `set selected tab of window w to t`, `set frontmost of w to true`, activate | AppleScript → Automation → Terminal |
| iTerm2 | `tty of session` (`iTerm2.sdef`, property `tty`) | `select` tab and session, activate | AppleScript → Automation → iTerm2 |
| Ghostty | `terminal` has `id`, `name` (current title) and `working directory`; no tty | command `focus` ("Focus a terminal, bringing its window to the front"), `select tab` | `Ghostty.sdef` → Automation → Ghostty |
| WezTerm | `wezterm cli list --format json` → panes with `tty_name`, `pane_id`, `tab_id`, `window_id`, `cwd`, `title` — **no pid** | `wezterm cli activate-pane --pane-id N`, then activate the app | bundled CLI, no permission |
| kitty | `kitten @ --to unix:/tmp/kitty-<kitty pid> ls` → windows with `pid`, `cwd`, `cmdline`; **only with remote control enabled** (`allow_remote_control` + `listen_on unix:/tmp/kitty`, which kitty suffixes with its pid — the pid is in the chain) | `kitten @ --to … focus-window --match pid:<shell pid>` | bundled CLI; without remote control, title match through System Events |
| tmux | `tmux list-panes -a -F '#{pane_tty} #{pane_pid} #{session_name}:#{window_index}.#{pane_index}'`; `tmux list-clients -F '#{client_tty} #{client_pid} #{client_session}'` | `select-window`, `select-pane`, then the client's tab by its tty | CLI |
| zellij 0.45 | the server pid is in the chain; `lsof -nP -U -a -p <server>` lists its sockets with their own kernel address (DEVICE) and the session-named socket path; `lsof -nP -U -a -p <client>` shows each client's peer as `->0x<address>` — client peer ∈ server DEVICE pairs them | the client's tab by its tty (phase C); fallback: the tab whose title contains the session name | CLI + `lsof`; title as fallback |
| VS Code | as today: the window by folder title | as today; **no deep link** for `cli` | System Events |

**Session files.** `~/.claude/sessions/<pid>.json` for a terminal session carries
`entrypoint: "cli"`, `kind: "interactive"`, `name: "<folder>-xx"` (derived, not
the title), `cwd`, `procStart`, and — for `cli` only — `status`, which has only
ever been seen as `idle` and stays unused (Contracts, `remote.sessions`). The
file gives the **pid**, which is what the click needs; the hook payload has no pid.
`procStart` differs by platform: Linux writes clock ticks (`"5480393"`, Contracts
`remote.sessions`); macOS writes a ctime string **in UTC, without a zone marker**,
at second resolution — `"Wed Aug 26 17:07:24 2026"` for a process `ps -o lstart`
shows at `19:07:24` local. `LiveSession` does not read the field today.

**Noise, measured.** Two terminal sessions live in the home folder right now,
both `cli`, both interactive. They are sessions a person is sitting in front of;
they deserve a row. The `sdk-cli` observers do not and are already excluded by
`nonInteractiveEntrypoints`.

---

## 1 · The decision to record — D25 · A folder nobody claims is a place too

**Decided (proposed).** With "Show terminal sessions" on, a local interactive
session whose `cwd` no editor window claims gets a row of its own, with **the
folder its session file names** as its workspace — the same rule D24 adopted for
other machines, brought home, anchored on the one `cwd` that does not move. The
row is born when the session speaks (hook) **or** is adopted from the session
file (like editor sessions, unlike remote ones: the pid is verifiable here with
`kill(0)`, so silence is not ambiguity). Either way it exists only if a **live
local session file** names that session id: a hook alone is not enough. That
one condition is what keeps out a forged `X-Clawd-Host` header treated as local,
a foreign path, and a signal for a process that is already gone. The row leaves
when the process is gone. A click on it **follows the process, not the folder**:
the pid is read from the file, the process tree is walked to the hosting
application, and that application's own way of selecting a tab is used. Off by
default (D8: the first click asks for an Automation permission per terminal app).

**The row knows what it is.** `SessionState.origin` is `.editor` or `.terminal`,
set where the workspace is set — by the resolver's answer at signal time or at
adoption — and nowhere else. Not on `Workspace`: that type is hashed over all its
fields and *is* the row identity, and a terminal session and an editor session in
the same folder must still group. Everything that treats a terminal row
differently — label, glyph, menu, click, `/new`, the toggle turning off — reads
this field. Nothing infers it from the entrypoint: a `cli` session inside an open
folder is an editor row (E2E, *a terminal-started session inside a workspace counts*).

**The click, by origin.** An editor row takes today's path unchanged — window by
folder title, no process walk, and the tab deep link only when the session's
entrypoint is `claude-vscode` (unknown entrypoint → today's behaviour, which is
to open). A terminal row goes through the seat resolver. Consequence, stated: a
`claude` started in a Terminal.app tab **inside a folder that is open in VS Code**
is an editor row, and its click raises the VS Code window. Correct for the
integrated terminal, a compromise for the external one; the alternative — a
process walk on every editor click — would show a Terminal Automation prompt
with the feature off, and D8 forbids that.

**The toggle.** Off → every row with origin `.terminal` is removed at once and
none is adopted; on → the live terminal sessions appear at the next poll, within
five seconds.

**What does not change.** Attribution of a session whose `cwd` is inside an open
folder. Grouping by folder; two terminal sessions in `~` are one row with two
sessions, and the click opens the most urgent one's tab. Slots, order, hide,
mute, calm, chat window, notifications, message delivery (hook-based, so it
reaches a terminal session the same way). Remote rows.

**What changes for everyone**, toggle or not: the deep-link policy above. For a
`cli` session in an editor window the click raises the window and stops there.

**Label.** A terminal row holding **one** session with a known conversation title
is named by that title; otherwise by the folder name, as today. The title is what
the person sees in their terminal's title bar, so it is the name they will look
for; the folder name of `~` is a username and says nothing. The name is renamed
**once**, when the title arrives (the terminal's own title bar does the same), and
falls back to the folder when a second session joins the row. A small terminal
glyph precedes the name in expanded mode, the way `@host` follows a remote one.
The rule lives on `SessionState.displayName`, in Core, and every surface that
names a session to a person goes through it: the row, its tooltip, the answers
of `open n` and `next`, the notification title, the hidden summary, the chat
roster header (already title-aware). What must keep `workspace.name`: window
title matching, `/sessions.workspace` and `.path`, the order list.

**When the folder is opened later.** A terminal session whose folder (or a parent
of it) gets opened in an editor is attributed to that window at its next signal
or poll: origin becomes `.editor`, the workspace may become the parent folder,
and the row moves there — the session moved into a window. Accepted; stated.

**A limit, pre-existing and now common.** `.reconcile` ignores an empty set of
live pids (a failed directory read must not empty the column). A lone terminal
row whose process dies without `SessionEnd` therefore stays until the twelve-hour
prune. Phase B fixes the root: `LiveSessionReader` returns `nil` for an unreadable
directory and `[]` for an honestly empty one — the distinction `RemoteSessionReader`
already makes — and `poll()` reconciles to empty when the read succeeded. Editor
rows gain the same fix.

**Discarded:** making the terminal tab part of the workspace identity (a row per
tab). It would split the folder rows people have already placed and ordered, and
the click resolves the tab anyway. **Discarded:** a row only when it speaks, as
for remote hosts. Turning the toggle on and seeing nothing until the next turn
would read as "it does not work"; locally the pid check makes adoption safe.
**Discarded:** the process tree overriding the folder for editor rows (see *The
click, by origin*).

---

## 2 · The pieces

Core, pure, under the domain suite:

- `SessionState.origin: SessionOrigin` (`.editor`, `.terminal`), `entrypoint: String?`,
  `title: String?`, `displayName`. Two write paths only: `remembering(transcriptOf:)`
  — the existing hook for orthogonal facts a signal carries — extended to carry
  the entrypoint; and a new `ReducerAction.remember(sessionId:title:)` for a title
  learned later. `.adopt` and `.signal(…, workspace:, origin:)` set the origin.
  Tests: a fact set once survives every transition (one test through `remembering`,
  not three through the constructors).
- `SessionSnapshot.origin` and `.title` (additive to `/sessions`).
- `DeepLinkPolicy.opensTab(entrypoint:)`: `claude-vscode` and `nil` → yes; anything
  else → no.
- `ProcessAncestor { pid, ppid, executablePath, tty }` (tty as `/dev/ttysNNN`), and
  `Seat`: `.terminal(TerminalKind, tty:)`, `.tmux(serverPid:, tty:)`,
  `.zellij(serverPid:, sessionName:)`, `.editor(IDEKind)`, `.application(path:)`,
  `.unknown`. `SeatClassifier.classify(_ chain: [ProcessAncestor]) -> Seat` walks
  the chain and answers from a table — tested against fixtures of every chain in §0.
- `TerminalKind` — a short table like `IDEKind`: bundle id, process name for
  System Events, and a `raising` strategy (`appleScriptTTY`, `appleScriptTitle`,
  `wezterm`, `kitty`, `activateOnly`). Deliberately short, for the same reason.
- `TerminalScripts` — AppleScript sources for Terminal, iTerm2 and Ghostty. Every
  string that crosses into a script or an argument list is validated first and
  tested: a tty must match `^/dev/ttys[0-9]+$`, a zellij session name
  `^[A-Za-z0-9._-]+$`, an id from Ghostty is quoted through `AppleScriptString`;
  **titles never leave Swift** — the Ghostty route enumerates terminals and
  compares `name`/`working directory` in Swift, then focuses by `id`. CLIs are
  run with argument arrays (`Process`), never through a shell.
- Parsers: `TmuxListing` (panes, clients), `WezTermListing` (JSON), `KittyListing`
  (JSON), `LsofUnixSockets` (DEVICE and `->peer` per pid), `ZellijSocketName`
  (last path component of the `--server` argument).
- `TerminalTitleMatcher` — finds `✳ <title>` and `<zellij session> |` in a list of
  titles; the VS Code matcher stays where it is.
- `TranscriptTitleScanner.title(in:)` = `TranscriptTail().consume(head).title`: the
  rule that already names the chat window (last record wins), applied to the
  first 512 KB (measured on 400 transcripts: the first `ai-title` sits within
  119 KB, and the record repeats identically). One rule, two readers.
- `ProcStart.parse(_:)` — darwin ctime in UTC (`%a %b %e %H:%M:%S %Y`) or Linux
  ticks; `matches(_ start: Date, tolerance: 1 s)`. Fixtures: the two measured values.

App:

- `ProcessTree` — `sysctl(KERN_PROC_PID)` → `kinfo_proc` (`e_ppid`, `e_tdev` →
  `devname`), `p_starttime`, `proc_pidpath`; walk up to twelve levels.
- `SeatResolver` — session id → pid (`LiveSessionReader`) → `procStart` guard →
  chain → `Seat`, at click time only; nothing is cached.
- `TerminalFocuser` — one strategy per `TerminalKind`, plus the tmux hop (pane by
  the claude's tty → `select-window`/`select-pane` → client pid → its chain) and
  the zellij hop (server pid → `lsof` pairing → client pid → its chain; title as
  fallback). Returns the existing `FocusResult`. `FocusError.automationDenied`
  gains an associated app name — a change to an existing case; its two call
  sites and the message follow: *Privacy & Security › Automation › clawd-light › Terminal*.
  Title-based routes keep the `noWindowsVisible` distinction: zero titles means
  accessibility cannot see the app (a locked screen), not "not found".
- `SessionTitleReader` — off the main actor (`Task.detached`, as the remote probe),
  result hopped back through `.remember`. Runs at adoption or first hook, and at
  each `Stop` while the title is still unknown.
- `LiveSessionReader.readLiveSessions() -> [LiveSession]?` — `nil` when the
  directory cannot be read; `poll()` reconciles to empty only on a successful read.
- `Preferences.showsTerminalSessions` (`terminal.sessions`, default `false`); menu
  item "Show terminal sessions"; a "Terminal sessions" section in Settings with the
  sentence that explains the permission; CLI `terminal on|off|status`; `status`
  prints the toggle and how many terminal rows there are.
- `StateStore.handle`: resolver returns `nil`, toggle on, `signal.host == nil`,
  `signal.deservesTrafficLight`, and a live session file names the id → workspace
  is that file's `cwd`, origin `.terminal`; log `adopted as a terminal session`.
  Otherwise dropped as today, and the log says which condition failed. `poll()`:
  adopt unclaimed local live sessions under the same rule; prune as today. Toggle
  off → `.forget(origin: .terminal)`.
- `PanelController.activate`: by origin (§1). Pid gone at click time → the row is
  about to leave; a menu message, no alert. `newConversation`, `/new` and
  `new <n>` refuse a terminal row with "runs in a terminal — start the new
  conversation there" (non-zero exit for the CLI).
- `TrafficLightRow`: glyph; "New conversation here" hidden for terminal rows;
  "Read here…" and ⌘-click stay — the transcript is local.

---

## 3 · Phases

Each phase ends green (`Scripts/test.sh`, `check-docs.sh`, `check-contract.sh`),
documented, committed. Tests first.

**A · The click that opened two tabs** — **done, 2026-08-27.**
`SessionState.entrypoint` through `remembering(factsOf:)`; `DeepLinkPolicy`;
`PanelController` uses it; adoption from the session file carries it. Tests: the
policy table including `nil` and empty; the fact survives a signal without it;
`/sessions` carries `entrypoint` (payload suite, two E2E cases). Docs: README,
D5, code map.

**B · The row** — **done, 2026-08-27**, with two departures from the list below:
the `LiveSessionReader` nil/empty fix is deferred (D25 says why — the E2E
harness leans on the current leniency), and a click on a terminal row says
"not built yet" until phase C, rather than raising an editor window of a
folder that has none. Originally estimated at one day. Verified live: with the switch on, the two
`cli` sessions running in `~` became one grouped row (glyph, badge `2`) within
five seconds, both with their titles in `/sessions`; off took the row away.
Origin, title, `displayName`, `.remember`; preference, menu, Settings section, CLI,
`status`; `StateStore.handle` and `poll()` rules with the session-file condition;
toggle-off removal; `LiveSessionReader` nil/empty and the reconcile fix;
`SessionTitleReader`; glyph; `/new` gate; payload fields.
Tests, domain: *an unclaimed folder becomes a terminal row when the toggle is on*,
*stays dropped when off*, *an `sdk` session stays out either way*, *no session
file, no row*, *the workspace is the file's cwd, not the hook's*, *toggle off
forgets terminal rows and nothing else*, *an honestly empty live list empties the
column, an unreadable directory does not*, title scanner (last wins, repeated
records yield one, malformed line skipped, none within the window → nil),
`displayName` (one session with title → title; two → folder; no title → folder;
editor row → folder), the notification title uses `displayName`.
Tests, E2E (each case `defer { terminal off }`): `terminal on` + hook with
entrypoint `cli` under no lock + `writeLiveSession(entrypoint: "cli")` → row
present with `origin: terminal`; same without the session file → absent; `terminal
off` → the row is gone; hook with an unknown host while on → absent (the existing
assertion, kept); a transcript fixture with an `ai-title` record at
`TranscriptLocator.candidateURL` → `/sessions` shows `title`; `new <slot>` on a
terminal row → refused.
Docs: D25, 01-architecture "Terminal sessions", README section, Contracts
`hook.cwd.follows.cd`, `sessions.file.procStart` (both formats), `terminal.title`.

**C · The click, Terminal.app and iTerm2** — **done, 2026-08-27** for
Terminal.app, verified live: `open 8` on the home-folder row resolved
`Terminal /dev/ttys000`, the Automation prompt for Terminal appeared once, and
the tab came to the front (`seat: Terminal /dev/ttys000 raised`, front
application Terminal). iTerm2 is built on its dictionary and not yet exercised.
One trap found on the way, recorded in 03-macos: an app launched from a
terminal inherits that terminal's TCC attribution, and a denial recorded for
VS Code → Terminal earlier in the day was reported as the panel's own.
`ProcessTree`, `SeatClassifier`, `TerminalKind`, `TerminalScripts` and validators,
`ProcStart`, `SeatResolver`, `TerminalFocuser` for the two tty hosts. Tests:
classifier fixtures for every chain in §0; script builders and every validator's
reject list; `ProcStart` on both formats and the zone trap; tty normalisation.
Live protocol in §4. Docs: 03-macos (one Automation entry per terminal app; `sdef`
is how to know what an app exposes), traps as found.

**D · Multiplexers** — three hours.
tmux hop; zellij hop by `lsof` pairing with the title fallback. Tests: listing
parsers, `LsofUnixSockets`, socket name, title matcher. Live: a tmux session
inside a Terminal tab; the zellij session already running.

**E · The other three, and the fallback** — three hours.
Ghostty by `name` + `working directory` compared in Swift, `focus` by `id`;
WezTerm by `tty_name` and `activate-pane`; kitty by `kitten @ --to … ls` when
remote control answers, else title. Generic fallback for an unknown chain:
activate the application owning the topmost GUI ancestor (`open -b`, bundle id
from the executable path). Live: one `claude` in each, launched from a test
config (kitty: `allow_remote_control socket-only`, `listen_on unix:/tmp/kitty`,
passed with `--config`).

**F · Closing** — two hours.
05-code-map figures, `check-docs`, Contracts (`terminal.sdef`, `zellij.socket`),
README requirements (which terminals, which permission), traps. Statements in the
code that this work makes false, rewritten: `WorkspaceResolver.swift` header
("the session is running in a terminal and is ignored"), `LiveSession.entrypoint`
("Used to exclude terminal sessions"), the drop log line in `StateStore.handle`,
the E2E `MARK` in `CoverageSuite`.

Order of value: A alone removes a daily annoyance; A+B+C cover the two hosts in
actual use here (Terminal.app, and zellij through its Terminal tab in D). E is
coverage for other people's setups and is the first thing to cut if time is short.

---

## 4 · Live verification protocol

Domain tests prove the pure parts; the click cannot be proven without a GUI and
a permission, so each host gets the same manual check, recorded in the commit:

1. Open two tabs in the host; in the second, `cd` somewhere no editor has open
   and run `claude`; ask it anything so the title appears.
2. Enable "Show terminal sessions". The row appears, named by the title.
3. Switch to another application. `clawd-light open <slot>` from a third terminal
   — the same path as a click, without a synthetic mouse.
4. Expected: the host comes to the front with the **second** tab selected. Check
   with the host's own dictionary or CLI (`osascript -e 'tell application
   "Terminal" to get tty of selected tab of front window'`; `wezterm cli list`;
   `kitten @ --to … ls`), and with the log line `seat: <host> <tty|title> raised`.
5. First run per host: the Automation prompt appears; deny once and confirm the
   menu message names the right pane.
6. Lock the screen and click once: the message must say accessibility sees no
   windows, not that the tab is missing.

The hosts needed are installed on the development machine (Homebrew, 2026-08-27):
tmux 3.7c, iTerm2, kitty 0.48, WezTerm 20240203, Ghostty; zellij 0.45 was
already there and is the one in daily use.

---

## 5 · Risks, stated

- **Automation prompts multiply.** One per terminal app, at the first click on a
  terminal row. Editor rows never walk the process tree, so the toggle being off
  (D8) keeps every prompt from appearing unasked.
- **Title matching is the weak leg.** It is used only where nothing better exists
  (zellij when `lsof` pairing fails, kitty without remote control, an unknown
  host) and the fallback is "activate the app", never "raise a wrong tab".
- **Home-folder rows.** Several terminal sessions in `~` collapse into one row
  labelled by the folder — a username. Ungrouped mode shows one row per session
  with its title; the label rule cannot do better for a group without lying.
- **The order list grows.** Every folder a terminal session starts in takes a
  place in `rowOrder`, forever, as every editor folder already does. Anchoring on
  the session file's `cwd` keeps `cd` out of it. If it becomes a nuisance, a
  separate decision can expire entries with no session for thirty days.
- **Sessions started by tools.** A wrapper that runs `claude` interactively gets a
  row; it is a session someone is in front of. `hide` covers the rest.
- **VS Code's integrated terminal** stays a window-level target: there is no API
  to select a terminal tab from outside. The row is attributed to the window as
  today, and the deep link stops opening a second tab — that is the whole fix.
- **Pid reuse.** Guarded by `procStart`, parsed as UTC; the zone trap is the kind
  of mistake that rejects every live session or accepts a dead one, so it has a
  fixture from the machine, not from the documentation.
- **An external terminal in an open folder** raises the editor window, not the
  tab (§1). Stated in the README next to the feature.
