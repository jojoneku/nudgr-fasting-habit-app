"""Tests for the advisor's prompt-cache layout (Plan 065, phase 5).

The prompt runs: tools + rules (breakpoint 1), the profile (breakpoint 2),
the chat history (breakpoint 3, on the second-to-last user turn), then the
briefing -- snapshot and historical record -- at the end of the user turn that opened
this turn, uncached. A ledger edit changes only the briefing, so everything
ahead of it stays cached. These tests pin the layout, because a later edit
that moves the briefing back would still work and only show up as a bigger
bill.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x SUPABASE_URL=https://p.supabase.co \\
    SUPABASE_ANON_KEY=k python -m pytest test_cache.py -q
"""

import copy

import pytest

import lambda_function as lf

# Bedrock rejects a request with more than this many cache_control markers.
_BEDROCK_MAX_BREAKPOINTS = 4

_TOOLS = [{
    "name": "findTransactions",
    "description": "Find transactions.",
    "input_schema": {"type": "object", "properties": {}},
}]


def _payload(summary="Cash: P1,000", historical="Jan: P500",
             profile="Paid on the 15th.", messages=None, **extra):
    return {
        "messages": messages or [{"role": "user", "text": "How am I doing?"}],
        "context": {"summary": summary, "profile": profile,
                    "historical": historical},
        "tools": _TOOLS,
        **extra,
    }


def _build(payload):
    request, err = lf._build_advisor_request(copy.deepcopy(payload))
    assert err is None
    return request


def _breakpoints(request):
    """Every cache_control marker in the request, as (where, index) pairs."""
    found = []
    for i, block in enumerate(request["system"]):
        if "cache_control" in block:
            found.append(("system", i))
    for i, tool in enumerate(request["tools"] or []):
        if "cache_control" in tool:
            found.append(("tools", i))
    for i, m in enumerate(request["messages"]):
        content = m.get("content")
        if isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and "cache_control" in block:
                    found.append(("messages", i))
    return found


def _canonical(messages):
    """`messages` as the model reads them: breakpoints off, strings as blocks.

    A breakpoint marks where a prefix ends; it is not part of the prefix. A
    string turn and a turn of one text block are the same prompt, and
    _mark_conversation_cache turns the one into the other when a breakpoint
    lands on it.
    """
    out = []
    for m in copy.deepcopy(messages):
        content = m["content"]
        if isinstance(content, str):
            content = [{"type": "text", "text": content}]
        for block in content:
            block.pop("cache_control", None)
        out.append({"role": m["role"], "content": content})
    return out


def _is_briefing(block):
    return (isinstance(block, dict) and block.get("type") == "text"
            and block.get("text", "").startswith("<briefing>"))


def _briefing_turns(request):
    """Indexes of the messages that carry a briefing block."""
    return [i for i, m in enumerate(request["messages"])
            if isinstance(m["content"], list)
            and any(_is_briefing(b) for b in m["content"])]


# A conversation two turns in: the user's third message is the newest.
_HISTORY = [
    {"role": "user", "text": "How am I doing?"},
    {"role": "assistant", "text": "You have P1,000 in cash."},
    {"role": "user", "text": "And my savings?"},
    {"role": "assistant", "text": "Nothing saved yet this month."},
]


# ── Layout ───────────────────────────────────────────────────────────────────


def test_the_system_is_rules_then_profile_each_with_a_breakpoint():
    system = _build(_payload())["system"]

    assert len(system) == 2
    rules, profile = system
    assert rules["text"] == lf._ADVISOR_SYSTEM_PREFIX
    assert rules["cache_control"] == {"type": "ephemeral"}
    assert profile["cache_control"] == {"type": "ephemeral"}
    assert "Paid on the 15th." in profile["text"]
    # The snapshot and the history are the briefing's, never the system's.
    for block in system:
        assert "Cash: P1,000" not in block["text"]
        assert "Jan: P500" not in block["text"]


def test_no_profile_leaves_the_rules_block_alone():
    system = _build(_payload(profile=""))["system"]

    assert system == [{"type": "text", "text": lf._ADVISOR_SYSTEM_PREFIX,
                       "cache_control": {"type": "ephemeral"}}]


_TODAY = "TODAY: Thursday, 15 Oct 2026 (2026-10-15). This is the real current date."


def test_the_today_line_moves_to_the_system_ahead_of_the_profile():
    request = _build(_payload(summary=_TODAY + "\nCash: P1,000"))
    system = request["system"][1]["text"]
    briefing = request["messages"][-1]["content"][-1]["text"]

    assert system.startswith(_TODAY + "\nCALENDAR")
    assert system.index("CALENDAR") < system.index("Paid on the 15th.")
    assert "TODAY:" not in briefing
    assert "Cash: P1,000" in briefing


def test_the_today_line_alone_still_makes_a_second_system_block():
    system = _build(_payload(summary=_TODAY + "\nCash: P1,000", profile=""))["system"]

    assert len(system) == 2
    assert system[1]["text"].startswith(_TODAY)
    assert system[1]["cache_control"] == {"type": "ephemeral"}


def test_a_ledger_edit_on_the_same_day_leaves_the_system_byte_identical():
    before = _build(_payload(summary=_TODAY + "\nCash: P1,000"))
    after = _build(_payload(summary=_TODAY + "\nCash: P1,250"))

    assert before["system"] == after["system"]


def test_a_snapshot_without_a_today_line_stays_whole():
    request = _build(_payload(summary="Cash: P1,000\nTODAY: not first"))

    assert "TODAY: not first" in request["messages"][-1]["content"][-1]["text"]


@pytest.mark.parametrize("today, expected", [
    ("2026-10-15", ["this month = Oct 2026 (2026-10-01 to 2026-10-15)",
                    "last month = Sep 2026 (2026-09-01 to 2026-09-30)",
                    "this quarter = Q4 2026 (2026-10-01 to 2026-10-15)",
                    "last quarter = Q3 2026 (2026-07-01 to 2026-09-30)",
                    "this year = 2026 (2026-01-01 to 2026-10-15)"]),
    # Year boundaries, and a leap-year February.
    ("2026-01-05", ["last month = Dec 2025 (2025-12-01 to 2025-12-31)",
                    "this quarter = Q1 2026 (2026-01-01 to 2026-01-05)",
                    "last quarter = Q4 2025 (2025-10-01 to 2025-12-31)"]),
    ("2024-03-01", ["last month = Feb 2024 (2024-02-01 to 2024-02-29)"]),
    ("2026-03-01", ["last month = Feb 2026 (2026-02-01 to 2026-02-28)"]),
    ("2026-07-31", ["this quarter = Q3 2026 (2026-07-01 to 2026-07-31)",
                    "last quarter = Q2 2026 (2026-04-01 to 2026-06-30)"]),
])
def test_the_calendar_line_states_each_named_period(today, expected):
    line = lf._calendar_periods(f"TODAY: x ({today}).")

    for period in expected:
        assert period in line


def test_a_today_line_with_no_iso_date_gets_no_calendar():
    assert lf._calendar_periods("TODAY: sometime") == "TODAY: sometime"


def test_the_briefing_closes_the_newest_user_turn_and_carries_breakpoint_4():
    content = _build(_payload())["messages"][-1]["content"]

    question, briefing = content
    # The user's words come first, unchanged; the data and its reminder last.
    assert question == {"type": "text", "text": "How am I doing?"}
    assert _is_briefing(briefing)
    assert briefing["text"].endswith(lf._BRIEFING_REMINDER + "\n</briefing>")
    # Cached for the next hop of this turn, which reads it back if the model
    # calls a tool (see the layout comment, breakpoint 4).
    assert briefing["cache_control"] == {"type": "ephemeral"}
    assert "cache_control" not in question


def test_the_briefing_holds_the_snapshot_then_the_history():
    text = _build(_payload())["messages"][-1]["content"][-1]["text"]

    assert "Cash: P1,000" in text
    assert "Jan: P500" in text
    assert "Paid on the 15th." not in text
    assert text.index("CURRENT FINANCIAL SNAPSHOT") < text.index("HISTORICAL RECORD")


def test_no_snapshot_still_sends_a_briefing_that_says_so():
    request = _build(_payload(summary="", historical=""))

    briefing = request["messages"][-1]["content"][-1]
    assert _is_briefing(briefing)
    assert "No financial snapshot" in briefing["text"]
    assert request["_has_summary"] is False


def test_a_snapshot_edit_leaves_system_and_tools_byte_identical():
    before = _build(_payload(summary="Cash: P1,000"))
    after = _build(_payload(summary="Cash: P1,250"))

    assert before["system"] == after["system"]
    # The tools sit ahead of the system in the cache prefix, so they must not
    # change either.
    assert before["tools"] == after["tools"]
    assert before["messages"] != after["messages"]


def test_an_image_turn_reads_images_question_then_briefing():
    request = _build(_payload(images=[
        {"base64": "aaaa", "mime_type": "image/jpeg"}]))
    content = request["messages"][-1]["content"]

    assert [b["type"] for b in content] == ["image", "text", "text"]
    assert content[1]["text"] == "How am I doing?"
    assert _is_briefing(content[2])


# ── Breakpoints ──────────────────────────────────────────────────────────────


def test_tools_carry_no_breakpoint_of_their_own():
    request = _build(_payload())

    # The rules breakpoint covers the tool catalogue ahead of it; a marker on
    # a tool would spend one of the four for nothing.
    assert all("cache_control" not in t for t in request["tools"])


def test_a_first_turn_marks_the_system_and_its_only_user_turn():
    assert _breakpoints(_build(_payload())) == [
        ("system", 0), ("system", 1), ("messages", 0)]


def test_the_history_and_newest_breakpoints_sit_on_the_last_two_user_turns():
    messages = _HISTORY + [{"role": "user", "text": "What about bills?"}]
    request = _build(_payload(messages=messages))

    assert _breakpoints(request) == [
        ("system", 0), ("system", 1), ("messages", 2), ("messages", 4)]
    # Only the newest turn carries the briefing; the next message strips it,
    # so the history breakpoint (3) never covers a briefing.
    assert _briefing_turns(request) == [4]


def test_a_long_tool_loop_stays_within_bedrocks_breakpoint_limit():
    request = _build(_payload(messages=_tool_loop(hops=4)))
    found = _breakpoints(request)

    assert len(found) == _BEDROCK_MAX_BREAKPOINTS
    assert found[:2] == [("system", 0), ("system", 1)]
    # The results of hop 3 (breakpoint 3) and of hop 4 (breakpoint 4).
    n = len(request["messages"])
    assert found[2:] == [("messages", n - 3), ("messages", n - 1)]


def test_cached_system_with_no_context_is_one_block():
    assert lf._cached_system("rules") == [
        {"type": "text", "text": "rules", "cache_control": {"type": "ephemeral"}},
    ]


# ── Only the newest turn changes ─────────────────────────────────────────────


def test_the_history_is_byte_identical_across_two_turns():
    turn_n = _HISTORY + [{"role": "user", "text": "What about bills?"}]
    first = _build(_payload(messages=turn_n, summary="Cash: P1,000"))
    turn_n1 = turn_n + [
        {"role": "assistant", "text": "One bill is due."},
        {"role": "user", "text": "When?"},
    ]
    # A ledger edit between the two turns, the case the layout is for.
    second = _build(_payload(messages=turn_n1, summary="Cash: P1,250"))

    history = len(turn_n) - 1
    assert (_canonical(first["messages"][:history])
            == _canonical(second["messages"][:history]))
    # Turn N's question loses its briefing and keeps the user's words.
    assert _canonical(second["messages"][history:history + 1]) == [
        {"role": "user", "content": [{"type": "text", "text": "What about bills?"}]}]
    assert first["system"] == second["system"]


def test_only_the_newest_user_turn_carries_a_briefing():
    messages = _HISTORY + [{"role": "user", "text": "What about bills?"}]
    request = _build(_payload(messages=messages))

    assert _briefing_turns(request) == [len(request["messages"]) - 1]


def test_a_replayed_briefing_in_an_older_turn_is_stripped():
    old_briefing = {"type": "text", "text": "<briefing>\nCash: P9\n</briefing>"}
    messages = [
        {"role": "user", "content_blocks": [
            {"type": "text", "text": "How am I doing?"}, old_briefing]},
        {"role": "assistant", "text": "Fine."},
        {"role": "user", "text": "Thanks."},
    ]
    request = _build(_payload(messages=messages))

    assert _briefing_turns(request) == [2]
    assert "Cash: P9" not in str(request["messages"])


# ── The tool loop ────────────────────────────────────────────────────────────


def _tool_loop(hops):
    """The transcript of the newest turn after `hops` tool calls."""
    messages = list(_HISTORY) + [{"role": "user", "text": "What did I spend on food?"}]
    for i in range(hops):
        messages += [
            {"role": "assistant", "content_blocks": [
                {"type": "tool_use", "id": f"t{i}", "name": "findTransactions",
                 "input": {}},
            ]},
            {"role": "user", "content_blocks": [
                {"type": "tool_result", "tool_use_id": f"t{i}", "content": "[]"},
            ]},
        ]
    return messages


def test_a_continuation_hop_keeps_the_briefing_in_the_question_turn():
    request = _build(_payload(messages=_tool_loop(hops=1)))

    question = len(_HISTORY)
    assert _briefing_turns(request) == [question]
    # Tool results open their turn; the briefing never goes there.
    assert [b["type"] for b in request["messages"][-1]["content"]] == ["tool_result"]


def test_each_hop_keeps_the_previous_hops_prompt_as_its_prefix():
    hops = [_build(_payload(messages=_tool_loop(hops=n))) for n in range(3)]

    for before, after in zip(hops, hops[1:]):
        assert before["system"] == after["system"]
        assert before["tools"] == after["tools"]
        n = len(before["messages"])
        assert _canonical(after["messages"][:n]) == _canonical(before["messages"])


def test_hop_two_reads_the_question_and_briefing_hop_one_cached():
    first = _build(_payload(messages=_tool_loop(hops=0)))
    second = _build(_payload(messages=_tool_loop(hops=1)))

    question = len(_HISTORY)
    # Hop 1 marks the question turn as its newest turn (breakpoint 4) ...
    assert ("messages", question) in _breakpoints(first)
    # ... and hop 2 marks the same turn as breakpoint 3, plus its own results.
    assert _breakpoints(second)[2:] == [
        ("messages", question), ("messages", question + 2)]
    # The marked prefix is byte-identical, so hop 2 reads what hop 1 wrote.
    assert (_canonical(first["messages"][:question + 1])
            == _canonical(second["messages"][:question + 1]))


def test_a_resumed_turn_of_only_tool_results_puts_the_briefing_last():
    messages = [
        {"role": "assistant", "content_blocks": [
            {"type": "tool_use", "id": "t0", "name": "findTransactions",
             "input": {}}]},
        {"role": "user", "content_blocks": [
            {"type": "tool_result", "tool_use_id": "t0", "content": "[]"}]},
    ]
    request = _build(_payload(messages=messages))
    content = request["messages"][-1]["content"]

    assert content[0]["type"] == "tool_result"
    assert _is_briefing(content[-1])
