"""ASGI front door for the STREAMING advisor only.

Why this file exists at all: Lambda cannot stream a response from the Python
managed runtime, and an HTTP API cannot stream one at any price — its maximum
integration timeout is 30 seconds and AWS lists it as not increasable. So an
advisor turn that took 43 seconds finished successfully in Lambda, was billed in
full by Bedrock, and was then thrown away by the gateway as a 504. The client
showed "The advisor had a hiccup on our end" for a working answer.

The fix is a Lambda Function URL in RESPONSE_STREAM mode, which needs a web
server rather than a handler — the Lambda Web Adapter layer runs this app and
translates. Only the advisor lives here. `respond`, `classifyFinance`,
`parseFoodFromImage` and `parseFoodWithCandidates` all finish well inside 30s
and stay on `lambda_function.lambda_handler` behind the existing HTTP API, with
its JWT authorizer and CORS untouched. Nothing about this file should tempt
anyone to move them: it is a second front door for one op, not a replacement for
the first.

Every rule that makes the advisor trustworthy is imported, not restated.
`_build_advisor_request` assembles the prompt — snapshot as sole source of
numeric truth, clipping caps, alternation enforcement, image placement, both
prompt-cache breakpoints — and `advise_finance_stream` runs the model. A second
copy of any of that would be a second place for it to rot.
"""

import json

from lambda_function import (
    _DAILY_CAP,
    AuthError,
    _build_advisor_request,
    _carries_tool_results,
    _check_rate_limit,
    advise_finance_stream,
    bearer_token_from_headers,
    verify_supabase_token,
)

# Mirrors backend/ai-coach/cors.json. Firebase serves the app from both hosts and
# CORS matches an origin exactly, so both are named. `authorization` must be
# listed explicitly — a wildcard does not cover it on an authenticated request,
# which is exactly the trap that took the web build down once already.
_ALLOWED_ORIGINS = (
    "https://nudgr-app.web.app",
    "https://nudgr-app.firebaseapp.com",
)
_CORS_HEADERS = "authorization,content-type"

_ADVISOR_PATH = "/v1/advisor"


def _cors_for(origin):
    if origin in _ALLOWED_ORIGINS:
        return [
            (b"access-control-allow-origin", origin.encode()),
            (b"access-control-allow-headers", _CORS_HEADERS.encode()),
            (b"access-control-allow-methods", b"POST,OPTIONS"),
            (b"vary", b"origin"),
        ]
    return []


async def _send_json(send, status, body, *, origin=None):
    raw = json.dumps(body).encode()
    await send({
        "type": "http.response.start",
        "status": status,
        "headers": [
            (b"content-type", b"application/json"),
            (b"content-length", str(len(raw)).encode()),
            *_cors_for(origin),
        ],
    })
    await send({"type": "http.response.body", "body": raw, "more_body": False})


async def _read_body(receive):
    chunks = []
    while True:
        message = await receive()
        if message["type"] != "http.request":
            break
        chunks.append(message.get("body") or b"")
        if not message.get("more_body"):
            break
    return b"".join(chunks)


async def app(scope, receive, send):
    if scope["type"] != "http":
        return

    headers = {k.decode().lower(): v.decode() for k, v in scope.get("headers") or []}
    origin = headers.get("origin")
    method = scope.get("method", "GET")
    path = scope.get("path", "/")

    if method == "OPTIONS":
        await send({
            "type": "http.response.start",
            "status": 204,
            "headers": [(b"content-length", b"0"), *_cors_for(origin)],
        })
        await send({"type": "http.response.body", "body": b"", "more_body": False})
        return

    # This function serves one op. Anything else belongs to the HTTP API, and
    # answering it here would quietly create a second general coach API that
    # nobody meant to operate.
    if path.rstrip("/") != _ADVISOR_PATH or method != "POST":
        await _send_json(send, 404, {"error": "not_found"}, origin=origin)
        return

    # Auth first, and before anything that costs money. There is no authorizer
    # in front of this endpoint, so a rejected caller must not reach Bedrock and
    # must not consume anyone's daily allowance.
    try:
        claims = verify_supabase_token(bearer_token_from_headers(headers))
    except AuthError as e:
        print(f"advisor auth rejected: {e}")
        await _send_json(send, 401, {
            "error": "unauthorized",
            "message": "Valid Bearer token required",
        }, origin=origin)
        return

    user_id = claims["sub"]
    raw_body = await _read_body(receive)
    try:
        body = json.loads(raw_body or b"{}")
    except json.JSONDecodeError:
        await _send_json(send, 400, {
            "error": "invalid_json",
            "message": "Body is not valid JSON",
        }, origin=origin)
        return

    payload = body.get("payload", {}) or {}

    # Metered per USER TURN, not per model call, exactly as the buffered path
    # does it: a tool-calling turn is several invocations, and counting each one
    # would quietly cut a cap of 100 down to ~25 conversations a day. A
    # continuation hop is the one carrying tool results.
    #
    # It runs before the first frame, so a caller over the cap is told so rather
    # than watching a reply begin and stop.
    if _carries_tool_results(body):
        allowed, count = True, 0
    else:
        allowed, count = _check_rate_limit(bearer_token_from_headers(headers))
    if not allowed:
        if count < 0:
            await _send_json(send, 503, {
                "error": "rate_limit_unavailable",
                "message": "Service temporarily unavailable. Please try again.",
            }, origin=origin)
        else:
            print(f"rate_limit_hit user={user_id} count={count} cap={_DAILY_CAP}")
            await _send_json(send, 429, {
                "error": "rate_limit_exceeded",
                "message": f"Daily limit of {_DAILY_CAP} AI requests reached. "
                           "Try again tomorrow.",
            }, origin=origin)
        return

    # Build before committing to a 200. A malformed turn is still expressible as
    # a status code at this point; once the stream starts it is not, and the
    # client would have to read a failure out of the body instead.
    request, err = _build_advisor_request(payload)
    if err:
        status = err.get("statusCode", 400)
        try:
            error_body = json.loads(err.get("body") or "{}")
        except json.JSONDecodeError:
            error_body = {"error": "bad_request"}
        await _send_json(send, status, error_body, origin=origin)
        return

    print(f"advisor stream start user={user_id} bytes={len(raw_body)}")
    await send({
        "type": "http.response.start",
        "status": 200,
        "headers": [
            (b"content-type", b"application/x-ndjson"),
            # No buffering anywhere in the path — the entire point is that the
            # first token leaves before the last one exists.
            (b"cache-control", b"no-cache, no-transform"),
            (b"x-accel-buffering", b"no"),
            *_cors_for(origin),
        ],
    })

    for frame in advise_finance_stream(payload, request):
        await send({
            "type": "http.response.body",
            "body": frame.encode(),
            "more_body": True,
        })
    await send({"type": "http.response.body", "body": b"", "more_body": False})
