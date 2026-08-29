# Development plan

> **Status as of 30 July 2026: executed and running.** Nineteen items implemented
> and verified; two left out with their original reasoning intact. The click chain
> is verified end to end, stable signature included. The chronicle of the
> execution, with the discoveries that changed the project along the way, is in
> [WORKLOG.md](WORKLOG.md).
>
> | | Proposal | Outcome |
> |---|---|---|
> | 0.1 | Stable signature | **done and verified**: identical requirement across two builds |
> | 0.2 | Row menu | done |
> | 1.1 | Terminal sessions | done — criterion inverted |
> | 1.2 | Subagent counter | done — **derived state**, not reset on `Stop` |
> | 1.3 | Other IDEs | done for Cursor; activation not verified at runtime |
> | 2.1 | One row per project | done, on by default |
> | 2.2 | Filter | done, with the count of what's excluded |
> | 2.3 | Pin / hide | done, with the summary that lights up |
> | 3.1 | `awaiting` notification | done, **off by default** |
> | 3.2 | Gate | done, then reduced to explicit silences only |
> | 3.3 | Summary on return | **not done**, waiting for 3.1 to prove noisy |
> | 3.4 | Mute | done |
> | 3.5 | Presence | done, **off by default** |
> | 4.1 | Alt+click | done |
> | 4.2 | Silence the blink | done |
> | 4.3 | New conversation | done |
> | 4.4 | Permissions from the row | **not done**, as planned |
> | 5.1 | `GET /sessions` | done, brought forward to phase 0 |
> | 5.2 | `next` | done |
> | 5.3 | Shortcut | **removed after testing**: Carbon registers and never delivers |
> | 5.4 | Launch at login | done and enabled |
>
> Off-plan, found along the way — **nine**, six of them in the code and three in
> the scripts: the server was listening on every interface; a startup crash outside
> the bundle; an API error that vanished because of a late signal; "new
> conversation" opened two tabs; the server's queue was serial; an expired
> continuation ran anyway; two installations in the same second failed; the columns
> of `sessions` didn't line up; and in the signing script: PKCS#12 incompatible
> with macOS, `“$VAR”` breaking bash, and a `grep -q` under `pipefail` failing
> intermittently through SIGPIPE.

Eighteen proposals that came out of two multi-agent audits, ordered into six
phases. Each phase can ship on its own: if you stop halfway, what's there works.

**Ordering criteria**, in this order:

1. what **unblocks** other work (foundations first)
2. what fixes a **coverage gap** — a session that exists and isn't visible is
   worse than one that's visible but wrong
3. what serves the **real scale**: 22 sessions across 12 windows, not three
4. what adds new capability

Indicative cost: **S** under 100 lines, **M** 100–300, **L** over 300 or with new
components.

---

## Phase 0 — Foundations

No visible feature. It exists to make everything else sustainable.

### 0.1 Stable signature · S · done and verified

`Scripts/create-signing-identity.sh` creates a persistent self-signed certificate;
`build-app.sh` uses it when present. Without it, every rebuild invalidates
Accessibility and Automation **while still showing the switch as on**, and the
symptom is a click that silently stops working. It has already cost two rounds of
diagnosis.

**Done on 30 July.** The script took five corrections before it worked — it was
the only piece of work shipped without ever having been run. Verified where it
counts: two builds in a row produce the same designated requirement, hooked to the
certificate rather than to the binary's hash.

### 0.2 Per-row context menu · S

Today `.contextMenu` sits on `PanelRootView`, that is, on the whole column. Five
proposals further on (1.3, 2.3, 3.4, 4.2, 4.3) need it **per row**.

Watch out for a known friction: a menu on `TrafficLightRow` shadows the panel's
one over the rows, so the global menu stays reachable only from the margins. It
has to be decided now whether to duplicate the global entries after the row ones.

**Files**: `TrafficLightRow.swift`, `PanelRootView.swift`
**Tests**: none automatable (SwiftUI), manual check

---

## Phase 1 — Coverage

Sessions that exist and the panel doesn't show. It is the most serious defect
left: a widget that doesn't see everything teaches you not to trust it.

### 1.1 Integrated-terminal sessions · S

`AppConfig.vsCodeEntrypoints = ["claude-vscode"]` discards every session launched
with `claude` from the terminal **inside** VS Code, even when it runs in a
workspace the panel already follows and in a window it already knows how to raise.

The fix is not to widen the entrypoint list — future entrypoints are unknown and a
deny-list springs leaks. It is to **invert the criterion**: what counts is whether
the `cwd` resolves to an open VS Code workspace, not how the session was started.
`WorkspaceResolver` already does exactly that.

**Files**: `HookSignal.isVSCodeHosted`, `LiveSession.isVSCodeHosted`, `AppConfig`
**Risk**: noise gets in from non-interactive sessions. Mitigation: filter on
`kind == "interactive"`, a field already present in the `~/.claude/sessions/` files.
**Tests**: a `cli` session with a cwd inside a workspace → row present; the same
session with a cwd outside → no row

### 1.2 Subagent counter · M

The case that brought the problem to light: a background workflow runs for
forty-five minutes and the traffic light stays put. `Stop` fires when the turn
closes, the subagents emit `SubagentStart`/`SubagentStop` which today are
discarded by the `agent_id != nil → ignore` rule.

The rule shouldn't be removed, it should be **refined**: a subagent has no traffic
light of its own, but its existence proves the session is working.

- `SessionState.activeSubagents: Int`
- `SubagentStart` increments, `SubagentStop` decrements, `Stop`/`SessionEnd` reset
- while it is above zero the row stays `working`
- the row shows `×3` before the label

**Real cost**: two extra hooks, but the spawning is proportional to the subagents,
not to tool calls — the 33-agent workflow would have cost 66 curl calls in 45
minutes, against thousands of `PreToolUse`.
**Requires**: re-installing the hooks, hence a re-authorization if 0.1 hasn't been
done first.
**Tests**: start/start/stop → counter 1, state `working`; `Stop` → reset

### 1.3 Other IDEs · M

`ideName` in the locks is `vscode.env.appName`: Cursor and the forks write their
own name. `IDEWindow.isVSCode` discards them.

The mechanism is verified, **Cursor is not verified at runtime**. Two real
obstacles: `WindowTitleMatcher` is tuned to VS Code's format
(`file — folder — profile`) and JetBrains uses `project – file`; and the bundle
identifier used for activation is hardcoded to `com.microsoft.VSCode`.

To be done only if genuinely needed: it introduces a matrix of cases that can't be
tested without having the IDEs installed.

**Prerequisite**: having Cursor installed to test it

---

## Phase 2 — Scale

Twenty-two rows across twelve windows. Here the problem isn't what to show but
what **not** to show.

### 2.1 One row per window · L

Measured: 26 live sessions, 24 in VS Code, **22 distinct sessionIds across 12
locks**. Seven workspaces produce more than one. The column draws 22 rows for 12
raisable windows.

Group by workspace: the dot shows the group's most urgent state, an `×4` says how
many there are, the tooltip lists them by `name` (`lampboard-d9`, a field already
present in the session files).

**Serious risk**: granularity is lost. If in one window one session is green and
another is working, a click marks the whole row as seen and the unread answer
disappears. Mandatory mitigation: `markSeen` acts only on the group's sessions that
were in the most urgent state, not on all of them.

**Cheaper alternative** if the collapse only half convinces: keep one row per
session but **sort by workspace**, so that siblings stay adjacent.

**Files**: `TrafficLightState.ordered` becomes `grouped`, `TrafficLightRow`,
`PanelController.activate`
**Tests**: a group with green + yellow → green dot, `×2`; markSeen → the yellow
stays yellow

### 2.2 "Only what's waiting" filter · S

Hides `idle` and `working`, leaves `awaiting`, `ready`, `failed`.

**The risk is movement**: the panel changes height on every transition, and in
peripheral vision movement is the worst defect for a widget you glance at.
Mitigation: fixed height based on the maximum number of rows seen recently, or
suppressed animation.

**Files**: `TrafficLightColumn`, `Preferences`
**Tests**: filter on with only idle rows → empty state, not a zero-height column

### 2.3 Pin to top or hide · M

Row menu: "Pin to top", "Hide". The hidden ones are collected into a summary row
that **lights up if one of them needs attention** — that's not an extra, it is what
stops the feature from causing the very harm the product exists to prevent.

**Depends on**: 0.2
**Files**: `Preferences` (workspace sets), `TrafficLightState.ordered`

---

## Phase 3 — Attention

For when you're not looking at the panel. To be handled with care: with 22
sessions, one notification per event is spam you disable after a day.

### 3.1 Notify only for `awaiting` · M

Only the state that **blocks** the work. Never for `ready`: a ready answer waits, a
permission doesn't.

`UNUserNotificationCenter` from an `LSUIElement` app signed ad-hoc: an agent claims
to have verified it with a probe, but I deleted that probe and never checked the
result myself. **To be re-verified before implementing.** With 0.1 done, the
unstable cdhash problem goes away.

**Tests**: the notification names the workspace and the reason; clicking it raises
the window

### 3.2 Don't alert if you're already looking · S

A gate before every notification: if the panel is really visible
(`occlusionState`) and there has been keyboard activity recently, you've already
seen the dot.

**Careful**: in the app's log `occlusionState` already comes out wrong at startup
(`occluded` with the window visible). A gate that is too closed is worse than no
notification. It should be used as an **attenuator**, not as a switch: at most it
delays, it doesn't suppress.

**Depends on**: 3.1

### 3.3 A summary on return · M

No notifications while you're away; one on your return: how many are waiting and
which.

The critic itself judged this the most easily useless of the group: when you come
back you look at the panel anyway, and the column already says everything. **To be
done only if 3.1 proves too noisy.**

### 3.4 Mute a row, or everything for an hour · S

"Don't alert me for this workspace", "Mute for one hour".

**Constraint**: it silences the notifications, never the color. A muted row has to
stay visibly there, otherwise it becomes a deletion you forget you performed.

**Depends on**: 0.2, 3.1

### 3.5 Presence for the phone's push notifications · S

`CLAUDE_CLIENT_PRESENCE_FILE` (documented, min-version 2.1.181): Claude Code skips
the push notifications to the phone when the file exists. The panel creates it
while you're at the Mac and deletes it when you lock the screen.

**Risk**: it inverts a Claude Code default. If the detection gets it wrong, you
lose notifications that today always arrive. To be kept **off by default**.

---

## Phase 4 — Row actions

### 4.1 Alt+click peeks without consuming the green · S

Today `markedSeen` is irreversible by construction. Alt+click raises the window
leaving the row green; in the menu, "Mark as unread" to remedy one click too many.

**Risk**: two behaviors under the same click. If the modifier isn't discoverable
the feature stays dead code — the menu entry is what makes it discoverable.

**Files**: `TrafficLightRow` (`NSEvent.modifierFlags`), `StateReducer`
(`markUnread` action)
**Tests**: alt+click → state unchanged; markUnread on idle → back to `ready`

### 4.2 Silence this row's blink · S

Stops the blinking until the next `UserPromptSubmit` (already registered, so zero
cost). The amber color **stays**: it silences the movement, not the signal.

**Depends on**: 0.2

### 4.3 New conversation in this project · S

The same deep link already implemented, without the `session` parameter:
`primaryEditor.open(undefined)` creates a new tab.

**Risk**: it makes multiplying sessions easy, and every extra session is an extra
row in a column that holds twelve. Worth deciding whether it is a feature or a
temptation.

**Depends on**: 0.2

### 4.4 Allow/Deny the permission from the row · L · not to be done now

The `PermissionRequest` hook exists in binary 2.1.220 and can decide the outcome.

**Two serious risks.** The hook **blocks the turn** until it answers: if
lampboard isn't running or has crashed, every permission request hangs. And a
widget that grants permissions to Claude Code is an attack surface on a local HTTP
endpoint that today is unauthenticated.

To be picked up again only after 5.1, and with authentication.

---

## Phase 5 — Integration

### 5.1 `GET /sessions` in JSON · S

The server already handles multiple paths (`/health`), and the state is already a
serializable value.

**Security prerequisite**: the endpoint would be readable by any local process,
including the Claude Code sessions themselves, and the workspace names are
information. It needs a token in `~/.lampboard/` with mode `0600`, read by the
hook script — which already runs as the user.

### 5.2 `lampboard next` · M

Raises the next waiting session. The CLI process knows nothing about the column's
state, so it has to **talk to the running instance**: a route that raises windows,
not one that colors dots.

**Depends on**: 5.1 and its authentication. Before that, it isn't done.

### 5.3 Global hotkey · M

`RegisterEventHotKey` verified to compile on SDK 26.0 with no deprecations.
Necessary because the panel is `.nonactivatingPanel` and never receives keyboard
focus.

**Risk**: a hotkey that doesn't fire is worse than no hotkey — you stop looking at
the column because "it'll tell me anyway". A registration failure has to be shown,
not swallowed.

**Depends on**: 5.2 for the "next waiting" logic

### 5.4 Launch at login · S

`SMAppService.mainApp.register()`, with a checkmark in the menu.

**Depends on 0.1**: without a stable signature, macOS registers an app that becomes
a different one on every build, and orphaned records pile up. With an ad-hoc
signature it **must not be done**.

---

## Recommended sequence

```
0.1 stable signature       ← once, unblocks 1.2, 3.1, 5.4
0.2 row menu               ← unblocks 2.3, 3.4, 4.2, 4.3
   │
1.1 terminal sessions      ← coverage gap, minimal cost
1.2 subagent counter       ← the case that brought the problem to light
   │
2.1 one row per window     ← 22 rows for 12 windows
2.2 filter
   │
3.1 awaiting notification  →  3.2 gate  →  3.4 mute
   │
4.1 alt+click   4.2 silence the blink   4.3 new conversation
   │
5.1 endpoint + token  →  5.2 next  →  5.3 hotkey
5.4 launch at login
```

**Excluded from the plan**: 4.4 (permissions from the row) until there is
authentication; 1.3 (other IDEs) until there is a way to test it; 3.3 (summary on
return) until 3.1 proves noisy.

---

## Rules this plan gives itself

**One release at a time, and tested.** Three consecutive fixes for three different
symptoms of the same never-diagnosed cause have already cost a day.

**Verify with the tool the app actually uses.** Title matching stayed broken for a
whole session with ten green tests, because it had been verified with `osascript` —
which serializes lists differently from `NSAppleScript`.

**Restart the app after every build.** A new bundle does not replace the running
process. It has already cost one wasted diagnosis.

**No checks that touch TCC, login items or notifications without saying so first.**
The agents from the second audit registered a login item and made two authorization
prompts appear in the middle of the work.
