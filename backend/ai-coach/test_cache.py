"""Tests for the advisor's prompt-cache layout (Plan 065, item 1e).

The system prompt is two blocks -- the rules, then the snapshot and what
follows it -- each ending in a breakpoint. A ledger edit changes only the
second block, so the tools + rules prefix stays cached. These tests pin the
layout, because a later edit that folds the blocks back together would still
work and only show up as a bigger bill.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x SUPABASE_URL=https://p.supabase.co \\
    SUPABASE_ANON_KEY=k python -m pytest test_cache.py -q
"""

import copy

import lambda_function as lf

# Bedrock rejects a request with more than this many cache_control markers.
_BEDROCK_MAX_BREAKPOINTS = 4

_TOOLS = [{
    "name": "findTransactions",
    "description": "Find transactions.",
    "input_schema": {"type": "object", "properties": {}},
}]


def _payload(summary="Cash: P1,000", historical="Jan: P500", **extra):
    return {
        "messages": [{"role": "user", "text": "How am I doing?"}],
        "context": {"summary": summary, "profile": "Paid on the 15th.",
                    "historical": historical},
        "tools": _TOOLS,
        **extra,
    }


def _build(payload):
    request, err = lf._build_advisor_request(payload)
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


def test_the_system_is_rules_then_context_each_with_a_breakpoint():
    system = _build(_payload())["system"]

    assert len(system) == 2
    rules, context = system
    assert rules["text"] == lf._ADVISOR_SYSTEM_PREFIX
    assert rules["cache_control"] == {"type": "ephemeral"}
    assert context["cache_control"] == {"type": "ephemeral"}
    assert "Cash: P1,000" in context["text"]
    assert "Paid on the 15th." in context["text"]
    assert "Jan: P500" in context["text"]
    # Nothing from the context leaks into the rules block, or an edit to it
    # would invalidate the rules too.
    assert "Cash: P1,000" not in rules["text"]


def test_the_context_keeps_its_order_snapshot_profile_history():
    text = _build(_payload())["system"][1]["text"]

    assert (text.index("CURRENT FINANCIAL SNAPSHOT")
            < text.index("WHAT YOU REMEMBER")
            < text.index("HISTORICAL RECORD"))


def test_a_snapshot_edit_leaves_the_rules_block_byte_identical():
    before = _build(_payload(summary="Cash: P1,000"))
    after = _build(_payload(summary="Cash: P1,250"))

    assert before["system"][0] == after["system"][0]
    assert before["system"][1] != after["system"][1]
    # The tools sit ahead of the system in the cache prefix, so they must not
    # change either.
    assert before["tools"] == after["tools"]


def test_no_snapshot_still_gives_two_blocks():
    system = _build(_payload(summary="", historical=""))["system"]

    assert len(system) == 2
    assert system[0]["text"] == lf._ADVISOR_SYSTEM_PREFIX
    assert "No financial snapshot" in system[1]["text"]


def test_tools_carry_no_breakpoint_of_their_own():
    request = _build(_payload())

    # The rules breakpoint covers the tool catalogue ahead of it; a marker on
    # a tool would spend one of the four for nothing.
    assert all("cache_control" not in t for t in request["tools"])


def test_a_first_turn_has_only_the_two_system_breakpoints():
    assert _breakpoints(_build(_payload())) == [("system", 0), ("system", 1)]


def test_a_long_tool_loop_stays_within_bedrocks_breakpoint_limit():
    payload = _payload()
    payload["messages"] = [
        {"role": "user", "text": "What did I spend on food?"},
        {"role": "assistant", "content_blocks": [
            {"type": "tool_use", "id": "t1", "name": "findTransactions",
             "input": {}},
        ]},
        {"role": "user", "content_blocks": [
            {"type": "tool_result", "tool_use_id": "t1", "content": "[]"},
        ]},
        {"role": "assistant", "text": "Nothing yet this month."},
        {"role": "user", "text": "And last month?"},
    ]
    request = _build(copy.deepcopy(payload))
    found = _breakpoints(request)

    assert len(found) <= _BEDROCK_MAX_BREAKPOINTS
    assert found[:2] == [("system", 0), ("system", 1)]
    # The conversation breakpoint sits on the second-to-last user turn.
    assert found[2:] == [("messages", 2)]


def test_cached_system_with_no_context_is_one_block():
    assert lf._cached_system("rules") == [
        {"type": "text", "text": "rules", "cache_control": {"type": "ephemeral"}},
    ]
