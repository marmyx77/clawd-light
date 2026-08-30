# Plan: one block per project, and Codex made real

> Written 30 August 2026, from `8ef77aa` plus uncommitted work.
>
> It merges two threads that turned out to be one: the panel can no longer tell
> apart the sessions inside a project, and Codex is only half present. Both end at
> the same place, a row that says exactly what it can prove and nothing more.

## 0. Where this starts

### What is already done, and green, but not committed

Written today against `8ef77aa`, with **586 domain cases, 82 end-to-end, 10
documentation gates and 22 mutations caught**:

- every session reads its own title, not only the terminal ones. Editor sessions
  had no name at all, which is why three conversations in one folder were
  literally the same string;
- `RowSession` gives a row's conversations a **stable order and a name each**, by
  first-seen time, never by urgency;
- `SessionState.firstSeenAt`, preserved by every copy, because `updatedAt` and
  `statusSince` both move and neither can order a list that must hold still;
- the tooltip lists **names**, not three copies of the word "working";
- `Preferences.expandedRows`, the store behind a row you opened.

A defect found and fixed on the way: reading a title for every session made
twenty-two sessions arriving together do twenty-two reads of files that did not
exist, and an end-to-end case failed once in three runs. The read is now gated on
the file being there.

### What is proven about Codex, and how

Measured on this machine on 30 August, not deduced:

| Claim | Evidence |
|---|---|
| The ChatGPT app runs real Codex sessions | a rollout under `~/.codex/sessions` with `originator: Codex Desktop`, updated while a message was being answered |
| It does not run our hooks | `~/.codex/hooks.json` holds all eight events with trusted hashes in `config.toml`, and the diagnostic log recorded not one signal for that session |
| A live session holds its rollout open | three of ten rollouts held open, one process each |
| The executable names the surface | ChatGPT app, Homebrew CLI and the VS Code extension are three different binaries |
| Records are flushed at once | last record `06:40:16.641Z`, file mtime `06:40:16Z` |
| The state vocabulary is small and shared | `task_started`, `task_complete`, `turn_aborted`, `token_count`, on desktop and CLI alike |
| Claude desktop is behind a wall | `com.apple.Virtualization.VirtualMachine` holding `claudevm.bundle/rootfs.img`, written at the moment a message was sent, VM address `172.16.10.3` |

Two things that are **not** proven and must not be written as if they were: that
no future Codex desktop will run hooks, and that a rollout can be turned into
`working` or `ready` without an event saying so.

### One risk smaller than the audit assumed

The response asks for a spike proving the signed bundle can read another
process's open files. Most of that answer already exists in production:
[`TerminalFocuser`](../../Sources/LampBoardApp/Focus/TerminalFocuser.swift#L208)
already runs `lsof -nP -U -a -p <pid>` against other processes from the signed
bundle, parses it with `LsofUnixSockets`, and does it inside
[`Command.run`](../../Sources/LampBoardCore/System/Command.swift#L90)'s deadline.
The spike is therefore narrow: regular files rather than Unix sockets, and the
three Codex surfaces rather than a terminal server. It is still a gate, because
"nearly the same call works" is not "this call works".

## 1. Decisions taken

Design, decided with the mockups in hand rather than in the abstract:

1. **A project with several sessions is a block**, a faint fill and a hairline
   holding the parent row and its children together. The block exists when
   collapsed too, and that is the sign that it opens. A single-session row has no
   block, so it cannot pretend to have one.
2. **The parent row opens and closes the block. It no longer raises a window.** A
   row that contains other rows is a heading, not a destination. What is lost was
   not reliable anyway: it opened "the most urgent", and between two sessions both
   working, which one that is was decided by our tie-breaking.
3. **The keyboard slot still opens** the most urgent session directly. It is a
   gesture made without looking and has to stay one press.
4. **One block per project, both agents inside.** This reverses `5185072`. It is
   safe now for a reason that did not hold this morning: a single dot could not
   say two things, and now the block says four, the dominant state, the state it
   is covering, how many, and the whole list when open.
5. **Sub-rows: zero indentation.** Smaller dot in the parent's dot column, ring in
   the parent's ring cell, name starting exactly where the parent's name starts,
   with the same width. The only mark is a spine three points inside the margin.
6. **Sub-rows in birth order, never re-sorted.** Selection order and display order
   become two different things.
7. **The handle becomes a dot grip**, six dots in two columns, at 46 percent
   instead of 30. Three horizontal lines also say "menu"; a grip only says "grab".
8. **The grip carries the agent**: terracotta `#D97757` at 80 percent for Claude,
   teal `#2DD4BF` for Codex. The parent's grip stays neutral, so the shape says
   what you are grabbing and the colour says whose it is.
9. **The narrow panel groups with a line**, full down the side of an open group,
   folded to a stub next to a collapsed one. Drawn inside the padding, because at
   35 points there is no room beside a 13 point dot and the dots must never move.
10. **Sub-rows can be reordered**, and the order is stored by session id, so it
    lasts as long as the session and no longer. Said out loud rather than
    discovered.
11. **Three names, two of them durable.** The project keeps its name, each agent
    keeps a name of its own inside that project, and a conversation shows its own
    title when it has one. Nothing is stored against a session id except its
    position in a reordered block, because a session id dies with its process.

Two consequences of 8 that the plan carries rather than hides. Teal is the one
tint tested that sits closest to `ready` green, so a Codex grip on a row that is
genuinely green puts two greens on one line; it was chosen anyway, and the
mitigation is opacity and the distance between the two cells. And after this the
panel has spent nearly all of its colour vocabulary: a third agent, or a sixth
state, will find little room.

Four questions were open in the design and are now settled:

- The parent's dot **stays lit** when the block is open, so the column reads the
  same whether blocks are open or not. The recall dot is what disappears instead,
  because open it would repeat something already visible below.
- The recall dot shows **one** state, the most urgent among those the dominant
  colour is covering. With two sessions it loses nothing; with five it can stay
  silent about one, always in the less urgent direction.
- **Six** sub-rows then a tail, everywhere, including the tooltip that caps at
  eight today. One cap, so the panel and the summary cannot say two different
  things about the same project.
- Per-agent names are **kept**, and A2b gives them a home.

## 2. Gate 0, make the README true

Before any of it, because it is false now and costs nothing to fix.

[`README.md`](../../README.md) claims both harnesses cover the CLI, the editor
extension and the copy inside the desktop app. Evidence says: Codex inside ChatGPT
is not discovered at all, and Claude desktop runs its sessions in an isolated VM
that cannot reach this machine's loopback.

Replace the per-harness claim with a per-surface matrix carrying, for each row,
what is **discovered**, whether liveness is **confirmed**, how good the **state**
is, whether **focus** works, and whether a **test** covers it. Every surface not
proven is marked unsupported, including both desktop apps, and a surface is
promoted only by a test of that surface.

Same commit, the removal command: `"~/Library/Application Support/lampboard"` has
the tilde inside the quotes, so the shell never expands it and the line deletes
nothing.

## 3. Track A, the panel

Independent of track B. Seven commits, each green on its own.

### A1 · Adopt the new icon

`Resources/LampBoard.icns` and `Scripts/make-icon.py` already carry the L of six
lamps, four down the stem and three along the foot, the corner counted once. The
commit adds nothing to the drawing; it checks that the three `assert`s in the
script still hold, that the README section describing it matches what the file
draws, and that the built app shows it at 16, 32 and 512 points.

### A2 · One block per project

`ColumnLayout.group` keys on path plus harness today. It goes back to keying on
path alone, and `ColumnRow.harness` becomes a property of the sessions rather than
of the row.

Tests must keep the guarantee that motivated the split: a project with Claude
working and Codex finished must not read as finished. It now holds through the
recall dot and the count instead of through two rows, so the case moves rather
than disappears.

The per-agent keys in `RowNames` are **kept**, and given a place rather than left
inert: see A2b.

### A2b · Three levels of name, and where each is set

The naming levels that actually survive a restart are two, because the third does
not exist: a folder is durable, a folder plus an agent is durable, and a session id
dies with its process. So:

- **the block header is renamed to name the project.** What `lampboard rename`
  already writes, and what the notification already reads.
- **a sub-row is renamed to name that agent's lane in this project.** This is the
  key written this morning, `folder + agent`, which the merge was about to leave
  unreachable. It now has the only durable home a per-agent name can have.

What a session shows, in order: its own conversation title; failing that the lane's
name, numbered when several sessions share it; failing that its position. So a
Codex lane called "migration" gives a fresh session "migration #2" instead of "#2",
which is the point of naming a lane at all.

One consequence to state on the menu itself rather than let somebody discover:
renaming a sub-row names the **lane**, so a second Codex session opened later
carries that name too. That is what a name per agent means. A name that belonged
to one conversation could not be offered honestly, because it would evaporate the
next time that session ended.

### A3 · The block, drawn

The fill, the hairline, the spine, the count, the turning chevron. Sub-rows with
zero indentation, the smaller dot, the ring, the name at the parent's x.

The one arithmetic risk in the whole track: `Layout.height(rowCount:showsIssue:)`
and `TrafficLightColumn.dragState` both assume a uniform 24 point pitch, and
`pitch = rowHeight + rowSpacing` drives drag by index. Sub-rows of a different
height break both, and a drag across an open block would land on the wrong row.
The pitch has to learn about them, with a test that drags over an open block.

### A4 · Click, and what it clears

Parent opens and closes. Sub-row raises that session and clears **only** that
session, which is strictly better than today, where opening a project can clear an
answer nobody read. The keyboard slot keeps opening the most urgent.

`Preferences.expandedRows` is already there; this wires it, including the rule
that a row stays open when its project drops back to one session.

### A5 · The handle, and the agent on it

The grip, its opacity, its tints. The parent's stays neutral.

### A6 · The narrow panel

The lateral line and its stub, drawn inside the padding so the dots never move.
This is also the first place where a group is legible at 35 points: today a
project with three sessions and one with a single session are the same pixel.

### A7 · Reordering inside a block

Order stored by session id. Unknown ids sort after the known ones, by birth, so a
new session appears at the end rather than in a place somebody has to hunt for.

## 4. Track B, Codex made real

### B0 · The spike, done, and it moved the premise

**Passed.** From `dist/LampBoard.app` signed with `Developer ID Application:
Marco Armellino (33Z4MPR4FF)`, hardened runtime on (`flags=0x10000(runtime)`) and
the two release entitlements, `lampboard codex-probe` listed the rollouts held
open by this account's Codex processes and classified all three surfaces from the
executable: `/Applications/ChatGPT.app/…/codex`,
`/opt/homebrew/Caskroom/codex/0.151.0/bin/codex`, and
`~/.vscode/extensions/openai.chatgpt-*/bin/macos-aarch64/codex`.

Two things it found that the plan had wrong, and both are worth more than the
gate itself.

**One process holds several rollouts.** Not a photograph any more: pid 4643, the
ChatGPT app's Codex, held **three** open at once. The audit asked for this to be
treated as one-to-many rather than assumed away, and it was right to.

**An open descriptor does not mean a running session.** The VS Code extension's
Codex, started on 29 August 2026, holds open a rollout whose last record is a
`turn_aborted` from **29 September 2025**. The file has not been written in a
year. So the evidence proves a conversation is *loaded in a live program*, which
is a real and useful fact, and it does not prove the agent is doing anything.

That changes what a scanner-only row is allowed to mean, and it happens to
strengthen B2 rather than fight it: presence yes, focus yes, state **unknown**,
never a colour by inference. And it needs no new pruning rule. The row takes the
rollout's own last-written time as its `updatedAt`, so a conversation loaded but
untouched for a year falls to the age rule the store already applies to every
other stale row.

The remaining questions from the audit's list, closing a session and resuming
one, are answered by the scanner-driven end-to-end in B4 rather than by hand,
because a claim made by watching once is the kind this plan exists to avoid.

### B0 · The original gate, for the record

From the **signed bundle**, not from a shell: list the `codex` processes of this
account, read each one's open files, and match them to rollouts under
`CODEX_HOME/sessions`. Keep sanitised output for ChatGPT, the VS Code extension
and the CLI, plus a session closed and a session resumed.

Six questions, from the audit response, all worth answering before any model is
built: the signed process sees the pids; the probe returns file and pid together
for all three surfaces; it survives the hardened runtime; closing a session really
closes the descriptor rather than only the window; a resumed session reopens the
right rollout; and one process may hold **several** rollouts open. The current
photograph shows one each, which is not a contract.

If the bundle cannot read the descriptors, stop and choose another source before
building anything on top.

### B1 · Discovery and liveness

Three components, not one scanner that does everything:

- **`CodexProcessScanner`** finds live `codex` processes and the rollouts they
  hold open, with the executable path, the pid, the start time and the ancestry.
  `ProcessTree` already gives pids by name, the executable through `proc_pidpath`,
  and the ancestry with tty and start time.
- **`CodexSessionMetadataReader`** reads `session_meta` from a file already proven
  open, under a byte cap, and takes `session_id` and `cwd` from it. It keeps
  `originator`, the metadata `source` and the version as **open strings**: four
  values have already been seen in one week, and the field must never become a
  closed enum that makes a record unreadable when a fifth appears.
- **`CodexHookCorrelator`** accepts a hook only after matching it to a session
  already discovered. Hooks sharpen the state; they no longer create a row.

The `cwd` comes from the file we read, never from `/signal`. That keeps the
security property the audit asked for without adding a secret: the route stays
unauthenticated and stops being believed.

The probe must fail without killing rows: off the main actor, machine-readable
output, only pids `ProcessTree` already found, inside `Command.run`'s deadline,
and **a failed probe is not evidence of death**. A successful probe that no longer
sees the file is. It is the same distinction the store already makes between a
silent remote host and a dead one.

### B2 · Capabilities, per session and not per harness

The audit's sharpest point, and it is right: what a row can say depends on the
channel it was observed through, not only on which agent it is.

```text
presence:  confirmed | unknown
liveness:  confirmed | unknown
state:     hooks | rollout-gated | unavailable
focus:     process | inferred | unavailable
reportable statuses: Set<SessionStatus>
```

A Codex session with hooks can say `working`, `ready`, `awaiting`, `waiting`, and
never `failed`. A session found only by its process can say it exists and is
alive; until a proven rollout parser exists it shows as idle or as an explicit
unknown, and **never green, amber or red by inference**.

Same commit closes the invariant that is currently written and not enforced:
`Harness.cannotReport` is consulted by tests only, while `StateReducer`'s
`.stopFailure` branch returns `.failed` without looking at the harness. Two
levels, refuse the incompatible event at the boundary with a diagnostic, and have
the reducer keep the previous state if one gets through. A mutation must prove it
bites.

### B3 · Focus, from the same evidence

The executable path proves the surface for a binary embedded in ChatGPT or in the
extension. It does not choose a window for a generic CLI: the same Homebrew binary
runs in Terminal, Ghostty, tmux or VS Code's integrated terminal. There the
ancestry, the tty and `SeatClassifier` decide, exactly as they already do for
Claude's terminal sessions.

So COD-001 and COD-002 stop being two roads. The record that proves liveness is
the record that proves the surface.

And COD-002 is real today, whatever we do here: a Codex session started in a
terminal, in a folder that happens to be open in VS Code, is admitted through the
Claude lock and then raised as a VS Code window. The folder is right and the
surface is wrong.

### B4 · Lifecycle, and tests that cannot pass while blind

`COD-003`: one coordinator for both harnesses, shared by the command line, the
first-run prompt and the menu. A per-harness result rather than one boolean.
`uninstall-hooks` removes Codex too, by exact path. `status` and `selftest` report
each harness separately. And errors name the file actually written:
`HookInstallError` says `~/.claude/settings.json` even when the failing installer
is the Codex one writing `~/.codex/hooks.json`.

Three test levels, and the second is the one that matters:

1. **Hook-driven end-to-end**, which exists for Claude and not for Codex. The word
   "Codex" appears zero times in the whole end-to-end target today.
2. **Scanner-driven end-to-end, which never calls `/signal`.** A helper opens a
   sanitised rollout under a temporary `CODEX_HOME` and **holds the descriptor
   open**, because it is the descriptor and not the file that is the evidence. It
   proves: adoption with no hook; id and `cwd` from `session_meta`; the state stays
   unknown; closing the descriptor removes the row; two rollouts held by one
   process are two sessions; a path outside the Codex root is ignored; a failed
   probe does not erase the last confirmed session; the executable path yields the
   expected surface and confidence.
3. **A platform smoke test from the signed bundle**, with output kept. If CI
   cannot run it, it becomes a release step with retained output, never a sentence
   somebody wrote by hand.

### B5 · The rollout as an unstable contract

`COD-005`, now more important than when it was P2, because the format would carry
the row's existence and not only a percentage. Fixtures named by Codex version,
fail closed so an unknown shape produces no ring rather than a plausible number, a
diagnostic naming the field that disappeared, and a contract gate separate from
the Claude one.

## 5. Where the two tracks collide

Three files, and both tracks want them.

`ColumnLayout` loses the harness from its key (A2) while track B adds capabilities
to the session (B2). They do not conflict logically, but A2 should land first so
that B's tests are written against one row per project.

`StateStore` gains the scanner (B1) and, in A4, nothing. Good.

`SessionState` gains capabilities (B2) and already gained `firstSeenAt` today.
Both are additive with defaults.

Recommended order: **Gate 0, then B0, then A2 and A3 while B1 is built**, because
B0 can invalidate track B entirely and must not be discovered late.

## 6. The gates that close this

Panel:

- [ ] Two sessions in one folder are told apart by name, in the panel and in the
      tooltip.
- [ ] A project can carry one name, and each agent inside it a different one, and
      both survive a restart.
- [ ] Renaming an agent's lane does not rename the project, and clearing it gives
      the project's name back rather than nothing.
- [ ] A project with Claude working and Codex finished does not read as finished.
- [ ] A row with one session has no block and opens a window on click.
- [ ] A row that was opened is still open after a restart.
- [ ] Dragging across an open block lands on the row under the pointer.
- [ ] The narrow panel distinguishes a project with three sessions from one with a
      single session.
- [ ] The keyboard slot still opens the most urgent session in one press.

Codex:

- [ ] The signed bundle lists the rollouts held open by this account's Codex
      processes.
- [ ] A ChatGPT session produces a row with no hook involved.
- [ ] A scanner-only row never claims a state its channel cannot prove.
- [ ] Closing the session removes the row; a failed probe does not.
- [ ] Two rollouts held by one process are two rows.
- [ ] The `cwd` comes from `session_meta`, never from `/signal`.
- [ ] A hook can only update a session already correlated to process evidence.
- [ ] Codex cannot reach `.failed`, not even through an event built on purpose to
      make it.
- [ ] ChatGPT, the extension and the CLI have separate proofs of discovery, state
      and focus.
- [ ] The scanner-driven end-to-end never calls `/signal`, not even indirectly.
- [ ] No unproven surface is described as supported.

Everywhere:

- [ ] Build with warnings as errors, both suites, the documentation gates and the
      mutations, green in the same commit.

## 7. What this plan does not do

- **Claude desktop.** Its sessions run in an isolated VM with its own address; a
  hook fired in there cannot reach this machine's loopback, and we cannot install
  anything inside it. It is a declared limit, not a backlog item, until the vendor
  offers a boundary to talk to.
- **States inferred from the rollout.** The vocabulary is there and the temptation
  is real, but a transcript changes for things that are not a turn, and the store
  has already been burned by exactly that. It is a separate capability, gated by
  fixtures, or it is nothing.
- **`originator` as a closed enum.** Four values in one week.
- **Swift 6 language mode.** Real debt, unrelated, and it must not ride along with
  any of this.
- **Defending against a hostile process running as this user.** A file this
  account can write is not a secret. The evidence stops an accidental or blind
  request and another account; it does not stop you attacking yourself, and the
  threat model should say so rather than calling the check authentication.
