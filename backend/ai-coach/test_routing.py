"""Tests for Haiku routing (Plan 065, phase 5).

The flag ships OFF, so the first thing to prove is that OFF changes nothing:
the same model id and the same request bytes as before, whatever `route` the
client sends. With the flag on, `route: "haiku"` runs on the route model and
every other value -- a missing or unknown one included -- on the advisor model.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x python -m pytest test_routing.py -q
"""

import io
import json

import pytest

import lambda_function as lf

SONNET_45 = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
HAIKU_45 = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
HAIKU_55 = "global.anthropic.claude-haiku-5-5"

_TEXT_REPLY = {"content": [{"type": "text", "text": "You have 1,000."}],
               "stop_reason": "end_turn", "usage": {}}
_STREAM_EVENTS = [
    {"type": "message_start", "message": {"usage": {"input_tokens": 10}}},
    {"type": "content_block_start", "index": 0,
     "content_block": {"type": "text", "text": ""}},
    {"type": "content_block_delta", "index": 0,
     "delta": {"type": "text_delta", "text": "You have 1,000."}},
    {"type": "content_block_stop", "index": 0},
    {"type": "message_delta", "delta": {"stop_reason": "end_turn"},
     "usage": {"output_tokens": 5}},
]


class _FakeBedrock:
    """Records the model id and the raw body bytes of each call."""

    def __init__(self):
        self.calls = []

    def invoke_model(self, *, modelId, body, **_):
        self.calls.append((modelId, body))
        return {"body": io.BytesIO(json.dumps(_TEXT_REPLY).encode())}

    def invoke_model_with_response_stream(self, *, modelId, body, **_):
        self.calls.append((modelId, body))
        return {"body": [{"chunk": {"bytes": json.dumps(e).encode()}}
                         for e in _STREAM_EVENTS]}


@pytest.fixture
def fake(monkeypatch):
    fake = _FakeBedrock()
    monkeypatch.setattr(lf, "_bedrock", fake)
    monkeypatch.setattr(lf, "_ADVISOR_MODEL_ID", SONNET_45)
    monkeypatch.setattr(lf, "_ADVISOR_ROUTE_MODEL_ID", HAIKU_45)
    return fake


def _payload(route=None):
    payload = {
        "messages": [{"role": "user", "text": "what is my cash balance?"}],
        "context": {"summary": "Cash: 1,000"},
    }
    if route is not None:
        payload["route"] = route
    return payload


def _buffered(payload):
    resp = lf._advise_finance(payload)
    assert resp["statusCode"] == 200


def _streamed(payload):
    request, err = lf._build_advisor_request(payload)
    assert err is None
    frames = [json.loads(f) for f in lf.advise_finance_stream(payload, request)]
    assert frames[-1]["type"] == "end"


_PATHS = [_buffered, _streamed]


# -- flag off: nothing changes -------------------------------------------------

def test_routing_is_off_by_default():
    # The module default, not a monkeypatched value: the flag ships off.
    assert lf._ADVISOR_HAIKU_ROUTING is False
    assert lf._ADVISOR_ROUTE_MODEL_ID == HAIKU_45


@pytest.mark.parametrize("path", _PATHS)
@pytest.mark.parametrize("route", ["haiku", "sonnet", "nonsense"])
def test_flag_off_request_is_byte_identical(fake, monkeypatch, path, route):
    monkeypatch.setattr(lf, "_ADVISOR_HAIKU_ROUTING", False)
    path(_payload())             # what an app before phase 5 sends
    path(_payload(route))
    (model_a, body_a), (model_b, body_b) = fake.calls
    assert model_a == model_b == SONNET_45
    assert body_a == body_b
    assert "route" not in json.loads(body_b)


# -- flag on -------------------------------------------------------------------

@pytest.mark.parametrize("path", _PATHS)
def test_flag_on_haiku_route_runs_on_the_route_model(fake, monkeypatch, path):
    monkeypatch.setattr(lf, "_ADVISOR_HAIKU_ROUTING", True)
    path(_payload("haiku"))
    model, body = fake.calls[0]
    assert model == HAIKU_45
    # Haiku 4.5 rejects the 5.5-only fields.
    sent = json.loads(body)
    assert "thinking" not in sent and "output_config" not in sent


@pytest.mark.parametrize("path", _PATHS)
@pytest.mark.parametrize("route", [None, "sonnet", "nonsense", "HAIKU", 1])
def test_flag_on_any_other_route_runs_on_the_advisor_model(
        fake, monkeypatch, path, route):
    monkeypatch.setattr(lf, "_ADVISOR_HAIKU_ROUTING", True)
    path(_payload(route))
    assert fake.calls[0][0] == SONNET_45


def test_route_model_is_a_setting(fake, monkeypatch):
    # Haiku 5.5 replaces Haiku 4.5 by config, and gets thinking turned off.
    monkeypatch.setattr(lf, "_ADVISOR_HAIKU_ROUTING", True)
    monkeypatch.setattr(lf, "_ADVISOR_ROUTE_MODEL_ID", HAIKU_55)
    _buffered(_payload("haiku"))
    model, body = fake.calls[0]
    assert model == HAIKU_55
    assert json.loads(body)["thinking"] == {"type": "disabled"}


# -- cost_line -----------------------------------------------------------------

@pytest.mark.parametrize("route,flag,want", [
    ("haiku", True, f"route=haiku model={HAIKU_45}"),
    ("haiku", False, f"route=haiku model={SONNET_45}"),
    ("sonnet", True, f"route=sonnet model={SONNET_45}"),
    (None, True, f"route=- model={SONNET_45}"),
    ("x y=1", True, f"route=other model={SONNET_45}"),
])
def test_cost_line_logs_route_and_model(fake, monkeypatch, capsys,
                                        route, flag, want):
    monkeypatch.setattr(lf, "_ADVISOR_HAIKU_ROUTING", flag)
    _buffered(_payload(route))
    line = next(l for l in capsys.readouterr().out.splitlines()
                if l.startswith("cost_line op=adviseFinance"))
    assert line.endswith(want)
