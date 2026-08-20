#!/bin/bash
#
# Runs both suites.
#
# There are two because they cover different things: the first verifies pure
# functions and is instantaneous, the second launches the real binary and talks
# to it over HTTP. The second one is needed because this project's worst defects
# all hid in the seams, where domain tests don't reach.
#
# Neither of them touches ~/.claude, the preferences or the system permissions:
# the end-to-end run uses a temporary home that it deletes at the end.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# A dedicated port: never the default one, or a test session would collide with
# the panel you have open.
PORT="${CLAWD_LIGHT_TEST_PORT:-9899}"

echo "▸ Building…"
swift build

echo
echo "▸ Domain tests"
swift run ClawdLightTests "$@"

echo
echo "▸ End-to-end tests (port $PORT)"
.build/debug/ClawdLightE2E --port "$PORT" "$@"

# Third, because documentation that states figures is documentation that can be
# wrong, and nothing else in this repository would ever notice. Twenty-one of the
# forty-seven figures in the code map had drifted before this ran for the first
# time. Cheap, offline, and it has no opinion about the prose.
echo
echo "▸ Documentation"
"$ROOT/Scripts/check-docs.sh"
