# Work log

Chronicle of the autonomous execution of the [plan](PLAN.md), 29 July 2026.
Every entry says **what** changed, **why**, and **how it was verified**.

## Rules I gave myself for working alone

The user was unreachable, so I worked under tighter constraints than usual. Three
things I did not do, and not out of forgetfulness:

1. **No password or keychain prompts.** `create-signing-identity.sh` is left to be
   run: it asks for the keychain password, and a dialog left open for hours is not
   something to do to somebody who isn't there.
2. **No system authorizations requested behind anyone's back.** Notifications and
   the presence file are **off by default**: you turn them on from the menu, and
   that is where the system prompt appears — when there is somebody to read it.
3. **No login item registered.** With an ad-hoc signature it would leave orphaned
   records behind, and that has already happened once in this story.

**I changed one rule halfway through, and it's worth saying why.** I had decided
not to touch `~/.claude/settings.json`. Then I verified that without registering
`SubagentStart` and `SubagentStop` the subagent counter **never receives
anything**: the most important feature of the day would have stayed inert waiting
for a command nobody knew about. The plan itself called it necessary ("Requires:
re-installing the hooks").

I ran `install-hooks`. The operation is additive — two extra events pointing at
the same already-registered script — it creates a dated backup, and it is undone
with `uninstall-hooks`. Verified afterwards by comparing the file with the earlier
copy: no key lost, no key modified outside `hooks`, no third-party hook touched.
Backup at `~/.claude/settings.json.clawd-light-backup-20260729-195635`.

All the automated test runs go through a fake home regardless.

---

## Phase 0 — Foundations

### F0.1 · Path isolation — `CLAWD_LIGHT_HOME`

`AppConfig` derived every path from `homeDirectoryForCurrentUser`. Convenient, but
it makes an honest end-to-end test impossible: either you touch the user's real
`~/.claude`, or you bypass the production code and verify something other than
what actually runs.

Now every path descends from `AppConfig.homeDirectory`, which honors the
`CLAWD_LIGHT_HOME` variable.

A detail worth remembering: **rewriting `$HOME` would not have been enough**.
`homeDirectoryForCurrentUser` reads from `getpwuid`, not from the environment, and
relying on it would have created the illusion of an isolation that isn't there.

The preferences are isolated too: with the variable set, `Preferences` uses a
separate `UserDefaults` domain, otherwise a test that switched a notification on
would leave it on afterwards.

**Files**: `AppConfig.swift`, `Preferences.swift`

### F0.2 · `--headless` mode

The app starts with the server and the realignment but no panel. It serves the
e2e tests, which have to run *this* binary without depending on a graphical
session.

**Files**: `AppDelegate.swift`, `CommandLineInterface.swift`, `main.swift`

### F0.3 · Security defect: the server was listening on every interface

It wasn't in the plan. I found it looking at `lsof` before adding an endpoint that
exposes the project names:

```
clawd-lig 32486 dev 4u IPv6 ... TCP *:9877 (LISTEN)
```

`*:9877` means the socket was reachable **by anyone on the same network**. The
code relied on `NWParameters.acceptLocalOnly`, which looks like it says "this
machine only" and actually says "this network link only" — that is, the Wi-Fi the
Mac is attached to.

Anyone who got there could inject signals and drive the panel's state. With the
read endpoint it would also have become a listing of the open projects.

**Correction**: `parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), …)`,
which really does constrain the bind.

**Verification**: an e2e case queries `lsof` against the live process and fails if
an address appears that doesn't start with `127.0.0.1`. It verifies the fact, not
the intention — which is exactly the distinction the defect had slipped through.

**Files**: `SignalServer.swift`, `TransportSuite.swift`

### F0.4 · `GET /sessions` with a token — *plan 5.1*

Brought forward from phase 5 because without a way to observe the state from
outside there are no e2e tests.

- `SessionSnapshot` / `SessionsResponse`: a contract type separate from
  `SessionState`, so an internal refactor doesn't break its consumers
- ISO 8601 dates — a numeric timestamp forces every reader to guess the unit, and
  whoever guesses wrong doesn't find out
- a 24-byte token in `~/.clawd-light/token`, mode `0600`
- **constant-time** token comparison: an `==` bails out at the first differing
  byte and the time it takes says how many leading characters were right
- if the file's permissions turn out wider than `0600` the token is
  **regenerated**, not repaired: a secret that has been readable is burned

`POST /signal`, by contrast, stays **without** a token, and that is a choice: the
hook script runs as the user and could read it, but a hook that fails
authentication would block a Claude Code turn because of a decorative widget. The
risk is asymmetric.

**Files**: `SessionsPayload.swift`, `AccessToken.swift`, `TokenStore.swift`,
`SignalServer.swift`, `SnapshotBox.swift`

A design note: the server reads the state from a lock-protected `SnapshotBox`
instead of crossing the boundary with `DispatchQueue.main.sync`. That would have
worked right up until somebody, on the main queue, waited for something that goes
through the server's queue — that is, until somebody introduced the deadlock.

### F0.5 · End-to-end harness

`swift run ClawdLightE2E` launches **the real binary** against a fake home and
talks to it over HTTP, the way the hooks do.

It exists for a precise reason: window title matching stayed broken for an entire
day **with ten green tests**, because it had been verified with `osascript` while
the app uses `NSAppleScript` — two transports that serialize lists differently.
The defect lived in the seam between the tested function and the real world.

The hook payloads are not invented: the shapes were taken from binary 2.1.220 with
`strings`. `SubagentStop` carries `agent_id`, `agent_type` and
`last_assistant_message`; `SubagentStart` only the first two.

**Files**: `Sources/ClawdLightE2E/`

---

## Phase 1 — Coverage

### 1.1 · Integrated-terminal sessions

`AppConfig.vsCodeEntrypoints = ["claude-vscode"]` discarded every session started
with `claude` from the terminal **inside** VS Code: same window, same project,
same click that would have brought it forward, and no traffic light.

The fix was not to widen the list. Future entrypoints are unknown, and an
allow-list punctures itself with every Claude Code release — silently, because a
missing row doesn't complain.

The criterion was **inverted**: what counts is *where* the session runs, not how
it was started. If the `cwd` sits inside a folder an IDE has open, the session is
in that window. A **deny**-list remains (`nonInteractiveEntrypoints`) for what
nobody is watching: when it's wrong it shows one row too many — a mistake you can
see — instead of hiding one.

For sessions read from the filesystem the best criterion is the `kind` field,
which Claude Code writes itself; the entrypoint stays as a fallback.

**Files**: `HookSignal.deservesTrafficLight`, `LiveSession.deservesTrafficLight`,
`AppConfig`, `StateReducer`

### 1.2 · Subagent counter

Verified before implementing, with `strings` on binary 2.1.220: `SubagentStart`
and `SubagentStop` **exist** (8 and 17 occurrences).

The plan said "`Stop`/`SessionEnd` reset the counter". **Implementing it revealed
that this is wrong**, and the discovery changed the project.

With background agents the real sequence is:

```
SubagentStart ×N  →  Stop (the parent turn returns control)
                  →  … the agents work for tens of minutes …
                  →  SubagentStop ×N
```

Resetting on `Stop` restores green **exactly during** the work: the very lie this
feature existed to remove.

The model adopted: **the displayed state is derived**.

```swift
public var status: SessionStatus {
    guard activeSubagents > 0 else { return baseStatus }
    return baseStatus == .awaiting ? .awaiting : .working
}
```

`baseStatus` is what the hooks say for the main turn; `status` is what the traffic
light shows. It follows on its own that when the last agent finishes, the green
set aside **resurfaces without anyone having to remember it**. Waiting for a
permission wins regardless: it blocks everything.

The counter resets at the **user's prompt**, not at the end of the turn: it is a
certain boundary and it doubles as a safety net if a `SubagentStop` gets lost
along the way — otherwise the row would stay yellow until the 12-hour pruning.

A subtlety that cost some thinking: the rule protecting green from late signals
now compares `baseStatus`, not the displayed state. A session with green waiting
and agents in flight *appears* yellow, and using the appearance would have made
legitimate precisely the downgrade that rule prevents.

**Files**: `SessionState`, `HookSignal.subagentDelta`, `HookEventKind`,
`StateReducer.applySubagent`, `HookConfigMerger.defaultEvents`

**Requires re-running `install-hooks`** to register the two new events.

---

## Phase 0.2 — Per-row context menu

It unblocked five later proposals, and indeed all five lean on it.

The known friction — a menu on the row shadows the panel's one — was resolved by
**not duplicating** the global entries. The row menu has eight entries, the
panel's twelve: adding them up would make twenty, and a twenty-item menu cannot be
read. The general menu stays reachable from the panel's margins.

**Files**: `TrafficLightRow.swift` (`RowActions`, `RowFlags`), `PanelRootView.swift`

---

## Phase 2 — Scale

All the logic lives in `ColumnLayout`, a pure function: same state and same
options, same rows. Grouping, filtering, pinning and the summary are a single
computation, verifiable without drawing anything — eighteen test cases.

### 2.1 · One row per project — on by default

The measured numbers: 22 distinct sessions across 12 windows. One row per session
drew 22 targets for 12 raisable windows.

The risk the plan flagged — the loss of granularity — was addressed where it
arises: `sessionIdsToClear` returns **only the sessions that were in the most
urgent state**. Opening a project to answer a permission must not erase the ready
answer of another session in the same project.

Verified on real data: 10 sessions → 5 rows, and the panel measured 134 px, that
is, exactly five rows. Two independent measurements that agree.

### 2.2 · "Only what's waiting" filter

The risk flagged was movement: a panel that changes height on every transition. I
didn't remove it — the height follows the rows, and that is what keeps the widget
small — but I removed the lie that came with it: the filter **says how many
sessions it is keeping out** (`and 7 more with nothing new`). A column with two
rows must not suggest there are only two sessions.

Pinned projects survive the filter: pinning them means wanting to see them always,
and a filter that hides them drains pinning of its meaning.

### 2.3 · Pin to top, hide

The hidden summary row **lights up** when one of them asks for attention — with
the same dot, blinking included. The plan called it mandatory and it was right:
without it, "hide" becomes "forget", which is the harm the panel exists to prevent.

Pinned rows carry a discreet vertical rule: without a mark, "pin to top" just
moves a row, and among ten rows there's no telling why that one is sitting there.

---

## Phase 3 — Attention

All three features are **off by default**, and none asks for a system permission
until you turn it on. With the user away it was the only possible choice, but it
is also the right one in steady state: an authorization prompt should be shown to
somebody who has just asked for it.

### 3.1 · Notify only for `awaiting`

Never for `ready`. A ready answer can wait until you look at it; a permission
can't — until you answer, that work is stopped.

A set of already-announced sessions prevents duplicates: the column updates
continuously, and without a memory every recomputation would resend the same
notification. Anything that becomes unblocked is a candidate again, so a new block
tomorrow is a new alert.

Clicking the notification takes you **to that session**: the `sessionId` travels
in `userInfo`. An alert that says "something is waiting" and then leaves you to
find out which has saved nobody anything.

**Not verified at runtime**: delivery requires the bundle and the authorization,
which I didn't request. The code protects itself — outside a bundle
`UNUserNotificationCenter` terminates the process, so there is a check on
`Bundle.main.bundleIdentifier` before every use.

### 3.2 · The gate

`occlusionState` comes out wrong at app startup, so on its own it would suppress
legitimate alerts. It is combined with keyboard inactivity
(`CGEventSource.secondsSinceLastEventType`, which requires no permissions and
doesn't read *what* was pressed, only *when*). When in doubt the notification
fires: a gate that is too closed is worse than no notification.

> **Later note (30 July).** Tested live, the presence condition suppressed
> everything: the panel is floating, so it is always visible, and if you're at the
> Mac you're active. The gate was reduced to the explicit silences only.

### 3.4 · Muting

Per project or for an hour. It silences the **alerts**, never the color: a muted
row stays visibly so in the tooltip, otherwise it would become a deletion you
forget you performed.

### 3.5 · Presence file

`CLAUDE_CLIENT_PRESENCE_FILE` verified present in binary 2.1.220.

Off by default because it **inverts a built-in behavior**: if the detection gets
it wrong, the result is not one notification too many but a notification lost, and
lost notifications go unnoticed. When the app closes the file is deleted — leaving
it would say "I'm at the Mac" forever.

### 3.3 · Summary on return — **not done**

The plan excluded it until 3.1 proved noisy. With 3.1 off by default, that
evidence doesn't exist yet.

---

## Phase 4 — Row actions

**4.1 alt+click** peeks without consuming the green, and `markedUnread` remedies
one click too many. The menu entry exists because a modifier nobody discovers is
dead code.

**4.2 silence the blink** stops the movement, not the signal: the amber stays.

**4.3 new conversation** uses the same deep link without the `session` parameter.
The risk flagged — making it easy to multiply sessions — is still real, but with
2.1's grouping an extra session is no longer an extra row.

**4.4 permissions from the row**: **not done**, as planned. The
`PermissionRequest` hook blocks the turn until it answers: if the panel isn't
running, every request hangs.

---

## Phase 5 — Integration

**5.1** brought forward to phase 0 (see above).

**5.2 `next`** talks to the running instance over `POST /next`, authenticated. It
is a route that **raises windows**, not one that colors dots, and the separation
matters: it deserves authentication even where the other has none.

**5.3 the ⌃⌥⌘L shortcut** with `RegisterEventHotKey`. The failure **is not
swallowed**: if the combination is taken, the switch goes back off and an alert
appears. A shortcut that doesn't fire is worse than no shortcut, because you stop
looking at the column in exchange for nothing.

> **Later note (30 July).** Tested live: the API returns `noErr` and never
> delivers the event, and the app cannot notice. The feature was **removed** —
> see [04 decisions · N6](docs/04-decisions.md#n6--a-global-shortcut-inside-the-app).

**5.4 launch at login** implemented but it **refuses to register with an ad-hoc
signature**, and the menu entry stays disabled. This is not theoretical caution:
in this project a login item registered by a process that then failed to remove it
has already happened. `CodeSignature.isAdHoc` reads `codesign -dv` once at
startup; when in doubt it assumes ad-hoc, which is the harmless failure of the two.

---

## Phase 1.3 — Other IDEs: done, with a stated limit

The plan excluded it "until there is a way to test it", with the prerequisite
"having Cursor installed". Verified: Cursor **is** installed and has the Claude
Code extension (`anthropic.claude-code-1.0.33`). The prerequisite is satisfied.

Implemented `IDEKind` with a **deliberately short** table: only the editors whose
declared name, bundle identifier and process name are known, and whose window
title follows VS Code's format. Cursor is a fork, so locks and titles are
identical; only the three names differ. The bundle identifier
(`com.todesktop.230313mzl4w4u92`) was **read** from the `Info.plist`, not guessed.

Recognition of "Visual Studio Code - Insiders" was added too, which the equality
comparison discarded.

**Stated limit**: no Cursor lock existed at the time of the work (all 12 said
"Visual Studio Code"), so the activation path on Cursor is **not verified at
runtime**. Recognition and routing are under unit test; the last mile is not.

---

## Defects found while I worked

None of the three was in the plan. Two were found by the end-to-end suite.

**1. The server was listening on every interface.** See F0.3. Reachable by anyone
on the same network.

**2. Two installations in the same second failed.** The `settings.json` backup
name carries the date down to the second, and `copyItem` refuses to overwrite: the
error bubbled up and failed the installation, with a message about the backup while
the problem looked like something else. You meet it by installing, uninstalling
and reinstalling in three clicks. Now there's a counter.

**3. The columns of `clawd-light sessions` were jammed together.**
`String(format:)` honors a width on C's placeholders but **ignores** it on `%@`.
Explicit padding.

**4. "New conversation here" opened two tabs.** Found by re-reading the code, not
by a test. The path raised the window passing the `sessionId` — so it opened the
existing session's tab — and immediately afterwards opened a new one. No test
could have seen it: the deep link runs as a separate process and nobody observes
its effect. Activation now takes a parameter to **not** open the tab, used only
from here.

It's worth noting that the first three were found by automated verification and
the fourth wasn't. A defect living outside the process — in an `open` that fires
and doesn't return — stays invisible to any suite, and the only tool against that
category is re-reading the path in full.

---

## What the review found, afterwards

I had the new code re-read by an independent reviewer. It found six things; five
were real. I report them because two are defects **I introduced today** and that
my own tests didn't see.

### A startup crash, introduced today

```
*** Terminating app due to uncaught exception 'NSInternalInconsistencyException',
    reason: 'bundleProxyForCurrentProcess is nil'
8  ClawdLightApp  AppDelegate.startNotifier(for:)
```

`UNUserNotificationCenter.current()` outside a `.app` bundle **does not return
nil**: it raises an exception and terminates the process. I had put the guard
inside `SessionNotifier`, where it was needed, and forgotten it on the line
assigning the delegate. Result: `swift run ClawdLightApp` during development died
before drawing the panel.

**Why no test saw it**: the entire end-to-end suite runs `--headless`, and
`--headless` skips `startInterface()`. I had built a test run that never went
through the branch with the interface on.

Now there is a case that starts the bare binary **without** `--headless` and
checks it is still alive after two and a half seconds. I tested it in reverse, by
putting the defect back: it goes red with `code 6` (SIGABRT) and green with the
fix. A regression test that doesn't fail on the bug is worth nothing.

### An error that vanished

`shouldKeep` protects green from trailing signals that arrived out of order, but
the protection was hooked to `blocksDowngrade`, which is false for `failed`. A
late `PostToolUse` — the tail of the turn that had just been cut short — downgraded
a failed session to "working" **and erased the cause of the error**.

The reason `failed` wasn't in `blocksDowngrade` was a good one: if the turn really
does resume, yellow is the correct information. But a trailing signal is not a
resumption. The protection now tells the two cases apart, with two tests pinning
both down.

Note: the tool events aren't registered by default, so the defect only hit anyone
using `--with-tool-events`.

### The token promised more than it delivers

The comment said the token protects against "any local process, including the
Claude Code sessions themselves". **False**: a `0600` file stops the other users
on the machine, not a process running as your own user — and that one can open the
file. No on-disk secret can prevent it.

There is no technical fix: I corrected the promise. The token remains useful — it
covers the multi-user case and raises the barrier from "a GET is enough" to "you
have to know where the token lives" — but presenting it as a defense against the
code running inside the sessions is a false reassurance, and a false reassurance is
worse than no defense because people stop thinking about it.

### Concurrency: two things true and one to scale back

**The server's queue was serial**, so a `/next` waiting on the main actor also
delayed reading the hooks' `POST /signal` — up to two seconds on a Claude Code
turn, which is precisely what all the rest of the project avoids. It is now
concurrent: connections share no mutable state, so it introduces no races.

**The expired continuation ran anyway.** A `DispatchQueue.main.async` cannot be
called back: after the timeout the client received "not now", and then the main
queue, once free, really did raise the window. It is now a `DispatchWorkItem` that
gets cancelled, and a work item cancelled before it starts never starts.

**The point to scale back**: the reviewer observes that the timeout doesn't protect
the main actor — if `focus` gets stuck on an AppleScript, the interface freezes
anyway. That is true, and I wrote it into the comment in place of the sentence
saying "the worst case is a request that answers not now". But it is not a risk I
introduced: a click on a row does exactly the same thing on the same thread.
`/next` doesn't add the risk, it adds a way to trigger it from outside.

---

## The live proof

At the end I made the **real** app walk the complete chain, using the hook script
installed at `~/.clawd-light/hook.sh` — the same one Claude Code runs — with a
test session backed by a live process:

```
prompt submitted:     working  ×0
two agents started:   working  ×2
parent turn closed:   working  ×2   ← the point: Stop doesn't clear the yellow
one agent closed:     working  ×1
last agent:           ready    ×0   ← the green resurfaces on its own
```

Then I removed the session file: the row disappeared at the next realignment and
the column went back to its ten real sessions, with no leftovers.

The **first** attempt at this proof was badly done: I had used a session with no
process, and the realignment took it away every five seconds, making the counter
look broken. It wasn't a defect in the code but in the test — worth writing down,
because it is the kind of false positive that leads to "fixing" something that
works.

## Eight hours of continuous operation

The panel stayed on all night, and that produced a verification you can't do
during the day.

```
PID    ELAPSED   %CPU    RSS
10103  07:41:50   0.0   25 MB
```

No memory leak, no runaway timer, `/health` still answers and the socket is still
bound to `127.0.0.1`.

But the best data point is a different one. Over the course of the night the
Claude Code sessions died one after another, and the realignment carried them away
by itself: the column went from **10 sessions across 5 projects** to **3 across
3**, and the panel resized accordingly — from 134 px to 86 px. Both heights come
out exact against the formula (`3 × 22 + 2 × 2 + 16 = 86`), and I imposed neither
of them: I measured them with the window server eight hours apart.

It is the proof that the hooks and the filesystem really are talking to each
other. The hooks never say what disappeared; without the second source, this
morning there would have been ten clickable rows leading nowhere.

## The last check, which arrived at unlock

The first check had waited the full eight hours and given up: the screen had never
been unlocked (29,281 seconds of idle time recorded). I put it back to waiting, and
at **07:09:39** it fired.

```
VS Code windows seen (9):
  → [1] Build floating Mac traff… — clawd-light — Claude Minimal
    [2] Q3-Proposal.pptx — acme-portal
    [3] Read documentation and s… — docs-site — Claude Minimal
    …
```

Two things, both important.

**Title recognition works through the real transport.** Nine titles read by
`NSAppleScript`, and the arrow on the right window. It is exactly the chain that
stayed broken for an entire day with ten green tests, because it had been verified
with `osascript` — a transport that serializes lists differently. Now it is
verified with what the app actually uses.

**And it confirms last night's diagnosis.** The empty list I had got with the
screen locked was not a regression: it was macOS restricting accessibility access.
Had I not checked the lock state before concluding, I would have spent the night
"fixing" something that worked — which is exactly how this story has already lost
a day.

**And then the last step too.** With the stable signature in place and the two
permissions re-granted, the real raise:

```
✓ window raised with AppleScript — this is the correct behavior
```

Nine titles read, the right window chosen, `AXRaise` performed. Nothing is left
unverified in the click chain — the same one that in this project stayed broken
for a whole day with ten green tests.

## The signing script was broken (30 July)

On the first attempt to run it:

```
security: SecKeychainItemImport: MAC verification failed during PKCS12 import (wrong password?)
```

The message sends you hunting for a wrong password. **The problem was the
algorithm.** OpenSSL 3 — 3.6.3 here — by default encrypts the PKCS#12 with AES-256
and computes the MAC with SHA-256, and macOS's Security framework PKCS#12 parser
can't digest them. A second stumble was layered on top: with an empty password,
"no password" and "a zero-length password" are two different things in the MAC
computation, and the two tools choose differently.

Fixed with `-legacy` (back to 3DES/SHA-1) and a random non-empty password that
lives for a few seconds inside the temporary folder. `-legacy` doesn't exist in
LibreSSL, which is the system openssl: the script retries without it, because
there the defaults are already the right ones.

Verified on temporary keychains, added to the search list and then removed by
restoring the exact configuration — no password prompt for the user and no
leftovers:

| | |
|---|---|
| p12 with OpenSSL 3's defaults | `MAC verification failed` — the defect |
| p12 with `-legacy` and a real password | `1 identity imported` |
| signing **without** marking trust | succeeded, correct `Authority=…` |
| ACL with `-T /usr/bin/codesign` | signed in under 20 s, **no dialog** |

The third outcome has a useful consequence: `add-trusted-cert` is not necessary
for signing, so the fact that the script tolerates its failure is right and not a
shortcut.

**But the real correction is a different one.** The previous version printed
"✓ identity created" right after the import: when the import failed, the error
scrolled past, the next build fell back to the ad-hoc signature **silently**, and
the user found out days later from a click that didn't work — the symptom hardest
to trace back to its cause. It is the same shape of error that had already produced
an alert shown after a success, months of wasted diagnosis on permissions, and a
`focus` that didn't tell "window absent" apart from "accessibility blind".

Now the script **signs a probe file and checks the Authority** before declaring
success. If it didn't work, it says so and exits 1.

### Then three more came out of the same script

**A typographic character that breaks bash.** `“$NAME”` — the guillemet
immediately after the variable name. In UTF-8 `”` is `0xC2 0xBB`, and bash 5.3
under `C.UTF-8` swallows the `0xC2` byte into the name, looking for a variable
`NAME\xC2` that doesn't exist. With `set -u` the script dies:

```
line 141: NAME�: unbound variable
```

Reproduced in isolation to be sure, and fixed with braces: `“${NAME}”`. All six
occurrences across the two scripts were fixed, not just the two that had exploded
— the search is `\$[A-Za-z_]\w*(?=[^\x00-\x7F])`, that is, "a variable followed by
a non-ASCII byte".

Remarkable how it manifested in `build-app.sh`: the faulty line was in the "sign
with a stable identity" branch, which until that moment had never been executed.
The defect had been there for hours, invisible, and it woke up exactly when the
certificate appeared.

**`codesign` doesn't fail: it hangs.** With the identity imported but the private
key not yet authorized, macOS opens an "allow access?" dialog. In a
non-interactive script that dialog reaches nobody and the command hangs forever —
that is, my verification, born so as not to lie, would have stayed mute for even
longer.

Two corrections. The first:
`security set-key-partition-list -S apple-tool:,apple:,codesign:` puts codesign on
the authorized list, and it is the step every signing setup on macOS ends up
discovering the same way — through a command that never returns. The second: both
the verification and the build now sign **with a deadline** of twenty seconds,
done by hand because macOS has no `timeout` out of the box. If it expires, they
say there is a dialog on screen; `build-app.sh` falls back to ad-hoc instead of
getting stuck.

**The repair advice didn't repair.** The script exited immediately with "nothing to
do" if the certificate already existed. But the real situation was exactly that:
identity present, authorization missing. "Run the script again" was a dead end. It
is now idempotent: if the identity is there it skips creation and goes to the
checks.

Four defects in a hundred-and-fifty-line file that isn't even the product. Worth
saying because there is a single cause: that script had never been run. Everything
else in the day went through a build or a test; it didn't, and it is the one piece
of work I shipped without watching it work.

## What is left for the user to do

1. **Stable signature: done** (30 July, after fixing five defects in the script —
   see above). Verified where it counts: two builds in a row produce the same
   designated requirement,
   `identifier "com.clawdlight.app" and certificate leaf = H"4dff4499…"`,
   hooked to the certificate and not to the binary's hash. From here on the
   authorizations survive rebuilds, and launch at login is unlocked in the menu.
2. **The click: verified in full**, recognition and raise. The side-effect-free
   diagnosis remains `clawd-light focus <project> --dry-run`.
3. **Claude Code sessions that are already open** don't have the two new hooks:
   they pick them up on their next start. Until then the subagent counter stays at
   zero for those sessions, and that is normal.
4. If something doesn't add up, the way back is: `uninstall-hooks` for the hooks,
   the dated backup in `~/.claude/` for the configuration, and the per-phase
   archives I left in the session's temporary folder.

## How the project stands now

| | |
|---|---|
| Domain tests | **242**, instantaneous |
| End-to-end tests | **66**, about a minute |
| Build | clean, no warnings |
| Longest file | 407 lines (limit the project sets itself: 800) |
| Off-plan defects found and fixed | 9, two of them introduced that day and found by the review |

## 27 August — sessions in a terminal

The day's question was whether the panel could show the `claude` sessions
started by hand in a terminal, and take you to their tab. Measured first: the
hooks already arrived and were dropped for want of an editor window; the hook's
`cwd` follows every `cd` Claude makes while the session file's does not; every
process chain from a `claude` up to its terminal, on this machine; what each
terminal's dictionary or CLI exposes (`sdef`, `--help`, then a real click).

A plan was written, then put through an adversarial review — three lenses and
a refuter per finding; nineteen findings confirmed, among them the anchoring on
the session file's folder, the row carrying its own origin, and `procStart`
being a UTC ctime string on macOS — and rewritten from it. Then six phases in a
day, each green and documented before the next: the deep link only for sessions
the extension hosts (A); the row, born only when a live session file names the
session (B, D25); the click by tty in Terminal.app and iTerm2 through the
process tree (C); through tmux and zellij (D — `lsof` does pair a zellij client
with its server, from the column the plan had first misread); Ghostty, WezTerm
and kitty (E). Every host was clicked live with a real `claude` inside it.

Three things found on the way and written into 07-traps: an app relaunched
from a Claude Code shell inherits VS Code's Automation denials; a `claude`
started from such a shell writes no session file; a `claude` that is Ghostty's
own command reports no working directory, so the matcher learned Claude's `✳`
mark. Deferred, and said so in D25: the reconcile that ignores an empty live
list, because the end-to-end harness leans on it.

