# clawd-light

A floating column of traffic lights that tells you, at a glance, what state your
Claude Code sessions are in — in VS Code, in a terminal, on another machine. One
traffic light per project. You click it and you're in that window, or that tab.

It comes from a concrete problem: with a dozen VS Code windows open, finding out
which one is waiting for an answer and which one is still working means going
through all of them.

> **Need to get your hands dirty?** The complete technical documentation lives in
> **[docs/](docs/)**. If you only have time for one file, read
> [docs/07 traps](docs/07-traps.md): it is the catalogue of defects already paid
> for, and each one is a day you won't have to spend again.

## The states

| Color | State | Meaning |
|---|---|---|
| 🟠 blinking amber | `awaiting` | Claude is waiting for an answer from you — a permission, or a dialog opened by an MCP server. It is the only state that blocks the work, and the only one that blinks. |
| 🟢 green | `ready` | The turn has finished: there is an answer to read. |
| 🔴 solid red | `failed` | The turn stopped without producing anything: rate limit, overload, authentication error. |
| 🟡 yellow | `working` | Claude is processing or running tools. |
| 🔵 soft blue | `waiting` | The turn is over, but something Claude started is still running — a shell, a monitor on a CI run, a subagent — and will wake it. Nothing for you to do yet. |
| 🔴 dim red | `idle` | The session is at rest. Nothing to read. |

The table is in order of urgency; the column is not — rows keep the order **you**
gave them, and a state lights a row up where it is. Green does not
mean "all good", it means "there is something you haven't seen yet". Clicking the
traffic light returns the session to dim red: you've seen it.

Blue is the one state that says *neither* "working" nor "done". Before it existed,
a session that had stopped and was waiting an hour for a CI run stayed yellow the
whole hour — and yellow reads as "Claude is thinking". The tooltip says what the
row is waiting on: `waiting on monitor ×2, shell`.

`failed` and `idle` share the hue and are told apart by brightness and glow — the
same grammar the palette uses for urgency, so the difference reads in compact
mode too, where there is no text. It sits **below** `ready` because a ready answer
is consumed at once, whereas there is nothing you can do about a rate limit until
it expires.

## The right-hand slot

It doesn't always show the same thing, because the useful information isn't always
the same:

| State | Shows | Why |
|---|---|---|
| `working`, `waiting` | `42m`, `7h` | On a working or waiting session what counts is *how long*: `7h` on a yellow reads in half a second, `08:14` has to be computed |
| `failed` | `rate limit`, `auth`, `billing` | What counts is *why* it died, not when |
| the others | `14:49`, `yesterday`, `2d ago`, `22/07` | The time of the last activity |

The time thresholds reason in calendar days: at 00:30 an event from 23:50 is
"yesterday", not "40 minutes ago". The full timestamp stays in the tooltip in
every case. The click does not update that timestamp: it records Claude's
activity, not yours.

With grouping off, the sessions of one project share its place: the most urgent
comes first, then the one waiting longest — never the alphabetically luckier name.

A badge can appear next to the name: `×3` is the number of **subagents** at work
in that session, `3` is the number of **sessions** collected into that row. The first wins when both apply, because it explains *why* the row is yellow — or
blue, once the parent turn has stopped and only the agents are left.

## One row per project

The number that decided the project: 22 distinct sessions across 12 windows. One
row per session drew 22 targets for 12 raisable windows, and ten of those targets
led where another already led.

The dot shows the **most urgent** state in the group, and the click opens the most
urgent session — not the most recent. If in one project one is waiting for a
permission and another has finished, it takes you where something is blocked.

The click marks as seen **only the sessions that were in the most urgent state**.
Without this limit, grouping would be a loss: you open the project for the
permission, and the other session's ready answer disappears without your having
read it.

You can switch it off from the menu (`One row per project`) if you prefer one row
per session.

## What to show and what not to

Right-click **on a row**:

| Entry | What it does |
|---|---|
| Read here — opens the conversations | the extended view on this conversation (same as ⌘+click); not offered for a session on another machine |
| Open | same as the click |
| Open without marking as read | same as alt+click |
| Mark as unread | remedies one click too many |
| Move up / Move down | the drag, in words |
| Rename… | the name you want to read; the session, its window and its folder keep theirs — leave it empty to go back |
| Hide | the row is collected into the summary |
| Don't blink | stops the movement, **not** the color |
| Don't alert me for this project | silences the notifications, **not** the color |
| New conversation here | opens a new Claude tab in the project |

One click is enough, even when you are working in another window: the panel
makes itself key before the click is dispatched, so the first click is delivered
rather than spent on focus. A double-click counts as one — the second click is
dropped.

Click the **gear** under the rows — or right-click **on the panel's margins** —
for the general menu: compact mode,
grouping, the "only what's waiting" filter, terminal sessions, notifications,
presence, hooks, launch at login — and **Settings…**, the window for what does
not fit a menu: the remote machines and the terminal-sessions switch.

**Hidden projects don't disappear.** They are collected into a summary row that
**lights up** when one of them asks for attention. That is not an aesthetic
detail: without it, "hide" would become "forget", which is precisely the harm this
panel exists to prevent. A click on the summary brings them all back into the
column.

The filter says what it is keeping out too (`and 7 more with nothing new`): a
column with two rows must not suggest there are only two sessions.

## When you're not looking

Two features, both **off by default**. Neither turns itself on. Notifications ask for their system permission only at
the moment you enable them; presence needs no permission, only the environment
variable below.

**Notify when a session gets blocked.** Only `awaiting`, never `ready`. That
distinction is the whole feature: a ready answer can wait until you look at it, a
permission cannot — until you answer, that work is stopped. With a dozen sessions,
notifying on green too would produce tens of alerts a day, and a channel that
alerts too often gets switched off within two days: at that point the real blocks
would stop arriving as well. Clicking the notification takes you **to that
session**.

What suppresses an alert is only what you asked for: the memory that avoids
duplicates, the per-project silence, and the timed one. A presence condition used
to be there too — no alert if the panel is visible and you touched the Mac
recently — and it was removed in the face of the evidence: the panel is floating,
so it is always on screen, and if you're at the Mac you're active. The result was
a feature you switched on and nothing ever arrived.

### Keyboard shortcuts

clawd-light does **not** register a global combination, and that is a choice: on
macOS 26 the only mechanism that requires no extra permissions
(`RegisterEventHotKey`) registers without errors and **never delivers** the
events, and the app has no way of noticing. A switch that can lie is worse than a
switch that isn't there.

The actions, though, do exist:

```bash
clawd-light next       # raise the next waiting session
clawd-light open 3     # raise whatever holds slot 3
clawd-light new 3      # open a new conversation in slot 3's project
clawd-light chat 3     # open the extended view on slot 3
clawd-light open       # list what the slots address
```

To bind one to a key, using the macOS **Shortcuts** app:

1. Shortcuts → **new shortcut** → the "Run Shell Script" action
2. paste the full path:
   `<your-checkout>/dist/ClawdLight.app/Contents/MacOS/clawd-light open 1`
3. **Details** panel on the right → "Add Keyboard Shortcut"

It is better than having it inside the app on three counts: you pick the
combination, the interface tells you straight away whether it is already taken,
and when it doesn't work **you can see it**. The same goes for Raycast, Alfred or
Karabiner, if you already use them.

#### The order is yours

The column **never reorders itself**. A project seen for the first time is
appended at the bottom, and from then on it moves only when you move it: drag a
row by its handle (≡, on the right), or right-click → **Move up / Move down**. A
row that needs you lights up where it is. The eye learns the column once, and a
row never slides under the pointer between two clicks.

#### Slots — one key, always the same project

The first nine rows are slots 1 to 9: the number appears next to the name, and
`clawd-light open 3` raises whatever sits third. Because the column keeps your
order, the third row is the same project tomorrow — and a shortcut you press
without looking has to be right every time. A project with no live session keeps
its place; its slot is simply empty until it has one.

`clawd-light open <n>` answers in three distinct ways, because a key pressed
blind has to tell them apart:

| | |
|---|---|
| exit 0 | raised, and it prints what |
| exit 1 | that slot is empty — nothing is bound, or the project has no live session |
| exit 2 | that isn't a slot number |

It never opens the neighboring row when a slot is empty. For a key you press
without looking, opening the wrong project is the worst thing it could do.

## The extended view

It opens on the **tail** of the conversation — the last three hundred entries,
read from the last few megabytes of a transcript that can be half a gigabyte —
and a note at the top says when the beginning was left on disk. Opening it takes
well under a second whatever the file's size (07-traps, *The window that read the
whole file*).

The panel is the resting state: a column of traffic lights that never takes focus.
When you want to read and answer, open the **extended window** — conversations on
the left, the selected one on the right. Close it and you are back to the lights.

Three ways in: the panel menu → **Open the conversations…**, **⌘+click** on a row
(which lands on that conversation), or:

```bash
clawd-light chat 3
```

The list shows, for each project, its light, its slot, and **the last thing
actually said** — yours or Claude's, read from the transcript rather than from the
hooks, because the hook value is only ever Claude's side and on an interrupted
turn it holds the error text.

Answers are drawn as they were written: headings, lists, tables, quotes, and code
blocks that **scroll sideways instead of wrapping** — a wrapped command line
cannot be copied and pasted, and copying things out of this window is most of why
it stays open.

### Writing back

**Off by default.** Turn it on from the panel menu → *Let the panel answer your
sessions*. Until you do, the window reads and nothing else — no listener, no
mailbox, nothing that can start a turn in your name. The dialog says why before
you agree to it.

With it on, there is a composer, and it writes into the session you are looking at — the real
one, running in VS Code, that you have been talking to all along.

```
you type  →  a file in ~/.clawd-light/inbox
          →  a second `Stop` hook, spawned detached, picks it up
          →  its stdout is the message, its exit code 2 is the send
          →  a full turn starts: reasoning, tools, answer
```

Measured end to end: **one second** from writing to the turn starting.

Three things you should know before relying on it, all of which the window tells
you as well:

- **It is not instant when Claude is working.** The message waits on disk until
  the current turn ends. That is deliberate — it is what lets you type *while* a
  session is busy, which a socket could not.
- **A dormant session hears nothing at first.** A listener can only be born at the
  end of a turn, so a conversation that is doing nothing has nobody waiting. The window says *"this conversation is asleep — a message will wait for it, not
vanish"* rather than spinning. Anything you do in
  that session fixes it.
- **The mechanism is undocumented.** `asyncRewake` is `@internal` in Claude Code
  and can be renamed without warning — at which point delivery stops **in
  silence**. `./Scripts/check-contract.sh` greps the shipped binary for it on every
  run. Run it after every Claude Code update.

Your messages appear as your own in this window. Inside the VS Code panel they
will look like system turns, because that is the envelope they arrive in, and
there is no way round it.

### Dictating

There is a microphone in the composer. Press, talk, press again: what was heard
lands **in the box**, not in the session — dictation mishears, and a sentence you
can still edit is a different thing from one already sent.

It runs entirely on the device (`SpeechTranscriber`, macOS 26), so no audio leaves
the Mac. The first press asks for the microphone and downloads the language model,
and the button says which of the two it is doing.

If the language you speak has no model, it says so rather than falling back to
English: the recognizer transcribes everything as the locale it is given, and the
wrong one produces fluent nonsense nothing downstream can detect.

macOS also has its own dictation, which works in this box like it does in any text
field and needs no permission from us at all. If it suits you, use it — turn it on
in System Settings › Keyboard › Dictation.

See [D14](docs/04-decisions.md), [D15](docs/04-decisions.md),
[D18](docs/04-decisions.md) and [Contracts/assumptions.md](Contracts/assumptions.md).

**Suppress phone push notifications while you're at the Mac.** Claude Code skips
the push notifications if the file named by `CLAUDE_CLIENT_PRESENCE_FILE` exists;
the panel creates it while you're there and deletes it when you lock the screen.
This one inverts a built-in behavior, and if the detection gets it wrong the
result is not one notification too many but a notification **lost**. To make it
work:

```bash
export CLAUDE_CLIENT_PRESENCE_FILE="$HOME/.clawd-light/presence"
```

## Sessions on other machines

A session running over ssh on an always-on box used to be invisible: no hook is
registered there, the hook posts to `127.0.0.1`, the server listens on
`127.0.0.1`, and a row needs a local editor window to claim its folder. Four
barriers, all by design — and reading the machine over ssh, the first answer,
gave rows that never changed colour and that a click could not open.

Now the machine's hooks **reach this Mac**. Right-click the panel → **Settings…**,
add the machine under the name ssh knows it by, and press **Install hooks**:
clawd-light writes the hook script and registers it in that machine's
`~/.claude/settings.json` (dated backup, atomic write, refused if the file changed
in between), and keeps a reverse ssh tunnel open so that a loopback port *of your
own over there* — derived from your uid, and checked after every connect to be
bound to loopback and nothing else — is this app. From a terminal:

```bash
clawd-light remote add node         # a name ssh understands; key login only
clawd-light remote install node     # two ssh round trips, nothing else installed
clawd-light remote check node       # python, curl, hooks, and whether the tunnel answers
```

A remote session gets its row when it **speaks** — its first hook arrives through
the tunnel — labeled `folder @host`, and loses it when the machine's probe says
the process is gone. Clicking the row raises the **Remote-SSH** window of that
folder here, if one is open (`… — folder [SSH: host]`); otherwise the menu says
where the session is. The chat window cannot open a remote transcript.

The machine needs ssh key login (no password prompt is possible), `python3` and
`curl`. The tunnel is restarted with backoff when the machine sleeps or the VPN
drops; the Settings window shows its state and the outcome of every operation.
Hosts were read from `~/.clawd-light/remotes` before; that file is imported once
and no longer consulted. See
[D24](docs/04-decisions.md#d24--other-machines-are-heard-through-a-tunnel-we-open).

## Sessions in a terminal

Off by default. `Show terminal sessions` (panel menu, Settings, or `clawd-light
terminal on`) gives a row to every `claude` started by hand in a folder no editor
window has open — Terminal, iTerm2, Ghostty, a tmux or zellij pane. The row is
named by its conversation title, carries a small terminal glyph, and is anchored
on the folder the session **started** in: the hook's folder follows every `cd`
Claude makes, the session file's does not. It exists only while
`~/.claude/sessions/` has a live file for it, and turning the switch off takes
those rows away at once.

Clicking a terminal row takes you to the **tab** hosting the session — found
through the session's process, never by guessing a window title:

| Where `claude` runs | How the tab is found | What it needs |
|---|---|---|
| **Terminal.app** | by tty, through Terminal's dictionary | Automation → Terminal, asked once |
| **iTerm2** | by tty, through iTerm2's dictionary | Automation → iTerm2, asked once |
| **Ghostty** | by the conversation title, the folder, or Claude's own `✳` mark when only one terminal carries it | Automation → Ghostty, asked once |
| **WezTerm** | by tty, through `wezterm cli` | nothing |
| **kitty** | by pid, over kitty's remote-control socket | `allow_remote_control yes` and `listen_on unix:/tmp/kitty` in `kitty.conf`; without them the click activates kitty and the menu says why |
| **tmux** pane | the pane is selected inside tmux, then the attached client's tab as above | nothing |
| **zellij** pane | the client is paired with its server, then its tab as above; the pane inside zellij is yours to find | nothing |
| VS Code's integrated terminal | the session belongs to that window (see below) | as any editor row |

Two limits, stated. A `claude` in a terminal tab **inside a folder that is open
in VS Code** is an editor row like any other — same project, same window — and
its click raises the VS Code window. And a `claude` started from a shell that a
Claude Code session opened (a nested one) writes no session file, so it gets no
row.

Rows can be **renamed** (right-click → Rename…, or `clawd-light rename <folder>
[name]`): the name is what the panel shows, by folder, and nothing else changes —
the window is still found by its title, `/sessions` still says the folder. Leave
the name empty to go back to the original.

## Installation

You need macOS 14 or later — **macOS 26 for dictation**, which uses the on-device
Speech framework that arrived there — and Xcode's Command Line Tools
(`xcode-select --install`), which ship the Swift 6.2 toolchain. Full Xcode is not
required.

```bash
./Scripts/build-app.sh
open dist/ClawdLight.app
```

On first launch the app offers to register the hooks in
`~/.claude/settings.json`. You can also do it from a terminal:

```bash
dist/ClawdLight.app/Contents/MacOS/clawd-light install-hooks
```

Existing hooks are preserved and a dated backup copy of the file is created.
Claude Code sessions that are **already open** pick up the new configuration only
when they restart.

### Permissions

On the first click on a traffic light, macOS asks for **two distinct
authorizations**, granted in two different panes:

- **Privacy & Security › Accessibility** — to raise the exact VS Code window
- **Privacy & Security › Automation › clawd-light › System Events** — to read the
  window titles
- **Privacy & Security › Automation › clawd-light › Terminal / iTerm2 / Ghostty**
  — one entry per terminal application, asked at the first click on a row of
  a session running there (only with *Show terminal sessions* on). WezTerm and
  kitty are driven through their own CLIs and ask for nothing.

Both of the first two are needed. Without them the click falls back to `open -b`: VS Code still comes to the
front, but the right window is not raised.

> **It has to be re-authorized after every rebuild.** The bundle is ad-hoc signed,
> and the signature changes on every build: macOS considers it a different app and
> the previous authorization no longer counts, while still showing the switch as
> on. If the app is already listed but the permission doesn't work, select it,
> press "−", and add it back from `dist/ClawdLight.app`.

**To never do that again**, once and for all:

```bash
./Scripts/create-signing-identity.sh   # asks for your keychain password
./Scripts/build-app.sh
```

It creates a self-signed certificate in the user keychain: the signing requirement
hooks onto the identity instead of the binary's hash, and the authorizations
survive rebuilds. No administrator privileges, no system modifications; at the
bottom of the script there is how to undo everything. It is also the prerequisite
for launch at login, which with an ad-hoc signature stays **blocked** — it would
leave an orphaned record in Settings on every build.

`clawd-light status` shows the state of the two permissions separately.

### Giving it to somebody else

```bash
./Scripts/release.sh            # dist/ClawdLight-<version>.dmg
```

The version comes from the git tag, so a disk image cannot carry a number no
commit has. The script has three outcomes and tells you which one you got,
asking Gatekeeper here before the file leaves:

| What is in the keychain | What comes out |
|---|---|
| the local certificate only | a disk image **macOS refuses** on any other Mac. A tester gets in with right-click on the app › Open, knowingly |
| a Developer ID certificate | a signed disk image, **still refused** the first time on a Mac that has never seen it: signing is not what lifts that |
| Developer ID + a notarization profile | signed, notarized, stapled — it opens with a double click |

The last one needs the Apple Developer Program, and two things from you once:
the **Developer ID Application** certificate, and a notarization profile in the
keychain, built from an app-specific password made at appleid.apple.com.

```bash
xcrun notarytool store-credentials clawd-light \
    --apple-id you@example.com --team-id TEAMID --password <app-specific>

export CLAWD_LIGHT_SIGNING_IDENTITY='Developer ID Application: … (TEAMID)'
export CLAWD_LIGHT_NOTARY_PROFILE='clawd-light'
```

Neither belongs in this repository, so the script reads both from the
environment; with a single Developer ID in the keychain it finds it on its own.
Notarization is what forces the **hardened runtime**, which by default takes
away exactly the two things this app does for a living — Apple Events and the
microphone — so the script signs it with the two entitlements that give them
back, and nothing else.

> If the click stops working, the first thing to check isn't the permission: it is
> **how long the app has been running**. A new bundle does not replace the process
> already running, and a build that is an hour old is indistinguishable from a
> revoked permission. `pkill -x clawd-light; open dist/ClawdLight.app`

## How it works

Two independent sources, because neither is enough on its own:

```
  what happens                        who exists right now
       │                                     │
Claude Code (hooks)                 ~/.claude/sessions/<pid>.json
       │                                     │  every 5 s, kill(pid, 0)
   hook.sh                                   │
       │                                     │
POST 127.0.0.1:9877/signal ──────┐   ┌───────┘
                                 ▼   ▼
                            state machine
                                  │
                     ~/.claude/ide/*.lock → workspace
                                  │
                        column of traffic lights
```

**The signal.** Claude Code exposes thirty-one lifecycle events. Nine are
needed: six at the edges of the turn — `SessionStart`, `UserPromptSubmit`,
`Notification`, `Stop`, `StopFailure`, `SessionEnd` — plus `SubagentStart`,
`SubagentStop`, and `PostToolUse`, the one in-turn heartbeat, which is there for
a single reason: it is the only event that can prove a permission prompt was
answered. A shell script of some twenty lines forwards them to the local server and
**always exits 0**: a failing hook can interrupt a Claude Code turn, and nobody
wants their work to stop because a widget wasn't running.

The two subagent events cost in proportion to the **number of agents**, not to
tool calls: a thirty-three agent workflow is sixty-six requests over three
quarters of an hour, against the thousands `PreToolUse` would produce.

With `--with-tool-events` you also register `PreToolUse`. It makes the yellow
move on every tool call rather than every completed one, at the cost of one more
process per **single tool call** — and it cannot release a pending question, since
it runs *before* the prompt, not after the answer.

**The workspace.** The hook only reports the `cwd`. To work out which window hosts
it, the app reads the lock files the extension drops in `~/.claude/ide/`, one per
window, with `workspaceFolders` inside. The match is by longest prefix, comparing
path components rather than strings: `/dev/project-old` must not come out as
inside `/dev/project`. If no window contains that `cwd`, the session belongs to no open editor: it is
ignored — unless *Show terminal sessions* is on, in which case the folder it
started in becomes its place (see 'Sessions in a terminal').

**It doesn't matter how you started the session, it matters where it runs.**
`claude` launched from VS Code's *integrated* terminal sits in the same window and
the same project, and deserves the same traffic light. The only filter left excludes what isn't interactive — the `sdk*` entrypoints,
`print`, and a session file whose `kind` is not `interactive` — because there
nobody is waiting. It is a **deny**-list, not an allow-list: when it's wrong it shows one
row too many, a mistake you can see and fix, instead of hiding one, which stays
silent.

**Cursor too.** The name in the lock is `vscode.env.appName`, and VS Code forks
write their own into it: discarding them was not a choice, it was a side effect of
the check on the name. The table of recognized editors is deliberately short —
only the ones whose declared name, bundle identifier and process name are known,
and whose window title follows VS Code's format.

**Who exists right now.** The hooks report what *happens*, never what disappeared
or what was already there. That's why every 5 seconds the app reads
`~/.claude/sessions/`, where Claude Code writes one file per process with the PID
in the name, and checks liveness with `kill(pid, 0)` — a syscall that sends no
signal, it only asks the kernel whether that process exists. It serves two
purposes:

- **dead rows disappear**: close a Claude panel and the row goes within 5 seconds,
  instead of staying clickable for hours pointing at nothing;
- **the column is full at startup**: sessions already open are adopted as `idle`
  with the timestamp taken from the file, instead of staying invisible until you
  do something in that window.

An empty set is ignored: it almost always means the read failed, not that every
session vanished at once.

**The subagents, and why the state is derived.** With background agents the real
sequence is: `SubagentStart` ×N → `Stop` (the parent turn returns control) → *the
agents work for tens of minutes* → `SubagentStop` ×N.

Taking that `Stop` literally paints green — "there is an answer to read" — onto a
session that is still working. So the displayed state is not the one the hooks
wrote, it is **derived**:

```swift
public var status: SessionStatus {
    guard activeSubagents > 0 else { return baseStatus }
    switch baseStatus {
    case .awaiting: return .awaiting
    case .working: return .working
    case .ready, .idle, .waiting, .failed: return .waiting
    }
}
```

It follows on its own that when the last agent finishes, the green set aside
resurfaces without anyone having to remember it. Waiting for a permission wins
regardless: it blocks everything.

The counter resets at the **next prompt**, not at the end of the turn — it is a
certain boundary, and it doubles as a safety net if a `SubagentStop` gets lost
along the way.

**Getting back to the window.** VS Code exposes no AppleScript dictionary, so the
only handle is the window title, which has the form
`<context> — <folder> — <profile>`. Recognition lives in Swift rather than inside
the AppleScript script, so it is verifiable without opening windows: it scores the
titles and raises the winner. If the Accessibility permission is missing, the
fallback is `open -b <bundle>` **with no path**: it brings VS Code to the front
without being able to create windows.

**The right tab, not just the window.** Once the window is raised, the click can
also open the Claude tab of that precise session. The extension registers a URI
handler for `/open` that reads the `session` and `prompt` parameters — verified by
reading `extension.js` of 2.1.220:

```js
case "/open": {
  let w = x.get("session"), E = x.get("prompt");
  executeCommand("claude-vscode.primaryEditor.open", w, E);
}
```

Hence `vscode://Anthropic.claude-code/open?session=<id>`.

Two cautions, because it is an extension's **internal** contract and not a public
API. First: the deep link fires **only once the right window is already in front**,
never as a fallback — the extension opens it in whichever window has the focus,
and if that were the wrong one, not finding the session there, it would open a new
tab for it. For the same reason it is never sent for a session the extension did
not start — `claude` typed in the integrated terminal has no tab to find, and the
link would open one on every click; the entrypoint the hook reports decides.
Second: there is a switch in the context menu, so if a future version
changes the contract there is no need to recompile. It is **off by default**,
because VS Code asks for confirmation on every invocation. If it stops working,
the click still takes you to the right window.

## Non-obvious choices

**Red is dim.** With a dozen sessions the column spends most of its time entirely
red. If rest shouted as loudly as green, the eye would stop distinguishing the
state that matters.

**Only amber blinks.** Blinking is a scarce signal: spent on several states it
signals nothing at all.

**Green resists late signals.** After `Stop`, a `PostToolUse` from the turn that
just closed can arrive. Without an explicit rule the traffic light would go back
to yellow and the ready answer would go unnoticed. A new `UserPromptSubmit`, by
contrast, does return it to yellow: it means you read it and started again.
`failed` is the exception — it clears on click like the others, but it does **not**
resist a restart: if the turn resumes after an error, yellow is the correct
information and red would be a leftover.

**Four events that stated falsehoods, and what became of them.**

| Event | Before | Now |
|---|---|---|
| `StopFailure` | `ready` (green) | `failed`. A turn cut short by a rate limit produced nothing to read: showing it green like a completed turn was the most expensive lie in the column. The only exception is `max_output_tokens`, where the text exists and is merely incomplete |
| `Notification(idle_prompt)` | `ready` (green) | nothing. It is an inactivity timer, not an answer: it invented answers that never arrived. If it does reveal a session the app didn't know about, it creates it as `idle` |
| `SessionStart(source: compact)` | `idle` (red) | nothing. Auto-compact fires **mid-turn**: treating it as the start of a session cleared the yellow of a working session and sank it to the bottom of the column |
| `Notification(elicitation_dialog)` | ignored | `awaiting`. An MCP dialog blocks the session as much as a permission request |

**Yellow expires.** The periodic cleanup exempted `working` unconditionally — the
rule was "a long turn is not a dead session". But `Stop` **doesn't fire if you
interrupt a turn with Esc**, and no other hook covers it: every interruption left
a yellow row behind forever. The threshold now applies to every state. If it gets
it wrong, the damage is bounded: on the next signal the reducer recreates the row.

**Subagents have no traffic light, but they count.** They work inside the parent's
turn, so their signals — recognizable by `agent_id` — are discarded.
`SubagentStart` and `SubagentStop` are the exception: they carry `agent_id` too,
but they don't report the subagent's *work*, they report that the subagent
**exists**, and that is a fact about the parent's turn.

**The panel is `nonactivating`.** Without it, clicking a traffic light would
activate clawd-light and take the focus away from VS Code an instant before giving
it back, with a visible flicker on every click.

**The server listens only on 127.0.0.1, and the constraint is explicit.** For a
while the code relied on `NWParameters.acceptLocalOnly`, which looks like it says
"this machine only" and actually says "this network link only": `lsof` showed
`TCP *:9877 (LISTEN)`, that is, a socket reachable by anyone on the Wi-Fi. Now
there is `requiredLocalEndpoint`, and an end-to-end test queries `lsof` against
the live process to verify the fact instead of the intention.

**`GET /sessions` wants a token, `POST /signal` doesn't.** The read endpoint
exposes the names and paths of the open projects, which on a development machine
are information: without a token any local process could read them, including the
Claude Code sessions themselves. The one that *receives* the signals stays open,
and that is a choice: the hook script could read the token, but a hook that fails
authentication would block a Claude Code turn for the sake of a decorative widget.
The risk is asymmetric and so is the treatment.

## Commands

```
clawd-light                          start the panel
clawd-light install-hooks            register the hooks in ~/.claude/settings.json
clawd-light install-hooks --with-tool-events
clawd-light uninstall-hooks          remove the registrations (the script stays on disk)
clawd-light status                   configuration and detected sessions
clawd-light selftest                 check the whole chain and report what's missing
clawd-light sessions                 the column as the running app sees it
clawd-light terminal on|off|status   rows for claude started in a terminal
clawd-light rename <folder> [name]   the panel's word for a row; no name restores it
clawd-light remote [list|add|install|check|uninstall|remove] [host]   another machine's sessions (see above)
clawd-light next                     raise the next waiting session
clawd-light open <n>                 raise the project bound to slot n
clawd-light open                     list what the slots address
clawd-light new <n>                  open a new conversation in slot n's project
clawd-light chat <n>                 open the extended view on slot n
clawd-light focus <workspace>        reproduce the click and explain what happens
clawd-light focus <workspace> --dry-run    diagnose without activating anything
clawd-light help
```

Options: `--port N` (default 9877), `--skip-setup-prompt` (useful if you launch
the app at login), `--headless` (server only, no panel: the e2e tests use it).

`sessions` and `next` talk to the **running instance**: the terminal process knows
nothing about the column's state, and asking it is the only way to get a true
answer instead of a plausible reconstruction.

The panel can be dragged and remembers its position.

With `CLAWD_LIGHT_DEBUG=1` the app writes `~/.clawd-light/debug.log`.
`CLAWD_LIGHT_HOME` moves every path under a different root — the end-to-end tests
use it so they never touch the real `~/.claude`.

### The read endpoint

```bash
curl -H "X-Clawd-Token: $(cat ~/.clawd-light/token)" \
     http://127.0.0.1:9877/sessions
```

It returns, for every session: `status`, `workspace` (the folder's name) and
`path`, the timestamps in ISO 8601, `activeSubagents` and `waitingOn`,
`failureReason` and `lastMessage`, `muted`, the **keyboard slot**, the
`transcriptPath`, the `host` when the session runs on another machine, the
`entrypoint` Claude Code reported, the `origin` (`editor` or `terminal`), the
conversation `title` once there is one, and the `label` — what the panel calls
the row: the name you gave it, or the title of a lone terminal row, or the
folder. The slot and the label are in the contract because no outside reader
could work them out: the order and the names are yours, and they live in the
preferences. The token lives in `~/.clawd-light/token`
with mode `0600`; if the app finds the permissions any wider it **regenerates** the
token instead of narrowing them: a secret that has been readable by others must be
considered burned.

## When something's wrong

`clawd-light selftest` checks, in order: the server opens the port, a signal
crosses HTTP, it gets decoded, the current folder resolves to a workspace, the
Accessibility permission is there, the Automation permission for System Events
is there, the hooks are registered. It says which link
broke instead of leaving you staring at an unlit dot.

`clawd-light status` reports how many sessions have a live process, how many
deserve a traffic light and how many resolve to a recognized workspace — the last
number is how many sessions you should see (grouped, there will be fewer rows).

`clawd-light sessions` shows the column as the running app sees it. If `status`
counts rows that `sessions` doesn't list, the problem sits between the filesystem
read and the state machine; if both list them but the panel is empty, it's in the
drawing.

`clawd-light focus <workspace>` reproduces the click and prints the window titles
read from System Events, with an arrow on the chosen one. If the read comes back
empty you see it at once, instead of inferring it from a click that does nothing.
With `--dry-run` it diagnoses without moving any windows.

If the panel stays empty even though `status` reports the rows you expect, check
the permissions: without Accessibility or Automation the click falls back to
`open -b`, which brings VS Code to the front but doesn't raise the right window.

## After a Claude Code update

```bash
./Scripts/check-contract.sh --live
```

Everything this app knows about Claude Code was worked out by observation: hook
event names and payload shapes, the files the extension leaves on disk, a URI
handler. None of it is promised to stay the same.

The check verifies those assumptions against the installed version —
`Contracts/assumptions.md` names each one and says where the code depends on it.
It **reports, it doesn't repair**: a wrong automatic fix would hide the breakage
instead of naming it.

The static tier is free and takes seconds. The `--live` tier records a real
session and costs a few tokens, and it is the one that matters: an event that
stops firing raises no error — the column simply freezes on a state that is no
longer true, which is the one failure you cannot see.

## Development

```
Sources/
  ClawdLightCore/     pure logic — parsing, workspace, state machine
    Models/           states, signals, durations, column composition
    Parsing/          decoding and validation of the hook payloads
    Reducer/          (state, action) -> new state
    Server/           HTTP parser, JSON contract, token
    Setup/            hook script generation and merge into settings.json
    Workspace/        IDE locks, live sessions, window title matching, remote hosts
    Seat/             where a session's process lives: chains, terminals, tty, procStart
    Transcript/       reading what was said: records, the tail, the window, the title
    Chat/             the mailbox files and the dictation locale
    Markdown/         parsing of the answers the extended view draws
    Config/           AppConfig — ports, paths, thresholds
  ClawdLightApp/      AppKit/SwiftUI shell — panel, server, focus, seats, notifications
  ClawdLightTests/    domain suite, instantaneous
  ClawdLightE2E/      end-to-end run: launches the real binary
  TestKit/            minimal assertions
```

```bash
./Scripts/test.sh                      # both suites, then the documentation
swift run ClawdLightTests              # 472 domain tests, instantaneous
swift run ClawdLightE2E                # 79 end-to-end tests, ~1 minute
swift run ClawdLightTests "Subagents"  # filter by suite or case
./Scripts/check-docs.sh                # the figures the docs state are still true
./Scripts/check-contract.sh            # the assumptions about Claude Code still hold
./Scripts/build-app.sh                 # bundle into dist/
./Scripts/release.sh                   # signed disk image into dist/
```

The Command Line Tools without Xcode provide neither XCTest nor the complete
swift-testing, hence `TestKit`: a couple of hundred lines covering what's needed
to verify pure functions. All the logic that decides a traffic light's color lives
in `ClawdLightCore` and never touches AppKit, precisely so it stays under test.

### Why there are two suites

`ClawdLightTests` verifies pure functions: it is instantaneous and precise, and it
touches neither network nor filesystem.

`ClawdLightE2E` launches **the real binary** against a fake home
(`CLAWD_LIGHT_HOME`) and talks to it over HTTP, the way the hooks do. It goes as
far as running the generated `hook.sh` script with the payload on stdin: in
between sit bash, `curl`, the socket, the HTTP parser, the decoder and the
reducer — the complete chain. It touches neither `~/.claude` nor the preferences,
asks for no system permissions, and deletes everything at the end.

It exists for the reason below.

### A lesson paid for dearly

Window title matching didn't work for an entire working session despite ten green
tests. The defect lived outside the function under test: `NSAppleScript` returns
the window list as an **AppleScript list**, and on a list `stringValue` is `nil`.
The code split it on `", "` and always got a single empty element.

The initial check had been done with `osascript` from a terminal, which
**serializes the list into text** — that is, with a tool that behaves differently
from the one the app actually uses. The tests covered the function, the manual
check covered a different transport, and nobody covered the joint between the two.

Two things came out of that: the `focus` command, which prints the titles actually
read, and the end-to-end suite, which verifies the **fact** instead of the
intention. The defect of the socket listening on every interface was found that
way — by looking at `lsof` instead of re-reading the code that configured it.

### Knowing when accessibility can't see anything

If `focus` says "accessibility sees no editor window at all", it doesn't mean the
project isn't open: it means macOS is not letting us read other applications'
windows. The most frequent cause is a **locked screen**, which restricts AX access
to other applications while still letting System Events answer simple questions.
The two cases have different remedies, so the app tells them apart instead of
saying "window not found" to both.

## License

MIT.
