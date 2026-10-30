"""Tests for op=logEvent, the app's client events (Plan 065, phase 5).

An event is checked against an allow-list of names and fields (numbers, enum
values and ids only), does not count against the daily AI cap, has its own
daily limit, and is written as one `client_event` JSON line.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x SUPABASE_URL=https://p.supabase.co \\
    SUPABASE_ANON_KEY=k python -m pytest test_log_event.py -q
"""

import json

import pytest

import lambda_function as lf

_USER = "0b7c2f8e-3d1a-4c5b-9e6f-112233445566"


@pytest.fixture(autouse=True)
def _fresh_limit(monkeypatch):
    monkeypatch.setattr(lf, "_client_event_counts", {"day": None, "users": {}})


@pytest.fixture
def cap_calls(monkeypatch):
    """Counts calls to the AI usage cap; a client event must make none."""
    calls = {"n": 0}

    def counted(token):
        calls["n"] += 1
        return True, 1

    monkeypatch.setattr(lf, "_check_rate_limit", counted)
    return calls


@pytest.fixture(autouse=True)
def _no_bedrock(monkeypatch):
    def explode(*a, **k):
        raise AssertionError("a client event must not call the model")

    monkeypatch.setattr(lf._bedrock, "invoke_model", explode, raising=False)


def _send(payload, user=_USER):
    event = {
        "headers": {"authorization": "Bearer t"},
        "requestContext": {"authorizer": {"jwt": {"claims": {"sub": user}}}},
        "body": json.dumps({"op": "logEvent", "payload": payload}),
    }
    return lf.lambda_handler(event, None)


def _event_lines(out):
    return [json.loads(l) for l in out.splitlines()
            if l.startswith("{") and lf._CLIENT_EVENT_LOG in l]


def test_a_valid_event_is_one_json_line(capsys, cap_calls):
    resp = _send({
        "event": "batch_answered",
        "trace_id": "a1b2c3d4e5f6a7b8",
        "fields": {"approved": 2, "declined": 0, "revised": 0, "removed": 1,
                   "failed": 0},
    })

    assert resp["statusCode"] == 200
    [line] = _event_lines(capsys.readouterr().out)
    assert line == {
        "event": "client_event",
        "name": "batch_answered",
        "trace": "a1b2c3d4e5f6a7b8",
        "user": _USER,
        "fields": {"approved": 2, "declined": 0, "revised": 0, "removed": 1,
                   "failed": 0},
    }


def test_an_event_does_not_count_against_the_ai_cap(cap_calls):
    for _ in range(3):
        assert _send({"event": "ask_nudgy_tapped"})["statusCode"] == 200

    assert cap_calls["n"] == 0


@pytest.mark.parametrize("payload", [
    {"event": "batch_opened", "fields": {"items": 3}},
    {"event": "stop_pressed", "trace_id": "t-1", "fields": {"phase": "batch"}},
    {"event": "ask_nudgy_tapped"},
    {"event": "batch_resumed", "trace_id": "t-1",
     "fields": {"items": 1, "outcome": "not_reviewed"}},
])
def test_each_allowed_event_is_accepted(cap_calls, payload):
    assert _send(payload)["statusCode"] == 200


SENTINEL = "SENTINEL_USER_TEXT_Meralco"


@pytest.mark.parametrize("payload", [
    {"event": "something_else"},
    {"event": None},
    {},
    {"event": "batch_opened", "fields": {"items": 3, "note": SENTINEL}},
    {"event": "batch_opened", "fields": {"items": SENTINEL}},
    {"event": "batch_opened", "fields": {"items": "3"}},
    {"event": "batch_opened", "fields": {"items": 2.5}},
    {"event": "batch_opened", "fields": {"items": True}},
    {"event": "batch_opened", "fields": {"items": -1}},
    {"event": "batch_opened", "fields": {"items": 1001}},
    {"event": "batch_opened", "fields": [3]},
    {"event": "stop_pressed", "fields": {"phase": SENTINEL}},
    {"event": "ask_nudgy_tapped", "trace_id": SENTINEL + " with spaces"},
    {"event": "ask_nudgy_tapped", "trace_id": 7},
])
def test_anything_off_the_allow_list_is_rejected_and_not_logged(
        capsys, cap_calls, payload):
    resp = _send(payload)
    out = capsys.readouterr().out

    assert resp["statusCode"] == 400
    assert json.loads(resp["body"])["error"] == "invalid_event"
    assert _event_lines(out) == []
    assert SENTINEL not in out


def test_a_payload_that_is_not_an_object_is_rejected(cap_calls):
    assert _send("batch_opened")["statusCode"] == 400


def test_the_daily_limit_is_per_user(monkeypatch, cap_calls):
    monkeypatch.setattr(lf, "_CLIENT_EVENT_DAILY_LIMIT", 2)
    other = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    assert _send({"event": "ask_nudgy_tapped"})["statusCode"] == 200
    assert _send({"event": "ask_nudgy_tapped"})["statusCode"] == 200
    assert _send({"event": "ask_nudgy_tapped"})["statusCode"] == 429
    assert _send({"event": "ask_nudgy_tapped"}, user=other)["statusCode"] == 200


def test_the_limit_starts_again_on_a_new_day(monkeypatch, cap_calls):
    monkeypatch.setattr(lf, "_CLIENT_EVENT_DAILY_LIMIT", 1)
    assert _send({"event": "ask_nudgy_tapped"})["statusCode"] == 200
    assert _send({"event": "ask_nudgy_tapped"})["statusCode"] == 429

    lf._client_event_counts["day"] = "2000-01-01"
    assert _send({"event": "ask_nudgy_tapped"})["statusCode"] == 200


def test_an_unauthenticated_event_is_401(cap_calls):
    event = {"body": json.dumps({"op": "logEvent",
                                 "payload": {"event": "ask_nudgy_tapped"}})}
    assert lf.lambda_handler(event, None)["statusCode"] == 401


def test_every_allowed_field_is_a_count_or_an_enum():
    # The allow-list itself must hold no free-text field.
    for fields in lf._CLIENT_EVENTS.values():
        for kind in fields.values():
            assert kind == lf._COUNT or (
                isinstance(kind, tuple)
                and all(isinstance(v, str) and v.isidentifier() for v in kind))
