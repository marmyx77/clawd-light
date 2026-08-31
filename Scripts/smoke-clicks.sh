#!/usr/bin/env bash
#
# Does a click still land where the row promises?
#
# Some things about this project can only be checked on a real Mac with real
# windows, and until now the only record of having checked them was somebody
# saying so. The README's Evidence column claims `live` for several surfaces on
# exactly that basis.
#
# What made it worth automating is that the mouse turns out to be unnecessary.
# Two commands already do what a click does, through the route the click takes:
# `lampboard open <n>` raises the project bound to a slot, and `lampboard focus`
# reproduces the whole decision and reports which strategy answered. The other
# half — who came forward — the window server will say. So the fragile part,
# clicking at a coordinate and looking at pixels, is not part of this.
#
# Two modes, because they prove different things and cost differently.
#
#   (default)  recognition. Nothing is activated, nothing moves, so it can run
#              whenever. It proves the panel knows where each session lives.
#   --live     the raise itself. It brings windows forward, so it needs the Mac
#              to be free. It remembers what was in front and puts it back.
#
# Deliberately outside the gate, for the reason check-contract.sh is outside it:
# a check that needs a screen, an unlocked session and other people's
# applications running cannot be a condition for merging. It runs on a person's
# machine, and it writes down what it saw.
set -euo pipefail
cd "$(dirname "$0")/.."

LIVE=0
[ "${1:-}" = "--live" ] && LIVE=1

APP="/Applications/LampBoard.app"
[ -d "$APP" ] || APP="dist/LampBoard.app"
BIN="$APP/Contents/MacOS/lampboard"
RECORD="docs/smoke-clicks.md"

if [ ! -x "$BIN" ]; then
    echo "No lampboard to test: neither /Applications nor dist/ holds one." >&2
    exit 2
fi

# The build under test, named in the record. A result that does not say which
# binary produced it is a result that cannot go stale visibly, which is the
# whole failure mode a written-down manual test has.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP/Contents/Info.plist" 2>/dev/null || echo unknown)"
SIGNATURE="$(codesign -dv --verbose=2 "$APP" 2>&1 \
    | sed -n 's/^Authority=\(.*\)$/\1/p' | head -1)"
[ -n "$SIGNATURE" ] || SIGNATURE="ad-hoc or unsigned"

curl -s -o /dev/null "http://127.0.0.1:9877/health" || {
    echo "The panel is not running, so there is nothing to click." >&2
    exit 2
}

export LIVE VERSION SIGNATURE BIN RECORD
python3 - <<'PY'
import json, os, subprocess, sys, time, datetime

BIN, RECORD = os.environ["BIN"], os.environ["RECORD"]
LIVE = os.environ["LIVE"] == "1"

def run(args, timeout=30):
    try:
        done = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return done.stdout + done.stderr
    except Exception as error:
        return f"(command failed: {error})"

def osascript(script):
    return run(["/usr/bin/osascript", "-e", script], timeout=10).strip()

def frontmost():
    """The application in front, and the title of its front window."""
    name = osascript(
        'tell application "System Events" to return name of first process whose frontmost is true'
    )
    title = osascript(
        'tell application "System Events" to tell (first process whose frontmost is true) '
        'to return name of window 1'
    )
    return name, ("" if title.startswith("execution error") else title)

token = open(os.path.expanduser("~/.lampboard/token")).read().strip()
payload = run([
    "/usr/bin/curl", "-s", "-H", f"X-LampBoard-Token: {token}",
    "http://127.0.0.1:9877/sessions",
])
# One entry per slot, not per session. A slot addresses a **row**, and a row can
# hold six conversations: asking the same question six times would say the same
# thing six times and read like six checks.
by_slot, unreachable = {}, {}
for session in json.loads(payload)["sessions"]:
    slot = session.get("slot")
    if slot:
        by_slot.setdefault(slot, session)
        continue
    # Beyond the ninth row there is no slot, and `open` addresses slots. The
    # panel's own click reaches these; nothing on the command line does, so this
    # run says nothing about them and says which ones.
    #
    # Grouped by folder and machine, which is what a row is. Grouping by label
    # would split one row into its conversations: for a terminal session the
    # label is the conversation's own title, not the project's.
    key = (session.get("host"), session.get("path", ""))
    unreachable.setdefault(key, []).append(session)
rows = [by_slot[slot] for slot in sorted(by_slot)]

# What may honestly come forward for each surface. Kept short and explicit: a
# generous list would turn this into a check that passes on anything, and the
# point is to catch the row that leads somewhere else.
EDITORS = {"Code", "Cursor", "Electron", "Code - Insiders", "Windsurf"}
TERMINALS = {"Terminal", "iTerm2", "Ghostty", "WezTerm", "kitty", "Alacritty"}

def expected(row):
    if row.get("host"):
        return EDITORS, "a Remote-SSH window"
    entry = row.get("entrypoint") or ""
    if entry == "local-agent":
        return {"Claude"}, "the Claude desktop app"
    if entry == "codex-chatgptApp":
        return {"ChatGPT"}, "the ChatGPT app"
    if row.get("origin") == "terminal" or entry == "codex-commandLine":
        return TERMINALS, "the terminal holding its tab"
    return EDITORS, "an editor window"

results = []
restore = frontmost()[0] if LIVE else None

for row in rows:
    allowed, description = expected(row)
    label, slot = row.get("label", "?"), row["slot"]

    if not LIVE:
        # Recognition only. `focus --dry-run` reports the whole decision without
        # activating anything, and names the window it would have chosen.
        # By the folder's own name, not the label: the label may be a name the
        # person gave the row, and `focus` matches what the editor writes in a
        # window title.
        folder = os.path.basename(row.get("path", "").rstrip("/")) or label
        output = run([BIN, "focus", folder, "--dry-run"])
        chose = any(line.strip().startswith("→") for line in output.splitlines())
        unknown = "No open workspace named" in output
        results.append((slot, label, description,
                        "recognised" if chose else ("not covered by --dry-run" if unknown else "NO TARGET"),
                        ""))
        continue

    run([BIN, "open", str(slot)])
    time.sleep(1.2)
    name, title = frontmost()
    verdict = "raised" if name in allowed else f"WRONG: {name}"
    results.append((slot, label, description, verdict, title))

if LIVE and restore:
    osascript(f'tell application "System Events" to set frontmost of process "{restore}" to true')

# From every row the panel holds, not only the ones this script can address:
# a terminal row sitting past the ninth slot is out of reach, which is not the
# same thing as absent, and saying both about it at once helps nobody.
held = list(rows) + [s for group in unreachable.values() for s in group]
surfaces = {expected(r)[1] for r in held}
missing = sorted({"the Claude desktop app", "the ChatGPT app", "the terminal holding its tab",
                  "an editor window", "a Remote-SSH window"} - surfaces)

now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
lines = [
    "# Live clicks, last checked",
    "",
    "Written by `Scripts/smoke-clicks.sh`. Not a gate: it needs a screen, an",
    "unlocked session and other people's applications running, so it cannot be a",
    "condition for merging. It is the record that the README's `live` column",
    "rests on.",
    "",
    f"- **When:** {now}",
    f"- **Build:** {os.environ['VERSION']}, signed by {os.environ['SIGNATURE']}",
    f"- **Mode:** {'live, windows really raised' if LIVE else 'recognition only, nothing moved'}",
    "",
    "| Slot | Row | Should lead to | Result | Window |",
    "|---|---|---|---|---|",
]
for slot, label, description, verdict, title in results:
    lines.append(f"| {slot} | {label} | {description} | {verdict} | {title or '—'} |")

if missing:
    lines += [
        "",
        "**Not exercised**, because no session of that kind was running:",
        "",
    ] + [f"- {surface}" for surface in missing]

if unreachable:
    lines += [
        "",
        "**Out of reach of this script**, because they sit past the ninth row and",
        "`open` addresses slots. The panel's own click reaches them; nothing on the",
        "command line does:",
        "",
    ] + [
        "- {} — {}".format(
            os.path.basename(path.rstrip("/")) + (f" on {host}" if host else ""),
            ", ".join(sorted({expected(s)[1] for s in group})),
        )
        for (host, path), group in sorted(unreachable.items(), key=lambda kv: kv[0][1])
    ]

if missing or unreachable:
    lines += ["", "Anything named above is something this run says nothing about."]

open(RECORD, "w").write("\n".join(lines) + "\n")

failed = [r for r in results if r[3].startswith(("WRONG", "NO TARGET"))]
for slot, label, _, verdict, _ in results:
    mark = "✗" if verdict.startswith(("WRONG", "NO TARGET")) else "✓"
    print(f"  {mark} {slot}  {label}: {verdict}")
print()
print(f"Written to {RECORD}")
sys.exit(1 if failed else 0)
PY
