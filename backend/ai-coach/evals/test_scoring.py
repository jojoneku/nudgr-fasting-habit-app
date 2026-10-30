"""Tests for the tool-choice eval's scorer and runner (Plan 065 phase 2).

No network: the runner is driven with a fake Bedrock call. Run from
backend/ai-coach/:
    BEDROCK_MODEL_ID=x python -m pytest evals -q
"""

import json
from pathlib import Path

import pytest

import run_eval
import scoring

HERE = Path(__file__).resolve().parent


def _call(name, **inputs):
    return {"id": f"t-{name}", "name": name, "input": inputs}


# ── match_value ──────────────────────────────────────────────────────────────

@pytest.mark.parametrize("spec,value,want", [
    ("dashboard", "Dashboard ", True),
    ("dashboard", "budget", False),
    (20000, 20000.0, True),
    (20000, "20000", True),
    (20000, 2000, False),
    (True, True, True),
    (True, 1, False),
    ({"contains": "mark"}, "Mark - concert", True),
    ({"contains": "mark"}, None, False),
    ({"prefix": "2026-10"}, "2026-10-01", True),
    ({"prefix": "2026-10"}, "2026-07-01", False),
    ({"any_of": ["budget", "dashboard"]}, "budget", True),
    ({"any_of": ["budget", "dashboard"]}, "bills", False),
])
def test_match_value(spec, value, want):
    assert scoring.match_value(spec, value) is want


def test_an_unknown_spec_is_an_error_not_a_pass():
    with pytest.raises(ValueError):
        scoring.match_value({"regex": "x"}, "x")


def test_a_required_input_key_must_be_present():
    option = {"tool": "find", "input": {"entity": "bill"}}
    assert scoring.match_call(option, _call("find", entity="bill", query="gym"))
    assert not scoring.match_call(option, _call("find", query="gym"))
    assert not scoring.match_call(option, _call("findTransactions", entity="bill"))


# ── score_reply ──────────────────────────────────────────────────────────────

_ANY = {"any": [
    {"tool": "getView", "input": {"view": "dashboard"}},
    {"tool": "find", "input": {"entity": "account"}},
]}


def test_any_scores_the_first_call_only():
    assert scoring.score_reply(_ANY, [_call("getView", view="dashboard")]) == (True, "ok")
    assert scoring.score_reply(_ANY, [_call("find", entity="account")]) == (True, "ok")
    # The right tool second does not rescue a wrong first call.
    passed, reason = scoring.score_reply(
        _ANY, [_call("queryFinance", metric="spend"), _call("getView", view="dashboard")])
    assert (passed, reason) == (False, "wrong tool")


def test_any_tells_a_wrong_input_from_a_wrong_tool():
    assert scoring.score_reply(_ANY, [_call("getView", view="budget")]) == (
        False, "right tool, wrong input")


def test_no_tool_call_fails():
    assert scoring.score_reply(_ANY, []) == (False, "no tool call (answered in text)")


_SOME = {"some": [{"tool": "getView", "input": {"view": "grocery"}}]}


def test_some_accepts_the_match_in_any_position():
    both = [_call("findTransactions", category="Groceries"), _call("getView", view="grocery")]
    assert scoring.score_reply(_SOME, both) == (True, "ok")
    assert scoring.score_reply(_SOME, [_call("getView", view="budget")]) == (
        False, "right tool, wrong input")
    assert scoring.score_reply(_SOME, [_call("findTransactions")]) == (False, "wrong tool")


_ANSWER = {"any": [
    {"answer": ["999", "22"]},
    {"tool": "find", "input": {"entity": "bill"}},
]}


def test_an_answer_option_accepts_text_with_every_figure():
    assert scoring.score_reply(_ANSWER, [], "Globe is ₱999, due Oct 22.") == (
        True, "ok (answered from the snapshot)")
    assert scoring.score_reply(_ANSWER, [], "Globe is ₱999.") == (
        False, "answered in text without the expected figure")
    # A tool call is still scored as a tool call.
    assert scoring.score_reply(_ANSWER, [_call("find", entity="bill")], "x") == (True, "ok")
    assert scoring.score_reply(_ANSWER, [_call("getView", view="bills")]) == (
        False, "wrong tool")


def test_reply_text_joins_the_text_blocks():
    content = [{"type": "text", "text": "a"}, {"type": "tool_use", "name": "x"},
               {"type": "text", "text": "b"}]
    assert scoring.reply_text(content) == "a\nb"


_ALL = {"all": [
    {"tool": "addBill", "input": {"amount": 1299}},
    {"tool": "addSetAside", "input": {"amount": 3000}},
]}


def test_all_needs_every_write_in_the_same_reply():
    both = [_call("addSetAside", amount=3000), _call("addBill", amount=1299)]
    assert scoring.score_reply(_ALL, both) == (True, "ok")
    assert scoring.score_reply(_ALL, [_call("addBill", amount=1299)]) == (
        False, "missing in the same reply: addSetAside")


def test_all_does_not_count_one_call_twice():
    expect = {"all": [{"tool": "addBill", "input": {}}, {"tool": "addBill", "input": {}}]}
    assert not scoring.score_reply(expect, [_call("addBill")])[0]
    assert scoring.score_reply(expect, [_call("addBill"), _call("addBill")])[0]


def test_tool_calls_skips_text_and_thinking():
    content = [
        {"type": "thinking", "thinking": "hm"},
        {"type": "text", "text": "Let me check."},
        {"type": "tool_use", "id": "a", "name": "find", "input": {"entity": "bill"}},
    ]
    assert scoring.tool_calls(content) == [
        {"id": "a", "name": "find", "input": {"entity": "bill"}}]


def test_pass_rate_and_table():
    results = [
        {"question": "Q1 | pipe", "expected": "e", "got": "g", "passed": True, "reason": "ok"},
        {"question": "Q2", "expected": "e", "got": "g", "passed": False, "reason": "wrong tool"},
    ]
    assert scoring.pass_rate(results) == 0.5
    assert scoring.pass_rate([]) == 0.0
    table = scoring.format_table(results)
    assert "Q1 \\| pipe" in table
    assert "FAIL (wrong tool)" in table


# ── The fixtures ─────────────────────────────────────────────────────────────

def _fixture(name):
    return json.loads((HERE / name).read_text(encoding="utf-8"))


def _options(expect):
    options = expect.get("any", []) + expect.get("some", []) + expect.get("all", [])
    return [o for o in options if "tool" in o]


def _all_questions():
    spec = _fixture("questions.json")
    return spec["questions"] + spec.get("holdout", [])


def test_every_expected_tool_and_input_exists_in_the_catalogue():
    """A typo in questions.json would fail every run for the wrong reason."""
    tools = {t["name"]: t for t in _fixture("tools.json")}
    for q in _all_questions():
        expects = [q["expect"]] + ([q["then"]["expect"]] if "then" in q else [])
        for option in (o for e in expects for o in _options(e)):
            assert option["tool"] in tools, (q["id"], option["tool"])
            props = tools[option["tool"]]["input_schema"]["properties"]
            for key in option.get("input") or {}:
                assert key in props, (q["id"], option["tool"], key)


def test_the_question_ids_are_unique():
    ids = [q["id"] for q in _all_questions()]
    assert len(ids) == len(set(ids))


# ── The runner, with a fake Bedrock ──────────────────────────────────────────

def _reply(*blocks):
    return {"content": list(blocks), "usage": {"input_tokens": 10, "output_tokens": 2}}


def _tool_use(name, **inputs):
    return {"type": "tool_use", "id": f"tu-{name}", "name": name, "input": inputs}


@pytest.fixture
def ctx():
    lf = run_eval._lambda_module(run_eval.PRODUCTION_MODEL)
    return {"lf": lf, "model_id": run_eval.PRODUCTION_MODEL,
            "snapshot": _fixture("snapshot.json"), "tools": _fixture("tools.json")}


def test_the_request_is_the_lambdas(ctx):
    body = run_eval.build_body(ctx["lf"], ctx["model_id"], ctx["snapshot"], ctx["tools"],
                               [{"role": "user", "text": "Hi"}])
    assert body["system"][0]["text"] == ctx["lf"]._ADVISOR_SYSTEM_PREFIX
    assert ctx["snapshot"]["summary"] in body["system"][1]["text"]
    assert body["tools"] == ctx["tools"]
    assert body["messages"] == [{"role": "user", "content": "Hi"}]
    # Sonnet 4.5 takes the plain body: no thinking or effort fields.
    assert "thinking" not in body


def test_a_two_step_question_replays_the_first_reply(ctx):
    q = {
        "id": "del", "question": "Delete my gym bill.",
        "expect": {"any": [{"tool": "find", "input": {"query": {"contains": "gym"}}}]},
        "then": {"tool_result": "status: found\nid: b1",
                 "expect": {"any": [{"tool": "deleteBill", "input": {"id": "b1"}}]}},
    }
    sent = []

    def call(body):
        sent.append(body)
        if len(sent) == 1:
            return _reply({"type": "text", "text": "Looking."},
                          _tool_use("find", entity="bill", query="gym"))
        return _reply(_tool_use("deleteBill", id="b1"))

    result = run_eval.run_question(q, call=call, **ctx)
    assert result["passed"], result
    assert len(sent) == 2
    second = sent[1]["messages"]
    assert [m["role"] for m in second] == ["user", "assistant", "user"]
    assert second[2]["content"][0]["type"] == "tool_result"
    assert second[2]["content"][0]["tool_use_id"] == "tu-find"
    assert "→" in result["expected"] and "deleteBill" in result["got"]


def test_a_failed_first_step_skips_the_second(ctx):
    q = {
        "id": "del", "question": "Delete my gym bill.",
        "expect": {"any": [{"tool": "find", "input": {}}]},
        "then": {"tool_result": "x", "expect": {"any": [{"tool": "deleteBill"}]}},
    }
    sent = []

    def call(body):
        sent.append(body)
        return _reply({"type": "text", "text": "Which bill?"})

    result = run_eval.run_question(q, call=call, **ctx)
    assert not result["passed"]
    assert result["got"] == "(text only)"
    assert len(sent) == 1


def test_usage_cost_estimate():
    usage = run_eval.Usage()
    usage.add({"input_tokens": 1_000_000, "output_tokens": 0})
    assert usage.cost(run_eval.PRODUCTION_MODEL) == pytest.approx(3.0)
    assert usage.cost("some-other-model") is None
