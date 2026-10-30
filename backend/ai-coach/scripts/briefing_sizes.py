"""Average briefing size per section over a time window (read-only).

Each turn's first advisor hop logs `briefing_chars` in its
`advisor_invocation` line: the characters of the snapshot and the historical
record, and of each snapshot section by a fixed key (see _BRIEFING_SECTIONS in
lambda_function.py). This script averages them, so a smaller briefing can be
designed from data. Counts only: the logs hold no briefing text.

Usage, from backend/ai-coach/:
    python scripts/briefing_sizes.py               # the last 24 hours
    python scripts/briefing_sizes.py --hours 72
"""

import argparse
import json
import os
import sys

import boto3

sys.path.insert(0, os.path.dirname(__file__))

from trace import _run_query  # noqa: E402  (scripts/trace.py, not the stdlib)

# Characters per token for this text, roughly: English with peso signs and
# figures. For an estimate only; the trace's in_tokens is the real count.
_CHARS_PER_TOKEN = 3.5


def average(sizes):
    """Mean characters per key over a list of `briefing_chars` dicts.

    Returns (turns, totals, sections): totals has "summary" and "historical",
    sections has one entry per key seen. A key missing from a turn counts as 0
    for that turn.
    """
    turns = len(sizes)
    if not turns:
        return 0, {}, {}
    totals = {k: sum(s.get(k) or 0 for s in sizes) / turns
              for k in ("summary", "historical")}
    keys = {k for s in sizes for k in (s.get("sections") or {})}
    sections = {k: sum((s.get("sections") or {}).get(k, 0) for s in sizes) / turns
                for k in keys}
    return turns, totals, sections


def render(turns, totals, sections):
    if not turns:
        return "no briefing_chars in this window (a deploy before it logs none)"
    whole = sum(sections.values()) or 1
    lines = [
        f"{turns} turns. Mean snapshot {totals['summary']:.0f} chars, "
        f"history {totals['historical']:.0f} chars "
        f"(~{(totals['summary'] + totals['historical']) / _CHARS_PER_TOKEN:.0f} tokens).",
        "",
        "| Section | Chars | ~Tokens | Share |",
        "|---|---:|---:|---:|",
    ]
    for key, chars in sorted(sections.items(), key=lambda kv: -kv[1]):
        lines.append(f"| {key} | {chars:.0f} | {chars / _CHARS_PER_TOKEN:.0f} "
                     f"| {chars / whole:.0%} |")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--hours", type=float, default=24)
    parser.add_argument("--profile", default="ifast-dev")
    parser.add_argument("--region", default="ap-southeast-1")
    args = parser.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8")

    logs = boto3.Session(profile_name=args.profile,
                         region_name=args.region).client("logs")
    rows = _run_query(logs, (
        "fields @message "
        '| filter @message like "briefing_chars" '
        "| sort @timestamp desc"), args.hours)
    sizes = []
    for row in rows:
        try:
            sizes.append(json.loads(row["@message"])["briefing_chars"])
        except (KeyError, ValueError, TypeError):
            continue
    print(render(*average(sizes)))


if __name__ == "__main__":
    main()
