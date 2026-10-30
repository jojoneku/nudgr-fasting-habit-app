"""Nudgy tool-choice eval (Plan 065 phase 2): which tool does the model call first?

Sends each question in questions.json to Bedrock with the fixed snapshot
(snapshot.json) and the app's tool catalogue (tools.json), scores the first
tool_use, prints a Markdown table and the pass rate, and exits 1 when the pass
rate is under the threshold. See README.md for setup and cost.

The request is built by the Lambda's own code (_build_advisor_request and
_generation_params), so the eval sends what production sends. Run from
backend/ai-coach/:

    python evals/run_eval.py                    # production advisor model
    python evals/run_eval.py --model sonnet-4.6
    python evals/run_eval.py --dry-run          # print the requests, no calls
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

import scoring  # noqa: E402

# The model food-advisor-stream runs (its ADVISOR_MODEL_ID, read 2026-10-30).
PRODUCTION_MODEL = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
MODEL_ALIASES = {
    "sonnet-4.5": PRODUCTION_MODEL,
    "sonnet-4.6": "global.anthropic.claude-sonnet-4-6",
}

# USD per 1M tokens (Singapore, global profile): input, output, cache write,
# cache read. For the cost estimate only.
PRICES = {
    "claude-sonnet-4-5": (3.0, 15.0, 3.75, 0.30),
    "claude-sonnet-4-6": (3.0, 15.0, 3.75, 0.30),
}


def _load(name):
    return json.loads((HERE / name).read_text(encoding="utf-8"))


def _lambda_module(model_id):
    # The Lambda reads BEDROCK_MODEL_ID at import. Its value is not used here:
    # the eval passes its own model to every call.
    os.environ.setdefault("BEDROCK_MODEL_ID", model_id)
    import lambda_function
    return lambda_function


def build_body(lf, model_id, snapshot, tools, messages):
    """The Bedrock body, built as _advise_finance builds it."""
    payload = {
        "messages": messages,
        "context": {k: v for k, v in snapshot.items() if k != "today"},
        "tools": tools,
    }
    request, err = lf._build_advisor_request(payload)
    if err is not None:
        raise RuntimeError(f"the Lambda rejected the payload: {err['body']}")
    return {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": lf._ADVISOR_MAX_TOKENS,
        "system": request["system"],
        "messages": request["messages"],
        **({"tools": request["tools"]} if request["tools"] else {}),
        **lf._generation_params(model_id, lf._ADVISOR_EFFORT),
    }


def _tool_results(calls, text):
    """One user turn that answers every call with the same canned text."""
    return [
        {"type": "tool_result", "tool_use_id": c["id"], "content": text}
        for c in calls
    ]


class Usage:
    def __init__(self):
        self.tokens = {"input_tokens": 0, "output_tokens": 0,
                       "cache_creation_input_tokens": 0,
                       "cache_read_input_tokens": 0}

    def add(self, usage):
        for key in self.tokens:
            self.tokens[key] += int(usage.get(key) or 0)

    def cost(self, model_id):
        price = next((p for k, p in PRICES.items() if k in model_id), None)
        if price is None:
            return None
        t = self.tokens
        return (t["input_tokens"] * price[0] + t["output_tokens"] * price[1]
                + t["cache_creation_input_tokens"] * price[2]
                + t["cache_read_input_tokens"] * price[3]) / 1e6


def run_question(q, *, call, lf, model_id, snapshot, tools):
    """Score one question. `call(body)` returns the Bedrock reply as a dict."""
    messages = [{"role": "user", "text": q["question"]}]
    reply = call(build_body(lf, model_id, snapshot, tools, messages))
    content = lf._without_thinking(reply.get("content") or [])
    calls = scoring.tool_calls(content)
    passed, reason = scoring.score_reply(q["expect"], calls)
    got = "; ".join(scoring.describe_call(c) for c in calls) or "(text only)"
    expected = scoring.describe_expect(q["expect"])

    then = q.get("then")
    if then and passed:
        messages += [
            {"role": "assistant", "content_blocks": content},
            {"role": "user", "content_blocks": _tool_results(calls, then["tool_result"])},
        ]
        reply = call(build_body(lf, model_id, snapshot, tools, messages))
        calls = scoring.tool_calls(lf._without_thinking(reply.get("content") or []))
        passed, reason = scoring.score_reply(then["expect"], calls)
        got += " → " + ("; ".join(scoring.describe_call(c) for c in calls) or "(text only)")
        if not passed:
            reason = "second step: " + reason
    if then:
        expected += " → " + scoring.describe_expect(then["expect"])

    return {"id": q["id"], "question": q["question"], "expected": expected,
            "got": got, "passed": passed, "reason": reason}


def _dry_run(questions, lf, model_id, snapshot, tools):
    """Print every request. System and tools are the same for all of them, so
    they are printed once, with the first request."""
    for i, q in enumerate(questions):
        body = build_body(lf, model_id, snapshot, tools,
                          [{"role": "user", "text": q["question"]}])
        if i:
            body["system"] = "(same as the first request)"
            body["tools"] = "(same as the first request)"
        print(f"── {q['id']} ──")
        print(json.dumps(body, ensure_ascii=False, indent=2))
        if q.get("then"):
            print(f"(then: canned tool_result, scored against "
                  f"{scoring.describe_expect(q['then']['expect'])})")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--model", default=PRODUCTION_MODEL,
                        help="a Bedrock model or inference profile id, or one of "
                             f"{', '.join(MODEL_ALIASES)} (default: production)")
    parser.add_argument("--profile", default="ifast-dev")
    parser.add_argument("--region", default="ap-southeast-1")
    parser.add_argument("--only", nargs="*", metavar="ID",
                        help="run only these question ids")
    parser.add_argument("--threshold", type=float,
                        help="pass rate needed (default: questions.json)")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the requests and make no calls")
    args = parser.parse_args(argv)
    # The table carries peso signs; a Windows console defaults to cp1252.
    sys.stdout.reconfigure(encoding="utf-8")

    model_id = MODEL_ALIASES.get(args.model, args.model)
    spec = _load("questions.json")
    questions = spec["questions"]
    if args.only:
        questions = [q for q in questions if q["id"] in set(args.only)]
    threshold = args.threshold if args.threshold is not None else spec["threshold"]
    snapshot, tools = _load("snapshot.json"), _load("tools.json")
    lf = _lambda_module(model_id)

    if args.dry_run:
        _dry_run(questions, lf, model_id, snapshot, tools)
        return 0

    import boto3
    from botocore.exceptions import ClientError

    client = boto3.Session(profile_name=args.profile,
                           region_name=args.region).client("bedrock-runtime")
    usage = Usage()

    def call(body):
        raw = client.invoke_model(modelId=model_id, contentType="application/json",
                                  accept="application/json", body=json.dumps(body))
        reply = json.loads(raw["body"].read())
        usage.add(reply.get("usage") or {})
        return reply

    results = []
    started = time.monotonic()
    for q in questions:
        try:
            results.append(run_question(q, call=call, lf=lf, model_id=model_id,
                                        snapshot=snapshot, tools=tools))
        except ClientError as e:
            code = e.response.get("Error", {}).get("Code", "")
            print(f"Bedrock refused the call ({code}): {e}", file=sys.stderr)
            print(f"Check that profile {args.profile!r} may call {model_id} "
                  f"in {args.region}. The eval changes nothing in AWS.",
                  file=sys.stderr)
            return 2
        print(f"{'pass' if results[-1]['passed'] else 'FAIL'}  {q['id']}",
              file=sys.stderr)

    rate = scoring.pass_rate(results)
    passed = sum(r["passed"] for r in results)
    print(f"Model: `{model_id}`\n")
    print(scoring.format_table(results))
    print(f"\nPass rate: {passed}/{len(results)} = {rate:.0%} "
          f"(threshold {threshold:.0%}) — {'PASS' if rate >= threshold else 'FAIL'}")
    cost = usage.cost(model_id)
    t = usage.tokens
    print(f"Tokens: {t['input_tokens']} in, {t['output_tokens']} out, "
          f"{t['cache_creation_input_tokens']} cache write, "
          f"{t['cache_read_input_tokens']} cache read"
          + (f" — about ${cost:.2f}" if cost is not None else "")
          + f"; {time.monotonic() - started:.0f}s")
    return 0 if rate >= threshold else 1


if __name__ == "__main__":
    sys.exit(main())
