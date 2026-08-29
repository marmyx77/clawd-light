#!/usr/bin/env python3
"""Where a session actually gets compacted, measured on real transcripts.

WHY THIS EXISTS
The panel divides a session's token count by its model's context window. That
denominator was nearly wrong. Claude Code's own indicator counts down to a
threshold below the window — `window - min(maxOutputTokens, 20000) - 13000`,
readable in the binary — and three readings of that indicator, taken by hand,
agreed with a denominator of 0.92 x window to within a point. Three points, one
plausible story, and a number about to be written into the code.

The story was wrong. That threshold is compared against Claude Code's OWN token
estimate, which is not the sum this project reads out of `message.usage`: on the
same compaction the two have been seen 0.4% apart and 60x apart. Borrowing the
threshold means dividing our numerator by their denominator.

So this asks the transcripts the only question that settles it: at what value of
OUR sum does a session actually get auto-compacted? Every `compact_boundary` with
`trigger: "auto"` is a session that hit the ceiling, and the last reply before it
is our reading at that moment.

WHAT IT PROVES, AND WHAT IT CANNOT
A reading above 100% of the recorded window would mean the denominator is too
small — that is the failure this returns non-zero for. It cannot prove the
denominator is not too LARGE: our reading is a floor (whatever was loaded after
the last reply is invisible), so the envelope approaches the ceiling from below
and never touches it. What it does say is that 0.92 is refuted: ten of these
compactions would print above 100% against it.

USAGE
    Scripts/measure-compaction.py            # reads ~/.claude/projects
    Scripts/measure-compaction.py --json     # the numbers, for a gate

EXIT
    0  every reading sits inside its window
    1  a reading exceeded its window - the table's denominator is wrong
    2  nothing here to look at (no transcripts) - a skip, not a pass
"""

import json
import os
import sys

HOME = os.path.expanduser("~")
TRANSCRIPTS = os.path.join(HOME, ".claude", "projects")
CONTRACT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "Contracts", "required-fields.json"
)

# The three fields whose sum is the context. Same list as ContextScanner.swift;
# if they ever disagree, this measurement is describing a different quantity
# than the panel shows, which is worse than not measuring at all.
FIELDS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")


def windows():
    """The model table, from the contract - never a second copy of it here."""
    with open(CONTRACT) as handle:
        return json.load(handle)["modelContextWindows"]["windows"]


def stripped(model):
    """`claude-sonnet-4-5-20250929` -> `claude-sonnet-4-5`, and nothing else."""
    parts = model.split("-")
    if len(parts) > 1 and len(parts[-1]) == 8 and parts[-1].isdigit():
        return "-".join(parts[:-1])
    return model


def total(block):
    return sum(int(block.get(field) or 0) for field in FIELDS)


def reading(record):
    """Our numerator for one record, or None if it is not a usable reply."""
    message = record.get("message")
    if not isinstance(message, dict):
        return None
    model = message.get("model")
    if not isinstance(model, str) or not model or model == "<synthetic>":
        return None
    usage = message.get("usage")
    if not isinstance(usage, dict):
        return None
    tokens = total(usage)
    if tokens <= 0:
        iterations = usage.get("iterations")
        if isinstance(iterations, list) and iterations:
            tokens = total(iterations[-1])
    return (tokens, model) if tokens > 0 else None


def transcripts():
    if not os.path.isdir(TRANSCRIPTS):
        return []
    found = []
    for project in os.listdir(TRANSCRIPTS):
        folder = os.path.join(TRANSCRIPTS, project)
        if not os.path.isdir(folder):
            continue
        for name in os.listdir(folder):
            if name.endswith(".jsonl"):
                found.append(os.path.join(folder, name))
    return found


def measure():
    table = windows()
    files = transcripts()
    points, boundaries = [], 0

    for path in files:
        try:
            with open(path, "rb") as handle:
                raw = handle.read()
        except OSError:
            continue
        if b'"compact_boundary"' not in raw:
            continue

        records = []
        for line in raw.split(b"\n"):
            if not line.strip():
                continue
            try:
                records.append(json.loads(line))
            except ValueError:
                records.append(None)

        for index, record in enumerate(records):
            if not record or record.get("subtype") != "compact_boundary":
                continue
            if (record.get("compactMetadata") or {}).get("trigger") != "auto":
                continue
            boundaries += 1
            # Backwards to the last reply that was ours. A sidechain record is a
            # subagent's context, which is a different conversation with the same
            # session id: one real pair read 41,990 and 987,346 within a minute.
            for back in range(index - 1, -1, -1):
                previous = records[back]
                if not previous or previous.get("isSidechain"):
                    continue
                found = reading(previous)
                if not found:
                    continue
                tokens, model = found
                window = table.get(stripped(model))
                if window:
                    points.append({"model": stripped(model), "tokens": tokens,
                                   "window": window, "fraction": tokens / window})
                break

    return {"transcripts": len(files), "autoCompactions": boundaries, "points": points}


def report(result):
    points = result["points"]
    print(f"    {result['transcripts']:,} transcripts, "
          f"{result['autoCompactions']} auto-compactions, "
          f"{len(points)} of them on a model in the table")
    if not points:
        return
    for window in sorted({point["window"] for point in points}, reverse=True):
        same = sorted((p["fraction"] for p in points if p["window"] == window))
        near = [f for f in same if f > 0.9]
        print(f"    window {window:>9,}  n={len(same):<4} "
              f"highest reading {same[-1] * 100:6.2f}% of it   "
              f"{len(near)} of them past 90%")
    over = [p for p in points if p["fraction"] > 1.0]
    if over:
        for point in over[:5]:
            print(f"    {point['model']}: {point['tokens']:,} of {point['window']:,} "
                  f"= {point['fraction'] * 100:.1f}% - above its own window")
    else:
        print("    none above 100%: the window is the ceiling, and it is the denominator")


def main():
    result = measure()
    if "--json" in sys.argv:
        print(json.dumps({k: v for k, v in result.items() if k != "points"} |
                         {"count": len(result["points"]),
                          "highest": max((p["fraction"] for p in result["points"]), default=0),
                          "over": sum(1 for p in result["points"] if p["fraction"] > 1.0)}))
    else:
        report(result)

    if not result["points"]:
        return 2
    return 1 if any(p["fraction"] > 1.0 for p in result["points"]) else 0


if __name__ == "__main__":
    sys.exit(main())
