"""Tests for scripts/trace.py and estimated_cost_usd (Plan 065, phase 5).

No AWS: the Logs client is a fake that answers with canned rows.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x python -m pytest test_trace_script.py -q
"""

import importlib.util
import json
import os

import pytest

import lambda_function as lf

_SPEC = importlib.util.spec_from_file_location(
    "trace_script", os.path.join(os.path.dirname(__file__), "scripts", "trace.py"))
ts = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(ts)

_SONNET = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
_STREAM = "123456789012:/aws/lambda/food-advisor-stream"
_COACH = "123456789012:/aws/lambda/food-coach-handler"


def _hop_json(stamp, **fields):
    return {"@timestamp": stamp, "@log": _STREAM, "@message": json.dumps({
        "event": "advisor_invocation", "op": "adviseFinance",
        "trace": "t1", "model": _SONNET, "route": None, "stream": True,
        "user": None, "error_class": None, **fields})}


def _cost_line(stamp, text):
    return {"@timestamp": stamp, "@log": _STREAM, "@message": text}


def _client_event(stamp, name, fields):
    return {"@timestamp": stamp, "@log": _COACH, "@message": json.dumps({
        "event": "client_event", "name": name, "trace": "t1",
        "user": None, "fields": fields})}


_FIRST = dict(hop="first", hops=0, in_tokens=1000, out_tokens=100,
              cache_read=8000, cache_write=500, latency_ms=4200,
              ttft_ms=900, stop="tool_use", tool_names=["addBill"],
              results=[])
_SECOND = dict(hop="cont", hops=1, in_tokens=200, out_tokens=50,
               cache_read=9000, cache_write=0, latency_ms=2100,
               ttft_ms=700, stop="end_turn", tool_names=[], results=["ok"])


def _rows():
    return [
        _hop_json("2026-10-30 10:00:04.200", **_FIRST),
        _cost_line("2026-10-30 10:00:04.199",
                   "cost_line op=adviseFinance in_tokens=1000 trace=t1"),
        _client_event("2026-10-30 10:00:05.000", "batch_opened", {"items": 1}),
        _client_event("2026-10-30 10:00:09.000", "batch_answered",
                      {"approved": 1, "declined": 0, "revised": 0,
                       "removed": 0, "failed": 0}),
        _hop_json("2026-10-30 10:00:11.300", **_SECOND),
        {"@timestamp": "2026-10-30 10:00:00.000", "@log": _STREAM,
         "@message": "advisor stream start user=u bytes=10"},
    ]


# -- estimated_cost_usd ---------------------------------------------------------

def test_cost_uses_input_output_and_cache_prices():
    cost = lf.estimated_cost_usd(_SONNET, {
        "input_tokens": 1_000_000, "output_tokens": 1_000_000,
        "cache_creation_input_tokens": 1_000_000,
        "cache_read_input_tokens": 1_000_000})

    # 3 + 15 + 3 * 1.25 + 3 * 0.1
    assert cost == pytest.approx(22.05)


def test_one_hour_cache_writes_cost_twice_input():
    cost = lf.estimated_cost_usd(_SONNET, {
        "cache_creation_input_tokens": 3_000_000,
        "cache_creation": {"ephemeral_1h_input_tokens": 1_000_000,
                           "ephemeral_5m_input_tokens": 2_000_000}})

    # 1M at 3 * 2, 2M at 3 * 1.25
    assert cost == pytest.approx(13.5)


def test_an_unknown_model_has_no_cost():
    assert lf.estimated_cost_usd("some-other-model", {"input_tokens": 5}) is None
    assert lf.estimated_cost_usd(None, {"input_tokens": 5}) is None


def test_missing_or_negative_counts_cost_nothing():
    assert lf.estimated_cost_usd(_SONNET, {"input_tokens": -1,
                                           "output_tokens": None}) == 0


# -- timeline -----------------------------------------------------------------

def test_the_json_line_wins_over_its_cost_line():
    entries = ts.timeline(_rows())

    assert [e["kind"] for e in entries] == ["hop", "event", "event", "hop"]
    assert all(e.get("source") != "cost_line" for e in entries)


def test_an_older_deploy_falls_back_to_the_cost_line():
    entries = ts.timeline([_cost_line(
        "2026-10-27 16:42:27.013",
        "cost_line op=adviseFinance msgs=3 in_tokens=845 out_tokens=120 "
        "cache_read=0 cache_write=0 latency_ms=5000 ttft_ms=800 "
        "stop=end_turn tools=40 calls=0 hop=first trace=t1 tool_names=- "
        "results=- hops=0")])

    [hop] = entries
    assert hop["source"] == "cost_line"
    assert hop["in_tokens"] == 845
    assert hop["cost_usd"] is None  # an old line names no model


def test_each_hop_gets_its_cost():
    hop = ts.timeline(_rows())[0]

    assert hop["cost_usd"] == lf.estimated_cost_usd(_SONNET, {
        "input_tokens": 1000, "output_tokens": 100,
        "cache_read_input_tokens": 8000, "cache_creation_input_tokens": 500})


def test_render_prints_hops_events_and_a_total():
    text = ts.render("t1", ts.timeline(_rows()))
    lines = text.splitlines()

    assert lines[0] == "trace t1: 2 model calls, 2 client events"
    assert "sonnet-4-5" in lines[1]
    assert "tools addBill" in lines[1]
    assert "(ttft 0.9s)" in lines[1]
    assert "batch_opened  items=1" in lines[2]
    assert lines[3].startswith("  +   4.8s")
    assert "results ok" in lines[4]
    assert lines[5].startswith("  total: in 1200 out 150 cache r17000 w500")


def test_render_with_nothing_found():
    assert "nothing found" in ts.render("t1", [])


def test_an_error_hop_shows_its_class():
    rows = [_hop_json("2026-10-30 10:00:00.000", hop="first", hops=0,
                      latency_ms=300, error_class="ThrottlingException")]

    assert "ERROR ThrottlingException" in ts.render("t1", ts.timeline(rows))


# -- main, against a fake Logs client ------------------------------------------

class _FakeLogs:
    def __init__(self, results):
        self.results = list(results)
        self.queries = []

    def start_query(self, **kwargs):
        self.queries.append(kwargs)
        return {"queryId": str(len(self.queries))}

    def get_query_results(self, queryId):
        rows = self.results.pop(0)
        return {"status": "Complete", "results": [
            [{"field": k, "value": v} for k, v in row.items()] for row in rows]}


@pytest.fixture
def fake_logs(monkeypatch):
    holder = {}

    class _Session:
        def __init__(self, profile_name, region_name):
            holder["profile"], holder["region"] = profile_name, region_name

        def client(self, name):
            assert name == "logs"
            return holder["logs"]

    monkeypatch.setattr(ts.boto3, "Session", _Session)
    return holder


def test_main_queries_both_functions_for_the_trace(fake_logs, capsys):
    fake_logs["logs"] = _FakeLogs([_rows()])

    ts.main(["t1"])

    [query] = fake_logs["logs"].queries
    assert set(query["logGroupNames"]) == set(ts.LOG_GROUPS)
    assert 'like "t1"' in query["queryString"]
    assert fake_logs["profile"] == "ifast-dev"
    assert fake_logs["region"] == "ap-southeast-1"
    assert capsys.readouterr().out.startswith("trace t1: 2 model calls")


def test_latest_finds_the_newest_trace(fake_logs, capsys):
    fake_logs["logs"] = _FakeLogs([
        [{"@timestamp": "x", "@message":
          "cost_line op=adviseFinance in_tokens=5 trace=abc123 tool_names=-"}],
        [],
    ])

    ts.main(["--latest"])

    assert 'like "abc123"' in fake_logs["logs"].queries[1]["queryString"]
    assert capsys.readouterr().out.startswith("trace abc123:")


@pytest.mark.parametrize("bad", ['x" | fields @message', "a b", "x" * 65])
def test_a_trace_id_that_could_change_the_query_is_refused(fake_logs, bad):
    fake_logs["logs"] = _FakeLogs([])

    with pytest.raises(SystemExit):
        ts.main([bad])
    assert fake_logs["logs"].queries == []
