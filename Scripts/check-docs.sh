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

problems = []
total = 0
for f in glob.glob("docs/*.md") + ["Contracts/assumptions.md", "README.md"]:
    if not os.path.exists(f):
        continue
    base = os.path.dirname(f)
    for match in re.finditer(r'\[[^\]]*\]\(([^)]+)\)', open(f).read()):
        target = match.group(1)
        if target.startswith(("http", "#", "mailto")):
            continue
        total += 1
        path = target.split("#")[0]
        if not path:
            continue
        if not os.path.exists(os.path.normpath(os.path.join(base, path))):
            problems.append(f"{f} -> {target}")

print(f"    {total} relative links checked", file=sys.stderr)
for p in problems:
    print(f"    broken: {p}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY

# ─────────────────────────────────────────────────────────────────────────────
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
