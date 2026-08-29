#!/bin/bash
#
# Checks that the documentation still describes this repository.
#
# WHY THIS EXISTS
# `docs/05-code-map.md` states figures — lines per target, lines per file, the
# longest file, how many test cases there are — and every one of them was written
# by hand and never checked again. Twenty-one of forty-seven were stale before this
# script existed, some by fifty per cent.
#
# That is the same criticism this project levelled at tmux: a hand-maintained table
# describing something that moves, with no test that any of it is still true. The
# answer there and here is the same one — if a document makes a claim a script can
# verify, a script should verify it.
#
# WHAT IT DOES NOT DO
# It does not rewrite the documentation. A number that drifted is usually a sign
# that the prose around it drifted too, and only a person can tell whether the file
# grew because it gained a responsibility or because it gained six lines.
#
# USAGE
#   ./Scripts/check-docs.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CHECKS=0
FAILURES=0
ok()   { CHECKS=$((CHECKS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { CHECKS=$((CHECKS+1)); FAILURES=$((FAILURES+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
note() { printf '    %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

MAP="docs/05-code-map.md"
[ -f "$MAP" ] || { echo "missing $MAP"; exit 2; }

# ─────────────────────────────────────────────────────────────────────────────
head_ "Figures in the code map"

python3 - "$MAP" <<'PY' && ok "every stated figure matches the repository" || bad "the code map states figures that are no longer true"
import glob, os, re, sys

doc = open(sys.argv[1]).read()
problems = []

def lines_of(path):
    with open(path) as handle:
        return sum(1 for _ in handle)

swift = {os.path.basename(p): p for p in glob.glob("Sources/**/*.swift", recursive=True)}

# Per-target totals: "  ClawdLightCore/    4,087 lines · 36 files"
for target, claimed_lines, claimed_files in re.findall(
    r'^\s+(\w+)/\s+([\d,]+) lines · \s*(\d+) files', doc, re.M
):
    paths = glob.glob(f"Sources/{target}/**/*.swift", recursive=True)
    if not paths:
        problems.append(f"{target}/ is described but no longer exists")
        continue
    actual_lines = sum(lines_of(p) for p in paths)
    if actual_lines != int(claimed_lines.replace(",", "")):
        problems.append(
            f"{target}/ says {claimed_lines} lines, has {actual_lines:,}"
        )
    if len(paths) != int(claimed_files):
        problems.append(
            f"{target}/ says {claimed_files} files, has {len(paths)}"
        )

# The self-imposed ceiling: "No file exceeds 590 lines. The limit … is 800."
ceiling = re.search(r'No file exceeds (\d+) lines\. The limit .*? is (\d+)', doc)
if not ceiling:
    problems.append("the sentence stating the longest file and the limit is gone")
else:
    stated, limit = int(ceiling.group(1)), int(ceiling.group(2))
    longest = max(swift.values(), key=lines_of)
    actual = lines_of(longest)
    if actual > limit:
        problems.append(
            f"{longest} is {actual} lines, over the project's own limit of {limit}"
        )
    elif actual != stated:
        problems.append(
            f'"no file exceeds {stated}" — {os.path.basename(longest)} is {actual}'
        )

# Test-case counts, stated next to the target they belong to.
for target, claimed in re.findall(r'(ClawdLight(?:Tests|E2E))/.*?(\d+) cases', doc):
    actual = sum(
        open(p).read().count("TestCase(")
        for p in glob.glob(f"Sources/{target}/**/*.swift", recursive=True)
    )
    if actual != int(claimed):
        problems.append(f"{target}/ says {claimed} cases, has {actual}")

# Per-file sizes, from headings "### `X.swift` · 220" and table rows.
for name, claimed in re.findall(r'`([A-Za-z0-9_]+\.swift)`\s*(?:·|\|)\s*(\d+)', doc):
    path = swift.get(name)
    if path is None:
        problems.append(f"{name} is documented but no longer in Sources/")
        continue
    actual = lines_of(path)
    # Rounded on purpose in the prose; only real drift is worth a report.
    if abs(actual - int(claimed)) > max(15, int(claimed) * 0.12):
        problems.append(f"{name} says {claimed} lines, has {actual}")

for p in problems:
    print(f"    {p}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY

# ─────────────────────────────────────────────────────────────────────────────
head_ "Links between documents"

python3 - <<'PY' && ok "every relative link resolves" || bad "the documentation links somewhere that is not there"
import glob, os, re, sys


def anchors_of(path):
    """GitHub's slug for every heading in a Markdown file."""
    slugs = set()
    for line in open(path):
        if not line.startswith("#"):
            continue
        text = line.lstrip("#").strip()
        slug = re.sub(r"[^\w\- ]", "", text.lower()).replace(" ", "-")
        slugs.add(slug)
    return slugs


FILES = glob.glob("docs/*.md") + ["Contracts/assumptions.md", "README.md"]
cache = {}
problems = []
total = 0

for f in FILES:
    if not os.path.exists(f):
        continue
    base = os.path.dirname(f)
    for match in re.finditer(r'\[[^\]]*\]\(([^)]+)\)', open(f).read()):
        target = match.group(1)
        if target.startswith(("http", "mailto")):
            continue
        total += 1
        path, _, anchor = target.partition("#")
        resolved = os.path.normpath(os.path.join(base, path)) if path else f
        if not os.path.exists(resolved):
            problems.append(f"{f} -> {target} (no such file)")
            continue
        # A #Lnn line reference points into source, not a heading.
        if not anchor or re.fullmatch(r"L\d+(-L\d+)?", anchor):
            continue
        if not resolved.endswith(".md"):
            continue
        if resolved not in cache:
            cache[resolved] = anchors_of(resolved)
        if anchor not in cache[resolved]:
            problems.append(f"{f} -> {target} (no such heading)")

print(f"    {total} links checked, anchors included", file=sys.stderr)
for problem in problems:
    print(f"    broken: {problem}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY

# ─────────────────────────────────────────────────────────────────────────────
head_ "Figures stated outside the code map"

# The code map was checked; README, 01-architecture and 06-working-here were not,
# and all three announced 242 domain tests when there were 416. A checker that
# looks in one place is a checker with one blind spot per other place.
python3 - <<'FIGPY' && ok "test counts and the longest-file figure agree everywhere they are stated" || bad "a document outside the code map states a stale figure"
import glob, re, sys
def lines_of(p):
    with open(p) as h: return sum(1 for _ in h)
def cases(target):
    return sum(open(p).read().count("TestCase(") for p in glob.glob(f"Sources/{target}/**/*.swift", recursive=True))
domain, e2e = cases("ClawdLightTests"), cases("ClawdLightE2E")
longest = max(lines_of(p) for p in glob.glob("Sources/**/*.swift", recursive=True))
total = sum(lines_of(p) for p in glob.glob("Sources/**/*.swift", recursive=True))
problems = []
for f in ["README.md", "docs/01-architecture.md", "docs/06-working-here.md", "docs/05-code-map.md"]:
    text = open(f).read()
    for n in set(re.findall(r"(\d+) (?:cases|domain tests)", text)):
        if int(n) not in (domain, e2e):
            problems.append(f"{f} says {n} cases; the suites have {domain} and {e2e}")
    for n in set(re.findall(r"(\d+) end-to-end tests", text)):
        if int(n) != e2e: problems.append(f"{f} says {n} end-to-end tests, there are {e2e}")
    for n in re.findall(r"longest today is (\d+)", text):
        if int(n) != longest: problems.append(f"{f} says the longest file is {n} lines, it is {longest}")
    for n in re.findall(r"~([\d,]+) lines of Swift", text):
        n = int(n.replace(",", ""))
        if abs(n - total) > 300: problems.append(f"{f} says ~{n:,} lines of Swift, the total is {total:,}")
for p in problems: print(f"    {p}", file=sys.stderr)
sys.exit(1 if problems else 0)
FIGPY

head_ "The status table says how the project stands now"

# WORKLOG.md was outside every check above, because it reads like a diary and
# nobody thought to include one. Inside it sits a table titled "How the project
# stands now", and it announced 242 domain tests, 66 end-to-end and a longest
# file of 407 lines while the truth was 497, 82 and 786 — plus a build declared
# free of warnings that had twenty-eight. Found by a semantic audit, not by this
# script, which is exactly what a blind spot is.
#
# Scoped to that one table on purpose. The rest of the file is history, and the
# figures in an entry from August are *correct* precisely because they are old:
# a rule demanding they be current would fire on every past entry, and a noisy
# gate stops being read.
python3 - <<'STATUSPY' && ok "the status table agrees with the repository" || bad "the status table describes a project that has moved"
import glob, re, sys

def lines_of(path):
    with open(path) as handle: return sum(1 for _ in handle)

def cases(target):
    return sum(open(p).read().count("TestCase(")
               for p in glob.glob(f"Sources/{target}/**/*.swift", recursive=True))

text = open("WORKLOG.md").read()
start = text.find("## How the project stands now")
if start < 0:
    print("    WORKLOG.md has no status table any more", file=sys.stderr)
    sys.exit(1)
# Only as far as the next heading: everything after it is the diary.
end = text.find("\n## ", start + 1)
table = text[start:end if end > 0 else len(text)]

domain, e2e = cases("ClawdLightTests"), cases("ClawdLightE2E")
longest = max(lines_of(p) for p in glob.glob("Sources/**/*.swift", recursive=True))

problems = []
for claimed, actual, label in [
    (re.search(r"Domain tests \| \*\*(\d+)\*\*", table), domain, "domain tests"),
    (re.search(r"End-to-end tests \| \*\*(\d+)\*\*", table), e2e, "end-to-end tests"),
    (re.search(r"Longest file \| (\d+) lines", table), longest, "longest file"),
]:
    if claimed is None:
        problems.append(f"the table no longer states the {label}")
    elif int(claimed.group(1)) != actual:
        problems.append(f"the table says {claimed.group(1)} {label}, the repository has {actual}")

for problem in problems: print(f"    {problem}", file=sys.stderr)
sys.exit(1 if problems else 0)
STATUSPY

head_ "No personal paths or private addresses in tracked files"

# Generic on purpose: the guard must not contain the very strings it guards
# against. Fixture homes are /Users/dev, /Users/you, /Users/sam, /Users/me and
# /home/dev; anything else under /Users or /home is somebody's real machine.
# 100.64.0.0/10 is the range VPN meshes hand out — a real box, not an example.
LEAKS=$(git ls-files -z | xargs -0 grep -nIE '(/Users/(?!dev|you|sam|me)[a-z]+|/home/(?!dev)[a-z]+|\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+|[a-z]+@[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)' 2>/dev/null | grep -v "^Scripts/check-docs.sh" || true)
if [ -z "$LEAKS" ]; then
    ok "no real home directory or private VPN address in the tree"
else
    bad "a tracked file carries what looks like a real path or address:"
    echo "$LEAKS" | head -8 | sed 's/^/    /'
fi

head_ "The contract knows which events we register"

# The one that got away. Everything was committed, 416 tests and 11 checks were
# green, and two documents still said eight registered events after PostToolUse
# made nine. Nothing looked, because the contract check verifies the inventory
# against Claude Code's binary — whether an event EXISTS — and never against what
# this app actually asks for.
python3 - <<'EVPY' && ok "the spec's registered list matches HookConfigMerger" || bad "the contract and the code disagree about what is registered"
import json, re, sys

spec = json.load(open("Contracts/required-fields.json"))["hookEventInventory"]
source = open("Sources/ClawdLightCore/Setup/HookConfigMerger.swift").read()
match = re.search(r"defaultEvents = \[(.*?)\n    \]", source, re.S)
if match is None:
    print("    could not find defaultEvents in HookConfigMerger.swift", file=sys.stderr)
    sys.exit(1)

code = set(re.findall(r'"([A-Za-z]+)"', match.group(1)))
declared = set(spec["registered"])
problems = []
for missing in sorted(code - declared):
    problems.append(f"{missing} is registered by the code and absent from the spec")
for extra in sorted(declared - code):
    problems.append(f"{extra} is in the spec's registered list and not in the code")

# And it must not be in two classes at once: the moment an event is registered it
# stops being "decoded but not registered", and that sentence is somewhere in prose.
for both in sorted(code & set(spec["decodedButNotRegistered"]["events"])):
    problems.append(f"{both} is both registered and listed as not registered")

print(f"    {len(code)} events registered by the code", file=sys.stderr)
for problem in problems:
    print(f"    {problem}", file=sys.stderr)
sys.exit(1 if problems else 0)
EVPY

# Prose is not machine-checkable, but a stale COUNT in a heading is.
COUNT=$(python3 -c "
import json;print(len(json.load(open('Contracts/required-fields.json'))['hookEventInventory']['registered']))")
WORDS="zero one two three four five six seven eight nine ten eleven twelve"
NAME=$(echo "$WORDS" | cut -d' ' -f$((COUNT+1)))
# Scoped to the documents that describe the CURRENT state. `docs/07-traps.md` is
# deliberately excluded: it is a record of what was true when each defect was
# found, and "the eight events registered at the time" is correct prose there.
# Rewriting history to satisfy a checker would be a worse failure than the drift
# this catches.
STALE=$(grep -lEi "the (two|three|four|five|six|seven|eight|nine|ten) events (clawd-light )?registers?" \
        docs/02-claude-code.md docs/05-code-map.md README.md \
        Contracts/assumptions.md 2>/dev/null | while read -r f; do
    grep -qiE "the $NAME events" "$f" || echo "$f"
done)
if [ -z "$STALE" ]; then
    ok "no document announces a different number of registered events"
else
    bad "a document still announces the old count (should be “the $NAME events”):"
    for f in $STALE; do note "$f"; done
fi

head_ "Test suites are registered"

# A suite that exists but was never added to the runner is a file nobody executes,
# which is where three of this project's defects were found.
python3 - <<'PY' && ok "every suite defined is run" || bad "a suite exists that the runner never calls"
import glob, re, sys

defined = set()
for path in glob.glob("Sources/ClawdLightTests/*.swift"):
    defined |= set(re.findall(r'^enum (\w+Suite) \{', open(path).read(), re.M))
registered = set(re.findall(r'(\w+Suite)\.suite', open("Sources/ClawdLightTests/main.swift").read()))

orphans = sorted(defined - registered)
for o in orphans:
    print(f"    {o} is defined but never registered in main.swift", file=sys.stderr)
sys.exit(1 if orphans else 0)
PY

printf '\n%s\n' "────────────────────────────────────────────────────────"
if [ "$FAILURES" -eq 0 ]; then
    printf '\033[32m✓\033[0m %d checks, all passing.\n' "$CHECKS"
else
    printf '\033[31m✗\033[0m %d of %d checks failed.\n\n' "$FAILURES" "$CHECKS"
    printf '  The documentation is describing a repository that has moved.\n'
    printf '  Each line above names the claim and what is true instead.\n'
    exit 1
fi
