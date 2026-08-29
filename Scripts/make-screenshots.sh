#!/bin/bash
# Takes the images the README shows, from the real app, against a fake home.
#
#     ./Scripts/make-screenshots.sh            # docs/images/*.png
#     ./Scripts/make-screenshots.sh --keep     # leave the fake home for poking at
#
# Why a script and not a person with ⌘⇧4. Three reasons, in order of how much
# they cost when ignored.
#
# **The names.** A screenshot of the panel on a working machine is a list of that
# person's projects. `Scripts/check-docs.sh` has a gate that refuses a real home
# directory anywhere in the tree, and it is right to: the picture at the top of a
# public README is the least private thing in a repository. Every row here is
# invented, and lives under a temporary `LAMPBOARD_HOME`.
#
# **The states.** A hand-taken shot shows whatever the machine happened to be
# doing. The panel has six states and three ring conditions, and the one worth
# photographing — six different colours at once — has never once happened by
# accident. They are set here, deliberately, by posting the signals.
#
# **It works with the screen locked.** `screencapture -l <window>` asks the window
# server for that window's backing store, which is drawn whether or not anybody
# is looking. A full-screen capture on a locked Mac returns the lock screen; this
# returns the panel. Measured, because the opposite was assumed for a while.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/images"
APP="$ROOT/dist/LampBoard.app"
BIN="$APP/Contents/MacOS/lampboard"
PORT=9899                       # not 9877: never disturb the panel actually in use
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

[ -x "$BIN" ] || { echo "Build it first:  ./Scripts/build-app.sh"; exit 1; }

HOME_DIR="$(mktemp -d /tmp/lampboard-shots.XXXXXX)"
mkdir -p "$HOME_DIR/.claude/ide" "$HOME_DIR/.claude/sessions" "$HOME_DIR/.codex/sessions"
mkdir -p "$OUT"

HOLDERS=()
cleanup() {
    for pid in "${HOLDERS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
    pkill -f "LAMPBOARD_HOME=$HOME_DIR" 2>/dev/null || true
    kill "${APP_PID:-0}" 2>/dev/null || true
    [ "$KEEP" = "1" ] && echo "  fake home kept at $HOME_DIR" || rm -rf "$HOME_DIR"
}
trap cleanup EXIT

# The rows. Six projects, six states, and names that belong to nobody.
#   folder | session id | state | model | tokens | window
ROWS=(
  "checkout-api|s-await|awaiting|claude-opus-5|412000|1000000"
  "billing-worker|s-ready|ready|claude-sonnet-5|188000|1000000"
  "search-index|s-work|working|claude-haiku-4-5|61000|200000"
  "mobile-client|s-wait|waiting|claude-opus-5|733000|1000000"
  "legacy-import|s-fail|failed|claude-sonnet-5|95000|1000000"
  "docs-site|s-idle|idle|gpt-5.6-sol|17002|258400"
)

echo "▸ A fake home at $HOME_DIR"
LOCK_PORT=41000
for row in "${ROWS[@]}"; do
    IFS='|' read -r folder session _ _ _ _ <<< "$row"
    mkdir -p "$HOME_DIR/work/$folder"

    # One editor window per project, so the workspace resolves and the row exists.
    printf '{"pid":%d,"workspaceFolders":["%s"],"ideName":"Visual Studio Code","transport":"ws"}' \
        "$$" "$HOME_DIR/work/$folder" > "$HOME_DIR/.claude/ide/$LOCK_PORT.lock"
    LOCK_PORT=$((LOCK_PORT + 1))

    # A live process per session: the five-second sweep keeps only rows whose pid
    # answers `kill(pid, 0)`, so each one needs a body. `sleep` is the cheapest.
    sleep 600 &
    holder=$!
    HOLDERS+=("$holder")
    printf '{"pid":%d,"sessionId":"%s","cwd":"%s","entrypoint":"claude-vscode","kind":"interactive"}' \
        "$holder" "$session" "$HOME_DIR/work/$folder" > "$HOME_DIR/.claude/sessions/$holder.json"

    # The transcript, and it is not optional: the ring is the thing this picture
    # is for, and without a token count every row draws the dashed circle that
    # means "nothing read yet". Claude Code's shape is a record whose
    # `message.usage` the reader sums; Codex's is a `token_count` payload that
    # carries its own window.
    IFS='|' read -r _ _ _ model tokens window <<< "$row"
    # The same transformation `TranscriptLocator.directoryName` applies: **every**
    # non-alphanumeric character becomes a dash, dots included. Replacing only the
    # slashes leaves the dot in `mktemp`'s name, the path does not match, and every
    # ring draws dashed — which looks like a missing feature rather than a wrong path.
    proj="$(printf '%s' "$HOME_DIR/work/$folder" | sed 's/[^a-zA-Z0-9]/-/g')"
    if [ "$model" = "${model#gpt}" ]; then
        mkdir -p "$HOME_DIR/.claude/projects/$proj"
        printf '{"timestamp":"%s","type":"assistant","message":{"model":"%s","usage":{"input_tokens":%d,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":900}}}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" "$model" "$tokens" \
            > "$HOME_DIR/.claude/projects/$proj/$session.jsonl"
    else
        mkdir -p "$HOME_DIR/.codex/sessions/2026/01/01"
        printf '{"timestamp":"%s","type":"turn_context","payload":{"turn_id":"t1","model":"%s"}}\n{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":%d},"model_context_window":%d}}}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" "$model" \
            "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" "$tokens" "$window" \
            > "$HOME_DIR/.codex/sessions/2026/01/01/rollout-$session.jsonl"
    fi
done

echo "▸ Starting the panel on port $PORT"
env LAMPBOARD_HOME="$HOME_DIR" "$BIN" --port "$PORT" --skip-setup-prompt &
APP_PID=$!
for _ in $(seq 1 40); do
    curl -sf --max-time 1 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
    sleep 0.25
done

signal() {  # signal <session> <event> [extra json]
    local body="{\"session_id\":\"$1\",\"hook_event_name\":\"$2\",\"cwd\":\"$3\"${4:+,$4}}"
    curl -s -o /dev/null --max-time 2 -X POST -H 'Content-Type: application/json' \
        ${5:+-H "X-LampBoard-Harness: $5"} --data-binary "$body" \
        "http://127.0.0.1:$PORT/signal"
}

echo "▸ Setting the six states"
for row in "${ROWS[@]}"; do
    IFS='|' read -r folder session state model tokens window <<< "$row"
    cwd="$HOME_DIR/work/$folder"
    harness=""; [ "$model" = "${model#gpt}" ] || harness="codex"

    case "$state" in
        awaiting) signal "$session" UserPromptSubmit "$cwd"
                  signal "$session" Notification "$cwd" '"notification_type":"permission_prompt"' ;;
        ready)    signal "$session" UserPromptSubmit "$cwd"
                  signal "$session" Stop "$cwd" '"last_assistant_message":"Rewrote the retry policy."' ;;
        working)  signal "$session" UserPromptSubmit "$cwd" ;;
        waiting)  signal "$session" UserPromptSubmit "$cwd"
                  signal "$session" SubagentStart "$cwd" '"agent_id":"a1"'
                  signal "$session" Stop "$cwd" '"background_tasks":[{"type":"monitor","status":"running"}]' ;;
        failed)   signal "$session" UserPromptSubmit "$cwd"
                  signal "$session" StopFailure "$cwd" '"reason":"rate_limit"' ;;
        idle)     # Codex files its rollouts by date, so there is nothing to derive
                  # from a session id and a folder: the path comes from the hook,
                  # exactly as it does in the real thing.
                  if [ -n "$harness" ]; then
                      roll="$HOME_DIR/.codex/sessions/2026/01/01/rollout-$session.jsonl"
                      signal "$session" SessionStart "$cwd" "\"transcript_path\":\"$roll\"" "$harness"
                  else
                      signal "$session" SessionStart "$cwd"
                  fi ;;
    esac
done

sleep 2

# The panel is a borderless NSPanel belonging to an accessory app, so it is
# absent from `.optionOnScreenOnly` — the list most examples reach for. `.optionAll`
# finds it. Run through the Swift interpreter rather than compiled: there is
# nothing here worth a build product, and Command Line Tools is enough.
find_panel_window() {   # find_panel_window <pid>
    /usr/bin/env swift - "$1" <<'SWIFT'
import CoreGraphics
import Foundation

// **By pid, never by name.** The person running this almost certainly has their
// own panel open, full of their own project names, and matching on the owner's
// name would photograph that one instead — putting exactly the thing this script
// exists to avoid into a public README, silently, and looking right.
guard let wanted = CommandLine.arguments.dropFirst().first.flatMap(Int.init) else { exit(1) }

// A borderless NSPanel owned by an accessory app is absent from
// `.optionOnScreenOnly`, the list most examples reach for. `.optionAll` finds it.
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == wanted }

// The widest: the column itself, never a tooltip or the legend that may be up.
let widest = mine.max {
    let a = ($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0
    let b = ($1[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0
    return a < b
}
if let id = widest?[kCGWindowNumber as String] as? Int { print(id) }
SWIFT
}

echo "▸ Capturing"
WINDOW_ID="$(find_panel_window "$APP_PID" 2>/dev/null | tail -1)"
if [ -z "$WINDOW_ID" ]; then
    echo "  No window for pid $APP_PID. Did the panel start?"
    exit 1
fi
# Amber blinks, so a single frame catches it dark half the time — and a picture
# of the panel with its most important state switched off is worse than no
# picture. Six frames, keep the brightest: the one where everything that can be
# lit is lit.
BEST=""; BEST_SUM=-1
for frame in $(seq 1 6); do
    screencapture -x -o -l "$WINDOW_ID" "$HOME_DIR/frame-$frame.png" 2>/dev/null || continue
    sum=$(/usr/bin/env python3 -c "
from PIL import Image, ImageStat
import sys
try: print(int(ImageStat.Stat(Image.open(sys.argv[1]).convert('L')).sum[0]))
except Exception: print(-1)" "$HOME_DIR/frame-$frame.png" 2>/dev/null || echo -1)
    if [ "$sum" -gt "$BEST_SUM" ]; then BEST_SUM=$sum; BEST="$HOME_DIR/frame-$frame.png"; fi
    sleep 0.35
done
[ -n "$BEST" ] || { echo "  No frame captured."; exit 1; }
cp "$BEST" "$OUT/panel.png"
echo "  ✓ $OUT/panel.png  (brightest of six frames)"

echo
echo "The images are regenerated, never edited. If one looks wrong, the panel is"
echo "wrong: fix the panel and run this again."
