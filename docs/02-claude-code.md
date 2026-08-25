# Claude Code from the outside

Everything here was worked out by observing **Claude Code 2.1.220** and the
**anthropic.claude-code 2.1.220-darwin-arm64** extension. None of it is official
documentation, and none of it is guaranteed stable between releases.

Every claim states **how it was verified**, because the difference between "I
read it in the binary" and "I expect it to be so" is exactly the difference
between a project that holds up and one that breaks at the next version.

> **How to redo the checks.** The binary is a 256 MB Mach-O with the JavaScript
> bundle inside it, so `strings` works:
> ```bash
> BIN=~/.local/share/claude/versions/2.1.220
> strings -a "$BIN" | grep -c '"SubagentStart"'
> ```
> The extension is minified JavaScript in the clear:
> ```bash
> EXT=~/.vscode/extensions/anthropic.claude-code-*/extension.js
> ```

---

## 1. The hooks

### How they are registered

In `~/.claude/settings.json`, under the `hooks` key, one entry per event:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/you/.clawd-light/hook.sh",
            "timeout": 3
          }
        ]
      }
    ]
  }
}
```

The intermediate level (the array of "matcher groups") exists because some events
support a `matcher` filter. clawd-light doesn't use it: it registers a group with
no matcher, which applies to everything.

**Mind the lifecycle.** Claude Code sessions that are **already open** do not
re-read `settings.json`: they pick up the new configuration only the next time
they start. After an `install-hooks`, the sessions in progress carry on with the
old one — and if you have just added two events, those will never arrive for them.

### The nine events clawd-light registers

Claude Code exposes around thirty. These are the ones that move a traffic light:

| Event | When | Effect on the traffic light |
|---|---|---|
| `SessionStart` | startup, resume, clear, **compact**, fork | `idle` — **except** when `source == "compact"` |
| `UserPromptSubmit` | the user submits a prompt | `working`, and clears the subagents |
| `Notification` | see the subtype table | it depends |
| `Stop` | the turn closes normally | `ready` |
| `StopFailure` | the turn is interrupted by an error | `failed`, or `ready` when truncated |
| `SessionEnd` | the session terminates | removes the row |
| `SubagentStart` | a subagent starts | counter +1 |
| `SubagentStop` | a subagent finishes | counter −1 |
| `PostToolUse` | a tool call completes | `working`, and it **releases a pending question** |

`PostToolUse` is the only one that costs a spawn per tool call, and it is here for
one reason: it is the sole registered event that can prove a permission prompt was
answered. Without it an amber row keeps flashing at somebody who has already
replied, until the turn ends — measured at thirty-three minutes. `PreToolUse`
cannot do the same job: it carries `permissionDecision` in its own output, so it
runs *before* the prompt.

One optional one, behind `--with-tool-events`:

| Event | Cost |
|---|---|
| `PreToolUse` | **one process per tool call** |
| `PostToolUse` | same |

They make the yellow more responsive mid-turn. Across several intense sessions
you feel it. By contrast, `SubagentStart`/`Stop` cost in proportion to the
**number of agents**: a thirty-three agent workflow is sixty-six requests over
three quarters of an hour, against thousands of `PreToolUse`.

### The payload

Fields common to every event:

```json
{
  "session_id": "8a46d71c-09c1-4a74-8530-3ff10d609933",
  "hook_event_name": "Stop",
  "cwd": "/Users/you/Development/project",
  "transcript_path": "/Users/you/.claude/projects/…/….jsonl"
}
```

Additional fields, per event:

| Event | Extra fields |
|---|---|
| `SessionStart` | `source`: `startup` · `resume` · `clear` · **`compact`** · `fork` |
| `Notification` | `notification_type` |
| `Stop` | `last_assistant_message` |
| `StopFailure` | `error_type` or `error`, plus `last_assistant_message` with the error text |
| `SubagentStart` | `agent_id`, `agent_type` |
| `SubagentStop` | `agent_id`, `agent_type`, `stop_hook_active`, `agent_transcript_path`, `last_assistant_message` |

The shapes of the two subagent events were read literally:

```
hook_event_name:"SubagentStart",agent_id:e,agent_type:t
hook_event_name:"SubagentStop",stop_hook_active:n,agent_id:o,
  agent_transcript_path:KA(o),agent_type:a??"",last_assistant_message:p,...f
```

### The `Notification` subtypes

| `notification_type` | Meaning | State |
|---|---|---|
| `permission_prompt` | Claude asks permission to run a tool | `awaiting` |
| `elicitation_dialog` | an MCP server opened a dialog | `awaiting` |
| `agent_needs_input` | an agent is waiting for input | `awaiting` |
| `agent_completed` | an agent has finished | `ready` |
| `idle_prompt` | inactivity timer | **nothing** |

`idle_prompt` is a timer, not an answer: mapping it to green invented answers
that never arrived. It does serve to **discover** a session the app didn't know
about — in that case it creates the row as `idle`, which is what it proves.

### `session_id` is not what it looks like

The field changes value when the conversation forks (`fork`) or restarts, and the
same project can produce many of them. Measured on a real machine:
**22 distinct `session_id`s across 12 windows**. It is the reason the column
groups by project and not by session.

### The `agent_id` field and the rule about it

Every event generated **inside** a subagent carries `agent_id`. The general rule
is to discard it: a subagent works inside the parent's turn and does not describe
the user session's state.

`SubagentStart` and `SubagentStop` are the exception, and the reason is subtle:
they do not report the subagent's *work*, they report that the subagent
**exists** — which is a fact about the parent's turn. In the reducer they are
therefore intercepted **before** the rule that discards.

### The hook script

Generated by `HookScriptBuilder`, fifteen lines, and it **always exits zero**:

```bash
BODY=$(cat)
curl --silent --show-error --output /dev/null \
     --connect-timeout 1 --max-time 2 \
     --request POST \
     --header 'Content-Type: application/json' \
     --header "X-Claude-Entrypoint: ${CLAUDE_CODE_ENTRYPOINT:-}" \
     --data-binary "$BODY" \
     'http://127.0.0.1:9877/signal' 2>/dev/null || true
exit 0
```

Three details, all deliberate:

- **Unconditional `exit 0` and `|| true`.** A failing hook can interrupt a Claude
  Code turn. Nobody wants their work to stop because a decorative widget wasn't
  running.
- **Short timeouts** (1 s to connect, 2 s in total), with the `timeout: 3` in the
  registration as a net.
- **`CLAUDE_CODE_ENTRYPOINT` in a header.** That variable is in the environment,
  not in the payload: this is the only way to get it through.

---

## 2. The files on disk

### `~/.claude/ide/<port>.lock` — one IDE window

Written by the extension, one per window:

```json
{
  "pid": 12345,
  "workspaceFolders": ["/Users/you/Development/project"],
  "ideName": "Visual Studio Code",
  "transport": "ws"
}
```

- **`workspaceFolders`** is what matters: it maps a `cwd` to a window.
- **`pid` does not identify the window.** VS Code writes the same PID into every
  lock. It only tells you whether the IDE is alive.
- **`ideName` is `vscode.env.appName`.** Forks write their own name into it:
  `Cursor`, and the beta build writes `Visual Studio Code - Insiders`. That is
  why recognition is by *containment* and not by equality.
- Locks are **not always removed** on close. Hence the freshness threshold
  (seven days).

### `~/.claude/sessions/<pid>.json` — a live process

```json
{
  "pid": 10653,
  "sessionId": "8a46d71c-09c1-4a74-8530-3ff10d609933",
  "cwd": "/Users/you/Development/event-tracker",
  "entrypoint": "claude-vscode",
  "kind": "interactive",
  "name": "event-tracker-64",
  "nameSource": "derived"
}
```

**These files survive the death of the process too.** The liveness check is
`kill(pid, 0)`: a syscall that sends no signal and only asks the kernel whether
that process exists. `EPERM` counts as alive — it means it exists but belongs to
another user.

The **`kind`** field is the best source for telling an interactive session apart:
Claude Code writes it itself, and it is more reliable than a deduction from the
command's name.

### `entrypoint`, and why it isn't a criterion

Observed values: `claude-vscode`, `cli`, `sdk`, `print`.

The project does **not** filter on an allow-list, and the reason is concrete:
`claude` launched from VS Code's **integrated** terminal has entrypoint `cli` but
runs in the same window and the same project — it deserves the same traffic
light. An allow-list discarded it, and silently discarded every future entrypoint
as well.

The criterion is **where it runs**, which `WorkspaceResolver` decides. All that
remains is a **deny-list** (`sdk`, `sdk-ts`, `sdk-py`, `print`) for what nobody is
watching. When a deny-list is wrong it shows one row too many — a mistake you can
see and fix — instead of hiding one, which stays silent.

### `CLAUDE_CLIENT_PRESENCE_FILE`

An environment variable read by Claude Code: if the file it points at **exists**,
the push notifications to your phone are skipped. clawd-light creates it while
you are at the Mac and deletes it when you lock the screen.

Off by default, because it **inverts a built-in behavior**: if the detection gets
it wrong the result is not one notification too many but a notification **lost**,
and lost notifications go unnoticed.

---

## 3. The VS Code extension

### The URI handler

The extension registers a handler for `vscode://Anthropic.claude-code/…`. The
`/open` path reads two parameters:

```js
case "/open": {
  let w = x.get("session") ?? void 0,
      E = x.get("prompt")  ?? void 0;
  Pe.commands.executeCommand("claude-vscode.primaryEditor.open", w, E);
  return;
}
```

Hence `vscode://Anthropic.claude-code/open?session=<id>`, and without `session` a
new conversation.

### What `primaryEditor.open` actually does

```js
registerCommand("claude-vscode.primaryEditor.open", async (g, x) => {
    u.createPanel(g, x, Pe.ViewColumn.Active)
})
```

And `createPanel`:

```js
createPanel(sessionId, prompt, column) {
  if (sessionId) {
    let existing = this.sessionPanels.get(sessionId);
    if (existing) {
      existing.reveal();
      if (prompt) showInformationMessage("Session is already open…");
      return { startedInNewColumn: false }
    }
  }
  // … otherwise:
  createWebviewPanel("claudeVSCodePanel", "Claude Code", …)
}
```

**It reuses the tab only if it already has one registered for that `sessionId`**,
and `sessionPanels` is per window. When the panel isn't there — which happens
**always for integrated-terminal sessions**, which have no Claude panel at all —
it creates a new, empty one.

### Why the deep link is off by default

Two consequences, both of which only surfaced once raising the window started
working properly — before that the deep link never fired, because it fires **only
after a successful raise**:

1. VS Code asks for permission on **every** invocation: *"Allow an extension to
   open this URI?"*. A click that asks for confirmation is no longer a click.
2. The new tab, for the reason above.

The click keeps its promise anyway, because taking you to the right window is
done by the accessibility raise, not by the link. It stays switchable from the
menu.

> **This is an extension's internal contract, not a public API.**
> It can change without warning. That is why the switch exists: if a future
> version breaks it, you turn it off without recompiling.

### The window titles

Observed format:

```
<context> — <folder> — <profile>
Build floating Mac traff… — clawd-light — Claude Minimal
tsconfig.base.json — os-platform — Claude Minimal
```

The default separator is the em dash. `WindowTitleMatcher` accepts six of them
(`— – - | · •`) to cover custom `window.title` settings, and assigns scores:

| Score | Condition |
|---|---|
| **100** | a segment matches the project name exactly |
| **50** | a segment starts or ends with the name (`project (Workspace)`) |
| **10** | the name appears as a whole word in the title |
| `nil` | no match |

The word boundary serves a real case: without it, `clawd-light` would capture the
window of `clawd-light-old`.

---

## 4. What was not used, and why

| Mechanism | Why not |
|---|---|
| **`PermissionRequest` hook** | it exists and can decide the outcome, but it **blocks the turn** until it answers: if the panel has crashed, every permission request hangs |
| **The extension's MCP server** (WebSocket, 12 tools) | it would give control over the editor, far beyond what a traffic light needs |
| **`windowId` in the deep links** | routing between windows turned out to be non-deterministic |
| **`transcript_path`** | reading the transcripts would give more context at the cost of continuous I/O and of depending on an internal format |
