#!/bin/bash
#
# Breaks this repository on purpose, and fails if the checks do not notice.
#
# WHY THIS EXISTS
# A check nobody has ever seen fail is not a check. `Scripts/check-docs.sh` had
# eight of them and one had never, in its whole life, examined a single file: the
# guard against leaking a real home directory into a public repository was
# written with a regular-expression lookahead that `/usr/bin/grep -E` rejects, so
# every run swallowed the error and printed a tick. It was green for weeks, and
# there was a real name in `Contracts/golden/hooks.jsonl` the whole time.
#
# Nothing about that failure was visible from the outside. The only way to tell a
# working guard from a broken one is to commit the violation it claims to catch
# and watch what happens. That is what this script does, once per guard.
#
# HOW IT WORKS
# Every attack copies the files it is about to damage, applies a mutation, runs
# the real gate, and restores what it touched — pass or fail, including on
# Ctrl-C. Three things have to hold for a bite to count:
#
#   1. the mutation actually changed something. A mutation that no longer applies
#      is a bite that quietly stopped testing anything, so it is a failure here;
#   2. the gate exited non-zero;
#   3. it said why, in the words this attack expects. "Something went red" is not
#      a proof — the gate could have tripped over an unrelated problem.
#
# WHAT IT DOES NOT DO
# It does not commit, push, or fix anything, and it refuses to leave the tree
# modified. If it is interrupted at the wrong moment, `git status` is the check.
#
# USAGE
#   ./Scripts/bite.sh            everything
#   ./Scripts/bite.sh --docs     only the documentation gates (a few seconds)
#   ./Scripts/bite.sh --swift    only the test instrument (needs a build)

set -uo pipefail   # deliberately not -e: half of what runs here is meant to fail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WHAT="${1:-all}"
WORK="$(mktemp -d)"
PROTECTED=()

# What the tree looked like before any damage. Compared again at the end: this
# script must give back exactly what it borrowed.
TREE_BEFORE="$(git status --porcelain)"

BITES=0
BLUNT=0

bit()   { BITES=$((BITES+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
blunt() { BLUNT=$((BLUNT+1)); printf '  \033[31m✗\033[0m %s\n' "$1"
          printf '      \033[31m%s\033[0m\n' "$2"; }

# A gate in check-docs.sh. The titles have to match its `head_` lines exactly:
# check-docs.sh compares the two lists and reports any gate with no bite, so a
# rule cannot be added here or there without the other noticing.
gate()    { printf '\n\033[1m%s\033[0m\n' "$1"; }
# Everything that is proven here but is not a documentation gate.
chapter() { printf '\n\033[1m%s\033[0m\n' "$1"; }

protect() {
    PROTECTED=("$@")
    local file
    for file in "$@"; do
        mkdir -p "$WORK/$(dirname "$file")"
        cp "$file" "$WORK/$file"
    done
}

restore() {
    local file
    for file in ${PROTECTED[@]+"${PROTECTED[@]}"}; do
        [ -f "$WORK/$file" ] && cp "$WORK/$file" "$file"
    done
    PROTECTED=()
}

trap 'restore; rm -rf "$WORK"' EXIT INT TERM

# What the protected files look like right now, so that a mutation which no
# longer applies is caught instead of silently proving nothing.
fingerprint() {
    local file
    for file in ${PROTECTED[@]+"${PROTECTED[@]}"}; do
        shasum "$file" 2>/dev/null || echo "absent $file"
    done | shasum | cut -d' ' -f1
}

# Applies the mutation on stdin, runs the gate, and demands it turns red for the
# stated reason.
#   attack <description> <expected fragment of the gate's output>
attack() {
    local description="$1" expected="$2"
    local before after status log="$WORK/gate.log"

    before="$(fingerprint)"
    if ! python3 - ; then
        blunt "$description" "the mutation itself failed to run"
        restore
        return
    fi
    after="$(fingerprint)"

    if [ "$before" = "$after" ]; then
        blunt "$description" "the mutation no longer applies — this bite is stale, and has been proving nothing"
        restore
        return
    fi

    ./Scripts/check-docs.sh > "$log" 2>&1
    status=$?
    restore

    if [ "$status" -eq 0 ]; then
        blunt "$description" "check-docs.sh stayed green with the violation in place"
    elif ! grep -Fq -- "$expected" "$log"; then
        blunt "$description" "it went red, but never said “${expected}” — it tripped over something else"
    else
        bit "$description"
    fi
}

# The same, for a mutation to the Swift sources: builds, runs the domain suite,
# and demands a specific exit code.
#   attack_swift <description> <expected fragment> <expected exit code>
attack_swift() {
    local description="$1" expected="$2" wanted="$3"
    local before after status log="$WORK/suite.log"

    before="$(fingerprint)"
    if ! python3 - ; then
        blunt "$description" "the mutation itself failed to run"
        restore
        return
    fi
    after="$(fingerprint)"

    if [ "$before" = "$after" ]; then
        blunt "$description" "the mutation no longer applies — this bite is stale"
        restore
        return
    fi

    if ! swift build > "$WORK/build.log" 2>&1; then
        blunt "$description" "the mutation does not compile, so it proves nothing"
        restore
        return
    fi

    .build/debug/ClawdLightTests > "$log" 2>&1
    status=$?
    restore

    if [ "$status" -ne "$wanted" ]; then
        blunt "$description" "the suite exited $status, expected $wanted"
    elif ! grep -Fq -- "$expected" "$log"; then
        blunt "$description" "it exited $status, but never said “${expected}”"
    else
        bit "$description"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
if [ "$WHAT" = "all" ] || [ "$WHAT" = "--docs" ]; then

gate "Figures in the code map"

protect docs/05-code-map.md
attack "a per-target line count that drifted" "says 9,999 lines" <<'PY'
import re
p = "docs/05-code-map.md"
# Whatever the number is today. A mutation that names it would need editing
# every time the figure legitimately moves, and a bite nobody maintains is a
# bite that quietly stops proving anything.
s = re.sub(r"(ClawdLightCore/\s+)[\d,]+( lines)", r"\g<1>9,999\g<2>", open(p).read(), count=1)
open(p, "w").write(s)
PY

protect docs/05-code-map.md
attack "the table reworded so the search matches nothing" "expected at least 5 per-target rows" <<'PY'
p = "docs/05-code-map.md"
s = open(p).read().replace(" lines · ", " lines, ")
open(p, "w").write(s)
PY

gate "Links between documents"

protect README.md
attack "a link that points nowhere" "no such file" <<'PY'
p = "README.md"
s = open(p).read().replace("(docs/07-traps.md)", "(docs/07-trapdoors.md)")
open(p, "w").write(s)
PY

protect Contracts/assumptions.md
attack "a guarded document that quietly disappeared" "no longer exists" <<'PY'
import os
os.remove("Contracts/assumptions.md")
PY

gate "Figures stated outside the code map"

protect README.md
attack "a test count that drifted outside the code map" "says 999 cases" <<'PY'
import re
p = "README.md"
s = re.sub(r"\d+ domain tests", "999 domain tests", open(p).read(), count=1)
open(p, "w").write(s)
PY

protect README.md
attack "the sentence reworded so the count is no longer stated" "expected 1 statement(s)" <<'PY'
import re
p = "README.md"
s = re.sub(r"\d+ domain tests", "the full domain suite", open(p).read())
open(p, "w").write(s)
PY

gate "The status table says how the project stands now"

protect WORKLOG.md
attack "a figure in the status table that no longer holds" "the table says 242 domain tests" <<'PY'
import re
p = "WORKLOG.md"
s = re.sub(r"(\| Domain tests \| \*\*)\d+", r"\g<1>242", open(p).read(), count=1)
open(p, "w").write(s)
PY

protect WORKLOG.md
attack "the status table renamed out of reach" "no status table any more" <<'PY'
p = "WORKLOG.md"
s = open(p).read().replace("## How the project stands now", "## Where things stand")
open(p, "w").write(s)
PY

gate "No personal paths or private addresses in tracked files"

protect docs/07-traps.md
attack "a real home directory committed to the tree" "notarealperson" <<'PY'
p = "docs/07-traps.md"
# Assembled rather than written out: this file is scanned by the very guard it
# is testing, and the alternative — an exemption for it — is exactly the kind of
# list that grows quietly until it is hiding a real leak.
planted = "/Users/" + "notarealperson/Development/thing"
s = open(p).read() + f"\n<!-- planted by bite.sh: {planted} -->\n"
open(p, "w").write(s)
PY

protect docs/07-traps.md
attack "a private VPN address committed to the tree" "101.5.7" <<'PY'
p = "docs/07-traps.md"
planted = "100." + "101.5.7"
s = open(p).read() + f"\n<!-- planted by bite.sh: {planted} -->\n"
open(p, "w").write(s)
PY

# The one that matters most: not "does the guard catch a violation", but "does
# the guard notice that it has stopped being able to catch anything". This is
# exactly how it failed for real, and no amount of planting fake leaks would
# have found it.
protect Scripts/check-docs.sh
attack "the guard blinded, and announcing it" "THE GUARD ITSELF IS BROKEN" <<'PY'
p = "Scripts/check-docs.sh"
s = open(p).read().replace(
    'HOME = re.compile(r"/(?:Users|home)/([A-Za-z0-9][A-Za-z0-9._-]*)")',
    'HOME = re.compile(r"/(?:Users|home)/(nobody-is-called-this)")',
)
open(p, "w").write(s)
PY

gate "The contract knows which events we register"

protect Contracts/required-fields.json
attack "an event the code registers and the contract forgot" "absent from the spec" <<'PY'
p = "Contracts/required-fields.json"
s = open(p).read().replace('"PostToolUse"', '"PostToolUsage"')
open(p, "w").write(s)
PY

protect docs/02-claude-code.md
attack "prose left behind on the old count" 'events", there are' <<'PY'
import re
p = "docs/02-claude-code.md"
text = open(p).read()
spelled = re.search(r"The (\w+) events clawd-light registers", text).group(1)
# Any word but the right one; which wrong word it is does not matter.
wrong = "eight" if spelled != "eight" else "seven"
s = text.replace(f"The {spelled} events clawd-light registers", f"The {wrong} events clawd-light registers")
open(p, "w").write(s)
PY

protect docs/02-claude-code.md docs/05-code-map.md
attack "every statement of the count reworded away" "no document states how many events are registered" <<'PY'
for p, old, new in [
    ("docs/02-claude-code.md", "events clawd-light registers", "hook events wired up here"),
    ("docs/05-code-map.md", "events registered by default", "hooks wired up by default"),
]:
    s = open(p).read().replace(old, new)
    open(p, "w").write(s)
PY

gate "Test suites are registered"

protect Sources/ClawdLightTests/main.swift
attack "a suite that exists and is never run" "is defined but never registered" <<'PY'
p = "Sources/ClawdLightTests/main.swift"
s = open(p).read().replace("    PathNormalizerSuite.suite,\n", "")
open(p, "w").write(s)
PY

gate "Every gate here can be shown to bite"

protect Scripts/check-docs.sh
attack "a gate added without anything that proves it works" "has no mutation in bite.sh" <<'PY'
p = "Scripts/check-docs.sh"
s = open(p).read().replace(
    'printf \'\\n%s\\n\' "────',
    'head_ "A gate nobody has ever proven"\nprintf \'\\n%s\\n\' "────',
    1,
)
open(p, "w").write(s)
PY

fi

# ═════════════════════════════════════════════════════════════════════════════
if [ "$WHAT" = "all" ] || [ "$WHAT" = "--swift" ]; then

chapter "The test instrument"

# The attack that worked. Neutralising one guard clause in the assertion library
# made 497 tests report success while verifying nothing at all — and there was
# nothing in the project that would have said so.
protect Sources/TestKit/Assertions.swift
attack_swift "an assertion that has stopped asserting" "THE INSTRUMENT IS BLUNT" 70 <<'PY'
p = "Sources/TestKit/Assertions.swift"
s = open(p).read().replace(
    "        guard !condition else { return }\n",
    "        if true { return }\n        guard !condition else { return }\n",
    1,
)
open(p, "w").write(s)
PY

protect Sources/TestKit/Assertions.swift
attack_swift "a collector that quietly drops what it is given" "THE INSTRUMENT IS BLUNT" 70 <<'PY'
p = "Sources/TestKit/Assertions.swift"
s = open(p).read().replace(
    '        collected.append("\\(name):\\(line) — \\(message)")',
    "        _ = (name, line, message)",
    1,
)
open(p, "w").write(s)
PY

protect Sources/TestKit/TestRunner.swift
attack_swift "a failing run that still exits zero" "a failing run still exits zero" 70 <<'PY'
p = "Sources/TestKit/TestRunner.swift"
s = open(p).read().replace(
    "        return report.allPassed ? 0 : 1",
    "        return 0",
    1,
)
open(p, "w").write(s)
PY

chapter "A real defect reaches the exit code"

# The whole chain, once, end to end: break a rule the domain tests cover and the
# process must exit 1 — not print a complaint and exit 0, which is how a suite
# ends up running in CI for a year without ever being able to fail it.
protect Sources/ClawdLightCore/Update/ReleaseVersion.swift
attack_swift "a broken comparison the suite catches" "0.10.0" 1 <<'PY'
p = "Sources/ClawdLightCore/Update/ReleaseVersion.swift"
s = open(p).read().replace(
    "        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)",
    "        (lhs.major, lhs.minor, lhs.patch) > (rhs.major, rhs.minor, rhs.patch)",
    1,
)
open(p, "w").write(s)
PY

# Whatever happened above, the binaries must match the sources again.
swift build > /dev/null 2>&1

fi

# ═════════════════════════════════════════════════════════════════════════════
printf '\n%s\n' "────────────────────────────────────────────────────────"
if [ "$(git status --porcelain)" != "$TREE_BEFORE" ]; then
    printf '\033[33m⚠\033[0m the tree is not how this script found it — run `git status` before trusting anything below.\n'
fi

if [ "$BLUNT" -eq 0 ]; then
    printf '\033[32m✓\033[0m %d violations committed, %d caught.\n' "$BITES" "$BITES"
    exit 0
else
    printf '\033[31m✗\033[0m %d of %d guards did not notice the violation they exist for.\n\n' \
        "$BLUNT" "$((BITES + BLUNT))"
    printf '  A guard that cannot be shown to fail is indistinguishable from no guard.\n'
    exit 1
fi
