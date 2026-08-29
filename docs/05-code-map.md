# Code map

~27,900 lines of Swift across five targets. For each file: what it contains, why
it exists, and **what you would break** by touching it.

```
Sources/
  ClawdLightCore/   7,341 lines · 61 files   pure logic, zero AppKit
  ClawdLightApp/    11,509 lines · 63 files   shell: AppKit, network, windows
  ClawdLightTests/  6,953 lines · 38 files   551 cases, instantaneous
  ClawdLightE2E/    1,939 lines ·  9 files   82 cases, the real binary
  TestKit/            369 lines ·  4 files   minimal assertions
```

No file exceeds 786 lines. The limit the project sets itself is 800.

---

# ClawdLightCore

No `import AppKit`, no I/O, no implicit clock: `now` is always a parameter.
Everything that **decides** lives here.

## `Config/`

### `AppConfig.swift` · 376
Every constant in the project. Port, paths, thresholds, excluded entrypoints.

`homeDirectory` honors `CLAWD_LIGHT_HOME` and is the root of **every** path: it
is what makes the e2e tests possible without touching the real `~/.claude`.

> **Touching here** changes behavior everywhere. `sessionStaleAfter` (12 h) and
> `liveSessionPollInterval` (5 s) are tuned to real use with a dozen sessions:
> lowering the first makes live rows disappear, raising the second leaves dead
> rows clickable.

## `Models/`

### `SessionStatus.swift`
The six states and the three properties governing their behavior:
`urgencyRank`, `clearsOnFocus`, `blocksDowngrade`.

> **Touching `blocksDowngrade`** changes which states resist a late signal.
> `failed` is deliberately outside it: the reducer handles it separately.

### `SessionState.swift` · 333
The state of one session. **Immutable**: every transition produces a new instance
through `replacing(…)`, which uses double optionals to tell "leave it alone"
apart from "clear it".

It keeps `baseStatus` and **computes** `status`. Read the comment on `status`
before changing anything here: it is the heart of the subagent correction.

> **Touching the computation of `status`** risks reintroducing green during
> background work. Coverage: `SubagentSuite`.

### `ColumnLayout.swift` · 350
From state to rows: grouping, filtering, slots, hidden summary. A pure function.

`ColumnRow.sessionIdsToClear` is the delicate point — only the sessions in the
most urgent state.

`sorted` is the second one. Rows come out in the **user's order and nothing
else**: no state moves a row, which is what makes `open 3` worth binding to a key
and what keeps a row from sliding under the pointer — see
[D23](04-decisions.md#d23--the-column-does-not-reorder-itself). Urgency still
decides which session is a group's face and which one a click opens.

> **Touching the ordering**, remember two things: the row `id` has to stay stable
> across two computations, or SwiftUI rebuilds the rows and the panel flickers;
> and letting any state into `sorted` would silently break every bound key.

### `RowNames.swift`
The names the user gave to rows, by folder: read, renamed, bounded. A name is
what the panel shows and nothing that finds a window or a file ever believes it
(D26).

### `ReleaseVersion.swift` · `ReleaseFeed.swift`
The update check as a parser that says no. Versions compare as three integers,
because `"0.10.0"` sorts before `"0.9.0"` and the tenth release would silently
stop being offered. The download URL is **pinned** to this project's own
releases: an answer arriving over HTTPS is still only an answer, and a field that
could name any host would be choosing the code that runs on a Mac where this app
holds the Accessibility permission. Drafts and pre-releases are published without
being offered, which is what they are for.

### `TranscriptPathPolicy.swift`
Which transcript paths the app will open: only those under `~/.claude`, after
`..` has been resolved and with the trailing separator that stops a sibling
directory from passing as a child. `POST /signal` carries no token by design,
and the path it names is opened for reading — measured before this rule existed,
a forged signal naming `/etc/passwd` produced a row holding it within a second.

### `PanelIssue.swift` · `PermissionWait.swift`
A fault the person looking at the panel can fix, as a value rather than a
sentence: which System Settings pane grants it, the line the strip shows, the
paragraph behind the button, and the `tccutil` cure for the records macOS keeps
per signature. `PermissionWait` is the one tick of the wait that follows —
granted, expired, or neither — with the tie resolved in favour of finishing the
click, because a permission granted at the last second was still granted.

### `RowOrder.swift`
The column's order as data: give newcomers a place (`absorbing`), move a row to
where the user dropped it (`placing`, `moving`) — translated from what is visible
into the full list — and read a slot off a position. It lives in Core because
deciding where a row goes is a decision, and decisions in the shell are decisions
no test can see.

### `TrafficLightState.swift`
The session dictionary plus the operations: `upserting`, `removing`, `pruning`,
`ordered`.

`pruning` applies to **every** state, `working` included. The exemption that used
to be there made yellows immortal, because `Stop` doesn't fire when you interrupt
a turn with Esc.

### `HookSignal.swift` · 196
The validated signal. `deservesTrafficLight` and `subagentDelta` are the two
questions the reducer asks it.

### `HookEventKind.swift`
The nine events registered by default, plus one decoded and registered only with `install-hooks --with-tool-events` (`PreToolUse`), and the five
`Notification` subtypes. An unknown event is not an
error: it is ignored, so the app doesn't break when Anthropic adds more.

### `StopFailureReason.swift`
A **closed** set of ten causes. An unexpected value falls back to `unknown`
instead of propagating as a free-form string all the way to the row.

`hasUsableOutput` is true only for `maxOutputTokens`: there the text exists, it
is merely incomplete, so the row is green rather than red.

### `SessionOrigin.swift`
`.editor` or `.terminal`: the kind of place a row lives in, set by whoever
resolves the workspace and read by everything that treats a terminal row
differently (D25). Not on `Workspace`, which is the row's identity.

### `Workspace.swift`
`Workspace` plus `PathNormalizer`. Path comparison is **component by component**,
not by string prefix: without that, `/dev/project-old` would come out as inside
`/dev/project`.

It deliberately does not resolve symlinks: `cwd` and `workspaceFolders` come from
the same source and are already consistent.

### `RowSummary.swift` · 177
Everything a row can say about itself, as **fields** rather than as a paragraph:
title, state, subtitle, an ordered grid of label/value/detail, the per-session
list of a group, the last message, the help line. It used to be a `private var`
on a SwiftUI view that appended sentences to an array — untestable by
construction, and, as it turned out, never once displayed. What a row tells you
is domain; only how it looks is drawing.

### `RelativeTime.swift` · `CompactDuration.swift`
The labels for the right-hand slot. `RelativeTime` reasons in **calendar days**:
at 00:30 an event from 23:50 is yesterday — `1d` — and not "40 minutes ago". The
row abbreviates and the tooltip spells it out, which is a trade that only became
available once the panel drew its own tooltips (D32).

### `StringHelpers.swift`
`trimmed`, `nilIfEmpty`, `padded(to:)`. The last one exists because
`String(format:)` **ignores** the width on `%@` placeholders.

## `Seat/`

Where a session's process lives — what a click on a terminal row has to bring
to the front (D25). Pure: the shell reads the process table, this decides.

### `ProcessAncestor.swift`
One process on the way up, and `TTYName`: tty names come as `ttys003` from the
kernel and `/dev/ttys003` from dictionaries, and only the normalised form —
matched, after any `/dev/` prefix is stripped, against `^ttys[0-9]{1,4}$` and re-prefixed — not escaped — may enter a script.

### `Seat.swift`
`TerminalKind`, a short table like `IDEKind` (Terminal, iTerm2, Ghostty, kitty,
WezTerm, each with how its tabs are raised), and `Seat`: a terminal tab on a tty,
a tmux or zellij pane, an editor, some other application, or nothing known.

### `SeatClassifier.swift`
Chain → seat. Every chain it recognises was measured; `SeatSuite` pins them. The
two VS Code helpers are told apart by bundle name, not by the word "Helper".

### `TerminalScripts.swift`
The AppleScript that selects a tab by tty in Terminal.app and iTerm2, erroring
`-1728` when no tab is on it — the code the editor path already reads as "not
there".

### `MultiplexerListings.swift`
What `lsof` and tmux print, parsed: a Unix socket's own address and peer (the
client–server pairing for zellij) and tmux's panes and clients in the formats
this app asks for. Names that go back to tmux as arguments are validated first.

### `TerminalListings.swift`
What WezTerm's and kitty's CLIs print, parsed, and the Ghostty match: the pane
on a tty, the window running or fronting a pid, the terminal whose title or
folder is the session's. Ghostty's ids are validated before they enter a script.

### `ProcStart.swift`
The session file's `procStart` in its two forms — Linux ticks, macOS ctime **in
UTC** — and whether a process that started at a given moment can be the one the
file names. The guard against a reused pid.

## `Transcript/`

Reading what was actually **said** in a session. The hooks describe state; this
describes content, and the two never infer each other.

### `TranscriptEntry.swift`
`TranscriptEntry` and `Conversation`. Four kinds of line — human, assistant,
activity, note — because a transcript record and a chat line are not the same
thing: one assistant record holds an answer *and* six tool calls.

> **`Conversation` counts what it dropped.** The window keeps a bounded tail, so
> `trimmed(to:)` carries an accumulating `omittedEntries` and the view says
> "N earlier messages not shown". A reader has to be able to tell a short
> conversation from a truncated one.

### `TranscriptDecoder.swift` · 257
Record → entries. The point where a second stream of external data enters the
domain, and it fails **quietly**: an unrecognized record yields nothing rather
than an error, because Claude Code adds record types between releases.

> **Read the comment on `isHuman` before touching it.** A record of type `user` is
> usually *not* a message — the protocol files tool results and injected context
> under the same role. The shortcut "no `toolUseResult` means a person wrote it"
> was measured: it invents 579 user messages against 209 real ones.

### `TranscriptTail.swift`
The half of "follow a file" that can be silently wrong: a chunk almost always ends
mid-object, and parsing the fragment loses one record per read. It lives in Core,
away from the `FileHandle`, precisely so it can be tested.

### `TranscriptTitleScanner.swift`
The conversation title out of a file's head, under `TranscriptTail`'s rule —
one rule for the chat window and the terminal rows.

### `TranscriptWindow.swift`
Where a window opening on a long transcript starts reading: a few megabytes
before the end, on a whole line. A transcript can be half a gigabyte and the
window shows three hundred entries; reading it all was the beachball on ⌘+click.

### `ContextReading.swift` · 170 · `ContextScanner.swift` · 117
How full a session's context is, read backwards from the end of its transcript.

The numerator is the sum of `input_tokens`, `cache_creation_input_tokens` and
`cache_read_input_tokens` — the same sum Claude Code's own status line reports as
`total_input_tokens`, verified against a live payload rather than derived. The
denominator is the model's window, which the transcript does **not** carry: it
records `claude-opus-5` and nothing else, and a session started with
`--model sonnet` and no suffix also resolves to a million. The table lives in
`ContextWindows`, mirrored in `Contracts/required-fields.json`, and
`check-contract.sh` re-reads Claude Code's binary on every run.

Four rules, each from a real file and each one the naive version gets wrong: a
`<synthetic>` record is a refusal with zeros, not a reply — one of them says
*"Prompt is too long"*, so reading the last usage-bearing record prints **0%**
at the moment a session is full; zero at the top level can hide the figure in
`usage.iterations`; the model comes from the same record as the tokens, because
a session switches models mid-flight; and the order in the file is not
chronological, because a resumed session replays its history.

The reading also carries what happened after it. Only assistant records hold a
count, so anything loaded since is invisible: measured across 171 compaction
boundaries the truth was a median of 1.00× and a maximum of **17.67×** the last
reading. Hence `exact`, `floor` and `unknown` — rendered `62%`, `≥62%` and `—`.
The `≥` and the dash are the feature; the bare number is the part that lies.

### `TranscriptLocator.swift`
Where a transcript **would** be, for sessions adopted from the filesystem with no
hook to tell us — after a restart, that is all of them. The rule matched 7065 of
7066 real transcripts; the exception is a git worktree, which is why the result is
a candidate the caller has to find on disk.

## `Chat/`

### `Mailbox.swift` · 264
Where a message waits between the composer and the session it is for, what may be
sent, what may become a filename, `ensureDirectory` — which `lstat`s the path and
refuses anything that is not a real directory of ours — and `MailboxReaper`, the
rule for what survives a restart.

> **The permissions are not decoration.** Dropping a file in the mailbox starts a
> turn that speaks in the user's voice with their tools. `0700`/`0600`, like the
> access token. They stop another account on the machine and stop nothing running
> as the user — which is stated in the doc comment rather than glossed.

> **`isValidSessionId` is an allow-list**, because the value is about to be
> concatenated into a path. A deny-list here is how you get a traversal.

> **`MailboxReaper` is in Core because it is a decision.** The first version of
> that rule lived in the shell, where no test could see it, and it deleted
> undelivered messages on every launch: something the user dictated, that the
> interface accepted, gone without a word. A conversation with a pending message
> now keeps its marker, or nobody would ever collect it.

### `DictationLocale.swift`
Which language to listen in, and what the microphone button is able to do.

> **`choose` returns `nil` rather than falling back to English.** The recognizer
> transcribes everything as the locale it is given, so the wrong one produces
> fluent nonsense that nothing downstream can detect. Silence is the honest
> failure; there is a test named for it.

## `Markdown/`

### `MarkdownBlock.swift` · `MarkdownParser.swift` · 240
Splitting an answer into blocks. Deliberately not a general markdown
implementation: what Claude writes, and anything unrecognized becomes a paragraph
— its own source text, readable — rather than disappearing.

> **Fences are parsed first and greedily.** A `# comment` inside a shell snippet
> is not a heading, and a table divider is what tells a table from a shell
> pipeline written in prose. Both have tests.

> **`plainSummary` strips only `*` and backticks.** The wider sweep that looks
> obvious eats `a > b`, `snake_case` and `#1`.

## `Parsing/`

### `HookPayloadDecoder.swift` · 176
The only point where external data enters the domain. Strict validation: no
required field is ever inferred or filled in with a default.

`ignoredEvent` is not a fault — the hook script forwards everything and the
filter lives here.

## `Reducer/`

### `StateReducer.swift` · 431
`(state, action) → new state`. The densest file in the project.

The order of the checks in `apply`, and it is **not arbitrary**:
1. does it deserve a traffic light? is there a workspace?
2. **is it a subagent lifecycle event?** ← before the rule that discards
3. does it come from a subagent? → discard
4. is it `SessionEnd`? → remove
5. map event → state, or discover a new session
6. protection from late signals (`shouldKeep`)

> **Step 2 before step 3** is the subagent correction. Swapping them undoes it,
> silently.

## `Server/`

### `HTTPRequestParser.swift` · 132
A minimal HTTP/1.1 parser. Deliberately not general-purpose: it accepts only what
the hook script sends.

### `SessionsPayload.swift` · 206
The JSON contract. A type **separate** from `SessionState`, so an internal
refactor doesn't break its consumers. ISO 8601 dates, sorted keys.

### `AccessToken.swift`
Generation and **constant-time** comparison. The comment at the top says what the
token protects and what it doesn't: read it before quoting it elsewhere.

## `Setup/`

### `HookConfigMerger.swift` · 193
Adds and removes the hooks in `settings.json` **working on dictionaries**, not on
files: the I/O lives in the shell, so this logic — which modifies an important
user file — stays verifiable.

### `HookScriptBuilder.swift`
Generates `hook.sh`. See [02 Claude Code](02-claude-code.md#the-hook-script).

### `RewakeScriptBuilder.swift` · 126
Generates `rewake.sh`, the second `Stop` hook that carries a message into a
running session. Its stdout **is** the message; exit code **2** is the send.

> **A separate file from `hook.sh`, not an option inside it.** The two have
> opposite obligations: the traffic light hook must return in milliseconds or it
> delays every turn, and this one waits for minutes.

> **Three defenses against a process that outlives everything**: it arms only when
> a conversation is selected, it gives up after thirty minutes, and a pid file
> stands a second listener down. Every path out is `exit 0` except the deliberate
> `exit 2` — a failing hook can interrupt a Claude Code turn.

### `RemoteInstallScripts.swift` · 216
The Python that runs on another machine to inspect it, write the hook script and the merged settings, or ask whether the tunnel answers. In Core and under test for the same reason the probe is: a promise to another machine has to be readable in one place. The data travels inside the source as base64 — no shell quoting rule is involved.

## `System/`

### `Command.swift` · 141
Running an outside tool without being taken hostage by it. The obvious three
lines have two failure modes and both are silence: `waitUntilExit` waits
forever, so a hung `spctl` took the updater with it and nothing was ever going
to appear on screen; and a pipe holds about 64 KB, so a tool that says more
blocks writing while the caller blocks waiting, and neither side is broken and
neither moves. Reading on another thread makes the deadline the only thing that
can end the wait. In Core rather than beside its caller so both failures can be
demonstrated instead of argued about — `CommandSuite` runs a tool that sleeps
and one that writes two hundred kilobytes.

## `Workspace/`

### `TunnelRefusal.swift` · 88
Which machine is actually at fault when a reverse tunnel cannot bind. ssh says
*"remote port forwarding failed for listen port 31000"*, which reads as an
accusation against the other machine; measured once, the port was held by this
app's own tunnel from a previous run, orphaned by the `pkill` the build script
itself recommends. Reads the local process table, matches on the forward
specification rather than on the word `ssh`, and names the pid with the command
that removes it. Nothing is killed automatically: another running panel is a
legitimate owner of that port.

### `RemoteHostList.swift` · 45
The rules for a remote host's name: `isUsable` is an allow-list because the name
becomes an argument to `ssh` — one starting with a dash would be read as
*options* — and `parse` reads the old `~/.clawd-light/remotes` file, imported
once into the preferences on upgrade (D24). The hosts themselves live in the
Settings window.

### `RemoteProbeScript.swift` · 131
The script that runs **on** the other machine, in one piece and under test. It is a
promise made to a machine we do not control, and the shape it prints is what
`RemoteSessionsDecoder` parses — if the two drift, activity silently falls back to
the session file, which is the frozen one.

> **Why the work happens there.** Two of the three facts a row needs are only true
> where the processes are: whether the pid is alive, and when the transcript last
> changed. Deciding here from shipped files would answer both about the wrong
> machine.

### `RemoteSessionsDecoder.swift` · 64
The other machine's answer, entering the domain. Validates like
`HookPayloadDecoder`, with one difference: **a single bad record is skipped, not
thrown**. The output comes from a Claude Code version we do not control, and one
unparsable entry is not a reason to blank a whole host.

### `WorkspaceResolver.swift`
`cwd` + locks → which window. `window(hosting:)` also returns **which editor**,
because Cursor's bundle identifier differs from VS Code's.

### `WindowTitleMatcher.swift` · 137
Scores 100/50/10, plus 1000 for a Remote-SSH window whose label is a name the host is known by. It lives in Swift rather than inside AppleScript precisely so
it can be verified without opening windows.

### `IDEKind.swift`
The table of recognized editors: declared name, bundle, process name.
**Deliberately short** — see [N3](04-decisions.md#n3--jetbrains-and-the-other-ides).

### `IDEWindow.swift` · `LiveSession.swift`
The two parsers for the on-disk files.

### `SessionDeepLink.swift` · `AppleScriptString.swift`
The extension's URI, the policy that sends it only to sessions the extension
hosts (`DeepLinkPolicy`: entrypoint `claude-vscode`, or unknown), and the
escaping of titles inside a script.

---

# ClawdLightApp

It does I/O and draws. **It does not decide.**

## Entry point

### `main.swift` · `AppDelegate.swift` · 282
`MainActor.assumeIsolated` in `main.swift` is needed because top-level code isn't
isolated to the main actor, but that is where we are by definition.

`AppDelegate` wires everything up. `--headless` skips `startInterface()`, and
that is why the E2E suite didn't see the notification crash: it never went
through that branch.

`onMain(timeout:)` is the only writing crossing towards the main actor.

### `CommandLineInterface.swift` · 786
Thirteen commands: install-hooks, uninstall-hooks, status, selftest, focus, next, open, new, chat, sessions, remote, terminal, rename. `new` and `chat` share `runSlotCommand`; `open` stays separate
because a bare `open` lists the assignments, which is a different command wearing
the same name. `focus --dry-run` diagnoses without moving any windows.

### `SelfTest.swift` · 240
`clawd-light selftest`: the whole chain, link by link — the port opens, a signal
crosses HTTP, decodes, resolves to a workspace, the Accessibility permission is
there, the hooks are registered — and it names the link that broke.

## `Runtime/`

| File | Lines | What |
|---|---|---|
| `StateStore.swift` | 587 | `@MainActor`, `@Published`, periodic realignment |
| `Preferences.swift` | 294 | `UserDefaults`, separate domain under `CLAWD_LIGHT_HOME` |
| `SnapshotBox.swift` | 27 | lock-protected copy for the server |
| `TokenStore.swift` | 78 | `0600` token, **regenerated** if the permissions are wide |
| `LocalClient.swift` | 154 | talks to the live instance for `sessions` and `next` |
| `SessionNotifier.swift` | 199 | `awaiting` notifications, anti-duplicate memory, gate |
| `TranscriptReader.swift` | 112 | follows one transcript by byte offset; opens on its tail, title from its head; resets when the file shrinks |
| `TranscriptPreviewReader.swift` | 98 | the last thing said, from the file's tail, cached on its size |
| `ContextReader.swift` | 98 | how full the context is, from the same tail, cached the same way — an `actor`, so the seek never lands on the thread that draws |
| `SessionTitleReader.swift` | 16 | the first 512 KB of a transcript, handed to the scanner; what names a terminal row |
| `IDEWindowReader.swift` | 54 | reads the locks and **confirms them against the editor's process**, not the file's age |
| `MailboxWriter.swift` | 179 | the panel's end of the mailbox; carries out the reaper's verdict |
| `RemoteSessionReader.swift` | 108 | asks another machine over ssh; `nil` means no answer, `[]` means nothing running |
| `RemoteCommand.swift` | 147 | runs a Python script on another machine over ssh: one shape, one set of timeouts, errors that name the fix |
| `RemoteTunnel.swift` | 283 | the reverse ssh tunnel per host, kept alive with backoff; `ExitOnForwardFailure` makes a taken port a reason, and `TunnelRefusal` says whether that reason is on this Mac |
| `RemoteFleet.swift` | 191 | every configured machine: its tunnel, its hooks, what it last said; follows the preference list live |
| `DictationService.swift` | 339 | `SpeechTranscriber` on the device, `AVAudioEngine` capture, macOS 26 only |
| `PresenceFile.swift` | 91 | presence file, deleted on shutdown |
| `LaunchAtLogin.swift` | 106 | blocked when the signature is ad-hoc |
| `LiveSessionReader.swift` | 90 | reads the live sessions; takes activity from the **transcript**, not the session file |
| `FinderReveal.swift` | 28 | opens a Finder window **inside** the folder, not on it (D33) |
| `UpdateChecker.swift` | 56 | asks GitHub for the latest release and compares it with this build |
| `UpdateInstaller.swift` | 288 | downloads, verifies the signature matches this one, swaps the bundle and relaunches — with a deadline on every step |
| `Diagnostics.swift` | | file log, active only with `CLAWD_LIGHT_DEBUG` |

> **`DictationService`** — the ordering in `start()` is load-bearing and
> commented at length. `SpeechAnalyzer.start(inputSequence:)` is the pump, not the
> ignition: it does not return until the audio ends. Awaiting it left the state
> down, the button idle, `stop()` refusing to act and the **microphone open with
> no way back short of quitting**. Every exit path releases the input device
> first and unconditionally, for that reason.


> **`SessionNotifier`**: the `announced` memory has to be updated **even with the
> feature off**, or flipping the switch with ten blocked sessions fires ten
> alerts at once.

## `Server/`

### `SignalServer.swift` · 319
Seven routes. A **concurrent** queue: with a serial one, a `/next` waiting on the
main queue would also block reading the hooks' signals.

`/open`, `/new` and `/chat` share `handleSlotRoute`: they differ only in the action, so
method, authentication, validation and the three answers are written once. All three
carry the slot in the **body**, not the path — a router that has to interpret path
segments is a router with a parsing bug waiting in it, and this parser is
deliberately not a general-purpose one.

`requiredLocalEndpoint` is the line that binds the socket to loopback.
`acceptLocalOnly` does **not** do that.

## `Focus/`

### `PermissionWatcher.swift`
Holds the click a missing permission interrupted, and finishes it when the
permission arrives. Granting a TCC authorization notifies nobody — the only way
to notice is to keep asking — and the point is not the noticing: it is that
making the user click again is how a permission they just granted feels like it
changed nothing.

### `ProcessTree.swift` · `SeatResolver.swift` · `TerminalFocuser.swift`
The click on a terminal row. `ProcessTree` reads parent, tty, start time and
arguments from the kernel (`sysctl`, `proc_pidpath`; no `ps`). `SeatResolver`
goes from a session id to its seat at click time — file, pid, `procStart`
guard, chain, classifier — and caches nothing. `TerminalFocuser` raises the
seat: by tty through the terminal's dictionary, or activates the application
and says where it stopped. Automation is per target application, and a refusal
names the one that refused.

### `VSCodeFocuser.swift` · 418
The most delicate file. Two strategies, three explicit outcomes.

> **To be read in full before touching it.** Every long comment in here
> corresponds to a defect that cost hours: null `stringValue` on lists,
> `activate()` lying, `open` with a path that creates new windows, the index that
> expires.

### `RemoteHostAddresses.swift` · 73
The names a Remote-SSH window may carry for a host — the configured one, what `ssh -G` resolves it to, and their addresses — because VS Code labels the window with whatever the user typed to connect.

## `Setup/`

### `HookInstaller.swift` · 239
Atomic writes and a dated backup. `availableBackupURL` appends a counter: two
installations in the same second used to fail.

### `RemoteHookInstaller.swift` · 181
The local installer's merge applied to another machine: inspect over ssh, merge here with `HookConfigMerger`, write there through `RemoteInstallScripts` — dated backup, atomic replace, no shell in the data path. Also asks the node whether the tunnel answers.

## `UI/`

| File | Lines | What |
|---|---|---|
| `PanelController.swift` | 768 | holds everything together; row and panel actions |
| `TrafficLightRow.swift` | 337 | one row: dot, context ring, name, badge, timestamp, folder, handle, menu |
| `DragHandle.swift` | 60 | the handle's grab area, an `NSView` so the drag moves the row and not the panel |
| `TrafficLightColumn.swift` | 252 | the column, the drag in progress, the hidden summary, the filter note |
| `PanelRootView.swift` | 393 | the general menu, and the strip under the rows: width on the left, legend and menu on the right |
| `TrafficLightDot.swift` | 73 | the dot, the silenceable blink, and the ring for an open ear |
| `ContextRing.swift` | 77 | the second ring: the arc is the context spent, the letter is the model (D30) |
| `LegendView.swift` | 180 | what the six colours and the two rings mean, counted live (D31) |
| `LegendWindowController.swift` | 57 | owns the legend window |
| `Tooltip.swift` | 243 | the panel's own tooltips: AppKit's need a key window, and this one never is (D32) |
| `TooltipCard.swift` | 149 | draws a `RowSummary`: header, the label/value grid, the context bar, the keys |
| `Blinking.swift` | 39 | the blink as a view that exists only while it blinks |
| `UpdateFlow.swift` | 57 | the update from the menu entry to the app coming back: what was found, what failed, nothing silent |
| `PermissionRequest.swift` | 45 | explains a permission — use, cost of refusing, way back — then opens the pane that grants it |
| `StatusPalette.swift` | 184 | colors and measurements |
| `FloatingPanel.swift` | 97 | non-activating `NSPanel`; makes itself key before a click, drops the second click of a double-click |
| `ChatWindowController.swift` | 123 | owns the one extended window; opened on request |
| `ChatShell.swift` | 185 | every conversation, the selection, and what each costs |
| `ChatShellView.swift` | 197 | the two columns, and one row of the list |
| `ChatSession.swift` | 245 | one conversation: transcript on disk + status from the hooks + the composer's state |
| `ChatView.swift` | 306 | bubbles, activity lines, the composer |
| `MarkdownView.swift` | 157 | draws the blocks; inline markup goes to `AttributedString` |
| `DictationButton.swift` | 97 | the microphone, and the box that hides the macOS-26 seam |
| `SettingsView.swift` | 164 | the Settings form: remote machines, their state, the buttons; the "Show terminal sessions" switch |
| `SettingsWindowController.swift` | 57 | owns the Settings window; activates the app so it comes up in front |
| `Alerts.swift` | | dialogs |

> **`StatusPalette.timeColor`** is `Color.primary.opacity(0.62)` and not
> `.secondary`: over an `NSVisualEffectView` the weak semantic hues get
> attenuated a second time and disappear. The hierarchy comes from the font
> **weight**.

---

# The tests

## `ClawdLightTests/` — 551 cases

One suite per domain area, and one file per group of them: `MailboxSuite.swift`
held ten suites and 610 lines, three of which were about dictation and the rewake
script, before it was split. The most important ones:

| Suite | Covers |
|---|---|
| `StateReducerSuite` · `ReducerFixesSuite` | the state machine, including the four semantic corrections |
| `SubagentSuite` | counter and derived state |
| `ColumnLayoutSuite` | grouping, the user's order, filtering, summary |
| `RowNamesSuite` | a name shown over folder and title, stored by folder, blank restores; the label in the payload |
| `RowOrderSuite` · `ColumnSlotSuite` | absorbing, placing and moving; that a slot is a position and survives any change of state |
| `MailboxSuite` · `MailboxPermissionSuite` | hostile session ids, message limits, owner-only permissions |
| `MailboxDirectorySafetySuite` | a symlink where the mailbox should be is refused |
| `RewakeScriptSuite` · `RewakeRegistrationSuite` | the script's promises, and the second `Stop` hook |
| `MarkdownParserSuite` | the constructs, and one whole answer containing all of them |
| `IDELockLivenessSuite` | a running editor is believed however old its lock is |
| `LivePruningSuite` | a session you can see running is never pruned for being quiet |
| `AwaitingReleaseSuite` | a question you have answered stops flashing |
| `WaitingSuite` | a session that has stopped but is not done is blue, and says what it waits on |
| `RemoteSessionsSuite` | another machine's sessions, and what deserves a row |
| `BackgroundTaskSuite` | pending work is work; only terminal statuses are not |
| `MailboxReapSuite` | an undelivered message keeps its conversation armed |
| `DictationLocaleSuite` | silence beats confident nonsense |
| `DeliveredMessageSuite` | recognizing our own messages on the way back |
| `TranscriptDecoderSuite` | who spoke — including the 579-against-209 case |
| `TranscriptTailSuite` | the half-written line, split across up to three chunks |
| `TranscriptLocatorSuite` | the naming rule, accents included |
| `SeatSuite` · `MultiplexerSuite` · `TerminalListingSuite` | every measured chain classified; tty names matched not escaped; the scripts; `procStart` as UTC and the zone trap; the `lsof` pairing and tmux listings; WezTerm, kitty and Ghostty listings |
| `ConversationSuite` | unread counts answers, and trimming says how much it dropped |
| `WindowTitleMatcherSuite` | the scores |
| `AppleScriptEscapeSuite` | title escaping, including a hostile title |
| `AccessTokenSuite` | constant-time comparison, prefixes, empty expected value |
| `ContextSuite` | the token sum; a refusal that must not read as 0%; the floor and the dash; the iterations fallback; a dated model id; an unknown model |
| `RowSummarySuite` | what a row says about itself: the fields and their order, a void reading that must not print its tokens, a help line that promises only what the row can do |
| `CommandSuite` | a tool that hangs is killed at the deadline; 200 KB of output does not deadlock; a refusal keeps its exit code and its reason |

## `TestKit/` — the assertions

Four files: `TestSuite` (a name and its cases), `TestRunner` (runs them, filters
by name, prints the ✓/✗ lines and the final count), `Assertions` (`expect`,
`expectEqual`, `expectNil`, `expectNotNil`, `expectThrows`, `expectNoThrow`,
`fail`) and `Instrument`. It exists because the Command Line Tools without Xcode
ship neither XCTest nor a complete swift-testing (D11).

### `Instrument.swift` · 133
Calibrates the assertions before anything is measured with them, and it is the
reason the number in the heading above means something. Adding one early
`return` to `expect` made every case in this target report success while verifying nothing —
a full green, no warning, no clue. So every assertion is now made to fail on
purpose and must record it, made to pass and must stay silent, and a failing run
must still reach a non-zero exit code; nineteen proofs, none of them written in
the vocabulary they are testing. A blunt instrument ends the process with 70
rather than the 1 of an ordinary failure, because the two mean different things.
`Scripts/bite.sh` attacks it from the outside as well.

## `ClawdLightE2E/` — 82 cases

| Suite | Covers |
|---|---|
| `TransportSuite` | **the socket via `lsof`**, token, methods, refusals |
| `LifecycleSuite` | the states walked over HTTP |
| `CoverageSuite` | integrated terminal, terminal rows outside every workspace, a renamed row, a signal from another machine, subagents |
| `ScaleSuite` | adoption, twenty-two sessions, dead process |
| `InstallationSuite` | `install-hooks`, **`hook.sh` actually executed**, non-headless startup |
| `TokenLifecycleSuite` | reuse, regeneration, corrupted token |

`AppUnderTest` is the harness: it starts the binary against a fake home, knows
how to run the commands and the hook script, and waits with `waitUntil` because
the realignment is asynchronous.

---

# Scripts

| File | What |
|---|---|
| `Scripts/build-app.sh` | bundle into `dist/`, stable signature when available, with a deadline |
| `Scripts/create-signing-identity.sh` | persistent certificate, **idempotent and self-verifying** |
| `Scripts/make-icon.py` | draws the icon at every size macOS asks for and writes `Resources/ClawdLight.icns`; `--preview` adds the small-size contact sheet |
| `Scripts/release.sh` | disk image into `dist/`; signs, notarizes and staples when the keychain allows it, and says which of the three outcomes it reached |
| `Scripts/test.sh` | both suites, then the documentation check |
| `Scripts/check-contract.sh` | the assumptions about Claude Code, static or `--live`; `--record` re-records the golden baseline |
| `Scripts/check-docs.sh` | the figures, links, event counts and suite registrations the docs state, and the WORKLOG's status table against the repository |
| `Scripts/bite.sh` | commits twenty-two violations and demands twenty-two catches; a gate nobody has seen fail has not been distinguished from a broken one |
| `Scripts/measure-compaction.py` | every auto-compaction in the transcripts, and the value our own reading had reached at each — the measurement that settles the context denominator |
