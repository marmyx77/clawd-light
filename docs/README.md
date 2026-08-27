# clawd-light documentation

This folder exists for a precise reason: **whoever comes next should not have to
pay again what this project has already paid.**

clawd-light is a two-hundred-and-forty-pixel widget, but it balances on four things that are documented nowhere — the Claude Code hooks,
the files the VS Code extension leaves on disk, the way macOS decides whether
you may touch another application's windows, and what each terminal's
dictionary, CLI or socket will tell you about which tab a process lives in. (and
"Each of the three has a trap" → "Each of them has a trap") Each of the three has a trap that shows up as "sometimes
it doesn't work", and each has already swallowed at least a day.

## Where to start

It depends on why you are here.

| If you want to… | Read, in this order |
|---|---|
| **use it** | the main [README](../README.md), and nothing else |
| **understand how it works** | [01 architecture](01-architecture.md) → [02 Claude Code](02-claude-code.md) |
| **change the code** | [01](01-architecture.md) → [05 map](05-code-map.md) → [06 working here](06-working-here.md) |
| **understand why it's like this** | [04 decisions](04-decisions.md) |
| **avoid repeating other people's mistakes** | [07 traps](07-traps.md) — if you read one file, read this one |
| **touch windows, permissions, signing** | [03 macOS](03-macos.md) |

## The documents

**[01 · Architecture](01-architecture.md)**
The complete flow of an event, from Claude Code emitting it to the dot changing
color. The layers, the boundaries, why the state has two sources instead of
one — and how sessions on other machines and in terminals join the column.

**[02 · Claude Code from the outside](02-claude-code.md)**
Everything this project worked out by reverse-engineering Claude Code 2.1.220
(and re-checked against 2.1.247):
the hook events and the exact shapes of their payloads, the extension's lock
files, the session files, the VS Code extension's URI handler. Nothing here is
officially documented. Every claim states **how it was verified**.

**[03 · macOS: permissions, windows, signing](03-macos.md)**
TCC and its distinct authorizations — one per application a click has to talk
to — the "responsible process" attribution that makes every check run from a
terminal a liar, System Events and window ordering, how a click finds a terminal
tab through the process tree, code signing and why the ad-hoc kind breaks the
permissions on every build.

**[04 · Decisions](04-decisions.md)**
Every non-obvious choice with its reason and the alternatives that were
discarded. Includes the **negative** decisions: what was decided against, and
why that reason still holds.

**[05 · Code map](05-code-map.md)**
File by file: what it contains, why it exists, what you would break by touching it.

**[06 · Working here](06-working-here.md)**
Build, test, diagnose. The two suites and why there are two. The rules the
project has given itself, every one of them derived from a concrete mistake.

**[07 · Traps](07-traps.md)**
The catalogue of the defects found, each with its symptom, cause, correction and
lesson. It is the most useful document of the set, because every entry is a day
of work you won't have to repeat.

## Other documents in the project

| File | What it is |
|---|---|
| [README.md](../README.md) | the front door: what it does, how to install it, how to use it |
| [Contracts/assumptions.md](../Contracts/assumptions.md) | every undocumented thing we depend on, where the code leans on it, and what breaks when it goes |
| [PLAN.md](../PLAN.md) | the development plan with the outcome table |
| [WORKLOG.md](../WORKLOG.md) | the chronicle of the execution, in chronological order |

A plan for work not started yet goes in `docs/plans/`, one file each, with the
review it went through; it leaves when its decision has landed in
[04](04-decisions.md) and its chronicle in `WORKLOG.md` — the terminal-sessions
plan of 27 August 2026 was the first to.

`PLAN.md` and `WORKLOG.md` describe **how we got here**; this folder describes
**where it arrived**. If the two contradict each other, the code is right: report
it and fix the documentation.

## A note on tone

The comments in the code and these documents explain **why**, not **what** — the
what is what the code says. Where a comment looks verbose, it usually recounts a
defect that cost dearly: `SessionState.status`, `VSCodeFocuser.windowTitles` and
`AccessToken` are the three places where it is worth reading everything before
changing a line.
