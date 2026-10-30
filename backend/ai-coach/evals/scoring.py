"""Scoring for the Nudgy tool-choice eval (Plan 065 phase 2).

Pure functions with no network, so test_scoring.py covers them for free. The
runner (run_eval.py) calls Bedrock and hands each reply's content here.

An expectation is {"any": [option, ...]}, {"some": [option, ...]} or
{"all": [option, ...]}:

- any: the FIRST tool_use in the reply must match one option.
- some: a tool_use in ANY position of the reply must match one option. For a
  two-part question, where the calls of one reply run together and their
  order changes nothing.
- all: every option must match its own tool_use in the reply. This is the
  batch check: two writes the user asked for in one message belong in one
  reply, so the user reviews them as one batch.

An option is {"tool": name, "input": {key: spec}}. Every key in "input" must be
present in the call and match its spec. An option can instead be
{"answer": [text, ...]}: the reply makes no tool call and its text contains
every listed text (ignoring case). Use it only when the snapshot states the
exact figure, so an answer without a tool is correct. A spec is:

- a literal: equal to the value (strings ignore case and outer spaces;
  numbers compare as numbers, so 20000 matches 20000.0),
- {"contains": s}: the value, as text, contains s (ignoring case),
- {"prefix": s}: the value, as text, starts with s (ignoring case),
- {"any_of": [literal, ...]}: equal to one of the literals.
"""


def _norm(value):
    return str(value).strip().lower()


def _equal(want, have):
    if isinstance(want, bool) or isinstance(have, bool):
        return want is have
    if isinstance(want, (int, float)):
        try:
            return float(have) == float(want)
        except (TypeError, ValueError):
            return False
    if isinstance(want, str):
        return isinstance(have, str) and _norm(have) == _norm(want)
    return want == have


def match_value(spec, value):
    """True when `value` satisfies `spec` (see the module docstring)."""
    if isinstance(spec, dict):
        if "contains" in spec:
            return value is not None and _norm(spec["contains"]) in _norm(value)
        if "prefix" in spec:
            return value is not None and _norm(value).startswith(_norm(spec["prefix"]))
        if "any_of" in spec:
            return any(_equal(w, value) for w in spec["any_of"])
        raise ValueError(f"unknown spec: {spec}")
    return _equal(spec, value)


def match_call(option, call):
    """True when the tool call `{"name", "input"}` satisfies `option`."""
    if "tool" not in option or call.get("name") != option["tool"]:
        return False
    given = call.get("input") or {}
    return all(
        key in given and match_value(spec, given[key])
        for key, spec in (option.get("input") or {}).items()
    )


def tool_calls(content):
    """The tool_use blocks of a reply's content, in order."""
    return [
        {"id": b.get("id"), "name": b.get("name"), "input": b.get("input") or {}}
        for b in content or []
        if isinstance(b, dict) and b.get("type") == "tool_use"
    ]


def reply_text(content):
    """The text blocks of a reply's content, joined."""
    return "\n".join(
        b.get("text") or ""
        for b in content or []
        if isinstance(b, dict) and b.get("type") == "text"
    )


def match_answer(option, text):
    """True when `text` contains every text an answer option lists."""
    return all(_norm(want) in _norm(text) for want in option["answer"])


def describe_call(call):
    """`name(key=value, ...)`, short enough for a table cell."""
    args = ", ".join(f"{k}={v!r}" for k, v in (call.get("input") or {}).items())
    return f"{call.get('name')}({args})"


def describe_option(option):
    if "answer" in option:
        return "text answer with " + " and ".join(repr(a) for a in option["answer"])
    parts = []
    for key, spec in (option.get("input") or {}).items():
        if isinstance(spec, dict):
            (kind, want), = spec.items()
            if kind == "any_of":
                parts.append(f"{key}∈{'|'.join(map(str, want))}")
            else:
                parts.append(f"{key} {kind} {want!r}")
        else:
            parts.append(f"{key}={spec!r}")
    return f"{option['tool']}({', '.join(parts)})"


def describe_expect(expect):
    if "all" in expect:
        return " + ".join(describe_option(o) for o in expect["all"])
    if "some" in expect:
        return "any call: " + " or ".join(describe_option(o) for o in expect["some"])
    return " or ".join(describe_option(o) for o in expect["any"])


def score_reply(expect, calls, text=""):
    """Score one reply's tool calls and text. Returns `(passed, reason)`."""
    options = expect.get("any") or expect.get("some") or expect.get("all") or []
    if not calls:
        answers = [o for o in options if "answer" in o]
        if any(match_answer(o, text) for o in answers):
            return True, "ok (answered from the snapshot)"
        if answers:
            return False, "answered in text without the expected figure"
        return False, "no tool call (answered in text)"
    if "some" in expect:
        if any(match_call(o, c) for o in options for c in calls):
            return True, "ok"
        names = {c["name"] for c in calls}
        if any(o.get("tool") in names for o in options):
            return False, "right tool, wrong input"
        return False, "wrong tool"
    if "all" in expect:
        unused = list(calls)
        missing = []
        for option in expect["all"]:
            hit = next((c for c in unused if match_call(option, c)), None)
            if hit is None:
                missing.append(option["tool"])
            else:
                unused.remove(hit)
        if missing:
            return False, "missing in the same reply: " + ", ".join(missing)
        return True, "ok"
    first = calls[0]
    if any(match_call(option, first) for option in expect["any"]):
        return True, "ok"
    if any(option.get("tool") == first["name"] for option in expect["any"]):
        return False, "right tool, wrong input"
    return False, "wrong tool"


def pass_rate(results):
    """Fraction of `results` (dicts with a bool "passed") that passed."""
    if not results:
        return 0.0
    return sum(1 for r in results if r["passed"]) / len(results)


def _cell(text):
    return str(text).replace("|", "\\|").replace("\n", " ")


def format_table(results):
    """A Markdown table of `results`, one row per question."""
    lines = [
        "| # | Question | Expected first tool | Got | Result |",
        "|---|---|---|---|---|",
    ]
    for i, r in enumerate(results, 1):
        verdict = "pass" if r["passed"] else f"FAIL ({r['reason']})"
        lines.append(
            f"| {i} | {_cell(r['question'])} | {_cell(r['expected'])} "
            f"| {_cell(r['got'])} | {_cell(verdict)} |"
        )
    return "\n".join(lines)
