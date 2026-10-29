"""Tests for the advisor trace on the cost_line (Plan 065, phase 2).

The trace is ids, names, statuses and hashes. These tests pin each field, and
that no message text or finance figure reaches the log line.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x SUPABASE_URL=https://p.supabase.co \\
    SUPABASE_ANON_KEY=k python -m pytest test_trace.py -q
"""

import hashlib
import io
import json

import pytest

import lambda_function as lf

_TOOLS = [{
    "name": "findTransactions",
    "description": "Find transactions.",
    "input_schema": {"type": "object", "properties": {}},
}]

_SECRET_SNAPSHOT = "Cash on hand: P98,765"
_SECRET_QUESTION = "Can I afford the Batangas trip?"


class _FakeBedrock:
    def __init__(self, reply):
        self.reply = reply

    def invoke_model(self, **_):
        return {"body": io.BytesIO(json.dumps(self.reply).encode())}


def _reply(*tool_names):
    content = [{"type": "text", "text": "Checking."}]
    for i, name in enumerate(tool_names):
        content.append({"type": "tool_use", "id": f"call{i}", "name": name,
                        "input": {}})
    return {
        "content": content,
        "stop_reason": "tool_use" if tool_names else "end_turn",
        "usage": {"input_tokens": 10, "output_tokens": 5},
    }


def _payload(messages=None, **extra):
    return {
        "messages": messages or [{"role": "user", "text": _SECRET_QUESTION}],
        "context": {"summary": _SECRET_SNAPSHOT},
        "tools": _TOOLS,
        **extra,
    }


def _tool_loop(*results):
    """A first question, the model's tool_use turns, and the results so far."""
    messages = [{"role": "user", "text": _SECRET_QUESTION}]
    for i, blocks in enumerate(results):
        messages.append({"role": "assistant", "content_blocks": [
            {"type": "tool_use", "id": f"t{i}", "name": "findTransactions",
             "input": {}},
        ]})
        messages.append({"role": "user", "content_blocks": blocks})
    return messages


def _ok(tool_use_id):
    return {"type": "tool_result", "tool_use_id": tool_use_id, "content": "3 rows"}


def _error(tool_use_id):
    return {"type": "tool_result", "tool_use_id": tool_use_id,
            "content": "Unknown account id.", "is_error": True}


def _declined(tool_use_id):
    # The summary AiToolResult.declined sends (lib/models/ai_tool.dart).
    return {"type": "tool_result", "tool_use_id": tool_use_id,
            "content": "The user declined this change. Nothing was saved. Do not "
                       "retry the same proposal — ask what they would prefer instead.",
            "is_error": True}


def _cost_line(monkeypatch, capsys, payload, reply=None):
    monkeypatch.setattr(lf, "_bedrock", _FakeBedrock(reply or _reply()))
    lf._advise_finance(payload)
    lines = [l for l in capsys.readouterr().out.splitlines()
             if l.startswith("cost_line ")]
    assert len(lines) == 1
    return lines[0]


def _fields(line):
    return dict(part.split("=", 1) for part in line.split()[1:])


def test_the_trace_id_is_logged(monkeypatch, capsys):
    line = _cost_line(monkeypatch, capsys, _payload(trace_id="a1b2c3d4e5f6"))

    assert _fields(line)["trace"] == "a1b2c3d4e5f6"


@pytest.mark.parametrize("bad", [None, "", "x" * 65, "abc def", "a\nb", 7])
def test_a_missing_or_unsafe_trace_id_is_a_dash(monkeypatch, capsys, bad):
    payload = _payload() if bad is None else _payload(trace_id=bad)
    line = _cost_line(monkeypatch, capsys, payload)

    assert _fields(line)["trace"] == "-"
    assert "\n" not in line


def test_the_reply_tool_names_are_logged_in_order(monkeypatch, capsys):
    line = _cost_line(monkeypatch, capsys, _payload(),
                      _reply("findTransactions", "proposeTransaction"))

    fields = _fields(line)
    assert fields["tool_names"] == "findTransactions,proposeTransaction"
    assert fields["calls"] == "2"


def test_a_reply_with_no_tools_logs_a_dash(monkeypatch, capsys):
    fields = _fields(_cost_line(monkeypatch, capsys, _payload()))

    assert fields["tool_names"] == "-"
    assert fields["results"] == "-"
    assert fields["hops"] == "0"


def test_each_newest_result_gets_its_status(monkeypatch, capsys):
    messages = _tool_loop([_ok("t0")], [_ok("t1"), _error("t1b"), _declined("t1c")])
    fields = _fields(_cost_line(monkeypatch, capsys, _payload(messages)))

    # Only the newest turn's results: the first hop already logged its own.
    assert fields["results"] == "ok,error,declined"
    assert fields["hops"] == "2"
    assert fields["hop"] == "cont"


def test_a_result_with_block_content_is_read_too(monkeypatch, capsys):
    declined = _declined("t0")
    declined["content"] = [{"type": "text", "text": declined["content"]}]
    fields = _fields(_cost_line(monkeypatch, capsys,
                                _payload(_tool_loop([declined]))))

    assert fields["results"] == "declined"


def test_the_hashes_are_short_sha256_of_each_part(monkeypatch, capsys):
    fields = _fields(_cost_line(monkeypatch, capsys, _payload()))

    def sha8(text):
        return hashlib.sha256(text.encode("utf-8")).hexdigest()[:8]

    assert fields["h_rules"] == sha8(lf._ADVISOR_SYSTEM_PREFIX)
    assert fields["h_tools"] == sha8(json.dumps(_TOOLS))
    assert len(fields["h_snapshot"]) == 8


def test_a_snapshot_edit_changes_only_the_snapshot_hash(monkeypatch, capsys):
    before = _fields(_cost_line(monkeypatch, capsys, _payload()))
    edited = _payload()
    edited["context"]["summary"] = "Cash on hand: P98,766"
    after = _fields(_cost_line(monkeypatch, capsys, edited))

    assert before["h_rules"] == after["h_rules"]
    assert before["h_tools"] == after["h_tools"]
    assert before["h_snapshot"] != after["h_snapshot"]


def test_no_tools_logs_a_dash_for_the_tools_hash(monkeypatch, capsys):
    payload = _payload()
    del payload["tools"]
    fields = _fields(_cost_line(monkeypatch, capsys, payload))

    assert fields["h_tools"] == "-"


def test_no_message_text_or_finance_figure_reaches_the_log(monkeypatch, capsys):
    line = _cost_line(monkeypatch, capsys,
                      _payload(_tool_loop([_declined("t0")]), trace_id="abc"))

    assert "98,765" not in line
    assert "Batangas" not in line
    assert "declined this change" not in line
    assert "Checking." not in line


def test_the_streamed_path_logs_the_same_trace(monkeypatch, capsys):
    events = [
        {"type": "message_start", "message": {"usage": {"input_tokens": 10}}},
        {"type": "content_block_start", "index": 0,
         "content_block": {"type": "tool_use", "id": "c0",
                           "name": "findTransactions"}},
        {"type": "content_block_delta", "index": 0,
         "delta": {"type": "input_json_delta", "partial_json": "{}"}},
        {"type": "content_block_stop", "index": 0},
        {"type": "message_delta", "delta": {"stop_reason": "tool_use"},
         "usage": {"output_tokens": 3}},
    ]

    class _Stream:
        def invoke_model_with_response_stream(self, **_):
            return {"body": [{"chunk": {"bytes": json.dumps(e).encode()}}
                             for e in events]}

    monkeypatch.setattr(lf, "_bedrock", _Stream())
    payload = _payload(_tool_loop([_ok("t0")]), trace_id="trace-1")
    request, err = lf._build_advisor_request(payload)
    assert err is None
    list(lf.advise_finance_stream(payload, request))
    line = next(l for l in capsys.readouterr().out.splitlines()
                if l.startswith("cost_line "))
    fields = _fields(line)

    assert fields["trace"] == "trace-1"
    assert fields["tool_names"] == "findTransactions"
    assert fields["results"] == "ok"
    assert fields["hops"] == "1"
