"""Tests for the advisor invocation log (Plan 065, phase 5).

One `advisor_invocation` JSON line per advisor invocation, metadata only. The
main test sends a request where every user-controlled string is a sentinel --
message text, snapshot, profile, history, tool inputs, tool results, the
model's own reply, and the auth headers -- and asserts that no sentinel
reaches stdout (which is what CloudWatch keeps), on both transports.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x SUPABASE_URL=https://p.supabase.co \\
    SUPABASE_ANON_KEY=k python -m pytest test_invocation_log.py -q
"""

import asyncio
import io
import json

import pytest

import app as advisor_app
import lambda_function as lf

_USER = "0b7c2f8e-3d1a-4c5b-9e6f-112233445566"

# Every string a log line must never carry. Each one is unique, so a hit
# names the leak.
SENTINELS = {
    "question": "SENTINEL_QUESTION_Batangas",
    "earlier": "SENTINEL_EARLIER_ASSISTANT_TEXT",
    "snapshot": "SENTINEL_SNAPSHOT_P98765",
    "profile": "SENTINEL_PROFILE_saving_for_car",
    "historical": "SENTINEL_HISTORY_P12345",
    "tool_input": "SENTINEL_TOOL_INPUT_Meralco",
    "tool_result": "SENTINEL_TOOL_RESULT_3_rows",
    "tool_error": "SENTINEL_TOOL_ERROR_unknown_account",
    "tool_description": "SENTINEL_TOOL_DESCRIPTION",
    "reply_text": "SENTINEL_REPLY_TEXT",
    "reply_input": "SENTINEL_REPLY_TOOL_INPUT",
    "token": "SENTINEL_BEARER_TOKEN",
    "nudgr_token": "SENTINEL_NUDGR_TOKEN",
    "apikey": "SENTINEL_SUPABASE_ANON_KEY",
}


def _payload():
    s = SENTINELS
    return {
        "trace_id": "trace-abc123",
        "context": {
            "summary": s["snapshot"],
            "profile": s["profile"],
            "historical": s["historical"],
        },
        "tools": [{
            "name": "findTransactions",
            "description": s["tool_description"],
            "input_schema": {"type": "object", "properties": {}},
        }],
        "messages": [
            {"role": "user", "text": s["question"]},
            {"role": "assistant", "text": s["earlier"], "content_blocks": [
                {"type": "text", "text": s["earlier"]},
                {"type": "tool_use", "id": "t0", "name": "findTransactions",
                 "input": {"query": s["tool_input"]}},
                {"type": "tool_use", "id": "t1", "name": "findTransactions",
                 "input": {"query": s["tool_input"]}},
            ]},
            {"role": "user", "text": "", "content_blocks": [
                {"type": "tool_result", "tool_use_id": "t0",
                 "content": s["tool_result"]},
                {"type": "tool_result", "tool_use_id": "t1",
                 "content": [{"type": "text", "text": s["tool_error"]}],
                 "is_error": True},
            ]},
        ],
    }


def _reply():
    return {
        "content": [
            {"type": "text", "text": SENTINELS["reply_text"]},
            {"type": "tool_use", "id": "c0", "name": "proposeTransaction",
             "input": {"note": SENTINELS["reply_input"]}},
        ],
        "stop_reason": "tool_use",
        "usage": {"input_tokens": 120, "output_tokens": 30,
                  "cache_read_input_tokens": 9000,
                  "cache_creation_input_tokens": 400},
    }


def _stream_events(reply_input_fragment=None):
    fragment = reply_input_fragment if reply_input_fragment is not None \
        else json.dumps({"note": SENTINELS["reply_input"]})
    return [
        {"type": "message_start", "message": {"usage": {
            "input_tokens": 120, "cache_read_input_tokens": 9000,
            "cache_creation_input_tokens": 400}}},
        {"type": "content_block_start", "index": 0,
         "content_block": {"type": "text", "text": ""}},
        {"type": "content_block_delta", "index": 0,
         "delta": {"type": "text_delta", "text": SENTINELS["reply_text"]}},
        {"type": "content_block_stop", "index": 0},
        {"type": "content_block_start", "index": 1,
         "content_block": {"type": "tool_use", "id": "c0",
                           "name": "proposeTransaction"}},
        {"type": "content_block_delta", "index": 1,
         "delta": {"type": "input_json_delta", "partial_json": fragment}},
        {"type": "content_block_stop", "index": 1},
        {"type": "message_delta", "delta": {"stop_reason": "tool_use"},
         "usage": {"output_tokens": 30}},
    ]


class _FakeBedrock:
    def __init__(self, reply=None, events=None, error=None):
        self.reply, self.events, self.error = reply, events, error

    def invoke_model(self, **_):
        if self.error:
            raise self.error
        return {"body": io.BytesIO(json.dumps(self.reply).encode())}

    def invoke_model_with_response_stream(self, **_):
        if self.error:
            raise self.error
        return {"body": [{"chunk": {"bytes": json.dumps(e).encode()}}
                         for e in self.events]}


class ThrottlingException(Exception):
    """Stands in for botocore's generated exception class of the same name."""


@pytest.fixture(autouse=True)
def _supabase(monkeypatch):
    """The real rate-limit code, against a fake PostgREST that answers 3."""
    monkeypatch.setattr(lf, "_SUPABASE_URL", "https://p.supabase.co")
    monkeypatch.setattr(lf, "_SUPABASE_ANON_KEY", SENTINELS["apikey"])

    class _Resp(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    monkeypatch.setattr(lf.urllib.request, "urlopen",
                        lambda req, timeout=None: _Resp(b"3"))


def _buffered(monkeypatch, bedrock, payload=None):
    monkeypatch.setattr(lf, "_bedrock", bedrock)
    event = {
        "headers": {
            "authorization": f"Bearer {SENTINELS['token']}",
            "x-nudgr-authorization": f"Bearer {SENTINELS['nudgr_token']}",
        },
        "requestContext": {"authorizer": {"jwt": {"claims": {"sub": _USER}}}},
        "body": json.dumps({"op": "adviseFinance",
                            "payload": payload or _payload()}),
    }
    return lf.lambda_handler(event, None)


def _streamed(monkeypatch, bedrock, payload=None):
    monkeypatch.setattr(lf, "_bedrock", bedrock)
    monkeypatch.setattr(advisor_app, "verify_supabase_token",
                        lambda token: {"sub": _USER})
    body = json.dumps({"op": "adviseFinance",
                       "payload": payload or _payload()}).encode()
    scope = {
        "type": "http", "method": "POST", "path": "/v1/advisor",
        "headers": [
            (b"authorization", f"Bearer {SENTINELS['token']}".encode()),
            (b"x-nudgr-authorization",
             f"Bearer {SENTINELS['nudgr_token']}".encode()),
        ],
    }

    async def receive():
        return {"type": "http.request", "body": body, "more_body": False}

    sent = []

    async def send(message):
        sent.append(message)

    asyncio.run(advisor_app.app(scope, receive, send))
    return sent


def _invocation_lines(out):
    lines = []
    for line in out.splitlines():
        if line.startswith("{") and lf._INVOCATION_LOG in line:
            lines.append(json.loads(line))
    return lines


def _assert_no_sentinel(out):
    for name, value in SENTINELS.items():
        assert value not in out, f"{name} reached the log"


# -- Nothing user-controlled reaches the log ---------------------------------

def test_the_buffered_path_logs_no_text_and_no_auth(monkeypatch, capsys):
    resp = _buffered(monkeypatch, _FakeBedrock(reply=_reply()))
    out = capsys.readouterr().out

    assert resp["statusCode"] == 200
    _assert_no_sentinel(out)
    assert len(_invocation_lines(out)) == 1


def test_the_streamed_path_logs_no_text_and_no_auth(monkeypatch, capsys):
    sent = _streamed(monkeypatch, _FakeBedrock(events=_stream_events()))
    out = capsys.readouterr().out

    body = b"".join(m.get("body") or b"" for m in sent).decode()
    assert SENTINELS["reply_text"] in body  # the user still gets the reply
    _assert_no_sentinel(out)
    assert len(_invocation_lines(out)) == 1


def test_an_unparseable_tool_input_logs_its_length_only(monkeypatch, capsys):
    broken = '{"note": "' + SENTINELS["reply_input"]
    _streamed(monkeypatch, _FakeBedrock(events=_stream_events(broken)))
    out = capsys.readouterr().out

    _assert_no_sentinel(out)
    assert f"{len(broken)} chars" in out


@pytest.mark.parametrize("path", ["buffered", "streamed"])
def test_a_bedrock_error_logs_its_class_only(monkeypatch, capsys, path):
    bedrock = _FakeBedrock(error=ThrottlingException("Rate exceeded"))
    if path == "buffered":
        _buffered(monkeypatch, bedrock)
    else:
        _streamed(monkeypatch, bedrock)
    out = capsys.readouterr().out

    _assert_no_sentinel(out)
    [log] = _invocation_lines(out)
    assert log["error_class"] == "ThrottlingException"
    assert log["trace"] == "trace-abc123"
    assert log["hop"] == "cont"
    assert log["hops"] == 1
    assert log["user"] == _USER
    assert log["stream"] is (path == "streamed")
    assert "Rate exceeded" not in json.dumps(log)


# -- The fields ----------------------------------------------------------------

def test_the_buffered_log_carries_the_metadata(monkeypatch, capsys):
    _buffered(monkeypatch, _FakeBedrock(reply=_reply()))
    [log] = _invocation_lines(capsys.readouterr().out)

    assert log["event"] == "advisor_invocation"
    assert log["op"] == "adviseFinance"
    assert log["trace"] == "trace-abc123"
    assert log["user"] == _USER
    assert log["stream"] is False
    assert log["model"] == lf._ADVISOR_MODEL_ID
    assert log["route"] is None
    assert log["hop"] == "cont"
    assert log["hops"] == 1
    assert log["in_tokens"] == 120
    assert log["out_tokens"] == 30
    assert log["cache_read"] == 9000
    assert log["cache_write"] == 400
    assert isinstance(log["latency_ms"], int)
    assert log["stop"] == "tool_use"
    assert log["tool_names"] == ["proposeTransaction"]
    assert log["results"] == ["ok", "error"]
    assert log["error_class"] is None
    for key in ("h_rules", "h_snapshot", "h_tools"):
        assert len(log[key]) == 8


def test_the_streamed_log_carries_time_to_first_token(monkeypatch, capsys):
    _streamed(monkeypatch, _FakeBedrock(events=_stream_events()))
    [log] = _invocation_lines(capsys.readouterr().out)

    assert log["stream"] is True
    assert isinstance(log["ttft_ms"], int)
    assert log["tool_names"] == ["proposeTransaction"]
    assert log["cache_read"] == 9000
    assert log["out_tokens"] == 30


def test_the_json_line_matches_the_cost_line(monkeypatch, capsys):
    _buffered(monkeypatch, _FakeBedrock(reply=_reply()))
    out = capsys.readouterr().out
    cost_line = next(l for l in out.splitlines() if l.startswith("cost_line "))
    [log] = _invocation_lines(out)

    # The cost_line text format is unchanged, and every field of it is in
    # the JSON line.
    for part in cost_line.split()[1:]:
        key, _, _ = part.partition("=")
        assert key in log


@pytest.mark.parametrize("user_id", [None, "user-123", "x" * 36 + "\n", 7])
def test_a_user_id_that_is_not_a_uuid_is_null(capsys, user_id):
    lf._invocation_log({"op": "adviseFinance"}, user_id=user_id)
    [log] = _invocation_lines(capsys.readouterr().out)

    assert log["user"] is None


def test_cost_fields_types_each_value():
    fields = lf._cost_fields(
        "cost_line op=adviseFinance in_tokens=12 ttft_ms=-1 trace=- "
        "tool_names=a,b results=- stop=end_turn")

    assert fields == {
        "op": "adviseFinance", "in_tokens": 12, "ttft_ms": -1, "trace": None,
        "tool_names": ["a", "b"], "results": [], "stop": "end_turn",
    }
