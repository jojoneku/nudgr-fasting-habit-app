"""Tests for the allowlisted debug log (ADVISOR_DEBUG_USERS).

For a listed user, each hop prints one `advisor_debug` line with the text the
invocation log never carries: the question, the tool calls, the tool results
and the reply. It must still never carry the briefing, the profile, the
history, the tool descriptions or anything from the auth headers. For anyone
else nothing changes: test_invocation_log.py checks that no text reaches the
log.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x SUPABASE_URL=https://p.supabase.co \\
    SUPABASE_ANON_KEY=k python -m pytest test_debug_log.py -q
"""

import json

import pytest

import lambda_function as lf
from test_invocation_log import (  # noqa: F401 -- _supabase is a fixture
    SENTINELS,
    _USER,
    _FakeBedrock,
    _buffered,
    _reply,
    _stream_events,
    _streamed,
    _supabase,
)

# Never in a debug line, even for a listed user.
_NEVER = ("snapshot", "profile", "historical", "tool_description", "token",
          "nudgr_token", "apikey")


def _debug_lines(out):
    return [json.loads(line) for line in out.splitlines()
            if line.startswith("{") and f'"{lf._DEBUG_LOG}"' in line]


def _assert_debug_line(line):
    s = SENTINELS
    assert line["trace"] == "trace-abc123"
    assert line["hop"] == "cont"
    assert line["user_text"] == s["question"]
    assert line["tool_results"] == [
        {"status": "ok", "text": s["tool_result"]},
        {"status": "error", "text": s["tool_error"]},
    ]
    assert line["tool_calls"] == [
        {"name": "proposeTransaction", "input": {"note": s["reply_input"]}},
    ]
    assert line["reply_text"] == s["reply_text"]


def _assert_nothing_private(out):
    for name in _NEVER:
        assert SENTINELS[name] not in out, f"{name} reached the log"


_OTHER_USER = "00000000-0000-0000-0000-000000000000"


@pytest.mark.parametrize("users", [frozenset(), frozenset({_OTHER_USER})])
def test_an_unlisted_user_gets_no_debug_line(monkeypatch, capsys, users):
    monkeypatch.setattr(lf, "_ADVISOR_DEBUG_USERS", users)
    _buffered(monkeypatch, _FakeBedrock(reply=_reply()))
    assert _debug_lines(capsys.readouterr().out) == []


def test_a_listed_user_gets_the_text_on_the_buffered_path(monkeypatch, capsys):
    monkeypatch.setattr(lf, "_ADVISOR_DEBUG_USERS", frozenset({_USER}))
    resp = _buffered(monkeypatch, _FakeBedrock(reply=_reply()))
    out = capsys.readouterr().out

    assert resp["statusCode"] == 200
    lines = _debug_lines(out)
    assert len(lines) == 1
    _assert_debug_line(lines[0])
    _assert_nothing_private(out)


def test_a_listed_user_gets_the_text_on_the_streamed_path(monkeypatch, capsys):
    monkeypatch.setattr(lf, "_ADVISOR_DEBUG_USERS", frozenset({_USER}))
    sent = _streamed(monkeypatch, _FakeBedrock(events=_stream_events()))
    out = capsys.readouterr().out

    body = b"".join(m.get("body") or b"" for m in sent).decode()
    assert SENTINELS["reply_text"] in body
    lines = _debug_lines(out)
    assert len(lines) == 1
    _assert_debug_line(lines[0])
    _assert_nothing_private(out)


def test_the_allowlist_reads_ids_and_drops_anything_else(monkeypatch):
    monkeypatch.setenv("ADVISOR_DEBUG_USERS",
                       f" {_USER.upper()} , not-a-user, ,{_USER}")
    users = frozenset(
        u.strip().lower()
        for u in lf.os.environ["ADVISOR_DEBUG_USERS"].split(",")
        if lf._USER_ID_RE.fullmatch(u.strip())
    )
    assert users == {_USER}


def test_a_long_text_is_cut_with_the_count(monkeypatch):
    monkeypatch.setattr(lf, "_DEBUG_FIELD_MAX", 10)
    assert lf._debug_clip("x" * 25) == "x" * 10 + "... [15 more chars]"
    assert lf._debug_clip("short") == "short"
    assert lf._debug_input({"q": "y" * 40}).startswith('{"q": "yyy')


def test_a_broken_payload_never_breaks_the_reply(monkeypatch, capsys):
    monkeypatch.setattr(lf, "_ADVISOR_DEBUG_USERS", frozenset({_USER}))
    lf._debug_log(payload=None, calls=[], response_text="hi", user_id=_USER)
    assert "advisor_debug skipped" in capsys.readouterr().out
