# Code map

~17,000 lines of Swift across five targets. For each file: what it contains, why
it exists, and **what you would break** by touching it.

```
Sources/
  ClawdLightCore/    4,087 lines · 36 files   pure logic, zero AppKit
  ClawdLightApp/     6,638 lines · 37 files   shell: AppKit, network, windows
  ClawdLightTests/   4,332 lines · 24 files   364 cases, instantaneous
  ClawdLightE2E/     1,680 lines ·  9 files    75 cases, the real binary
  TestKit/             227 lines ·  3 files   minimal assertions
```

No file exceeds 590 lines. The limit the project sets itself is 800.

---

# ClawdLightCore

No `import AppKit`, no I/O, no implicit clock: `now` is always a parameter.
Everything that **decides** lives here.

## `Config/`

### `AppConfig.swift` · 157
Every constant in the project. Port, paths, thresholds, excluded entrypoints.

`homeDirectory` honors `CLAWD_LIGHT_HOME` and is the root of **every** path: it
is what makes the e2e tests possible without touching the real `~/.claude`.

> **Touching here** changes behavior everywhere. `sessionStaleAfter` (12 h) and
> `liveSessionPollInterval` (5 s) are tuned to real use with a dozen sessions:
> lowering the first makes live rows disappear, raising the second leaves dead
> rows clickable.

## `Models/`

### `SessionStatus.swift`
The five states and the three properties governing their behavior:
`urgencyRank`, `clearsOnFocus`, `blocksDowngrade`.

> **Touching `blocksDowngrade`** changes which states resist a late signal.
> `failed` is deliberately outside it: the reducer handles it separately.

### `SessionState.swift` · 194
The state of one session. **Immutable**: every transition produces a new instance
through `replacing(…)`, which uses double optionals to tell "leave it alone"
apart from "clear it".

It keeps `baseStatus` and **computes** `status`. Read the comment on `status`
before changing anything here: it is the heart of the subagent correction.

> **Touching the computation of `status`** risks reintroducing green during
> background work. Coverage: `SubagentSuite`.

### `ColumnLayout.swift` · 260
From state to rows: grouping, filtering, slots, hidden summary. A pure function.

`ColumnRow.sessionIdsToClear` is the delicate point — only the sessions in the
most urgent state.

`ColumnRow.slot` is the second one. Pinned rows sort by slot and **not** by
urgency, which is what makes `open 3` worth binding to a key — see
[D13](04-decisions.md#d13--a-keyboard-slot-is-a-pin-not-a-row-number).

> **Touching the ordering**, remember two things: the row `id` has to stay stable
> across two computations, or SwiftUI rebuilds the rows and the panel flickers;
> and sorting the pinned rows by urgency would silently break every bound key.

### `SlotAssignment.swift`
The only two operations that change which project a key addresses: append/remove,
and move by one. It lives in Core because deciding an address is a decision, and
decisions in the shell are decisions no test can see.

### `TrafficLightState.swift`
The session dictionary plus the operations: `upserting`, `removing`, `pruning`,
`ordered`.

`pruning` applies to **every** state, `working` included. The exemption that used
to be there made yellows immortal, because `Stop` doesn't fire when you interrupt
a turn with Esc.

### `HookSignal.swift` · 113
The validated signal. `deservesTrafficLight` and `subagentDelta` are the two
questions the reducer asks it.

### `HookEventKind.swift`
The eight events and the five `Notification` subtypes. An unknown event is not an
error: it is ignored, so the app doesn't break when Anthropic adds more.

### `StopFailureReason.swift`
A **closed** set of ten causes. An unexpected value falls back to `unknown`
instead of propagating as a free-form string all the way to the row.

`hasUsableOutput` is true only for `maxOutputTokens`: there the text exists, it
is merely incomplete, so the row is green rather than red.

### `Workspace.swift`
`Workspace` plus `PathNormalizer`. Path comparison is **component by component**,
not by string prefix: without that, `/dev/project-old` would come out as inside
`/dev/project`.

It deliberately does not resolve symlinks: `cwd` and `workspaceFolders` come from
the same source and are already consistent.

### `RelativeTime.swift` · `CompactDuration.swift`
The labels for the right-hand slot. `RelativeTime` reasons in **calendar days**:
at 00:30 an event from 23:50 is "yesterday", not "40 minutes ago".

### `StringHelpers.swift`
`trimmed`, `nilIfEmpty`, `padded(to:)`. The last one exists because
`String(format:)` **ignores** the width on `%@` placeholders.

## `Transcript/`

Reading what was actually **said** in a session. The hooks describe state; this
describes content, and the two never infer each other.

### `TranscriptEntry.swift`
`TranscriptEntry` and `Conversation`. Four kinds of line — human, assistant,
activity, note — because a transcript record and a chat line are not the same
thing: one assistant record holds an answer *and* six tool calls.

### `TranscriptDecoder.swift` · 210
Record → entries. The point where a second stream of external data enters the
domain, and it fails **quietly**: an unrecognised record yields nothing rather
than an error, because Claude Code adds record types between releases.

> **Read the comment on `isHuman` before touching it.** A record of type `user` is
> usually *not* a message — the protocol files tool results and injected context
> under the same role. The shortcut "no `toolUseResult` means a person wrote it"
> was measured: it invents 579 user messages against 209 real ones.

### `TranscriptTail.swift`
The half of "follow a file" that can be silently wrong: a chunk almost always ends
mid-object, and parsing the fragment loses one record per read. It lives in Core,
away from the `FileHandle`, precisely so it can be tested.

### `TranscriptLocator.swift`
Where a transcript **would** be, for sessions adopted from the filesystem with no
hook to tell us — after a restart, that is all of them. The rule matched 7065 of
7066 real transcripts; the exception is a git worktree, which is why the result is
a candidate the caller has to find on disk.

## `Chat/`

### `Mailbox.swift` · 220
Where a message waits between the composer and the session it is for, what may be
sent, what may become a filename, and `MailboxReaper` — the rule for what survives
a restart.

> **`MailboxReaper` is in Core because it is a decision.** The first version of
> that rule lived in the shell, where no test could see it, and it deleted
> undelivered messages on every launch: something the user dictated, that the
> interface accepted, gone without a word. A conversation with a pending message
> now keeps its marker, or nobody would ever collect it.

### `DictationLocale.swift`
Which language to listen in, and what the microphone button is able to do.

> **`choose` returns `nil` rather than falling back to English.** The recogniser
> transcribes everything as the locale it is given, so the wrong one produces
> fluent nonsense that nothing downstream can detect. Silence is the honest
> failure; there is a test named for it.

> **The permissions are not decoration.** Dropping a file in the mailbox starts a
> turn that speaks in the user's voice with their tools. `0700`/`0600`, like the
> access token. They stop another account on the machine and stop nothing running
> as the user — which is stated in the doc comment rather than glossed.

> **`isValidSessionId` is an allow-list**, because the value is about to be
> concatenated into a path. A deny-list here is how you get a traversal.

## `Markdown/`

### `MarkdownBlock.swift` · `MarkdownParser.swift` · 220
Splitting an answer into blocks. Deliberately not a general markdown
implementation: what Claude writes, and anything unrecognised becomes a paragraph
— its own source text, readable — rather than disappearing.

> **Fences are parsed first and greedily.** A `# comment` inside a shell snippet
> is not a heading, and a table divider is what tells a table from a shell
> pipeline written in prose. Both have tests.

> **`plainSummary` strips only `*` and backticks.** The wider sweep that looks
> obvious eats `a > b`, `snake_case` and `#1`.

## `Parsing/`

### `HookPayloadDecoder.swift` · 128
The only point where external data enters the domain. Strict validation: no
required field is ever inferred or filled in with a default.

`ignoredEvent` is not a fault — the hook script forwards everything and the
filter lives here.

## `Reducer/`

### `StateReducer.swift` · 297
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

### `SessionsPayload.swift` · 101
The JSON contract. A type **separate** from `SessionState`, so an internal
refactor doesn't break its consumers. ISO 8601 dates, sorted keys.

### `AccessToken.swift`
Generation and **constant-time** comparison. The comment at the top says what the
token protects and what it doesn't: read it before quoting it elsewhere.

## `Setup/`

### `HookConfigMerger.swift` · 127
Adds and removes the hooks in `settings.json` **working on dictionaries**, not on
files: the I/O lives in the shell, so this logic — which modifies an important
user file — stays verifiable.

### `HookScriptBuilder.swift`
Generates `hook.sh`. See [02 Claude Code](02-claude-code.md#the-hook-script).

### `RewakeScriptBuilder.swift` · 130
Generates `rewake.sh`, the second `Stop` hook that carries a message into a
running session. Its stdout **is** the message; exit code **2** is the send.

> **A separate file from `hook.sh`, not an option inside it.** The two have
> opposite obligations: the traffic light hook must return in milliseconds or it
> delays every turn, and this one waits for minutes.

> **Three defences against a process that outlives everything**: it arms only when
> a conversation is selected, it gives up after thirty minutes, and a pid file
> stands a second listener down. Every path out is `exit 0` except the deliberate
> `exit 2` — a failing hook can interrupt a Claude Code turn.

## `Workspace/`

### `WorkspaceResolver.swift`
`cwd` + locks → which window. `window(hosting:)` also returns **which editor**,
because Cursor's bundle identifier differs from VS Code's.

### `WindowTitleMatcher.swift` · 92
Scores 100/50/10. It lives in Swift rather than inside AppleScript precisely so
it can be verified without opening windows.

### `IDEKind.swift`
The table of recognized editors: declared name, bundle, process name.
**Deliberately short** — see [N3](04-decisions.md#n3--jetbrains-and-the-other-ides).

### `IDEWindow.swift` · `LiveSession.swift`
The two parsers for the on-disk files.

### `SessionDeepLink.swift` · `AppleScriptString.swift`
The extension's URI and the escaping of titles inside a script.

---

# ClawdLightApp

It does I/O and draws. **It does not decide.**

## Entry point

### `main.swift` · `AppDelegate.swift` · 300
`MainActor.assumeIsolated` in `main.swift` is needed because top-level code isn't
isolated to the main actor, but that is where we are by definition.

`AppDelegate` wires everything up. `--headless` skips `startInterface()`, and
that is why the E2E suite didn't see the notification crash: it never went
through that branch.

`onMain(timeout:)` is the only writing crossing towards the main actor.

### `CommandLineInterface.swift` · 583
Ten commands. `new` and `chat` share `runSlotCommand`; `open` stays separate
because a bare `open` lists the assignments, which is a different command wearing
the same name. `focus --dry-run` diagnoses without moving any windows.

## `Runtime/`

| File | Lines | What |
|---|---|---|
| `StateStore.swift` | 149 | `@MainActor`, `@Published`, periodic realignment |
| `Preferences.swift` | 224 | `UserDefaults`, separate domain under `CLAWD_LIGHT_HOME` |
| `SnapshotBox.swift` | 32 | lock-protected copy for the server |
| `TokenStore.swift` | 78 | `0600` token, **regenerated** if the permissions are wide |
| `LocalClient.swift` | 122 | talks to the live instance for `sessions` and `next` |
| `SessionNotifier.swift` | 178 | `awaiting` notifications, anti-duplicate memory, gate |
| `TranscriptReader.swift` | 108 | follows one transcript by byte offset; resets when the file shrinks |
| `TranscriptPreviewReader.swift` | 108 | the last thing said, from the file's tail, cached on its size |
| `IDEWindowReader.swift` | 75 | reads the locks and **confirms them against the editor's process**, not the file's age |
| `MailboxWriter.swift` | 180 | the panel's end of the mailbox; carries out the reaper's verdict |
| `DictationService.swift` | 300 | `SpeechTranscriber` on the device, `AVAudioEngine` capture, macOS 26 only |
| `PresenceFile.swift` | 92 | presence file, deleted on shutdown |
| `LaunchAtLogin.swift` | 106 | blocked when the signature is ad-hoc |
| `LiveSessionReader.swift` | 70 | reads the live sessions; takes activity from the **transcript**, not the session file |
| `Diagnostics.swift` | | file log, active only with `CLAWD_LIGHT_DEBUG` |

> **`SessionNotifier`**: the `announced` memory has to be updated **even with the
> feature off**, or flipping the switch with ten blocked sessions fires ten
> alerts at once.

## `Server/`

### `SignalServer.swift` · 320
Seven routes. A **concurrent** queue: with a serial one, a `/next` waiting on the
main queue would also block reading the hooks' signals.

`/open`, `/new` and `/chat` share `handleSlotRoute`: they differ only in the action, so
method, authentication, validation and the three answers are written once. Both
carry the slot in the **body**, not the path — a router that has to interpret path
segments is a router with a parsing bug waiting in it, and this parser is
deliberately not a general-purpose one.

`requiredLocalEndpoint` is the line that binds the socket to loopback.
`acceptLocalOnly` does **not** do that.

## `Focus/`

### `VSCodeFocuser.swift` · 397
The most delicate file. Two strategies, three explicit outcomes.

> **To be read in full before touching it.** Every long comment in here
> corresponds to a defect that cost hours: null `stringValue` on lists,
> `activate()` lying, `open` with a path that creates new windows, the index that
> expires.

> **`DictationService`** — the ordering in `start()` is load-bearing and
> commented at length. `SpeechAnalyzer.start(inputSequence:)` is the pump, not the
> ignition: it does not return until the audio ends. Awaiting it left the state
> down, the button idle, `stop()` refusing to act and the **microphone open with
> no way back short of quitting**. Every exit path releases the input device
> first and unconditionally, for that reason.

## `Setup/`

### `HookInstaller.swift` · 187
Atomic writes and a dated backup. `availableBackupURL` appends a counter: two
installations in the same second used to fail.

## `UI/`

| File | Lines | What |
|---|---|---|
| `PanelController.swift` | 407 | holds everything together; row and panel actions |
| `TrafficLightRow.swift` | 222 | one row: dot, name, badge, timestamp, menu |
| `TrafficLightColumn.swift` | 188 | the column, the hidden summary, the filter note |
| `PanelRootView.swift` | 163 | the general menu |
| `TrafficLightDot.swift` | 52 | the dot and the silenceable blink |
| `StatusPalette.swift` | 99 | colors and measurements |
| `FloatingPanel.swift` | 45 | non-activating `NSPanel` |
| `ChatWindowController.swift` | 140 | owns the one extended window; opened on request |
| `ChatShell.swift` | 187 | every conversation, the selection, and what each costs |
| `ChatShellView.swift` | 215 | the two columns, and one row of the list |
| `ChatSession.swift` | 200 | one conversation: transcript on disk + status from the hooks + the composer's state |
| `ChatView.swift` | 250 | bubbles, activity lines, the composer |
| `MarkdownView.swift` | 175 | draws the blocks; inline markup goes to `AttributedString` |
| `DictationButton.swift` | 95 | the microphone, and the box that hides the macOS-26 seam |
| `Alerts.swift` | | dialogs |

> **`StatusPalette.timeColor`** is `Color.primary.opacity(0.62)` and not
> `.secondary`: over an `NSVisualEffectView` the weak semantic hues get
> attenuated a second time and disappear. The hierarchy comes from the font
> **weight**.

---

# The tests

## `ClawdLightTests/` — 364 cases

One suite per domain area. The most important ones:

| Suite | Covers |
|---|---|
| `StateReducerSuite` · `ReducerFixesSuite` | the state machine, including the four semantic corrections |
| `SubagentSuite` | counter and derived state |
| `ColumnLayoutSuite` | grouping, filtering, pinning, summary |
| `SlotAssignmentSuite` · `ColumnSlotSuite` | the arrangement, and that a slot survives an urgency reorder |
| `MailboxSuite` · `MailboxPermissionSuite` | hostile session ids, message limits, owner-only permissions |
| `RewakeScriptSuite` · `RewakeRegistrationSuite` | the script's promises, and the second `Stop` hook |
| `MarkdownParserSuite` | the constructs, and one whole answer containing all of them |
| `IDELockLivenessSuite` | a running editor is believed however old its lock is |
| `LivePruningSuite` | a session you can see running is never pruned for being quiet |
| `MailboxReapSuite` | an undelivered message keeps its conversation armed |
| `DictationLocaleSuite` | silence beats confident nonsense |
| `DeliveredMessageSuite` | recognising our own messages on the way back |
| `TranscriptDecoderSuite` | who spoke — including the 579-against-209 case |
| `TranscriptTailSuite` | the half-written line, split across up to three chunks |
| `TranscriptLocatorSuite` | the naming rule, accents included |
| `ConversationSuite` | unread counts answers, not your own messages |
| `WindowTitleMatcherSuite` | the scores |
| `AppleScriptEscapeSuite` | title escaping, including a hostile title |
| `AccessTokenSuite` | constant-time comparison, prefixes, empty expected value |

## `ClawdLightE2E/` — 75 cases

| Suite | Covers |
|---|---|
| `TransportSuite` | **the socket via `lsof`**, token, methods, refusals |
| `LifecycleSuite` | the states walked over HTTP |
| `CoverageSuite` | integrated terminal, subagents |
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
| `Scripts/test.sh` | both suites |
