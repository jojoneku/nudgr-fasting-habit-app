"""Tests for the `ai_usage` field of an advisor reply (Plan 065, phase 5).

Each reply carries the user's AI requests today (count), the daily cap, and
the estimated cost of this model call. The cost also goes on the cost_line.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x SUPABASE_URL=https://p.supabase.co \\
    SUPABASE_ANON_KEY=k python -m pytest test_ai_usage.py -q
"""

import asyncio
import io
import json

import pytest

import app as advisor_app
import lambda_function as lf

_USER = "0b7c2f8e-3d1a-4c5b-9e6f-112233445566"
_SONNET = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
_USAGE = {"input_tokens": 1000, "output_tokens": 100,
          "cache_read_input_tokens": 8000, "cache_creation_input_tokens": 500}


class _FakeBedrock:
    def invoke_model(self, **_):
        return {"body": io.BytesIO(json.dumps({
            "content": [{"type": "text", "text": "Fine."}],
            "stop_reason": "end_turn", "usage": _USAGE}).encode())}

    def invoke_model_with_response_stream(self, **_):
        events = [
            {"type": "message_start", "message": {"usage": {
                k: v for k, v in _USAGE.items() if k != "output_tokens"}}},
            {"type": "content_block_start", "index": 0,
             "content_block": {"type": "text", "text": ""}},
            {"type": "content_block_delta", "index": 0,
             "delta": {"type": "text_delta", "text": "Fine."}},
            {"type": "content_block_stop", "index": 0},
            {"type": "message_delta", "delta": {"stop_reason": "end_turn"},
             "usage": {"output_tokens": 100}},
        ]
        return {"body": [{"chunk": {"bytes": json.dumps(e).encode()}}
                         for e in events]}


@pytest.fixture(autouse=True)
def _setup(monkeypatch):
    monkeypatch.setattr(lf, "_bedrock", _FakeBedrock())
    monkeypatch.setattr(lf, "_ADVISOR_MODEL_ID", _SONNET)
    monkeypatch.setattr(lf, "_DAILY_CAP", 100)
    monkeypatch.setattr(lf, "_check_rate_limit", lambda token: (True, 7))
    monkeypatch.setattr(advisor_app, "_check_rate_limit",
                        lambda token: (True, 7))
    monkeypatch.setattr(advisor_app, "verify_supabase_token",
                        lambda token: {"sub": _USER})


def _messages(continuation=False):
    messages = [{"role": "user", "text": "How am I doing?"}]
    if continuation:
        messages += [
            {"role": "assistant", "content_blocks": [
                {"type": "tool_use", "id": "t0", "name": "find", "input": {}}]},
            {"role": "user", "content_blocks": [
                {"type": "tool_result", "tool_use_id": "t0", "content": "ok"}]},
        ]
    return messages


def _buffered(continuation=False):
    event = {
        "headers": {"authorization": "Bearer t"},
        "requestContext": {"authorizer": {"jwt": {"claims": {"sub": _USER}}}},
        "body": json.dumps({"op": "adviseFinance", "payload": {
            "messages": _messages(continuation)}}),
    }
    return json.loads(lf.lambda_handler(event, None)["body"])


def _streamed_end(continuation=False):
    body = json.dumps({"payload": {"messages": _messages(continuation)}})
    scope = {"type": "http", "method": "POST", "path": "/v1/advisor",
             "headers": [(b"authorization", b"Bearer t")]}

    async def receive():
        return {"type": "http.request", "body": body.encode(),
                "more_body": False}

    sent = []

    async def send(message):
        sent.append(message)

    asyncio.run(advisor_app.app(scope, receive, send))
    raw = b"".join(m.get("body") or b"" for m in sent).decode()
    frames = [json.loads(l) for l in raw.splitlines() if l]
    return next(f for f in frames if f["type"] == "end")


_COST = lf.estimated_cost_usd(_SONNET, _USAGE)


def test_the_buffered_reply_carries_count_cap_and_cost():
    assert _buffered()["ai_usage"] == {"count": 7, "cap": 100,
                                       "cost_usd": _COST}


def test_the_streamed_end_frame_carries_count_cap_and_cost():
    assert _streamed_end()["ai_usage"] == {"count": 7, "cap": 100,
                                           "cost_usd": _COST}


@pytest.mark.parametrize("reply", [_buffered, _streamed_end])
def test_a_continuation_hop_has_no_count(reply):
    usage = reply(continuation=True)["ai_usage"]

    assert usage["count"] is None
    assert usage["cap"] == 100
    assert usage["cost_usd"] == _COST


def test_without_rate_limiting_there_is_no_count(monkeypatch):
    monkeypatch.setattr(lf, "_check_rate_limit", lambda token: (True, 0))

    assert _buffered()["ai_usage"]["count"] is None


def test_an_unknown_model_has_no_cost(monkeypatch):
    monkeypatch.setattr(lf, "_ADVISOR_MODEL_ID", "some-other-model")

    assert _buffered()["ai_usage"]["cost_usd"] is None


def test_the_cost_goes_on_the_cost_line_and_the_json_line(capsys):
    _buffered()
    out = capsys.readouterr().out
    cost_line = next(l for l in out.splitlines() if l.startswith("cost_line "))
    log = next(json.loads(l) for l in out.splitlines()
               if l.startswith("{") and "advisor_invocation" in l)

    assert cost_line.endswith(f"cost_usd={_COST:.6f}")
    assert log["cost_usd"] == pytest.approx(_COST)


def test_an_unknown_cost_is_a_dash_on_the_cost_line(monkeypatch, capsys):
    monkeypatch.setattr(lf, "_ADVISOR_MODEL_ID", "some-other-model")
    _buffered()
    out = capsys.readouterr().out

    assert "cost_usd=-" in out
