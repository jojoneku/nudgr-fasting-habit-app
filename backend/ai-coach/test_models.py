"""Tests for the model-aware request body (Plan 064).

The migration to the 5.5 models is an env-var flip on a live function, so the
code has to be right for BOTH sides of it: the old models must get exactly the
body they got before, and the new ones must get thinking turned off and have
their reply read by block type.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x SUPABASE_URL=https://p.supabase.co \\
    SUPABASE_ANON_KEY=k python -m pytest test_models.py -q
"""

import io
import json

import pytest

import lambda_function as lf

HAIKU_3 = "anthropic.claude-3-haiku-20240307-v1:0"
# What production actually ran before Plan 064 (the template said Claude 3 Haiku).
HAIKU_45 = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
HAIKU_55 = "global.anthropic.claude-haiku-5-5"
SONNET_45 = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"


class _FakeBedrock:
    """Records each request body and answers with a canned reply."""

    def __init__(self, reply):
        self.reply = reply
        self.bodies = []

    def invoke_model(self, *, modelId, body, **_):
        self.bodies.append(json.loads(body))
        return {"body": io.BytesIO(json.dumps(self.reply).encode())}


def _install(monkeypatch, model_id, reply):
    fake = _FakeBedrock(reply)
    monkeypatch.setattr(lf, "_bedrock", fake)
    monkeypatch.setattr(lf, "_MODEL_ID", model_id)
    return fake


def _thinking_then_text(text):
    return {
        "content": [
            {"type": "thinking", "thinking": "", "signature": "sig"},
            {"type": "text", "text": text},
        ],
        "stop_reason": "end_turn",
    }


_REFUSAL = {"content": [], "stop_reason": "refusal"}


# -- _generation_params --------------------------------------------------------

@pytest.mark.parametrize("model_id", [HAIKU_3, HAIKU_45, SONNET_45, "x"])
def test_older_models_get_no_extra_fields(model_id):
    assert lf._generation_params(model_id, "low") == {}


def test_haiku_5_5_turns_thinking_off_and_sets_effort():
    assert lf._generation_params(HAIKU_55, "low") == {
        "thinking": {"type": "disabled"},
        "output_config": {"effort": "low"},
    }


# -- _reply_text ---------------------------------------------------------------

def test_reply_text_skips_a_leading_thinking_block():
    assert lf._reply_text(_thinking_then_text(" hi ")) == "hi"


def test_reply_text_is_empty_on_a_refusal():
    assert lf._reply_text(_REFUSAL) == ""


# -- call sites ----------------------------------------------------------------

def test_old_model_body_is_unchanged(monkeypatch):
    fake = _install(monkeypatch, HAIKU_45, {
        "content": [{"type": "text", "text": '{"foodId": "f1", "confidence": 0.9}'}],
    })
    resp = lf._disambiguate_food({"query": "rice", "candidates": [{"id": "f1", "name": "Rice"}]})
    assert resp["statusCode"] == 200
    assert "thinking" not in fake.bodies[0]
    assert "output_config" not in fake.bodies[0]


def test_new_model_json_op_reads_past_thinking(monkeypatch):
    fake = _install(monkeypatch, HAIKU_55,
                    _thinking_then_text('{"foodId": "f1", "confidence": 0.9}'))
    resp = lf._disambiguate_food({"query": "rice", "candidates": [{"id": "f1", "name": "Rice"}]})
    assert json.loads(resp["body"]) == {"foodId": "f1", "confidence": 0.9}
    assert fake.bodies[0]["thinking"] == {"type": "disabled"}


def test_a_refused_json_op_returns_its_fallback(monkeypatch):
    _install(monkeypatch, HAIKU_55, _REFUSAL)
    resp = lf._disambiguate_food({"query": "rice", "candidates": [{"id": "f1", "name": "Rice"}]})
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"]) == {"foodId": None, "confidence": 0.0}


def test_respond_reads_past_thinking(monkeypatch):
    _install(monkeypatch, HAIKU_55, _thinking_then_text("Keep going!"))
    resp = lf._respond({"messages": [{"role": "user", "text": "hi"}]})
    assert json.loads(resp["body"]) == {"response": "Keep going!"}


def test_a_refused_respond_is_never_a_blank_bubble(monkeypatch):
    _install(monkeypatch, HAIKU_55, _REFUSAL)
    resp = lf._respond({"messages": [{"role": "user", "text": "hi"}]})
    assert json.loads(resp["body"])["response"] == lf._RESPOND_FALLBACK


def test_classify_finance_sends_thinking_off(monkeypatch):
    fake = _install(monkeypatch, HAIKU_55, _thinking_then_text("[]"))
    resp = lf._classify_finance({"prompt": "spent 100 on lunch"})
    assert json.loads(resp["body"]) == {"text": "[]"}
    assert fake.bodies[0]["output_config"] == {"effort": lf._EFFORT}


# -- advisor (Sonnet 5.5) ------------------------------------------------------

SONNET_55 = "global.anthropic.claude-sonnet-5-5"


def test_sonnet_5_5_uses_between_tools_not_disabled():
    assert lf._generation_params(SONNET_55, "medium") == {
        "thinking": {"type": "between_tools"},
        "output_config": {"effort": "medium"},
    }


def _advisor_payload(messages):
    return {"messages": messages, "context": {"summary": "Cash: 1,000"}}


def test_replayed_thinking_blocks_are_stripped():
    request, err = lf._build_advisor_request(_advisor_payload([
        {"role": "user", "text": "what can I spend?"},
        {"role": "assistant", "content_blocks": [
            {"type": "thinking", "thinking": "checking", "signature": "s"},
            {"type": "tool_use", "id": "t1", "name": "get_balance", "input": {}},
        ]},
        {"role": "user", "content_blocks": [
            {"type": "tool_result", "tool_use_id": "t1", "content": "1000"},
        ]},
    ]))
    assert err is None
    assistant = request["messages"][1]["content"]
    assert [b["type"] for b in assistant] == ["tool_use"]


def test_a_thinking_only_turn_falls_back_to_its_text():
    request, _ = lf._build_advisor_request(_advisor_payload([
        {"role": "user", "text": "hi"},
        {"role": "assistant", "text": "Hello.", "content_blocks": [
            {"type": "thinking", "thinking": "", "signature": "s"},
        ]},
        {"role": "user", "text": "thanks"},
    ]))
    assert request["messages"][1]["content"] == "Hello."


class _FakeAdvisorBedrock(_FakeBedrock):
    def __init__(self, reply=None, events=()):
        super().__init__(reply)
        self.events = events

    def invoke_model_with_response_stream(self, *, modelId, body, **_):
        self.bodies.append(json.loads(body))
        return {"body": [{"chunk": {"bytes": json.dumps(e).encode()}}
                         for e in self.events]}


def _install_advisor(monkeypatch, fake):
    monkeypatch.setattr(lf, "_bedrock", fake)
    monkeypatch.setattr(lf, "_ADVISOR_MODEL_ID", SONNET_55)
    return fake


def test_buffered_advisor_returns_no_thinking_blocks(monkeypatch):
    fake = _install_advisor(monkeypatch, _FakeAdvisorBedrock({
        "content": [
            {"type": "thinking", "thinking": "note", "signature": "s"},
            {"type": "text", "text": "You can spend 400."},
        ],
        "stop_reason": "end_turn",
    }))
    resp = lf._advise_finance(_advisor_payload([{"role": "user", "text": "hi"}]))
    body = json.loads(resp["body"])
    assert body["response"] == "You can spend 400."
    assert [b["type"] for b in body["assistant_content"]] == ["text"]
    assert fake.bodies[0]["thinking"] == {"type": "between_tools"}


def test_buffered_advisor_refusal_is_never_blank(monkeypatch):
    _install_advisor(monkeypatch, _FakeAdvisorBedrock(_REFUSAL))
    resp = lf._advise_finance(_advisor_payload([{"role": "user", "text": "hi"}]))
    body = json.loads(resp["body"])
    assert body["response"] == lf._ADVISOR_REFUSAL
    assert body["truncated"] is False


def test_streamed_thinking_never_reaches_the_user(monkeypatch):
    _install_advisor(monkeypatch, _FakeAdvisorBedrock(events=[
        {"type": "message_start", "message": {"usage": {"input_tokens": 10}}},
        {"type": "content_block_start", "index": 0,
         "content_block": {"type": "thinking", "thinking": ""}},
        {"type": "content_block_delta", "index": 0,
         "delta": {"type": "thinking_delta", "thinking": "a note"}},
        {"type": "content_block_delta", "index": 0,
         "delta": {"type": "signature_delta", "signature": "s"}},
        {"type": "content_block_stop", "index": 0},
        {"type": "content_block_start", "index": 1,
         "content_block": {"type": "text", "text": ""}},
        {"type": "content_block_delta", "index": 1,
         "delta": {"type": "text_delta", "text": "Hello."}},
        {"type": "content_block_stop", "index": 1},
        {"type": "message_delta", "delta": {"stop_reason": "end_turn"},
         "usage": {"output_tokens": 5}},
    ]))
    payload = _advisor_payload([{"role": "user", "text": "hi"}])
    request, _ = lf._build_advisor_request(payload)
    frames = [json.loads(f) for f in lf.advise_finance_stream(payload, request)]

    assert [f["text"] for f in frames if f["type"] == "delta"] == ["Hello."]
    end = frames[-1]
    assert end["type"] == "end"
    assert end["response"] == "Hello."
    assert [b["type"] for b in end["assistant_content"]] == ["text"]
