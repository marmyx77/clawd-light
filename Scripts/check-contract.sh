#!/bin/bash
#
# Checks that the assumptions clawd-light makes about Claude Code still hold.
#
# WHY THIS EXISTS
# This project balances on things nobody promised: hook event names and payload
# shapes, the files the VS Code extension leaves on disk, an extension's URI
# handler. None of it is documented, and none of it is stable by contract.
#
# The dangerous failure is not "they moved the furniture" — that one errors out
# and gets noticed. It is the silent one: if `SubagentStop` stops firing, nothing
# breaks, no exception is raised, and the column simply stays yellow forever while
# you believe an agent is still working.
#
# WHAT IT DOES NOT DO
# It does not repair anything. A script can notice that `session_id` became
# `sessionId`; it cannot decide what that means, and a wrong automatic fix hides
# the breakage instead of reporting it. The report IS the repair here — it names
# the assumption, where the code depends on it, and what changed. Hand that to a
# person or an agent and the fix takes minutes.
#
# USAGE
#   ./Scripts/check-contract.sh            static checks only — seconds, free
#   ./Scripts/check-contract.sh --live     also runs a real probe session
#   ./Scripts/check-contract.sh --record   re-records the golden baseline
#
# The live probe spends a few tokens: it runs two tiny `claude -p` sessions.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS="$ROOT/Contracts"
SPEC="$CONTRACTS/required-fields.json"
GOLDEN="$CONTRACTS/golden/hooks.jsonl"

MODE="static"
case "${1:-}" in
    --live)   MODE="live" ;;
    --record) MODE="record" ;;
    "")       ;;
    *) echo "unknown option: $1"; exit 2 ;;
esac

# Every check increments one of these. A run that ends with CHECKS at zero is a
# run that verified nothing, and it must fail rather than print a reassuring
# summary — the project has already shipped a test script that reported success
# after executing zero tests.
CHECKS=0
FAILURES=0

ok()   { CHECKS=$((CHECKS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { CHECKS=$((CHECKS+1)); FAILURES=$((FAILURES+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
note() { printf '    %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

[ -f "$SPEC" ] || { echo "missing spec: $SPEC"; exit 2; }

# ─────────────────────────────────────────────────────────────────────────────
head_ "Claude Code"

INSTALLED="$(claude --version 2>/dev/null | awk '{print $1}')"
EXPECTED="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["verifiedAgainst"])' "$SPEC")"

if [ -z "$INSTALLED" ]; then
    bad "claude not found on PATH"
elif [ "$INSTALLED" = "$EXPECTED" ]; then
    ok "version $INSTALLED — the version the contract was verified against"
else
    # Not a failure on its own: a new version is normal. It is the reason to run
    # the live probe, which is what actually knows whether anything moved.
    ok "version $INSTALLED (contract recorded against $EXPECTED)"
    note "different version → run with --live before trusting the column"
fi

# ─────────────────────────────────────────────────────────────────────────────
head_ "Hook registration"

SETTINGS="$HOME/.claude/settings.json"
SCRIPT_PATH="$HOME/.clawd-light/hook.sh"

if [ ! -f "$SETTINGS" ]; then
    bad "no ~/.claude/settings.json"
else
    MISSING="$(python3 - "$SETTINGS" "$SCRIPT_PATH" "$SPEC" <<'PY'
import json, sys
settings, script, spec = sys.argv[1], sys.argv[2], sys.argv[3]
wanted = set(json.load(open(spec))["events"])
hooks = json.load(open(settings)).get("hooks", {})
registered = {
    event for event, groups in hooks.items()
    if isinstance(groups, list) and any(
        entry.get("command") == script
        for group in groups if isinstance(group, dict)
        for entry in group.get("hooks", []) if isinstance(entry, dict)
    )
}
print(" ".join(sorted(wanted - registered)))
PY
)"
    if [ -z "$MISSING" ]; then
        ok "every event the contract needs is registered"
    else
        bad "events not registered: $MISSING"
        note "fix: clawd-light install-hooks"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
head_ "Files on disk"

python3 - "$SPEC" <<'PY' && ok "lock and session files carry the fields we read" || bad "see above"
import json, os, sys, glob
spec = json.load(open(sys.argv[1]))
home = os.path.expanduser("~")
problems = []

def check(pattern, fields, label):
    files = glob.glob(pattern)
    if not files:
        problems.append(f"no {label} found at {pattern}")
        return
    sample = max(files, key=os.path.getmtime)
    try:
        data = json.load(open(sample))
    except Exception as exc:
        problems.append(f"{label} unreadable: {exc}")
        return
    missing = [f for f in fields if f not in data]
    if missing:
        problems.append(f"{label} {os.path.basename(sample)} lacks: {', '.join(missing)}")

check(f"{home}/.claude/ide/*.lock", spec["lockFileFields"], "IDE lock")
check(f"{home}/.claude/sessions/*.json", spec["sessionFileFields"], "session file")

for p in problems:
    print(f"    {p}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY

# ─────────────────────────────────────────────────────────────────────────────
head_ "Message delivery (rewake)"

# The chat window's send path depends on hook options Claude Code marks @internal.
# When they are renamed nothing errors — the message simply never arrives — so the
# only defence is asserting the names still exist in the shipped binary.
CLAUDE_BIN="$(readlink -f "$(command -v claude 2>/dev/null)" 2>/dev/null || true)"
if [ -z "$CLAUDE_BIN" ] || [ ! -f "$CLAUDE_BIN" ]; then
    bad "claude binary not found — cannot check the message delivery contract"
else
    MISSING_OPTS=""
    for opt in $(python3 -c '
import json,sys
spec = json.load(open(sys.argv[1]))["rewake"]
print(" ".join(spec["hookOptions"] + spec["deliverySignals"]))
' "$SPEC"); do
        grep -a -q "$opt" "$CLAUDE_BIN" || MISSING_OPTS="$MISSING_OPTS $opt"
    done
    if [ -z "$MISSING_OPTS" ]; then
        ok "the asyncRewake options and the task-notification path are still there"
        note "@internal — no deprecation is owed to us; this check is the warning"
    else
        bad "message delivery is broken — absent from the binary:$MISSING_OPTS"
        note "the chat window will accept messages and silently never deliver them"
        note "see Contracts/assumptions.md -> rewake.mechanism"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
head_ "Background work (the reason a working session is not green)"

# The traffic light trusts Claude Code to have already filtered this list down to
# work the session is waiting on. That filter is the assumption, not the field, and
# it lives in the binary where nobody owes us a deprecation.
if [ -z "${CLAUDE_BIN:-}" ] || [ ! -f "${CLAUDE_BIN:-}" ]; then
    bad "claude binary not found - cannot check the background-work contract"
else
    python3 - "$SPEC" "$CLAUDE_BIN" <<'BGPY' && ok "the in-flight list is still filtered the way the column assumes" || bad "the background-work contract moved - see above"
import json, re, subprocess, sys

spec = json.load(open(sys.argv[1]))["backgroundTasks"]
blob = subprocess.run(
    ["strings", "-n", "12", sys.argv[2]], capture_output=True, text=True
).stdout
problems, notes = [], []

if spec["wireField"] not in blob:
    problems.append(
        f'the `{spec["wireField"]}` field is gone from the binary - every turn will '
        "look clean and green-during-work comes back in silence"
    )

for marker in spec["filterMarkers"]:
    if marker not in blob:
        problems.append(
            f"`{marker}` is gone: the filter that drops non-backgrounded work may "
            "no longer run, and unrelated tasks would hold rows yellow"
        )

if not re.search(spec["filterPattern"], blob):
    problems.append(
        "the running/pending filter is no longer recognisable. If it loosened, "
        "finished tasks now arrive and those rows stay yellow for ever; if it "
        "tightened, pending work is dropped and the row goes green in front of it"
    )

# A status vocabulary that grew is safe by construction - the decoder counts
# anything it does not recognise as work - but it is worth saying out loud.
#
# Anchored on `task_updated` rather than on the words themselves: the binary holds
# half a dozen unrelated enums that also start with "pending" or "running", and one
# of them is the SQL keyword list.
# Every occurrence, not the first: the anchor appears in several places and only
# one of them is followed by the enum.
enum = None
for anchor in re.finditer(re.escape(spec["statusEnumAnchor"]), blob):
    window = blob[anchor.start():anchor.start() + 400]
    enum = re.search(r'\[("[a-z_]+",?){3,}\]', window)
    if enum:
        break
if enum:
    found = set(re.findall(r'"([a-z_]+)"', enum.group(0)))
    fresh = found - set(spec["knownStatuses"])
    if fresh:
        notes.append(
            "new task statuses, counted as work until classified: "
            + ", ".join(sorted(fresh))
        )
    for gone in set(spec["finishedStatuses"]) - found:
        problems.append(
            f"`{gone}` is no longer a task status; the decoder still denies it, "
            "which is now dead code hiding whatever replaced it"
        )
else:
    notes.append(
        f'could not locate the status enum near `{spec["statusEnumAnchor"]}` '
        "- the deny-list is unverified"
    )

for n in notes:
    print(f"    {n}", file=sys.stderr)
for problem in problems:
    print(f"    {problem}", file=sys.stderr)
sys.exit(1 if problems else 0)
BGPY
    note "see Contracts/assumptions.md -> hook.background_tasks"
fi

# ─────────────────────────────────────────────────────────────────────────────
head_ "Session transcripts"

# This one costs nothing and proves a lot: the transcripts are already on disk,
# by the thousand, written by every version of Claude Code that ever ran here.
# Sampling the most recent ones checks the format against reality rather than
# against a fixture we wrote ourselves.
python3 - "$SPEC" <<'PY' && ok "transcripts carry the fields the chat window reads" || bad "the transcript contract moved — see above"
import json, os, sys, glob

spec = json.load(open(sys.argv[1]))["transcript"]
home = os.path.expanduser("~")
files = glob.glob(f"{home}/.claude/projects/*/*.jsonl")
problems, notes = [], []

if not files:
    print("    no transcript found under ~/.claude/projects/", file=sys.stderr)
    sys.exit(1)

files.sort(key=os.path.getmtime, reverse=True)
sample = files[: spec["_sampleSize"]]

origin = spec["humanOrigin"]
known_assistant = set(spec["assistantBlocks"])
known_user = set(spec["userBlocks"])

humans = 0
titles = 0
seen_assistant = set()
seen_user = set()
missing_fields = set()

for path in sample:
    for line in open(path, errors="ignore"):
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except Exception:
            continue

        kind = record.get("type")
        if kind == spec["titleRecord"]["type"]:
            if spec["titleRecord"]["field"] in record:
                titles += 1
            continue
        if kind not in ("user", "assistant"):
            continue

        missing_fields |= {f for f in spec["recordFields"] if f not in record}

        if kind == "user" and (record.get(origin["field"]) or {}).get(origin["key"]) == origin["value"]:
            humans += 1

        content = (record.get("message") or {}).get("content")
        target = seen_assistant if kind == "assistant" else seen_user
        if isinstance(content, list):
            target |= {b.get("type") for b in content if isinstance(b, dict)}

if missing_fields:
    problems.append(f"records lack fields we read: {', '.join(sorted(missing_fields))}")
if humans == 0:
    problems.append(
        f"no record with {origin['field']}.{origin['key']} == '{origin['value']}' in "
        f"{len(sample)} transcripts — the human-message discriminator is gone"
    )
if titles == 0:
    notes.append(f"no '{spec['titleRecord']['type']}' record found — chat windows fall back to the folder name")

for label, seen, known in (("assistant", seen_assistant, known_assistant), ("user", seen_user, known_user)):
    new = {b for b in seen if b and b not in known}
    if new:
        notes.append(f"new {label} block types: {', '.join(sorted(new))} — rendered as a placeholder until handled")

print(f"    {len(sample)} transcripts sampled, {humans} human messages found", file=sys.stderr)
for n in notes:
    print(f"    \033[33m→\033[0m {n}", file=sys.stderr)
for p in problems:
    print(f"    {p}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY

# ─────────────────────────────────────────────────────────────────────────────
head_ "VS Code extension"

EXT="$(ls -d "$HOME"/.vscode/extensions/anthropic.claude-code-* 2>/dev/null | tail -1 || true)"
if [ -z "$EXT" ] || [ ! -f "$EXT/extension.js" ]; then
    bad "extension bundle not found under ~/.vscode/extensions/"
else
    python3 - "$SPEC" "$EXT/extension.js" <<'PY' && ok "the /open URI handler still reads session and prompt" || bad "the deep link contract moved"
import json, sys
spec = json.load(open(sys.argv[1]))["extensionPatterns"]
source = open(sys.argv[2], encoding="utf-8", errors="replace").read()
missing = [
    f"{name}: {pattern}"
    for name, pattern in spec.items()
    if not name.startswith("_") and pattern not in source
]
for m in missing:
    print(f"    absent from extension.js — {m}", file=sys.stderr)
sys.exit(1 if missing else 0)
PY
    note "$(basename "$EXT")"

    # Opportunities are checked the other way round: their disappearance is the
    # interesting event, and it never fails the run. Today the extension refuses
    # to apply a prompt to an already-open session; the day it stops refusing,
    # decision N7 is worth reopening.
    python3 - "$SPEC" "$EXT/extension.js" <<'PY'
import json, sys
spec = json.load(open(sys.argv[1])).get("extensionOpportunities", {})
source = open(sys.argv[2], encoding="utf-8", errors="replace").read()
for name, pattern in spec.items():
    if name.startswith("_"):
        continue
    if pattern not in source:
        print(f"    \033[33m→\033[0m {name} is GONE — this may have become possible, see N7")
PY
fi

# ─────────────────────────────────────────────────────────────────────────────
run_probe() {
    # Records a real session's hooks into $1.
    #
    # The environment is scrubbed on purpose. CLAUDE_CODE_ENTRYPOINT is inherited
    # by child processes, so a probe launched from inside a Claude Code session
    # records the PARENT's entrypoint and quietly proves nothing. That mistake
    # produced a recording claiming `claude -p` reports `claude-vscode`.
    local out="$1" prompt="$2" tools="${3:-}"
    local work; work="$(mktemp -d)"

    cat > "$work/capture.sh" <<'CAP'
#!/bin/bash
BODY=$(cat)
printf '%s\t%s\n' "${CLAUDE_CODE_ENTRYPOINT:-<unset>}" "$BODY" >> "$CAPTURE_FILE"
exit 0
CAP
    chmod +x "$work/capture.sh"

    python3 - "$work" <<'PY'
import json, sys
work = sys.argv[1]
events = ["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","Notification",
          "Stop","StopFailure","SessionEnd","SubagentStart","SubagentStop"]
hooks = {e: [{"hooks":[{"type":"command","command":f"{work}/capture.sh","timeout":5}]}]
         for e in events}
json.dump({"hooks": hooks}, open(f"{work}/settings.json","w"))
PY

    : > "$out"
    (
        cd "$work"
        CAPTURE_FILE="$out" env -u CLAUDE_CODE_ENTRYPOINT -u CLAUDECODE \
            claude -p "$prompt" --settings "$work/settings.json" \
            ${tools:+--allowedTools "$tools"} >/dev/null 2>&1 </dev/null
    ) || true
    rm -rf "$work"
}

if [ "$MODE" = "live" ] || [ "$MODE" = "record" ]; then
    head_ "Live probe"
    echo "  running two probe sessions, this takes about a minute…"

    TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
    run_probe "$TMP/plain.jsonl" "Reply with exactly the word: pong"
    run_probe "$TMP/agent.jsonl" \
        "Use the Task tool to launch one general-purpose agent whose entire job is to reply with the word: ok. Then reply: done." \
        "Task"
    cat "$TMP/plain.jsonl" "$TMP/agent.jsonl" > "$TMP/recording.jsonl"

    LINES="$(wc -l < "$TMP/recording.jsonl" | tr -d ' ')"
    if [ "$LINES" = "0" ]; then
        bad "the probe captured nothing — no conclusion can be drawn from this run"
        note "check that `claude` is authenticated and can run non-interactively"
    else
        ok "$LINES hook invocations captured"

        if [ "$MODE" = "record" ]; then
            mkdir -p "$(dirname "$GOLDEN")"
            cp "$TMP/recording.jsonl" "$GOLDEN"
            ok "golden baseline written to Contracts/golden/hooks.jsonl"
        fi

        python3 - "$SPEC" "$TMP/recording.jsonl" <<'PY' && ok "every event carries the fields we read" || bad "the payload contract moved — see above"
import json, sys
spec = json.load(open(sys.argv[1]))
required = spec["events"]
seen, problems = {}, []

for line in open(sys.argv[2]):
    entrypoint, body = line.rstrip("\n").split("\t", 1)
    payload = json.loads(body)
    event = payload.get("hook_event_name")
    seen.setdefault(event, []).append((entrypoint, payload))

for event, fields in required.items():
    if event not in seen:
        problems.append(f"{event}: never fired during the probe")
        continue
    for _, payload in seen[event]:
        missing = [f for f in fields if f not in payload]
        if missing:
            problems.append(f"{event}: missing {', '.join(missing)}")
            break

# The entrypoint is not in the payload — it only exists in the environment, which
# is why the hook script carries it in a header. Verify the value we record as
# non-interactive is the one a headless session really reports.
entrypoints = {e for values in seen.values() for e, _ in values}
excluded = set(spec["nonInteractiveEntrypoints"])
unlisted = entrypoints - excluded
if unlisted:
    problems.append(
        f"headless probe reported entrypoint {sorted(unlisted)}, "
        f"which is NOT in nonInteractiveEntrypoints — those sessions would get a row"
    )

for p in problems:
    print(f"    {p}", file=sys.stderr)
print(f"    events seen: {', '.join(sorted(seen))}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY
    fi
else
    head_ "Live probe"
    note "skipped — run with --live to check the payload shapes against a real session"
    note "the static checks above cannot see a field that changed meaning"
fi

# ─────────────────────────────────────────────────────────────────────────────
printf '\n%s\n' "────────────────────────────────────────────────────────"

if [ "$CHECKS" = "0" ]; then
    echo "✗ no check ran. This run proves nothing."
    exit 1
fi

if [ "$FAILURES" = "0" ]; then
    echo "✓ $CHECKS checks, all passing."
    [ "$MODE" = "static" ] && echo "  (static only — the semantic drift lives behind --live)"
    exit 0
fi

echo "✗ $FAILURES of $CHECKS checks failed."
echo
echo "  Each failure above names an assumption. Contracts/assumptions.md says"
echo "  where the code depends on it and what breaks when it goes away."
exit 1
