"""Tests for the briefing size log and scripts/briefing_sizes.py.

The first hop of each turn logs how many characters each briefing section
takes, by a fixed key, so a smaller briefing can be designed from data. It
must never log the text, and a header that carries figures must not leak them
through its key.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x SUPABASE_URL=https://p.supabase.co \\
    SUPABASE_ANON_KEY=k python -m pytest test_briefing_sizes.py -q
"""

import json
import os
import sys
from pathlib import Path

import lambda_function as lf
from test_invocation_log import (  # noqa: F401 -- _supabase is a fixture
    _FakeBedrock,
    _buffered,
    _reply,
    _supabase,
)

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "scripts"))
import briefing_sizes  # noqa: E402

_SNAPSHOT = json.loads(
    (Path(__file__).parent / "evals" / "snapshot.json").read_text(encoding="utf-8"))


def _sizes():
    return lf._briefing_sizes({"context": _SNAPSHOT})


def test_every_section_of_the_apps_snapshot_has_a_key():
    """A new header in the app shows up here as "other": add it to the table."""
    assert "other" not in _sizes()["sections"]


def test_the_sections_add_up_to_the_whole_briefing():
    sizes = _sizes()
    # Each line counts its newline; the last line of each part has none.
    assert sum(sizes["sections"].values()) == sizes["summary"] + sizes["historical"] + 2
    assert sizes["summary"] == len(_SNAPSHOT["summary"])


def test_a_header_with_figures_is_logged_by_its_key_only():
    sizes = lf._briefing_sizes({"context": {
        "summary": "Total liquid cash: ₱59,620\n  - GCash: ₱6,420\n"
                   "Net worth by month (oldest → newest): ₱1\n"
                   "Net worth: ₱312,450\nSomething new: ₱9",
    }})
    assert set(sizes["sections"]) == {"accounts", "hist_net_worth", "totals", "other"}
    assert "₱" not in json.dumps(sizes)


def test_no_context_logs_nothing():
    assert lf._briefing_sizes({}) is None
    assert lf._briefing_sizes(None) is None


def _invocation_lines(out):
    return [json.loads(line) for line in out.splitlines()
            if line.startswith("{") and lf._INVOCATION_LOG in line]


def test_the_first_hop_logs_the_sizes_and_no_text(monkeypatch, capsys):
    payload = {"trace_id": "t-first", "context": {"summary": "SENTINEL_SNAPSHOT_X"},
               "messages": [{"role": "user", "text": "SENTINEL_QUESTION_X"}]}
    _buffered(monkeypatch, _FakeBedrock(reply=_reply()), payload)
    out = capsys.readouterr().out

    [line] = _invocation_lines(out)
    assert line["briefing_chars"]["summary"] == len("SENTINEL_SNAPSHOT_X")
    assert "SENTINEL_" not in out


def test_a_continuation_hop_logs_no_sizes(monkeypatch, capsys):
    # test_invocation_log's default payload already carries tool results.
    _buffered(monkeypatch, _FakeBedrock(reply=_reply()))
    [line] = _invocation_lines(capsys.readouterr().out)
    assert "briefing_chars" not in line


def test_the_script_averages_per_key_and_counts_a_missing_key_as_zero():
    turns, totals, sections = briefing_sizes.average([
        {"summary": 100, "historical": 40, "sections": {"bills": 60, "goals": 40}},
        {"summary": 300, "historical": 0, "sections": {"bills": 200}},
    ])
    assert turns == 2
    assert totals == {"summary": 200, "historical": 20}
    assert sections == {"bills": 130, "goals": 20}
    text = briefing_sizes.render(turns, totals, sections)
    assert text.splitlines()[0].startswith("2 turns.")
    assert "| bills | 130 |" in text


def test_the_script_says_so_when_the_window_is_empty():
    assert "no briefing_chars" in briefing_sizes.render(*briefing_sizes.average([]))
