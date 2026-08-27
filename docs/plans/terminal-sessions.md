# Terminal sessions — implementation plan

**Status:** planned, 2026-08-27. Nothing below is built yet.
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
the click follows with the extension's deep link, which finds no tab for that
session and **opens a new one** (README, *Two tabs instead of one*). The
entrypoint is known at signal time (`X-Claude-Entrypoint: cli`) and in the
session file, so this is a one-line policy.

**Process chains**, read with `ps -o pid,ppid,tty,comm` on live sessions:

| Started from | Chain from `claude` upwards | tty of `claude` |
|---|---|---|
| Terminal.app tab | `claude → -zsh → login → Terminal` | the tab's, e.g. `ttys003` |
| zellij inside a Terminal tab | `claude → zsh → zellij --server …/zellij-<uid>/<version>/<session>` (ppid 1) | a pty of the server's, **not** the tab's |
| the zellij client | `zellij → -zsh → login → Terminal`, on the tab's tty | — |
| VS Code, Claude panel | `claude → Code Helper (Plugin) → Code` | none |
| VS Code, integrated terminal | `claude → zsh → Code Helper → Code` — the pty host lives in `Code Helper.app`, the extension host in `Code Helper (Plugin).app`; the classifier must tell the two apart by the bundle name, not the word "Helper" | the tab's pty, e.g. `ttys004` |

**Titles.** Claude Code sets the terminal title to `✳ <conversation title>` (the
`ai-title` record of the transcript, e.g. `✳ Wire the release script`). Terminal.app
shows it as `you — ✳ Wire the release script — python ◂ claude … — 80×45`; inside
zellij the session name comes first: `you — quiet-owl | ✳ Wire the release script — zellij — 121×51`.

**What each host exposes**, read from the bundles, no permission needed:

| Host | How a tab can be found | How it is raised | Source |
|---|---|---|---|
| Terminal.app | `tty of tab` (`Terminal.sdef`, property `tty`, read-only) | `set selected tab of window w to t`, `set frontmost of w to true`, activate | AppleScript → needs Automation → Terminal |
| iTerm2 | `tty of session` (`iTerm2.sdef`, property `tty`) | `select` tab and session, activate | AppleScript → Automation → iTerm2 |
| Ghostty | `terminal` has `name` (current title) and `working directory`; no tty | command `focus` ("Focus a terminal, bringing its window to the front"), `select tab` | `Ghostty.sdef` → Automation → Ghostty |
| WezTerm | `wezterm cli list --format json` → panes with `tty_name`, `pid`, `tab_id`, `window_id` | `wezterm cli activate-pane --pane-id N`, then activate the app | bundled CLI, no permission |
| kitty | `kitten @ ls` → windows with `pid`, `foreground_processes`; **only with remote control enabled** (`allow_remote_control` + `listen_on`) | `kitten @ focus-window --match pid:<shell pid>` | bundled CLI; without remote control, title match through System Events |
| tmux | `tmux list-panes -a -F '#{pane_tty} #{pane_pid} #{session_name}:#{window_index}.#{pane_index}'`; `tmux list-clients -F '#{client_tty} #{client_pid} #{client_session}'` | `select-window`, `select-pane`, then the client's tab by its tty | CLI |
| zellij 0.45 | server socket path ends with the session name; `zellij --session <name> action list-clients` works from outside but gives no tty | the tab whose title contains the session name (zellij writes it there) | CLI + title |
| VS Code | as today: the window by folder title | as today; **no deep link** for `cli` | System Events |

`lsof` cannot pair a zellij client with its server on macOS: both sides print
peer addresses (`->0x…`), never their own, so the sets do not intersect. The
title route is the honest one.

**Session files.** `~/.claude/sessions/<pid>.json` for a terminal session carries
`entrypoint: "cli"`, `kind: "interactive"`, `name: "<folder>-xx"` (derived, not
the title), `procStart`, and — for `cli` only — `status`, which has only ever
been seen as `idle` and stays unused (Contracts, `remote.sessions`). The file
gives the **pid**, which is what the click needs; the hook payload has no pid.

**Noise, measured.** Two terminal sessions live in the home folder right now,
both `cli`, one driven through a python wrapper (`python ◂ claude` in the title).
They are sessions a person is sitting in front of; they deserve a row. The
`sdk-cli` observers do not and are already excluded by `nonInteractiveEntrypoints`.

---

## 1 · The decision to record — D25 · A folder nobody claims is a place too

**Decided (proposed).** With "Show terminal sessions" on, a local interactive
session whose `cwd` no editor window claims gets a row of its own, with the
folder as its workspace — the same rule D24 adopted for other machines, brought
home. The row is born when the session speaks (hook) **or** is adopted from the
session file (like editor sessions, unlike remote ones: the pid is verifiable
here with `kill(0)`, so silence is not ambiguity). It leaves when the process is
gone. A click **follows the process, not the folder**: the session's pid is read
from its file, the process tree is walked to the hosting application, and that
application's own way of selecting a tab is used. Off by default (D8: the first
click asks for an Automation permission per terminal app).

**What does not change.** A session whose `cwd` is inside an open folder is still
attributed to that editor window, however it was started. Grouping is still by
folder; two terminal sessions in `~` are one row with two sessions, and the click
opens the most urgent one's tab. Slots, order, hide, mute, calm, chat window —
all unchanged. Remote rows unchanged.

**What changes for everyone**, toggle or not: the tab deep link is sent only for
sessions whose entrypoint is `claude-vscode`. For a `cli` session in an editor
window the click raises the window and stops there.

**Label.** A row holding **one** terminal session with a known conversation title
is labelled by that title; otherwise by the folder name, as today. The title is
what the person sees in their terminal's title bar, so it is the name they will
look for; the folder name of `~` is a username and says nothing. A small terminal
glyph precedes the name in expanded mode, the way `@host` follows a remote one.

**Discarded:** making the terminal tab part of the workspace identity (a row per
tab). It would split the folder rows people have already placed and ordered, and
the click resolves the tab anyway. **Discarded:** a row only when it speaks, as
for remote hosts. Turning the toggle on and seeing nothing until the next turn
would read as "it does not work"; locally the pid check makes adoption safe.

---

## 2 · The pieces

Core, pure, under the domain suite:

- `ProcessAncestor { pid, ppid, executablePath, ttyName }` and `Seat`:
  `.terminal(TerminalKind, tty:)`, `.tmux(tty:)`, `.zellij(sessionName:)`,
  `.editor(IDEKind)`, `.application(path:)`, `.unknown`. `SeatClassifier.classify(_ chain: [ProcessAncestor]) -> Seat`
  walks the chain and answers from a table — tested against fixtures of every
  chain in §0.
- `TerminalKind` — a short table like `IDEKind`: bundle id, process name for
  System Events, and a `raising` strategy (`appleScriptTTY`, `appleScriptTitle`,
  `wezterm`, `kitty`, `activateOnly`). Deliberately short, for the same reason.
- `TerminalScripts` — AppleScript sources for Terminal, iTerm2 and Ghostty as
  functions of a tty / title / cwd, through `AppleScriptString.escaped`. Tests
  check shape and escaping; running them is a live check (§4).
- Parsers: `TmuxListing` (panes, clients), `WezTermListing` (JSON), `KittyListing`
  (JSON), `ZellijSocketName` (last path component of the `--server` argument).
- `TerminalTitleMatcher` — finds `✳ <title>` and `<zellij session> |` in a list of
  window or tab titles; the VS Code matcher stays where it is.
- `TranscriptTitleScanner.title(in:)` — the first `ai-title` line within the first
  512 KB of a transcript; `TranscriptDecoder` already knows the record.
- `SessionState` gains `entrypoint: String?` and `title: String?`; `SessionSnapshot`
  gains both (additive to `/sessions`). `ColumnRow.displayName` implements the
  label rule. `DeepLinkPolicy.opensTab(entrypoint:)` is the one-line rule of §1.
- `TrafficLightState`/reducer: an `.adopt` and a `.signal` with a workspace the
  resolver did not produce are already representable; what is new is *who*
  produces the workspace (StateStore), not the state machine.

App:

- `ProcessTree` — `sysctl(KERN_PROC_PID)` → `kinfo_proc` (`e_ppid`, `e_tdev` →
  `devname`), `proc_pidpath`; walk up to twelve levels. Pid reuse guard: the
  session file's `procStart` against `p_starttime`, the same idea as the remote
  probe's field 22.
- `SeatResolver` — session id → pid (`LiveSessionReader`) → chain → `Seat`, at
  click time only; nothing is cached.
- `TerminalFocuser` — one strategy per `TerminalKind` plus tmux and zellij hops,
  returning the existing `FocusResult`. New `FocusError.automationDenied(app:)`
  naming the exact pane: *Privacy & Security › Automation › clawd-light › Terminal*.
- `SessionTitleReader` — reads the title once on adoption or first hook, again on
  `Stop` while it is still unknown.
- `Preferences.showsTerminalSessions` (`terminal.sessions`, default `false`); menu
  item "Show terminal sessions"; a "Terminal sessions" section in Settings with
  the sentence that explains the permission; CLI `terminal on|off|status`.
- `StateStore.handle`: resolver returns `nil`, toggle on, `signal.deservesTrafficLight`
  → `Workspace(path: cwd)`, log `adopted as a terminal session`. `poll()`: adopt
  unclaimed local live sessions under the same rule; prune as today.
- `PanelController.activate`: local session → `SeatResolver`; `.editor` → today's
  path with the deep-link policy; a terminal seat → `TerminalFocuser`; pid gone →
  title match across running terminal apps → else a menu message, no alert (the
  session may have ended between two polls, which is normal).
- `TrafficLightRow`: glyph; "New conversation here" hidden for terminal rows
  (there is no tab to open one in); "Read here…" and ⌘-click stay — the
  transcript is local.

---

## 3 · Phases

Each phase ends green (`Scripts/test.sh`, `check-docs.sh`, `check-contract.sh`),
documented, committed. Tests first.

**A · The click that opened two tabs** — about an hour.
`SessionState.entrypoint` from hook header and session file; `DeepLinkPolicy`;
`PanelController` uses it. Tests: reducer keeps the entrypoint across
transitions; policy table; E2E `/sessions` carries `entrypoint`. Docs: README
caveat rewritten, `SessionsPayloadSuite`.

**B · The row** — half a day.
Preference, menu, Settings section, CLI; `StateStore.handle` and `poll()` rules;
`SessionTitleReader` and `title` in state and payload; label rule; glyph.
Tests: *an unclaimed folder becomes a workspace when terminal sessions are on*,
*stays dropped when off*, *an `sdk` session stays out either way*, title scanner
(first line wins, none within the window → nil, malformed line skipped), label
rule (one session with title → title; two → folder; no title → folder). E2E:
`terminal on`, hook with entrypoint `cli` and a `cwd` under no lock → row present,
`terminal off` → absent; `writeLiveSession(entrypoint: "cli")` outside any lock →
adopted; `/sessions` shows `title`. Docs: D25, 01-architecture "Terminal sessions",
README section, Contracts `terminal.title`.

**C · The click, Terminal.app and iTerm2** — half a day plus live checks.
`ProcessTree`, `SeatClassifier`, `TerminalKind`, `TerminalScripts`, `SeatResolver`,
`TerminalFocuser` for the two tty hosts and the `.editor` seat. Tests: classifier
fixtures for every chain in §0; script builders; pid-reuse guard. Live protocol
in §4. Docs: 03-macos (one Automation entry per terminal app; `sdef` is how to
know what an app exposes), traps as found.

**D · Multiplexers** — two to three hours.
tmux: pane by the claude's tty → `select-window`/`select-pane` → client tty →
phase C on the client's tab. zellij: session name from the server's `--server`
argument → tab whose title contains it. Tests: listing parsers, socket name,
title matcher. Live: a tmux session inside a Terminal tab; the zellij session
already running.

**E · The other three, and the fallback** — two to three hours.
Ghostty by `name` + `working directory` and `focus`; WezTerm by `tty_name` and
`activate-pane`; kitty by `kitten @ ls` when remote control answers, else title.
Generic fallback for an unknown chain: activate the application owning the
topmost GUI ancestor (`open -b`, bundle id from the executable path) — the row
is still honest about where it leads. Live: one `claude` in each, launched from
a test config (kitty needs `allow_remote_control socket-only` and
`listen_on unix:/tmp/kitty` in a config passed with `--config`).

**F · Closing** — two hours.
05-code-map figures, `check-docs`, Contracts entries (`terminal.title`,
`terminal.sdef`, `zellij.socket`, `sessions.file.pid`), README requirements
(which terminals, which permission), traps.

Order of value: A alone removes a daily annoyance; A+B+C cover the two hosts in
actual use here (Terminal.app, zellij via its Terminal tab in D). E is coverage
for other people's setups and is the first thing to cut if time is short.

---

## 4 · Live verification protocol

Domain tests prove the pure parts; the click cannot be proven without a GUI and
a permission, so each host gets the same manual check, recorded in the commit:

1. Open two tabs in the host; in the second, `cd` somewhere no editor has open
   and run `claude`; ask it anything so the title appears.
2. Enable "Show terminal sessions". The row appears with the conversation title.
3. Switch to another application. `clawd-light open <slot>` from a third terminal
   — the same path as a click, without a synthetic mouse.
4. Expected: the host comes to the front with the **second** tab selected. Check
   with the host's own dictionary or CLI (`osascript -e 'tell application
   "Terminal" to get tty of selected tab of front window'`; `wezterm cli list`;
   `kitten @ ls`), and with the log line `seat: <host> <tty|title> raised`.
5. First run per host: the Automation prompt appears; deny once and confirm the
   menu message names the right pane.

The hosts needed are installed on the development machine (Homebrew, 2026-08-27):
tmux 3.7c, iTerm2, kitty 0.48, WezTerm 20240203, Ghostty; zellij 0.45 was
already there and is the one in daily use.

---

## 5 · Risks, stated

- **Automation prompts multiply.** One per terminal app, at the first click. The
  toggle being off by default (D8) keeps them from appearing unasked.
- **Title matching is the weak leg.** It is used only where nothing better exists
  (zellij tab, kitty without remote control, an unknown host) and the fallback
  is "activate the app", never "raise a wrong tab".
- **Home-folder rows.** Several terminal sessions in `~` collapse into one row
  labelled by the folder — a username. Ungrouped mode shows one row per session
  with its title; the label rule cannot do better for a group without lying.
- **Sessions started by tools.** A wrapper that runs `claude` interactively gets a
  row; it is a session someone is in front of. `hide` covers the rest.
- **VS Code's integrated terminal** stays a window-level target: there is no API
  to select a terminal tab from outside. The row is attributed to the window as
  today, and the deep link stops opening a second tab — that is the whole fix.
- **Pid reuse.** Guarded by `procStart`; without the guard a dead session's pid
  could point the click at an unrelated process.
