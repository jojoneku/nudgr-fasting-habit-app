"""Print the timeline of one Nudgy message from CloudWatch Logs (read-only).

Plan 065, phase 5. Every advisor hop of one user message carries the same
trace_id, and so do the app's client events. This script runs one CloudWatch
Logs Insights query over both advisor functions and prints, in time order:
each hop (model, tokens, cache, latency, stop reason, tools, result statuses,
estimated cost) and each client event.

The logs hold metadata only, so neither does the output: no message text, no
finance figures, no user id.

Usage, from backend/ai-coach/:
    python scripts/trace.py <trace_id>
    python scripts/trace.py --latest           # the newest trace_id
    python scripts/trace.py <trace_id> --hours 168 --json

Needs AWS credentials for the account that runs the functions (the default
profile is ifast-dev) and logs:StartQuery / logs:GetQueryResults. It only
reads.
"""

import argparse
import json
import os
import re
import sys
import time

import boto3

# lambda_function reads these at import; the script never calls Bedrock.
os.environ.setdefault("BEDROCK_MODEL_ID", "-")
os.environ.setdefault("AWS_DEFAULT_REGION", "ap-southeast-1")
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from lambda_function import (  # noqa: E402
    _TRACE_ID_RE,
    _cost_fields,
    estimated_cost_usd,
)

LOG_GROUPS = {
    "/aws/lambda/food-coach-handler": "coach",
    "/aws/lambda/food-advisor-stream": "stream",
}

_ROWS_LIMIT = 1000


def _run_query(logs, query, hours):
    end = int(time.time())
    started = logs.start_query(
        logGroupNames=list(LOG_GROUPS),
        startTime=end - int(hours * 3600),
        endTime=end,
        queryString=query,
        limit=_ROWS_LIMIT,
    )
    while True:
        result = logs.get_query_results(queryId=started["queryId"])
        if result["status"] in ("Complete", "Failed", "Cancelled", "Timeout"):
            break
        time.sleep(1)
    if result["status"] != "Complete":
        sys.exit(f"query {result['status'].lower()}")
    return [{f["field"]: f["value"] for f in row} for row in result["results"]]


def latest_trace_id(logs, hours):
    """The trace_id of the newest advisor invocation that has one."""
    rows = _run_query(logs, (
        'fields @timestamp, @message '
        '| filter @message like "cost_line op=adviseFinance" '
        'and @message not like "trace=- " '
        '| sort @timestamp desc | limit 1'), hours)
    for row in rows:
        match = re.search(r"\btrace=([A-Za-z0-9_-]{1,64})\b", row["@message"])
        if match:
            return match.group(1)
    return None


def _function(log):
    """Short name of a row's function. @log is `account:group`."""
    group = (log or "").split(":", 1)[-1]
    return LOG_GROUPS.get(group, group)


def _entry(row):
    """One row as a timeline entry, or None for a line this script ignores."""
    message = row.get("@message", "").strip()
    base = {"time": row.get("@timestamp"), "function": _function(row.get("@log"))}
    if message.startswith("{"):
        try:
            data = json.loads(message)
        except json.JSONDecodeError:
            return None
        if data.get("event") == "advisor_invocation":
            return {**base, "kind": "hop", "source": "json", **data}
        if data.get("event") == "client_event":
            return {**base, "kind": "event", "name": data.get("name"),
                    "fields": data.get("fields") or {}}
        return None
    if message.startswith("cost_line op=adviseFinance"):
        return {**base, "kind": "hop", "source": "cost_line",
                **_cost_fields(message)}
    return None


def timeline(rows):
    """The entries of one trace, in time order.

    A deployed Lambda writes both a cost_line and an advisor_invocation line
    per hop; the JSON line wins. An older deploy writes only the cost_line,
    which is then used instead.
    """
    entries = [e for e in (_entry(r) for r in rows) if e]
    if any(e["kind"] == "hop" and e["source"] == "json" for e in entries):
        entries = [e for e in entries
                   if not (e["kind"] == "hop" and e["source"] == "cost_line")]
    for e in entries:
        # A deploy with the per-user usage field logs the cost it computed.
        if e["kind"] == "hop" and e.get("cost_usd") is None:
            e["cost_usd"] = estimated_cost_usd(e.get("model"), {
                "input_tokens": e.get("in_tokens"),
                "output_tokens": e.get("out_tokens"),
                "cache_read_input_tokens": e.get("cache_read"),
                "cache_creation_input_tokens": e.get("cache_write"),
            })
    return sorted(entries, key=lambda e: e["time"] or "")


def _seconds(ms):
    return "-" if ms is None or ms < 0 else f"{ms / 1000:.1f}s"


def _model(model):
    """`global.anthropic.claude-sonnet-4-5-20250929-v1:0` -> `sonnet-4-5`."""
    match = re.search(r"claude-([a-z]+-\d+(?:-\d+)?)", model or "")
    return match.group(1) if match else (model or "?")


def _hop_line(e):
    tools = ",".join(e.get("tool_names") or []) or "-"
    results = ",".join(e.get("results") or []) or "-"
    cost = e.get("cost_usd")
    parts = [
        f"{e['function']:<6}",
        f"hop {e.get('hops', '?')} {e.get('hop') or '?'}",
        _model(e.get("model")) + (f" route={e['route']}" if e.get("route") else ""),
        f"in {e.get('in_tokens')} out {e.get('out_tokens')} "
        f"cache r{e.get('cache_read')} w{e.get('cache_write')}",
        _seconds(e.get("latency_ms"))
        + (f" (ttft {_seconds(e['ttft_ms'])})"
           if e.get("ttft_ms") not in (None, -1) else ""),
        f"stop {e.get('stop')}",
        f"tools {tools}",
        f"results {results}",
        "cost ?" if cost is None else f"${cost:.4f}",
    ]
    if e.get("error_class"):
        parts.append(f"ERROR {e['error_class']}")
    return "  ".join(parts)


def _event_line(e):
    fields = " ".join(f"{k}={v}" for k, v in sorted(e["fields"].items()))
    return f"{'event':<6}  {e['name']}" + (f"  {fields}" if fields else "")


def render(trace_id, entries):
    hops = [e for e in entries if e["kind"] == "hop"]
    events = [e for e in entries if e["kind"] == "event"]
    lines = [f"trace {trace_id}: {len(hops)} model calls, "
             f"{len(events)} client events"]
    if not entries:
        return "\n".join(lines + ["  (nothing found in this time window)"])
    start = _epoch(entries[0]["time"])
    for e in entries:
        offset = _epoch(e["time"]) - start
        body = _hop_line(e) if e["kind"] == "hop" else _event_line(e)
        lines.append(f"  +{offset:6.1f}s  {body}")
    costs = [e["cost_usd"] for e in hops if e.get("cost_usd") is not None]

    def total(key):
        return sum(e.get(key) or 0 for e in hops)

    lines.append(
        f"  total: in {total('in_tokens')} out {total('out_tokens')} "
        f"cache r{total('cache_read')} w{total('cache_write')}  "
        + (f"~${sum(costs):.4f}" if costs else "cost ?")
        + ("" if len(costs) == len(hops) else
           f" ({len(hops) - len(costs)} calls with no known model price)"))
    return "\n".join(lines)


def _epoch(stamp):
    """Seconds since the epoch for an Insights `@timestamp` (UTC)."""
    import calendar
    whole, _, frac = (stamp or "1970-01-01 00:00:00.000").partition(".")
    return calendar.timegm(time.strptime(whole, "%Y-%m-%d %H:%M:%S")) \
        + float("0." + (frac or "0"))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("trace_id", nargs="?", help="the message's trace_id")
    parser.add_argument("--latest", action="store_true",
                        help="use the newest trace_id in the window")
    parser.add_argument("--hours", type=float, default=72,
                        help="how far back to look (default 72)")
    parser.add_argument("--profile", default="ifast-dev")
    parser.add_argument("--region", default="ap-southeast-1")
    parser.add_argument("--json", action="store_true",
                        help="print the entries as JSON instead")
    args = parser.parse_args(argv)

    logs = boto3.Session(profile_name=args.profile,
                         region_name=args.region).client("logs")
    trace_id = args.trace_id
    if args.latest:
        trace_id = latest_trace_id(logs, args.hours)
        if trace_id is None:
            sys.exit(f"no trace_id in the last {args.hours:g} hours")
    if not trace_id or not _TRACE_ID_RE.fullmatch(trace_id):
        # Checked before it goes into the query string.
        parser.error("give a trace_id (letters, digits, _ and -) or --latest")

    rows = _run_query(logs, (
        "fields @timestamp, @log, @message "
        f'| filter @message like "{trace_id}" '
        "| sort @timestamp asc"), args.hours)
    entries = timeline(rows)
    if args.json:
        print(json.dumps(entries, indent=2))
    else:
        print(render(trace_id, entries))


if __name__ == "__main__":
    main()
