"""Tests for the 1-hour TTL on the tools + rules breakpoint (Plan 065, phase 5).

ADVISOR_CACHE_TTL_1H is off by default. On, breakpoint 1 (tools + rules) gets
`ttl: "1h"` and every other breakpoint stays on 5 minutes, because Bedrock
wants the longer TTL first. If Bedrock rejects the TTL, the call is made once
more without it, a warning is logged, and the container stays on 5 minutes.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x SUPABASE_URL=https://p.supabase.co \\
    SUPABASE_ANON_KEY=k python -m pytest test_cache_ttl.py -q
"""

import io
import json

import pytest

import lambda_function as lf

_TOOLS = [{
    "name": "findTransactions",
    "description": "Find transactions.",
    "input_schema": {"type": "object", "properties": {}},
}]

_PAYLOAD = {
    "messages": [
        {"role": "user", "text": "How am I doing?"},
        {"role": "assistant", "text": "Fine."},
        {"role": "user", "text": "And savings?"},
    ],
    "context": {"summary": "Cash: P1,000", "profile": "Paid on the 15th."},
    "tools": _TOOLS,
}

_REPLY = {"content": [{"type": "text", "text": "Nothing yet."}],
          "stop_reason": "end_turn", "usage": {}}


@pytest.fixture
def ttl(monkeypatch):
    """Turn the flag on (or off) for one test, with no earlier rejection."""
    def set_flag(on):
        monkeypatch.setattr(lf, "_ADVISOR_CACHE_TTL_1H", on)
        monkeypatch.setattr(lf, "_ttl_1h_rejected", False)
    set_flag(False)
    return set_flag


def _request():
    request, err = lf._build_advisor_request(json.loads(json.dumps(_PAYLOAD)))
    assert err is None
    return request


def _cache_controls(request):
    """Every cache_control in prompt order: system, then messages."""
    found = [b["cache_control"] for b in request["system"] if "cache_control" in b]
    for m in request["messages"]:
        if isinstance(m["content"], list):
            found += [b["cache_control"] for b in m["content"]
                      if isinstance(b, dict) and "cache_control" in b]
    return found


class _ValidationError(Exception):
    """The shape of a botocore ClientError, as _invoke_advisor reads it."""

    def __init__(self, code="ValidationException"):
        super().__init__(f"An error occurred ({code}): ttl is not supported")
        self.response = {"Error": {"Code": code}}


class _FakeBedrock:
    """Fails the first `fail` calls with `error`, then answers."""

    def __init__(self, fail=0, error=None):
        self.fail = fail
        self.error = error or _ValidationError()
        self.bodies = []

    def _call(self, body):
        self.bodies.append(json.loads(body))
        if len(self.bodies) <= self.fail:
            raise self.error

    def invoke_model(self, *, body, **_):
        self._call(body)
        return {"body": io.BytesIO(json.dumps(_REPLY).encode())}

    def invoke_model_with_response_stream(self, *, body, **_):
        self._call(body)
        events = [
            {"type": "message_start", "message": {"usage": {}}},
            {"type": "content_block_start", "index": 0,
             "content_block": {"type": "text", "text": ""}},
            {"type": "content_block_delta", "index": 0,
             "delta": {"type": "text_delta", "text": "Nothing yet."}},
            {"type": "content_block_stop", "index": 0},
            {"type": "message_delta", "delta": {"stop_reason": "end_turn"}},
        ]
        return {"body": [{"chunk": {"bytes": json.dumps(e).encode()}}
                         for e in events]}


def _ttls(body):
    return [b["cache_control"].get("ttl") for b in body["system"]]


# ── The flag ─────────────────────────────────────────────────────────────────


def test_off_by_default_every_breakpoint_is_five_minutes(ttl):
    controls = _cache_controls(_request())

    # Rules, profile, the history turn and the newest turn.
    assert len(controls) == 4
    assert all(c == {"type": "ephemeral"} for c in controls)


def test_on_only_the_rules_breakpoint_gets_one_hour(ttl):
    ttl(True)
    request = _request()
    controls = _cache_controls(request)

    assert request["system"][0]["text"] == lf._ADVISOR_SYSTEM_PREFIX
    assert controls[0] == {"type": "ephemeral", "ttl": "1h"}
    # Profile, history and the newest turn stay on 5 minutes, after the
    # 1-hour entry.
    assert controls[1:] == [{"type": "ephemeral"}] * 3


def test_on_the_longer_ttl_always_comes_first(ttl):
    ttl(True)
    ttls = [c.get("ttl") for c in _cache_controls(_request())]

    # Bedrock rejects a 1-hour entry after a 5-minute one.
    first_short = ttls.index(None)
    assert "1h" not in ttls[first_short:]


def test_the_shared_constants_are_never_mutated(ttl):
    ttl(True)
    request = _request()
    request["system"][0]["cache_control"]["ttl"] = "5m"
    request["system"][1]["cache_control"]["x"] = 1

    assert lf._CACHE_CONTROL_1H == {"type": "ephemeral", "ttl": "1h"}
    assert lf._CACHE_CONTROL == {"type": "ephemeral"}


# ── Fallback when Bedrock rejects the TTL ────────────────────────────────────


def test_off_a_validation_error_is_not_retried(ttl, monkeypatch):
    fake = _FakeBedrock(fail=1)
    monkeypatch.setattr(lf, "_bedrock", fake)

    resp = lf._advise_finance(json.loads(json.dumps(_PAYLOAD)))

    assert resp["statusCode"] == 502
    assert len(fake.bodies) == 1


def test_on_a_rejected_ttl_falls_back_and_warns(ttl, monkeypatch, capsys):
    ttl(True)
    fake = _FakeBedrock(fail=1)
    monkeypatch.setattr(lf, "_bedrock", fake)

    resp = lf._advise_finance(json.loads(json.dumps(_PAYLOAD)))

    assert resp["statusCode"] == 200
    assert json.loads(resp["body"])["response"] == "Nothing yet."
    assert _ttls(fake.bodies[0])[0] == "1h"
    assert _ttls(fake.bodies[1]) == [None, None]
    assert "WARNING advisor_cache_ttl_1h rejected" in capsys.readouterr().out
    # The container stays on 5 minutes from here on.
    assert lf._ttl_1h_rejected is True
    assert all(c == {"type": "ephemeral"} for c in _cache_controls(_request()))


def test_on_the_stream_falls_back_too(ttl, monkeypatch, capsys):
    ttl(True)
    fake = _FakeBedrock(fail=1)
    monkeypatch.setattr(lf, "_bedrock", fake)
    payload = json.loads(json.dumps(_PAYLOAD))
    request, _ = lf._build_advisor_request(payload)

    frames = [json.loads(f) for f in lf.advise_finance_stream(payload, request)]

    assert frames[-1]["type"] == "end"
    assert frames[-1]["response"] == "Nothing yet."
    assert _ttls(fake.bodies[1]) == [None, None]
    assert "WARNING advisor_cache_ttl_1h rejected" in capsys.readouterr().out


def test_on_another_error_is_not_retried(ttl, monkeypatch):
    ttl(True)
    fake = _FakeBedrock(fail=1, error=_ValidationError("ThrottlingException"))
    monkeypatch.setattr(lf, "_bedrock", fake)

    resp = lf._advise_finance(json.loads(json.dumps(_PAYLOAD)))

    assert resp["statusCode"] == 502
    assert len(fake.bodies) == 1
    assert lf._ttl_1h_rejected is False


def test_on_a_validation_error_that_is_not_the_ttl_keeps_the_ttl(ttl, monkeypatch):
    ttl(True)
    # Both calls fail: the TTL was not the problem.
    fake = _FakeBedrock(fail=2)
    monkeypatch.setattr(lf, "_bedrock", fake)

    resp = lf._advise_finance(json.loads(json.dumps(_PAYLOAD)))

    assert resp["statusCode"] == 502
    assert len(fake.bodies) == 2
    assert lf._ttl_1h_rejected is False
