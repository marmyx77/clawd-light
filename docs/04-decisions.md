# Decisions

Every entry says **what** was decided, **why**, and **what was discarded**.
The negative decisions — the ones about what *not* to do — are at the bottom and
are worth as much as the others: they are the ones somebody will redo first if
the reason isn't written down.

Format: the decision, the context, the alternatives, and the **signal that would
make it worth revisiting**.

---

## D1 · The state has two independent sources

**Decided.** Hooks for the events, filesystem for existence, realigned every five
seconds.

**Why.** The hooks report what happens, never what disappeared or what was
already there. With only the first source the column fills with dead rows and
starts empty on every launch; with only the second you would know who exists but
not what state they're in.

**Discarded:** reading the transcripts in `~/.claude/projects/`. It would give
more context at the cost of continuous I/O and of depending on an internal format
that changes.

**Signal to revisit:** if Claude Code exposed a reliable close event for every
way of terminating a session — Esc included.

---

## D2 · The displayed state is derived, not stored

**Decided.** `SessionState` keeps `baseStatus` and computes `status` from the
subagent counter.

**Why.** With background agents, `Stop` arrives **while they are working**.
Taking it literally paints green — "there is an answer to read" — onto a session
that is still working: the most expensive lie the column can tell.

Deriving also solves the way back: when the last agent finishes, the green that
was set aside resurfaces on its own, without anyone having to remember it.

**Discarded:** resetting the counter on `Stop`, as the plan said. It was written,
tried, and turned out to be exactly the wrong behavior.

**Cost accepted:** a lost `SubagentStop` leaves the counter hanging and the row
yellow. Mitigated by resetting at the **next prompt**, which is a certain boundary.

**The same rule, later, through a second door.** Background shells do it too: the
turn ends, the recap is written, and `run_in_background` work carries on. `Stop`
carries `background_tasks`, and any of them `running` now keeps the row working.
That case was examined on day one and dismissed with a coherent argument — that a
turn had ended and an answer existed — which answered the wrong question. Green
asserts *there is something to read* **and** *nothing more is coming*; only the
first was ever true there. See [Traps](07-traps.md).

---

## D3 · The criterion is where it runs, not how it was started

**Decided.** A session deserves a traffic light if its `cwd` sits inside a folder
an editor has open. The entrypoint only serves to **exclude** what isn't
interactive.

**Why.** `claude` launched from the integrated terminal has entrypoint `cli` but
runs in the same window, in the same project, and answers to the same click.
Filtering on an allow-list discarded it — and silently discarded every future
entrypoint too.

**The general point:** an **allow**-list, when it's wrong, hides. A **deny**-list,
when it's wrong, shows one row too many. The second mistake can be seen and
fixed; the first stays silent.

**Signal to revisit:** if enough non-interactive sessions appeared to make noise.
Today `kind == "interactive"` covers them.

---

## D4 · One row per project, on by default

**Decided.** Sessions from the same project share a single row. The dot shows the
most urgent state; the click opens the most urgent session.

**Why.** Measured: **22 distinct `session_id`s across 12 windows**. One row per
session drew 22 targets for 12 raisable windows, and ten of them led where
another already led.

**The risk, and its mandatory mitigation.** A click marks as seen **only the
sessions that were in the most urgent state** (`sessionIdsToClear`). Without that
limit, opening a project to answer a permission would erase the ready answer of
another session: grouping would become a loss of information instead of a
reduction in noise.

**Discarded:** keeping one row per session while sorting by project, so that
siblings stay adjacent. It reduces the disorder but not the number of redundant
targets.

---

## D5 · The deep link to the tab is off by default

**Decided.** The click raises the window. Opening the Claude tab as well is
optional, and starts off.

**Why.** Two consequences, which only surfaced once raising started working
properly:

1. VS Code asks for permission on **every** invocation. A click that asks for
   confirmation is no longer a click.
2. The extension reuses the tab only if it already has a panel for that
   `sessionId`; otherwise it **creates a new one**. That always happens for
   integrated-terminal sessions, which have no Claude panel at all.

The click keeps its promise anyway, because taking you to the right window is
done by accessibility, not by the link.

**Why it stays in the code:** for anyone working with one session per window and
Claude panels always open, it works well. The switch is also the escape hatch if
a future version of the extension breaks the contract.

---

## D6 · It raises by title, not by index

**Decided.** Recognition picks the title in Swift; AppleScript receives the
**name** to look for.

**Why.** Reading the titles and raising are two distinct Apple Events, and the
list is in depth order: between the two, the order changes on its own as soon as
the focus moves. The index computed against the first list ends up pointing at
another window — typically the last one used. Symptom: "sometimes it raises the
wrong one".

**Discarded:** moving the recognition inside AppleScript to do everything in one
call. It would make the most bug-prone part of the project unverifiable without
opening windows.

**Cost accepted:** the title can change between the two calls. In that case the
script fails with `-1728` and falls back, instead of raising the wrong window.

---

## D7 · `POST /signal` without a token, `GET /sessions` with one

**Decided.** Asymmetric on purpose.

**Why.** The read endpoint exposes the names and paths of the open projects,
which on a development machine are information. The one that *receives* the
signals, by contrast, cannot afford to fail: the hook script runs as the user and
could read the token, but a hook that fails authentication would block a Claude
Code turn for the sake of a decorative widget.

**What the token really protects against.** Other users on the machine, and
anyone arriving from the network. **Not** a process running as your own user:
that one can open the `0600` file, and no on-disk secret can prevent it.

Presenting it as a defense against the code running inside the sessions would be
a false reassurance — worse than no defense, because people stop thinking about it.

---

## D8 · The features that ask for permissions start off

**Decided.** Notifications and the presence file are off by default. Neither asks
for an authorization until you turn it on.

**Why.** A system dialog that appears unasked gets a "no", and that "no" is
forever. Asking at the moment the user flips the switch is the only moment when
the answer is informed.

For the presence file there is a further reason: it **inverts a built-in
behavior** of Claude Code. If the detection gets it wrong, the result is not one
notification too many but a notification **lost** — and lost notifications go
unnoticed.

---

## D9 · Only `awaiting` is notified, never `ready`

**Decided.** Only the state that **blocks**.

**Why.** A ready answer can wait until you look at it; a permission cannot —
until you answer, that work is stopped. With a dozen sessions, notifying on green
as well would produce tens of alerts a day, and a channel that alerts too often
gets switched off within two days. At that point the real blocks would stop
arriving too.

**A detail that matters:** what gets notified is a **transition**, not a state.
With the feature off the notifier keeps taking note of what is already blocked,
so flipping the switch with ten stalled sessions doesn't fire ten alerts at once.

**The gate holds only explicit silences.** There used to be a presence condition
as well — no alert if the panel is visible and you touched the Mac recently — and
it was removed in the face of the evidence: the panel is floating, so it is
always on screen, and if you're at the Mac you're active. What remains are three
checks the user chooses and can see: the memory that avoids duplicates, the
per-project silence, and the timed one.

---

## D10 · Failures get stated

**Decided.** Every operation that can fail silently declares it: a raise that
only half worked leaves a note in the menu, the signing script verifies before
declaring success, `LaunchAtLogin` refuses to register instead of registering an
identity that will change on the next build.

**Why.** This project lost more time to **fake successes** than to errors. An
alert shown after a success, a script that said "✓ created" after a failed
import, an `activate()` returning `true` without activating anything: every time
the symptom appeared days later, far from the cause.

**Concrete form:** `FocusResult` is a three-case enum rather than an `Error?`,
because `raised`, `activatedOnly` and `failed` deserve different reactions —
silence, a note, an alert.

---

## D11 · A test framework of our own

**Decided.** `TestKit`, 227 lines.

**Why.** The Command Line Tools without Xcode provide neither XCTest nor the
complete swift-testing. This is not a preference: the alternative was having no
tests.

**Consequence:** the tests are executables (`swift run ClawdLightTests`), not a
test target. That's fine: it makes running them anywhere trivial, even inside
another process.

---

## D12 · Two suites, not one

**Decided.** `ClawdLightTests` for the domain, `ClawdLightE2E` for the chain.

**Why.** In this project the worst defects have never been inside a function:
they were in the **seams**. Title matching stayed broken for a whole day with ten
green tests; the socket was listening on every interface while the code looked
like it said the opposite.

The E2E suite launches the production binary against a fake home and talks to it
over HTTP, going as far as running `hook.sh` with the payload on stdin. It
verifies the **fact**, not the intention: the socket defect was found by looking
at `lsof`, not by re-reading the code that configured it.

**Cost accepted:** a minute against instantaneous. That is why they are separate.

---

## D13 · A keyboard slot is a pin, not a row number

**Superseded by [D23](#d23--the-column-does-not-reorder-itself).** The premise —
that the column reorders by urgency and so a row number cannot be an address —
no longer holds: the column keeps the user's order, and a slot is now simply a
position in it. Kept as written, for what it teaches about addresses.

**Decided.** Pinning a project binds it to the next free slot, 1 to 9.
`clawd-light open 3` raises whatever holds slot 3. Pinned rows sit at the top of
the column **in slot order**.

**Why not just number the rows.** The column reorders by urgency continuously —
that is its whole job. A key bound to "the third row" would point at a different
project every few minutes, and a shortcut that acts on the wrong session is worse
than no shortcut: you press it without looking, which is the only reason to have
it. An address that moves is not an address.

So the order cannot come from anything the app observes. It has to come from the
user, and pinning was already exactly that — a short, deliberate list of projects
that matter. One concept now does two jobs that were always the same job: keep it
on top, and give it a key.

**What it cost.** Pinned rows no longer sort by urgency among themselves. A pinned
project that starts waiting stays where it is — it lights up, and it is still
above everything unpinned, but it does not jump to the front of its own group.
That is the price of the address being stable, and it is pinned down by a test so
nobody removes it as a bug.

**Discarded:** a second concept, "slots", separate from pinning. It would have
avoided touching existing behavior at the cost of two near-identical lists in the
menu, and this project's rule is that a feature which doesn't answer the question
doesn't get in.

**Discarded:** leaving a hole when a middle slot is unpinned, so the ones below
keep their keys. It is the more faithful analogue of physical keys, but it needs
an array with gaps in `UserDefaults` for a rare case. Unpinning compacts instead,
and "Move up / Move down" exists for anyone who wants to rearrange without
unbinding.

**Where the idea came from.** The Codex Micro's six Agent Keys, each bound to a
thread. The hardware makes the stability obvious — a key is a physical place. In
software it is the part you have to build on purpose.

---

## D14 · Two surfaces: a column you glance at, a window you sit down in

**Decided.** The panel is unchanged — a column of traffic lights that never takes
focus. The **extended window** is separate and opens on request: conversations on
the left, the selected one on the right. Close it and you are back to the lights.

Three ways in: the panel menu, ⌘+click on a row (which lands on that
conversation), and `clawd-light chat <n>`.

**Why the panel could not simply grow.** It is a non-activating `FloatingPanel`,
and that is the whole reason it works: it sits beside the editor you are typing in
and must never steal focus. The extended view needs the opposite — you scroll it,
you select out of it, you type into it, you want it in ⌘-tab. One window cannot be
both, and the choice is not close.

**Discarded: one window per conversation, the ICQ shape.** It was argued for at
length — a roster of *states* rather than a list of messages, which is
structurally what this column is — and it was built, and it lost to half a day of
use. Switching project meant hunting for a window; with a dozen open, the desk
becomes the thing you manage. A list you click down is faster than a window you
look for. The argument was good and the use was better.

What survived that reversal is everything that was not about window management:
the transcript reader, the decoder, the mailbox, their tests. Only the pixels
moved.

**The cost, and the number that bounds it.** Every conversation you visit stays
parsed in memory so returning is instant, but **only the selected one polls its
file and only the selected one arms a message listener**. The running cost of the
window is one file poll and at most one waiting process, whatever the length of
the list.

**Discarded: embedding the real VS Code panel.** macOS does not let one
application host another's window; the ways round it are private SkyLight APIs and
a weakened SIP. What *is* reachable — positioning detached VS Code windows behind
our sidebar and raising the one you want — turns clawd-light into a window
manager, and window managers die on Spaces, full screen and multiple displays.
Left as an experiment, not a plan. Note in passing that VS Code already ships the
useful half: **Claude Code: Open in New Window** detaches the chat into a bare
window of its own.

---

## D15 · Writing into a running session, through the front door nobody documented

**Decided.** The extended window has a composer. A message written there is left
in a mailbox on disk, and a **second `Stop` hook** marked `asyncRewake` carries it
into the session at the end of its next turn.

The mechanism in one line: Claude Code spawns that hook **detached**, so it
outlives the turn; whatever it prints on stdout becomes a message and **exit code
2 sends it**. Both halves of "send" are one act.

**Why this and not the obvious routes.** Eight ingress surfaces were investigated
and six are closed for good — recorded under
[N7](#n7--acting-on-a-running-session--the-codex-micro-command-keys) and in
`Contracts/assumptions.md`. The deep link refuses a prompt to an open panel;
the IDE WebSocket exposes twelve editor tools and no way into the chat; a
companion extension cannot reach another extension's webview, by platform
invariant; `--resume` from a second process **forks the transcript into a tree
with no warning**, and a completed turn was lost that way in testing.

**Why files and not a socket or a pipe.** The reader is not ours: Claude Code
spawns it, at a moment we do not choose, and it has to find the message already
there. Opening a named pipe for writing blocks until a reader exists — so typing
while Claude worked would hang the panel, which is exactly when you most want to
type. A file is late-binding by nature, and "queue it while busy" falls out for
free.

**Three things that are true and unpleasant, and are surfaced rather than hidden:**

- **`asyncRewake` is `@internal`.** It can be renamed without deprecation, and
  when it is, delivery stops **in silence** — no error, no log, the message simply
  never arrives. The contract check greps the shipped binary for the names on
  every run. That check is the warning, and it is not optional.
- **A dormant session hears nothing.** A listener can only be born at the end of a
  turn, so opening a conversation that is doing nothing arms nothing. The window
  says so — *"this session is dormant"* — instead of showing a spinner for
  something that will never happen. It resolves itself the moment anything happens
  in that session.
- **The mailbox has no authentication, so the whole feature is off by default.**
  Dropping a file in it starts a turn that speaks in the user's voice with their
  tools. Permissions are `0700`/`0600`, like the access token, which stops another
  account on the machine — and stops nothing running as the user. There is no fix
  available: the reader is a shell script Claude Code spawns and it cannot know who
  wrote the file.

  So the switch decides, and it starts **off**. While it is off the listener is not
  registered at all: no hook, no mailbox, nothing on the machine that can start a
  turn in your name. Turning it on shows a dialog that states the trade in those
  words. The window reads everything either way.

  This follows [D8](#d8--the-features-that-ask-for-permissions-start-off), and for
  a sharper reason than the features it joins: those default off to avoid being a
  nuisance, this one defaults off because it is a capability.

  **The precise shape of that limit**, which took reading tmux to state properly:
  it is not that authentication was left out of the mailbox, it is that **a file
  has no author and a socket does**. tmux carries the same threat model — a socket
  in a directory anyone on the machine can try — and answers it with `getpeereid()`
  on the connection, a uid and gid attested by the kernel rather than claimed by
  the caller, with an ACL layer on top. A file dropped in a directory carries no
  equivalent. So per-writer authorization here is not a feature that is missing; it
  is a consequence of choosing a drop directory as the channel, and it could only
  ever be reopened by changing the channel — which the paragraph above explains we
  cannot do, because the reader is not ours to design.

  What *is* borrowed from tmux, and now implemented, is the smaller half: before
  writing through that path, `lstat` it and refuse anything that is not a real
  directory belonging to this user. Creating narrowly and being narrow are not the
  same thing — `createDirectory` succeeds against a symlink already in place, and
  the `chmod` that follows lands on the link's target. tmux refuses to start at all
  in that situation.

**What it looks like on the way back.** A delivered message returns wearing a
`task-notification` origin, the same envelope a background agent gets. The window
recognizes its own by the preamble it puts on outbound messages and draws it as
the user's own bubble; the VS Code panel cannot, and will show it as a system
turn. That difference is not fixable and is not worth hiding.

**Verified by reproduction**, three times, twice through the shipped scripts: an
idle session, a message written by an unrelated process, and a full agentic turn —
reasoning, tool call, answer — one second later.

---

## D16 · Markdown is parsed in Core and drawn in the shell

**Decided.** Answers are split into blocks by `MarkdownParser` and drawn by
`MarkdownView`. Headings, paragraphs, lists, fenced code, quotes, rules and pipe
tables; inline markup goes to `AttributedString`, which the platform already
provides.

**Why not a library.** The project has no dependencies, and a rendering package
brings a build story, a version to track and a surface to follow, in exchange for
constructs Claude does not write.

**Why the split.** Parsing is a decision and belongs where it can be tested
against awkward input without drawing anything; the seams between constructs are
where such parsers fail, and there is a test that feeds it one answer containing
every construct at once and asserts the order.

**Two rules that came from the content, not from taste:**

- **Code blocks and tables scroll sideways rather than wrap.** A wrapped command
  line cannot be copied and pasted, and copying things out of this window is most
  of why it stays open.
- **The user's own messages are not rendered as markdown.** They typed plain text;
  turning their asterisks into emphasis would put stress in their mouth they did
  not write, and would eat the characters.

**Anything unrecognized becomes a paragraph** — its own source text, readable —
rather than disappearing. That is the safe direction to be wrong in.

---

## D17 · The conversation list shows what was actually said

**Decided.** The line under each name is the last thing spoken, read from the
transcript.

**Why not `last_assistant_message`**, which the hooks hand over for free: it is
wrong twice. It is only ever Claude's side, so a project you have just written to
shows the previous answer — and on an interrupted turn it holds the **error text**
rather than anything anybody said.

**How the cost is kept.** Only the last 32 KB of each file is read; when that
slice holds nothing but tool calls — which is what the tail of a working session
looks like — it widens twice and then leaves the row blank rather than reading the
whole file; and results are cached on the file's size, which only grows. Drawing
the list costs one `stat` per row when nothing has moved.

---

## D18 · Dictation is ours, on the device, and it does not press send

**Decided.** A microphone button in the composer, using `SpeechTranscriber` — the
macOS 26 speech API. Everything on the device: no audio leaves the Mac and the
language model is a local asset. Press to start, press to stop, and what was heard
**goes into the box**, not into the session.

**Why not just the system's dictation**, which needs no code and no microphone
permission from us because the system captures and inserts the text. It is the
right answer for anybody it works for, and the README says so. It is driven by a
system shortcut rather than a control, it is off by default on a fresh Mac, and it
cannot do the one thing that makes dictation worth having in a chat: stop talking
and have the words be there.

**Why it does not send.** Dictation mishears. A wrong sentence you can still edit
is a different object from one already delivered, and delivery here starts a turn
that spends tokens and runs tools.

**Why the language is chosen strictly.** The recognizer transcribes everything as
the locale it is given, so handing it English for an Italian speaker does not
degrade politely — it produces fluent nonsense that nothing downstream can detect.
The rule is exact language and region, then the same language elsewhere, then
**nothing**: a refusal the interface can explain beats a confident lie. There is a
test named for it.

**What it costs.** Two permissions, and the feature exists only on macOS 26 —
below that the button is not drawn at all, because a control that cannot work
invites a click and answers with silence.

**Discarded:** shipping without the pulsing indicator. It is the only proof the
microphone is open; a dictation that silently failed to start looks exactly like
one listening patiently. That was not hypothetical — the first version had a
defect where the microphone opened and the state never went up, and without the
pulse there was nothing on screen to say which of the two had happened.

---

## D19 · The panel reports what it knows, and does not deduce what it doesn't

**Decided.** A session adopted from the filesystem, about which no hook has yet
spoken, is `idle`. Not because it is at rest — we have no idea — but because that
is what "no information" looks like in this vocabulary. The first hook replaces it.

**Why this is a decision and not a default.** It was briefly replaced by an
inference: *the transcript moved in the last forty-five seconds, therefore a turn
is in flight*. It reads as reasonable and it is wrong on exactly the day it
matters. A transcript is appended for many things that are not a turn, **resuming
a session among them** — so after a reboot, twelve sessions resume at once, twelve
files move at once, and every light turns yellow. A column that is uniformly wrong
is worse than one that is uniformly cautious: the panel exists to make one session
stand out.

**The general rule this belongs to**, which the project had already and which the
episode cost a day to relearn: **a state is measured or it is absent.** Deriving
it from a proxy — a file's age, a directory's contents, a count — produces a value
that is right in the calm case and confidently wrong in the busy one, and the busy
one is when somebody is looking.

The corollary is what to do with the proxy. The transcript's timestamp is real
evidence of *when*, and it is used for the clock on the row. It is not evidence of
*what*, and it is kept away from the color. Same measurement, two questions, one
answer each.

**Signal to revisit:** a source that says what a session is doing rather than when
it last did something. The last record of a transcript is a candidate — a
`tool_use` means a turn is in flight, an `end_turn` means it is not — and that
would be measurement rather than inference. It is not built, and it is worth an
hour with tests rather than ten minutes without.

---

## D20 · The traffic light does not answer questions

**Decided.** clawd-light registers only hooks that **observe**. The four that
**decide** — `PermissionRequest`, `PermissionDenied`, `Elicitation`,
`ElicitationResult` — stay unregistered, and this is a standing rule rather than
a to-do item.

**What makes them different.** Every hook this app registers today is a spectator:
Claude Code sends the event, the script forwards it, the turn continues whatever
happens. The script cannot alter the session, because there is no channel through
which it could. The decision hooks have one. Their output schema, read in the
binary, carries a verdict:

```
hook_event_name: "PermissionRequest",
decision: { behavior: "allow", … } | { behavior: "deny", message?, interrupt? }
```

Registering one puts the script between *"Claude wants to run `rm -rf build/`"*
and *"the user decides"*. It would print nothing, as it does today, and the
question would reach the user unchanged. But the **cost of a defect** changes
class: today the worst a broken hook does is leave a light behind; there, stray
output that parses as a verdict approves a tool call the user never saw.

**What we would gain, stated fairly**, because the trade is real and not
one-sided. `PermissionRequest` carries `tool_name` and `tool_input`, so the row
could say *"waiting: Bash — rm -rf build/"* instead of an unexplained amber. And
it would replace an inference: today `awaiting` is derived from `Notification`
plus a `notification_type` subtype that nobody documents and that also carries
`idle_prompt` — the field that once had this app inventing answers that never
arrived. A dedicated event is strictly better evidence.

**Why the answer is still no.** The gain is precision on a state that already
works. The cost is that a monitor becomes a participant. This project keeps its
capabilities off by default and its one writing feature behind an explicit switch
([D15](#d15--writing-into-a-running-session-through-the-front-door-nobody-documented));
sitting in the permission path by default would contradict that on the app's most
sensitive surface.

**And the evidence is not there anyway.** The schema is measured. The *firing* is
not: a non-interactive `claude -p` never reaches an approval prompt — three probe
sessions, including one forced with `--permission-mode manual`, ran the tool and
produced no `PermissionRequest`. Which is exactly the standard of proof that had
just collapsed under `TaskCreated`, one hour earlier, in
[docs/07-traps.md](07-traps.md).

**Signal to revisit:** a measured, interactive recording showing that a hook
returning empty output leaves the approval flow untouched — **and** a decision
that the amber row is worth naming the tool. The first is a fact; the second is a
posture, and it is the user's to take, not the code's.

---

## D21 · Other machines are read, not heard

**Superseded in part by [D24](#d24--other-machines-are-heard-through-a-tunnel-we-open).**
Reading stayed — it is how a remote row is confirmed alive — but it stopped being
how a row is *born*: a row nobody can click and that never changes colour turned
out to be noise, and the tunnel D24 opens is not the network exposure this entry
refused. Kept as written for the reasoning about `/signal`, which still holds.

**Decided.** Sessions on another machine appear in the column because clawd-light
**asks that machine over ssh**, on a slow timer. The alternative — installing the
hook there and letting it post here — stays closed.

**What made the choice.** `POST /signal` carries no token. `GET /sessions` does,
`/signal` never did, and on loopback that was a defensible asymmetry: anything
already running as the user can move the column, and a token would not change
that. It stops being defensible the moment the endpoint is on a network. Opening
it on the tailnet would put **unauthenticated state injection** on every device
that can reach the Mac, to save twenty seconds of latency on a machine nobody is
looking at.

Reading needs nothing open, no token to distribute, and no new listening surface.
It also matches what the distributed-brain plan already says out loud —
local-first with aggregation, no single point of failure — and it fails in the
right direction: a node that is asleep costs one poll that returns nothing.

**What the node does, and why there.** Two of the three facts a row needs are only
true where the processes are: whether the pid is alive, and when the transcript
last changed. So the probe runs *there* — piped to `python3` over the connection,
nothing installed, nothing left behind — and returns one JSON array. Deciding
here from shipped files would answer both questions about the wrong machine.

**Three things this makes different, on purpose:**

- **A remote workspace is the session's own folder.** Locally a row exists only if
  an editor window claims the `cwd`, because the panel is about windows you can
  click. That criterion is meaningless for a tmux pane on a headless node, and
  applying it there is exactly what kept those rows invisible: no lock on this
  machine claims `/home/…`, so every one was dropped.
- **`nil` and `[]` are different answers.** The reader returns an optional: `[]`
  means *asked, nothing running*, `nil` means *no answer*. Collapsing them would
  let a dropped VPN erase live rows — the same mistake as reading a timestamp and
  calling it a heartbeat. A host that does not answer keeps its previous rows.
- **A click on a remote row raises nothing.** There is no window here. It says
  where the session is instead of opening a modal that says "cannot open".

**What it does not do.** The chat window cannot open a remote conversation: the
transcript is on the other machine. Reading it over ssh on every poll is a
different feature with a different cost, and it is not in this one.

**Cost.** One ssh handshake per host every twenty seconds, against five seconds
for the local pass. `BatchMode=yes` so a host wanting a password fails in a second
instead of waiting for a prompt nobody will see, and a hard kill at twice the
timeout so a half-open connection to a sleeping node cannot hold the poll.

**Off unless asked.** Hosts come from `~/.clawd-light/remotes`, one per line.
Absent or empty means off, which is the default: reading another machine is an
outbound connection this app would otherwise never make. Names are checked against
an allow-list before reaching ssh — a name starting with a dash would be read as
*options*.

**Signal to revisit:** a token on `/signal`. With one, the push route becomes
defensible and the latency goes away; without one, this decision stands.

---

## D22 · A sixth state, for a session that has stopped but is not done

**Decided.** `waiting`, soft blue: the turn is over, and something Claude started
— a background shell, a monitor on a CI run, a subagent — is still running and
will wake the session. It sits between `working` and `idle`, does not blink, has
nothing to clear on click, and resists a trailing tool event the way green does.

**Why five were not enough.** The rule "work in flight at `Stop` keeps the row
working" fixed a real lie — green over a session with a shell still running — by
telling a smaller one. Yellow means *Claude is thinking*. After a `Stop` with two
monitors on a CI run and a shell serving the tests, Claude is not thinking: it has
handed control back and is **waiting for an event**. A CI run takes an hour; the
row said "working" for an hour; and the person looking at it, rightly, asked what
on earth it was working on. Measured on the log that answered:

```
Stop  working -> working  inFlight=3[monitor,monitor,shell]
```

**It is not an inference.** The state is exactly what the payload declares:
Claude Code documents `background_tasks` as the way to tell *"session is done"*
from *"session is paused waiting for background work to wake it"*. The first is
green, the second is blue. Nothing is guessed from timestamps or silence.

**What the row says.** `waitingOn` keeps the types, so the tooltip reads
`waiting on monitor ×2, shell`. A blue row that stays blue for a day is now a
row that names the shell holding it — which is what makes the remaining honest
question, "is that shell a dev server nobody will ever stop?", askable.

**Subagents follow the same grammar.** A subagent alive after the parent's `Stop`
used to paint yellow over any state; it now paints blue, for the same reason.
And a subagent *starting* proves the turn is running, so the declared state
becomes `working` wherever the row was — that is what releases a pending question
too (D20's sibling rule).

**The way back is the same as before.** The work finishes, Claude Code starts a
turn to report it, `UserPromptSubmit` paints yellow and empties `waitingOn`, and
that turn's `Stop` is green if nothing else is in flight.

**Alternatives.** Keeping it yellow with a tooltip — but the colour is what you
see from across the room, and it was the colour that lied. Going straight to
green — the lie D17's ancestor fixed. A blinking blue — blinking is spent on the
one state that blocks you, and this one does not.

---

## D23 · The column does not reorder itself

**Decided.** Rows keep the place the user gave them. A project seen for the first
time is appended at the bottom; from then on it moves only when dragged by its
handle (≡, on the right of the row) or nudged from the menu. A change of state
lights a row up **where it is**. Slots are positions: the first nine rows are
keys 1 to 9. This supersedes D13, which no longer has a problem to solve.

**Why.** Reported by use, and true on reflection: a column that re-sorts itself
has to be re-read every time it changes. A green rising to the top pushes every
other row down by one; a red sinking pulls them all up; and the eye, which had
learned that the third row is *that* project, finds something else there. The
urgency sort was built to answer "which one needs me" — but the colour already
answers that, and answers it without moving anything. Sorting moved rows to say
what the colour was saying already.

The second cost is what made it a defect rather than a taste. A row that moves
under the pointer is how the wrong session gets opened (07-traps, *The click that
only knocked*): the first click cleared a green, the column re-sorted, the second
click landed on whatever had moved in. A fixed order removes the mechanism, not
just the symptom.

**What it cost.** A row asking for attention at the bottom of a twelve-row column
is a dot at the bottom, not at the top. The notification and the blinking amber
still cover the case where you are not looking, and "only what's waiting"
collapses the column to the rows that need you — in your order. Pinning is gone
as a concept: every row is where you put it, so "pin to top" is a drag. The
`pinned` field left the `/sessions` contract; nothing outside read it and it had
no meaning left.

**Discarded:** freezing the order only while the pointer is over the panel. It
prevents the mis-click and keeps the urgency sort — but the column still shuffles
the moment you look away, which is the part that was reported as confusing.

**Discarded:** urgency *within* the user's order, e.g. a green rising among its
neighbours only. Half a fixed order is no order: the eye cannot learn a rule
with an exception in it.

**Where the order lives.** `preferences.rowOrder`, one list for three readers —
the panel, the extended window and `/sessions`. `StateStore` gives a newcomer its
place *before* publishing the state, so headless mode and the CLI agree with the
panel; the panel rebuilds its view when the options it was built with change. The
list may name projects with no live session: their slot is empty, and `open n`
says so rather than opening the neighbour — unchanged from D13, and still the
worst thing a blind key could do. Whoever upgrades finds their pinned projects at
the top, in slot order, and everything else below as it is seen.

---

## D24 · Other machines are heard through a tunnel we open

**Decided.** A remote machine's Claude Code hooks reach this Mac through a reverse
ssh tunnel clawd-light opens and keeps open: `ssh -N -R 127.0.0.1:9877:127.0.0.1:9877
host`. On the node, `127.0.0.1:9877` *is* this app, so the hook script installed
there — by clawd-light, over ssh, with the same merge the local installer uses —
posts exactly like the local one and adds one header, `X-Clawd-Host`, naming the
machine. A remote row is **born when the session speaks** and **dies when the
node's probe no longer lists its pid** (or on `SessionEnd`). Clicking it raises the
Remote-SSH window of its folder, if one is open here. Hosts are configured in the
Settings window (or `clawd-light remote add`), not in a file.

**What was wrong with D21, measured.** Reading alone produced rows that never
changed colour — no hook ever reached this machine — and that a click could not
open; and it listed every live `claude` on the node, including one left in a
detached tmux for two days that nobody had opened from here. *"Always red, the
click goes nowhere, the sessions look random"* is the accurate description of a
row that carries no state, no target and no consent. The session the user actually
drives lives in a **Remote-SSH** window on this Mac, titled `… — folder [SSH:
host]`: there was a window to raise all along.

**Why a tunnel and not a token.** D7's argument stands: `/signal` has no token,
and putting it on a network interface would be unauthenticated state injection
from every device on the VPN. The tunnel does not do that. Its far end is bound to
the node's loopback, so the only thing that can post through it is a process
running on the node as that user — the same trust the local loopback already
extends to every process on this Mac. A token would have to be distributed and
rotated on every node; the tunnel needs only what already exists, the ssh key.

**Why born by hooks, not by the probe.** The obvious presence rule — "the cwd is
inside a folder some editor window has open on the node", i.e. the local rule
applied there — was tried on paper against the node and failed: the one ide lock
there is `/home/<user>`, and every session on the machine is under it. A row that
exists because the session did something is a row about something you did; the
probe still answers the one question it is good at, *is this pid still alive*,
now with a guard against reuse (`procStart` against `/proc/<pid>/stat`). A host
that has never answered keeps its rows — silence is not death — and a host
removed from the settings takes its rows with it.

**What it cost.** A remote session that has said nothing since the panel started
is invisible until it does. The tunnel is a long-lived ssh process per host,
restarted with backoff when the node sleeps or the VPN drops, and `POST /signal`
is reachable by any process on the node's loopback. Installing the hooks means
clawd-light writes `~/.claude/settings.json` on another machine — with a dated
backup, atomically, through Python fed on stdin so no shell ever sees the data.
No tab deep link for a remote row: the link goes to the local extension host.

**Discarded:** reading Claude Code's own `status` from the session files. It is
there — for `cli` sessions, since 2.1.243 — but not for the VS Code extension's
sessions, and only `idle` was ever observed. Half a source is a guess with a
timestamp.

**Discarded:** a token on `/signal` and the port on the tailnet. Right in
principle, and a second secret to manage on every node for what one existing key
already does.

**Signal to revisit:** a node that is not reachable over ssh but can reach the Mac
— the tunnel then has to be opened from the other side, and that is a different
feature.

---

# Negative decisions

What was decided **against**. If somebody picks these up again, they have to
answer first the reason they were excluded.

## N1 · Allowing or denying a permission from the row

The `PermissionRequest` hook exists in binary 2.1.220 and can decide the outcome.

**Why not.** The hook **blocks the turn** until it answers. If clawd-light isn't
running or has crashed, **every permission request hangs** — a decorative widget
would become a breaking point for the real work.

And a widget that grants permissions to Claude Code is an attack surface on a
local endpoint.

**What it would take:** authentication on every route, and a safe default
behavior if the panel doesn't answer within a short time.

## N2 · A summary when you come back

A single notification on your return, instead of one per event.

**Why not.** When you come back you look at the panel anyway, and the column
already says everything. To be done **only if** the per-event notifications prove
noisy — and today they are off, so that evidence doesn't exist yet.

## N3 · JetBrains and the other IDEs

**Why not.** `WindowTitleMatcher` is tuned to VS Code's format
(`file — folder — profile`); JetBrains uses `project – file`, which is a
different grammar. Adding an editor that can't be tested doesn't widen coverage:
it creates a row you can see and a click that doesn't work, which is **worse than
no row** because it teaches you not to trust it.

Cursor is included because it is a VS Code fork — same lock format, same title
format — and only three names differ, read from the `Info.plist` rather than
guessed.

## N4 · The extension's MCP server

The extension exposes an MCP server over WebSocket with twelve tools for
manipulating the editor.

**Why not.** It would give far more control than a traffic light needs, and it
would tie the project to an internal interface much wider than a URI handler.

## N5 · `windowId` in the deep links

**Why not.** Routing between windows turned out to be non-deterministic: the link
lands where the focus is, not where the parameter says.

## N6 · A global shortcut inside the app

**Implemented, tested, and removed.**

`RegisterEventHotKey` is the only route without extra permissions for an
*accessory* app. On macOS 26 it **registers and never delivers**: verified with
two independent binaries, same recipe, live panel, zero events.

The alternative that does work requires **Input Monitoring** — permission to read
every key pressed. For a traffic light that is out of proportion.

**But the reason it was removed rather than left switched off is a different
one:** `register()` returns success, the switch stays on, and nothing happens.
The app **cannot notice** that it doesn't work, so it cannot say so. It is the
"fake success" category — the same as `activate()` returning `true` without
activating, and the script that said "✓ created" after a failed import. A switch
that can lie is worse than a switch that isn't there.

**In its place**: `clawd-light next` exists and works, and binding a combination
to that command is what the macOS Shortcuts app is for. It isn't a fallback — it
is better on three counts: the user picks the combination, the interface says
whether it is already taken, and when it doesn't work you can see it.

**Signal to revisit:** a system API letting an accessory app register *one*
combination with verifiable delivery.

---

## N7 · Acting on a running session — the Codex Micro command keys

OpenAI's Codex Micro (July 2026) puts *command keys* on a macropad: accept, reject,
push-to-talk, branch, new chat — all acting on the agent thread that is currently
running. The question was whether clawd-light could do the software equivalent.

**Why not.** Every one of those reduces to the same primitive: *send text to that
specific session*. The channel looked available — the extension's `/open` URI
handler reads a `prompt` parameter next to `session`. It isn't. The extension
applies the prompt **only when it creates a new panel**, and refuses otherwise
with a message written for the user:

> `"Session is already open. Your prompt was not applied — enter it manually."`

The one case where sending text would be useful — a session that is open and
waiting for you — is exactly the case it refuses. What remains reachable is
"open a **new** conversation, pre-loaded with a prompt", which starts work rather
than steering work in flight. That is not the feature.

**What was worth taking anyway.** Two things, both of which needed an address
rather than a channel — see [D13](#d13--a-keyboard-slot-is-a-pin-not-a-row-number):

- **Agent Keys** → `clawd-light open <n>`, raise the project in slot n.
- **"Start new chat"**, which is one of their command keys and the only one that
  survives, because it creates a **new** panel instead of touching a running one
  → `clawd-light new <n>`.

**And the half-measure that was left out.** The `prompt` parameter does work on a
new conversation — but following it into the webview shows it ends at
`setInputText`, which **prefills the composer and does not submit**. A key that
opens a tab with text you still have to confirm is not a command key, so
`clawd-light new` sends no prompt. It is recorded in
`Contracts/assumptions.md` under `extension.newconversation`, because "we already
checked, and here is how far it goes" is the part that stops the question being
reopened from scratch.

**The rotary dial, for completeness.** `effort.level` arrives on every `Stop`, and
`--effort` / `/effort` can set it — but only when a session starts, or by typing
into it. The dial's whole value is changing it mid-flight, which is the same wall.

**Cost avoided.** The refusal was found by reading the shipped extension, not by
testing against a live session. Two minutes instead of an intrusion into a working
desktop — and a firmer answer, because a user-facing string in the code is a rule,
not an observation that might have been a fluke.

**Signal to revisit.** The refusal disappearing. It is tracked in
`Contracts/required-fields.json` under `extensionOpportunities`, and
`check-contract.sh` reports it as an **opening** rather than a breakage — the one
place where the contract checker watches for good news.

## How to add a decision here

When you make a non-obvious choice, write it down **before** implementing it,
with the alternatives you are discarding. If the implementation then proves you
wrong — as happened with D2 — rewrite the entry saying what you learned, instead
of deleting it. A decision overturned by a fact is more instructive than one that
was right first time.
