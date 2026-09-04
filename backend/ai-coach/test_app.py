"""Tests for the streaming advisor's ASGI front door.

The point of these is cost and exposure, not correctness of prose: this endpoint
runs with AuthType NONE, so an unauthenticated caller must be turned away
*before* anything bills. Every rejection test therefore asserts that Bedrock was
never called, not merely that the status code was right.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x SUPABASE_URL=https://p.supabase.co \\
    SUPABASE_ANON_KEY=k python -m pytest test_app.py -q
"""

import asyncio
import json

import pytest

import app as advisor_app
import lambda_function as lf


class _Recorder:
    """Collects what the app sent, and whether anything reached the model."""

    def __init__(self):
        self.messages = []

    async def send(self, message):
        self.messages.append(message)

    @property
    def status(self):
        return next(m["status"] for m in self.messages
                    if m["type"] == "http.response.start")

    @property
    def headers(self):
        start = next(m for m in self.messages
                     if m["type"] == "http.response.start")
        return {k.decode().lower(): v.decode() for k, v in start["headers"]}

    @property
    def body(self):
        raw = b"".join(m.get("body") or b"" for m in self.messages
                       if m["type"] == "http.response.body")
        return raw.decode()

    def json(self):
        return json.loads(self.body)


def _call(*, method="POST", path="/v1/advisor", headers=None, body=b"{}"):
    scope = {
        "type": "http",
        "method": method,
        "path": path,
        "headers": [(k.lower().encode(), v.encode())
                    for k, v in (headers or {}).items()],
    }

    async def receive():
        return {"type": "http.request", "body": body, "more_body": False}

    rec = _Recorder()
    asyncio.run(advisor_app.app(scope, receive, rec.send))
    return rec


@pytest.fixture(autouse=True)
def _no_bedrock(monkeypatch):
    """Make any model call an immediate, loud failure."""
    called = {"n": 0}

    def explode(*a, **k):
        called["n"] += 1
        raise AssertionError('Bedrock was called on a path that must not bill')

    monkeypatch.setattr(lf._bedrock, "invoke_model_with_response_stream",
                        explode, raising=False)
    monkeypatch.setattr(lf._bedrock, "invoke_model", explode, raising=False)
    return called


@pytest.fixture(autouse=True)
def _no_rate_limit_calls(monkeypatch):
    """The Supabase RPC must not be reached on a rejected request either."""
    hits = {"n": 0}

    def counted(token):
        hits["n"] += 1
        return True, 1

    # Patched on BOTH modules: app.py does `from lambda_function import
    # _check_rate_limit`, which binds the function at import, so patching only
    # the source module leaves app.py calling the real Supabase RPC.
    monkeypatch.setattr(lf, "_check_rate_limit", counted)
    monkeypatch.setattr(advisor_app, "_check_rate_limit", counted)
    return hits


# ── Rejections that must not cost anything ───────────────────────────────────

def test_no_token_is_401_and_never_bills(_no_bedrock, _no_rate_limit_calls):
    rec = _call()
    assert rec.status == 401
    assert rec.json()["error"] == "unauthorized"
    assert _no_bedrock["n"] == 0
    # Not even the rate-limit RPC: an unauthenticated flood should not be able
    # to spend anyone's allowance, or make us call Supabase per request.
    assert _no_rate_limit_calls["n"] == 0


def test_a_bad_token_is_401_and_never_bills(_no_bedrock, _no_rate_limit_calls):
    rec = _call(headers={"authorization": "Bearer garbage"})
    assert rec.status == 401
    assert _no_bedrock["n"] == 0
    assert _no_rate_limit_calls["n"] == 0


def test_a_non_bearer_authorization_is_401(_no_bedrock):
    rec = _call(headers={"authorization": "Basic abc"})
    assert rec.status == 401
    assert _no_bedrock["n"] == 0


# ── Routing ──────────────────────────────────────────────────────────────────

def test_another_path_is_404_and_never_bills(_no_bedrock):
    # This function serves ONE op. Answering anything else would quietly create
    # a second general coach API nobody meant to operate.
    rec = _call(path="/v1/coach")
    assert rec.status == 404
    assert _no_bedrock["n"] == 0


def test_a_get_is_404(_no_bedrock):
    rec = _call(method="GET")
    assert rec.status == 404
    assert _no_bedrock["n"] == 0


def test_routing_is_checked_before_auth_is_not_assumed(_no_bedrock):
    # Whichever order it runs in, an unauthenticated request to an unknown path
    # must not bill. Asserted so a later reordering cannot open a hole.
    for path in ("/", "/v1", "/v1/advisor/extra/deep", "/admin"):
        rec = _call(path=path)
        assert rec.status in (401, 404), path
        assert _no_bedrock["n"] == 0, path


# ── CORS ─────────────────────────────────────────────────────────────────────

def test_preflight_from_an_allowed_origin_is_answered(_no_bedrock):
    rec = _call(method="OPTIONS",
                headers={"origin": "https://nudgr-app.web.app"})
    assert rec.status == 204
    h = rec.headers
    assert h["access-control-allow-origin"] == "https://nudgr-app.web.app"
    # `authorization` must be named explicitly — a wildcard does not cover it on
    # an authenticated request, which is the trap that took web down once.
    assert "authorization" in h["access-control-allow-headers"]
    assert "content-type" in h["access-control-allow-headers"]
    assert _no_bedrock["n"] == 0


def test_both_firebase_origins_are_allowed(_no_bedrock):
    for origin in ("https://nudgr-app.web.app",
                   "https://nudgr-app.firebaseapp.com"):
        rec = _call(method="OPTIONS", headers={"origin": origin})
        assert rec.headers["access-control-allow-origin"] == origin, origin


def test_an_unknown_origin_gets_no_allow_header(_no_bedrock):
    rec = _call(method="OPTIONS", headers={"origin": "https://evil.example"})
    assert rec.status == 204
    assert "access-control-allow-origin" not in rec.headers


def test_a_401_still_carries_cors_so_the_browser_can_read_it(_no_bedrock):
    # Without this the browser reports a CORS failure instead of the 401, and
    # the user is told to check their connection when they need to sign in.
    rec = _call(headers={"origin": "https://nudgr-app.web.app"})
    assert rec.status == 401
    assert rec.headers["access-control-allow-origin"] == \
        "https://nudgr-app.web.app"


# ── Authenticated requests ───────────────────────────────────────────────────

@pytest.fixture
def _valid_token(monkeypatch):
    monkeypatch.setattr(lf, "verify_supabase_token",
                        lambda token: {"sub": "user-123"})
    monkeypatch.setattr(advisor_app, "verify_supabase_token",
                        lambda token: {"sub": "user-123"})
    return {"authorization": "Bearer good"}


def test_a_malformed_body_is_400_before_any_model_call(
        _valid_token, _no_bedrock):
    rec = _call(headers=_valid_token, body=b"{not json")
    assert rec.status == 400
    assert rec.json()["error"] == "invalid_json"
    assert _no_bedrock["n"] == 0


def test_an_empty_turn_is_rejected_with_a_status_not_a_stream(
        _valid_token, _no_bedrock):
    # The build happens before the 200 is committed, so a malformed turn can
    # still be expressed as a status code. Once the stream starts it cannot.
    rec = _call(headers=_valid_token, body=json.dumps({"payload": {}}).encode())
    assert rec.status == 400
    assert rec.headers["content-type"] == "application/json"
    assert _no_bedrock["n"] == 0


def test_over_cap_is_429_with_no_frames_sent(_valid_token, _no_bedrock,
                                             monkeypatch):
    monkeypatch.setattr(advisor_app, "_check_rate_limit",
                        lambda token: (False, 101))
    body = json.dumps({
        "payload": {
            "context": {"summary": "ACCOUNTS\n- Cash: 100"},
            "messages": [{"role": "user", "text": "how am i doing?"}],
        }
    }).encode()
    rec = _call(headers=_valid_token, body=body)
    assert rec.status == 429
    assert "rate_limit_exceeded" in rec.body
    # Told before anything streams, rather than watching a reply begin and stop.
    assert "\"type\": \"delta\"" not in rec.body
    assert _no_bedrock["n"] == 0


def test_an_unavailable_rate_limit_check_is_a_retryable_503(
        _valid_token, _no_bedrock, monkeypatch):
    monkeypatch.setattr(advisor_app, "_check_rate_limit",
                        lambda token: (False, -1))
    body = json.dumps({
        "payload": {
            "context": {"summary": "ACCOUNTS\n- Cash: 100"},
            "messages": [{"role": "user", "text": "hi"}],
        }
    }).encode()
    rec = _call(headers=_valid_token, body=body)
    assert rec.status == 503
    assert _no_bedrock["n"] == 0


def test_a_continuation_hop_does_not_re_charge_the_cap(_valid_token,
                                                       _no_rate_limit_calls):
    # A tool-calling turn is several invocations; charging each would cut a cap
    # of 100 down to ~25 conversations a day.
    body = json.dumps({
        "payload": {
            "context": {"summary": "ACCOUNTS\n- Cash: 100"},
            "messages": [
                {"role": "user", "text": "set aside 500"},
                {"role": "assistant", "content_blocks": [
                    {"type": "tool_use", "id": "t1", "name": "x", "input": {}}]},
                {"role": "user", "content_blocks": [
                    {"type": "tool_result", "tool_use_id": "t1",
                     "content": "ok"}]},
            ],
        }
    }).encode()
    # Streaming itself will fail (Bedrock is stubbed to explode), but the cap
    # decision happens first and is what this asserts.
    try:
        _call(headers=_valid_token, body=body)
    except AssertionError:
        pass
    assert _no_rate_limit_calls["n"] == 0, \
        'a continuation hop must not be charged again'
