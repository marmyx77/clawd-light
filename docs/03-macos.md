# macOS: permissions, windows, signing

This document collects everything the platform does **differently from how it
looks**. Each section describes a mechanism, how to verify it, and the trap
hiding inside it.

If you are about to touch windows, permissions or signing: read all of it. It's
ninety seconds that save a day.

---

## 1. TCC — the authorizations

### There are two, not one

| Permission | What it's for | Where it's granted |
|---|---|---|
| **Accessibility** | reading and manipulating other apps' windows | Privacy & Security › Accessibility |
| **Automation** | sending Apple Events to System Events | Privacy & Security › Automation › lampboard › System Events |

**Both** are needed to raise a window. Confusing them sends you off to check a
switch that is already on, and that has already happened.

They are also granted in different ways: Accessibility is a checkbox you tick in
a list, Automation appears as a **dialog** the first time the app tries to send
an Apple Event, and if you answer "no" it doesn't come back on its own.

### How to read them, and why the terminal lies

```swift
AXIsProcessTrusted()                        // Accessibility: passive, asks nothing
VSCodeFocuser.checkAutomationPermission()   // Automation: tries a harmless event
```

For Automation there is **no** API that queries without using: the first attempt
is also what makes the prompt appear.

> ### The trap: the "responsible process"
>
> When you launch a binary from a terminal, macOS does **not** attribute the
> permissions to that binary: it attributes them to the *responsible process*,
> which up the chain is Terminal.
>
> ```bash
> # This does NOT tell you whether the app has the permissions.
> # It tells you whether Terminal has them.
> dist/LampBoard.app/Contents/MacOS/lampboard status
> ```
>
> This project fell for it: `focus` from a terminal answered `✓ window raised`,
> while the clicked panel did something else. It is the **same deception** as
> verifying the matching with `osascript` instead of `NSAppleScript` — different
> tool, different answer, wrong conclusion.
>
> **How to verify for real**: make the app itself write down what it sees.
> ```bash
> pkill -x lampboard
> LAMPBOARD_DEBUG=1 open dist/LampBoard.app
> grep "accessibility=" ~/.lampboard/debug.log
> ```

### The AppleScript error codes that matter

| Code | Meaning | How the project treats it |
|---|---|---|
| `-1743` | the user has not authorized Apple Events | `automationDenied` |
| `-1744` | authorization not requested yet | `automationDenied` |
| `-25211` | accessibility API disabled for the process | `accessibilityDenied` |
| `-1728` | object not found | used by the script for "title vanished" |

---

### One Automation entry per application

The permission is granted per *target* application: "lampboard → System
Events" lets the panel raise editor windows, and says nothing about Terminal.
Selecting a tab in Terminal.app or iTerm2 sends an Apple Event to that
application, so the first click on a terminal row shows a second prompt naming
it, and a refusal is reported as *Automation permission for Terminal missing* —
not as the System Events one, which is already on. `sdef /Applications/X.app`
prints what an application exposes without sending it anything: that is how
`tty` on Terminal's tabs and iTerm2's sessions, and Ghostty's `name` and
`working directory`, were found.

## 2. The locked screen

With the screen locked, **two verification tools stop working without saying so**:

- screenshots capture the lock screen, not the desktop;
- enumerating windows via accessibility returns an **empty** list, while still
  answering simple questions and while the permissions still show as "granted".

The second one is insidious because it looks like a regression. Hence the
dedicated `noWindowsVisible` error, distinct from `windowNotFound`: the two cases
have opposite remedies — checking a permission versus reopening a folder.

**Always check it before concluding anything:**

```swift
let d = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
let locked = (d["CGSSessionScreenIsLocked"] as? Int) == 1
```

What keeps working while locked: `CGWindowListCopyWindowInfo` (existence, bounds,
alpha, window layer) and the `GET /sessions` endpoint. Two independent
measurements that agree are worth more than one screenshot.

---

## 3. System Events and the windows

### The order is z-order, and it changes on its own

```applescript
tell application "System Events" to tell process "Code" to get name of every window
```

The list arrives **in depth order**: frontmost first. That order changes as soon
as the focus moves — that is, exactly while you click a floating panel and
activate the editor.

**Practical consequence:** reading the titles and raising by index are two
distinct Apple Events, and between the two the index expires. The symptom is
"sometimes it raises the wrong window, typically the last one used".

**The correct form** — by title, which is an identity rather than a position:

```applescript
tell application "System Events"
    tell process "Code"
        set candidate to (every window whose name is "…")
        if (count of candidate) is 0 then error "title vanished" number -1728
        perform action "AXRaise" of item 1 of candidate
    end tell
end tell
tell application id "com.microsoft.VSCode" to activate
```

Putting a title inside a script's source means putting a **file name** in it,
which is text the user doesn't fully control. Hence
`AppleScriptString.escaped`, with six dedicated tests.

### `NSAppleScript` is not `osascript`

`NSAppleScript` returns an AppleScript list as `typeAEList`, and on a list
**`stringValue` is `nil`**. The elements have to be read:

```swift
if descriptor.numberOfItems > 0 {
    let titles = (1...descriptor.numberOfItems).compactMap {
        descriptor.atIndex($0)?.stringValue
    }
}
// with a single window it may instead return a string
if let single = descriptor.stringValue, !single.isEmpty { … }
```

`osascript` from the terminal **serializes the list into text**, so verifying
with that proves nothing about `NSAppleScript`. This confusion kept title
matching broken for an entire day **with ten green tests**.

### `NSRunningApplication.activate()` lies

Invoked from an *accessory* app that isn't frontmost, macOS ignores it — and it
returns `true` anyway. The caller believes it activated the app when nothing
happened.

The route that works is `/usr/bin/open`, which is a system process and does have
the right to activate:

```swift
process.arguments = ["-b", bundleIdentifier]   // ← no path
```

**No path among the arguments.** `open -b <bundle> <folder>` asks the editor to
*open* that folder, and when it doesn't recognize it as already open it
materializes a new window for it.

### The panel

```swift
styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView]
level = .floating
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
canBecomeKey  = true    // needed so the clicks reach SwiftUI
canBecomeMain = false   // the user's work is elsewhere
sendEvent(_:) // makes the panel key before a mouse-down is dispatched
```

`nonactivatingPanel` is what makes the widget usable: without it, clicking a
traffic light would activate lampboard and take the focus away from the editor
an instant before giving it back, with a flicker on every click.

`mouseDownCanMoveWindow` is what decides whether a drag moves the panel or a
row. The panel is movable by its background, and a SwiftUI subtree says yes to
that question — so the reorder handle's grab area is an `NSView` (`DragHandle`)
that says no and takes the mouse itself (see 07-traps, "The drag that moved the
panel").

`sendEvent` is what makes the *first* click count. AppKit spends the first
click in a non-key window on making it key, and delivers it only if the view
under the pointer says `acceptsFirstMouse` — and that view is SwiftUI's own
scroll view, which says no; overriding the answer on the hosting view changes
nothing, because nobody asks the hosting view. Every return from the editor
leaves the panel non-key, so every visit began with a click that only knocked
(see 07-traps, "The click that only knocked"). Making the panel key *before*
`super.sendEvent` turns the first click into an ordinary one. The panel logs
`became key` / `resigned key` so that the per-signal log can tell a delivered
first click from a second one.

### Tooltips do not appear in it, and that is not a bug

`NSToolTipManager` puts a tooltip on screen only when the window under the
pointer is **key** and the application is **active**. This panel is neither by
construction — a `nonactivatingPanel` in an accessory app that becomes key for
the instant of a click — so `.help("…")` on a row compiles, reads correctly and
displays nothing. Every tooltip in the panel was dead text for weeks, and the
row's whole second layer with it (07-traps, "The tooltips that were written and
never shown").

The panel draws its own instead: one borderless window that ignores the mouse,
never becomes key, and removes itself on any mouse-down — including the
right-click that opens a context menu over the row it was explaining, which
SwiftUI's `.contextMenu` gives no notice of. `.help` stays only in the ordinary
windows — Settings, the conversations, the legend — where it works, because those
windows do become key.

The size has to be known before the window is shown, and there is no layout to
supply it: `NSHostingView.fittingSize` on a view with no width lays the text out
one word per line and answers **358 × 3,332 points**. Decide the width first.

`occlusionState` is **not reliable**: it reports `occluded` even with the window
in plain sight. Using it as a switch would suppress legitimate alerts; `occlusionState` is **not reliable**: it reports `occluded` even with the window
in plain sight. It once attenuated notifications together with keyboard
inactivity; that gate was removed (04-decisions, 'The gate holds only explicit
silences'), and today the value is only logged.

---

## 4. Code signing

### Why the ad-hoc kind breaks the permissions

The "designated requirement" of an ad-hoc signed app hooks onto the **binary's
hash**. You rebuild, the hash changes, and to macOS it is **a different
application**: the authorizations lapse **while still showing the switch as on**.

The symptom is a click that silently stops working. It cost this project two
rounds of diagnosis.

With a stable certificate the requirement hooks onto the **identity**:

```
designated => identifier "com.lampboard.app" and
              certificate leaf = H"4dff44990eb2166d5a002f5969ea5f6a88559a48"
```

**How to verify it** — two builds in a row must produce the same requirement:

```bash
./Scripts/build-app.sh && codesign -d --requirements - dist/LampBoard.app 2>&1 | tail -1
./Scripts/build-app.sh && codesign -d --requirements - dist/LampBoard.app 2>&1 | tail -1
```

### Creating the identity: three traps

`Scripts/create-signing-identity.sh` handles all of them, but they are worth
knowing because they come back wherever anything is signed on macOS.

**1. OpenSSL 3 produces PKCS#12 files macOS can't read.** By default it encrypts
with AES-256 and computes the MAC with SHA-256; the Security framework's parser
can't digest them and answers:

```
SecKeychainItemImport: MAC verification failed during PKCS12 import (wrong password?)
```

The message sends you hunting for a wrong password when the problem is the
algorithm. `-legacy` (3DES/SHA-1) is what's needed. **LibreSSL**, which is the
system `openssl`, doesn't know that flag but already has the right defaults: the
script tries and falls back.

**2. An empty password is ambiguous.** In computing a PKCS#12's MAC, "no
password" and "a zero-length password" are two different things, and the two
tools choose differently. A real password — random, in a temporary folder, alive
for a few seconds — removes the problem.

**3. `codesign` doesn't fail: it hangs.** If the private key isn't in the
"partition list", macOS opens an *"allow access?"* dialog. In a non-interactive
script that dialog reaches nobody and the command hangs forever.

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$KEYCHAIN"
```

`-T /usr/bin/codesign` at import time is **not enough** in the `login` keychain,
even though it is enough in a keychain created on the spot. Every signing script
of this kind meets this step sooner or later — always in the same way: through a
command that never returns.

Hence the rule: **every command that might wait on a dialog must be run with a
deadline**. macOS has no `timeout` out of the box, so it's done by hand:

```bash
command & PID=$!
for _ in $(seq 1 20); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
if kill -0 "$PID" 2>/dev/null; then kill "$PID"; echo "there's a dialog on screen"; fi
```

### Verifying that it worked

A script that says "✓ done" without checking is worse than one that fails.
`create-signing-identity.sh` signs a probe file and compares the `Authority`
before declaring success.

**While doing that, do not use `… | grep -q` under `set -o pipefail`**: `grep -q`
exits at the first match and closes the pipe, `codesign` receives SIGPIPE, exits
with 141, and `pipefail` fails the pipeline **even when the match was there**. It
is a race: it works one time in two. Write to a file and grep the file.

---

## 5. Notifications

`UNUserNotificationCenter.current()` outside a `.app` bundle **does not return
nil**: it raises `NSInternalInconsistencyException` —
*"bundleProxyForCurrentProcess is nil"* — and terminates the process.

Every use therefore has to be guarded:

```swift
guard Bundle.main.bundleIdentifier != nil else { return }
```

**Including assigning the delegate**, which is a use like any other and not an
exception. Forgetting it there crashes `swift run LampBoardApp` at startup,
before the panel even appears.

Authorization must be requested **when the user turns the feature on** — and at
startup only if the switch is already on — never unasked: a dialog that appears
unprompted gets a "no", and that "no" is forever.: a dialog that appears unasked gets a "no", and that "no" is forever.

---

## 6. Global shortcut — why there isn't one

This section records what was learned, not a feature that exists: the global
shortcut was implemented, tested, and **removed**. See
[04 decisions · N6](04-decisions.md#n6--a-global-shortcut-inside-the-app) and
[07 traps](07-traps.md#the-shortcut-that-registers-and-never-arrives).

`RegisterEventHotKey` (Carbon) is the only route that works for an *accessory*
app that isn't frontmost. It is old but not deprecated; the modern alternatives
either require the focus or require permission to monitor every event, which for
a single combination is out of proportion.

The callback is a context-free C function, so the action has to live in a static
property.

On this macOS the API returns `noErr` and **never delivers the event**. A
standalone probe with the same recipe received nothing either, and neither did
`NSEvent.addGlobalMonitorForEvents`. The app **cannot detect** the difference
between "registered and working" and "registered and mute": that is what made
the feature indefensible, not the malfunction itself.

The workaround that does work is the macOS Shortcuts app, bound to
`lampboard next` — see the [README](../README.md).

---

## 7. Launch at login

`SMAppService.mainApp.register()` **must not be used with an ad-hoc signature**:
macOS registers an app that becomes a different one on every build, and orphaned
records pile up in Settings that the user cannot trace back to anything. It has
already happened in this project.

`LaunchAtLogin.availability` blocks the feature until the signature is stable.
The signature is read once at startup:

```bash
codesign -dv <bundle> 2>&1 | grep "Signature=adhoc"
```

When in doubt it assumes ad-hoc: of the two, that's the harmless failure.

---

## 8. Isolating the tests from the real machine

`FileManager.default.homeDirectoryForCurrentUser` reads from `getpwuid`, **not
from the environment**: rewriting `$HOME` isolates nothing and creates the
opposite illusion.

Hence `AppConfig.homeDirectory`, which honors `LAMPBOARD_HOME`. With that
variable set, `Preferences` also uses a separate `UserDefaults` domain, otherwise
a test that switched a notification on would leave it on afterwards.

---

## Quick command reference

```bash
# lock state and idle time
CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]

# what a process is really listening on
lsof -nP -iTCP:9877 -sTCP:LISTEN

# windows as seen by the window server (works with the screen locked too)
CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)

# how a bundle is signed
codesign -dvv dist/LampBoard.app
codesign -d --requirements - dist/LampBoard.app

# available signing identities
security find-identity -p codesigning

# is there a system dialog waiting?
pgrep -x SecurityAgent
```

## Terminal seats: where a session's process lives

A terminal row's click has nothing to match a window title against — the row
is a folder, and a folder is not a window. What it has is the session's **pid**
(the session file), and from the pid the kernel gives the chain up to the
hosting application: `sysctl(KERN_PROC_PID)` for the parent, the controlling
tty and the start time, `proc_pidpath` for the executable, `KERN_PROCARGS2` for
the arguments (the zellij server names its session there). No `ps`, no shell.
The chains measured on a real machine, which `SeatSuite` pins:

| Started from | Chain from `claude` upwards | tty of `claude` |
|---|---|---|
| Terminal.app tab | `claude → -zsh → login → Terminal` | the tab's |
| zellij pane in a Terminal tab | `claude → zsh → zellij --server …/<session>` (ppid 1) | the server's pty, not the tab's |
| tmux pane | `claude → zsh → tmux` (ppid 1) | the pane's pty |
| VS Code, Claude panel | `claude → Code Helper (Plugin) → Code` | none |
| VS Code, integrated terminal | `claude → zsh → Code Helper → Code` | the tab's pty |

The two VS Code helpers are told apart by bundle name — the pty host lives in
`Code Helper.app`, the extension host in `Code Helper (Plugin).app` — and both
are editor seats. tty names come as `ttys003` from the kernel and
`/dev/ttys003` from dictionaries and tmux; `TTYName` normalises them, and `TTYName` normalises them; a tty is matched against a pattern rather than
escaped before it may enter a script, and the same rule holds for the only other
process-table string that does — the zellij session name, validated against
`^[A-Za-z0-9._-]{1,128}$` before the title-match fallback.

**Each host, its own way.** Terminal.app and iTerm2 expose the tty on their
tabs and sessions, so the tab is selected by tty. Ghostty has no tty but lists
every terminal's title and working directory: the match happens in Swift —
title, then folder, then Claude's own `✳` mark when only one terminal carries
it — and only the chosen id goes back into a script.

A description names one surface nearly always, and it named the wrong one the
moment it did not: two Codex conversations in `~/Development/turing`, both
titled `turing`, and the click could only ever raise the first. So where the
listing fails to name exactly one surface — several alike, or none at all — the
tty settles it. The panel knows the tty and Ghostty does not expose it; Ghostty
knows the surface id and the panel cannot derive it. A title nobody would choose
is written to the tty, the listing is taken again, and the surface now carrying
it is the surface on that tty. The old title goes straight back. Writing to a
slave pty is a display and never an input, which is how `wall` and `write(1)`
have always worked, so nothing is typed into the program running there. See
`TerminalTitle`. WezTerm's CLI lists panes
by `tty_name`; kitty's answers over its remote-control socket with the pid of
each window's process. A tmux pane is selected inside tmux and the attached
client's tab raised by its own chain; a zellij client is paired with its server
through their Unix sockets (`lsof`: own address in `DEVICE`, peer in `NAME`),
with the tab titled by the session name as the fallback. One Automation entry
per application, and a `claude` started from a Claude Code shell writes no
session file at all — both in [07-traps](07-traps.md).

**The pid guard.** Hours can pass between a signal and a click, and a pid can
be handed to another process in between. The session file's `procStart` is
compared with the kernel's start time — a ctime string **in UTC** on macOS,
ticks on Linux (`ProcStart`); parsed as local time it rejects every live
session, which is the kind of mistake that has a fixture from the machine.

