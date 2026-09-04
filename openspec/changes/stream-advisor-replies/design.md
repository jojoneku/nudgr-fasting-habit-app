## Context

An advisor turn today is one blocking `invoke_model` inside `food-coach-handler`, reached through `POST /v1/coach` on the HTTP API `food-coach-api` (`hjqhlbkiw1`, ap-southeast-1), behind a JWT authorizer. The function's own timeout is 45s and the client waits 120s, but the gateway integration timeout is 30,000 ms — and for an HTTP API that is a hard ceiling, not a default:

> | Maximum integration timeout | 30 seconds | Can be increased: **No** |

So the only component that gives up is the one nobody can reconfigure. Past 30s the gateway returns 504, `CloudAiCoachService` maps the non-200 to "The advisor had a hiccup on our end", and an answer the model finished writing — and Bedrock billed — is thrown away. CloudWatch over 24h: `turns=20 avg=19.7s max=43.4s over30s=5 (25%)`.

Two mitigations already landed and are assumed here: prompt caching (PR #608, two `cache_control` breakpoints, verified cold `cache_write=9805` → warm `cache_read=9805`, 11,970ms → 8,167ms) and memory 128 → 1024 MB. Both bought headroom under the ceiling. Neither moved it.

Constraints that shape every decision below:

- **Lambda response streaming is not available on the Python managed runtime.** Node.js managed runtimes only; otherwise a custom runtime or the Lambda Web Adapter. (Streaming reached all commercial regions in April 2026, so ap-southeast-1 is fine.)
- **HTTP APIs cannot stream at all.** REST APIs gained it in Nov 2025 with integration timeouts up to 15 minutes; HTTP APIs never did.
- **There is no CloudFormation stack.** The function, API, authorizer and CORS are hand-managed; `template.yaml` is stale and already documented as untrustworthy. CI only pushes function code.
- **The advisor is one op among five.** `respond`, `classifyFinance`, `parseFoodFromImage` and `parseFoodWithCandidates` all finish comfortably inside 30s and have no reason to be put at risk.
- The client's tool loop calls `adviseFinance` once per hop and already distinguishes first hop from continuation server-side (`hop=first|cont` via `_carries_tool_results`).

## Goals / Non-Goals

**Goals:**

- No advisor turn that the model completes is ever reported as a server error.
- Time to first token is a few seconds regardless of total reply length; the user reads the answer as it is written.
- The Python prompt-assembly logic — system prefix, clipping, alternation enforcement, snapshot and historical handling, tool catalogue, caching breakpoints — is reused, not reimplemented.
- Blast radius stays on the advisor. The four short ops keep their current transport, authorizer and CORS untouched.
- A build without the new endpoint still works, on today's buffered behavior.

**Non-Goals:**

- Migrating the other four ops, or the HTTP API, its JWT authorizer, or its CORS config.
- Migrating to a REST API. Streaming plus 15-minute timeouts is genuinely attractive, but REST has no built-in JWT authorizer (HTTP-API-only), so it trades this problem for a Lambda authorizer plus a full gateway migration.
- Porting the advisor to Node.js for native streaming.
- Raising `ADVISOR_MAX_TOKENS`. `stop=end_turn` throughout the logs; the ceiling was never the constraint.
- A client-side typewriter over an already-complete reply. It fixes nothing and lengthens the wait.

## Decisions

### 1. A second Lambda, not a second door on the existing one

**Decision:** add `food-advisor-stream`, a new function built from the same `backend/ai-coach/` source tree, with the Lambda Web Adapter layer and a Function URL (`InvokeMode: RESPONSE_STREAM`, `AuthType: NONE`). `food-coach-handler` is not modified.

The obvious-looking alternative is to keep one function and give it both an API Gateway trigger and a Function URL. It does not survive contact with LWA: LWA replaces the handler with a bootstrap that runs a web server and proxies *every* invocation to it, API Gateway events included. That turns the entry layer for all five ops into a rewrite — precisely the blast radius this change is trying to avoid, and on the path that photo logging and chat classification depend on.

Two functions from one source tree keeps the proven buffered path byte-identical while the advisor changes shape. The cost is a second deploy target and a second env map to keep in sync; both are mitigated in the migration plan by deploying both from the same zip and asserting env keys.

*Alternatives considered:* one function with two entrypoints (rejected above); a custom runtime instead of LWA (more moving parts than a layer, for the same result); Node.js rewrite (duplicates prompt assembly and the tool loop in a second language).

### 2. Newline-delimited JSON as the wire format

**Decision:** the stream is NDJSON — one JSON object per line, `\n`-terminated.

```
{"type":"start"}
{"type":"delta","text":"You are at "}
{"type":"delta","text":"4,120 of a 6,000 budget"}
{"type":"end","tool_calls":[],"assistant_content":[…],"truncated":false,"usage":{…}}
```

Chosen over SSE because nothing here benefits from SSE's framing: the client cannot use `EventSource` anyway (it needs POST with an `Authorization` header), so SSE would only add `data:` prefixes and blank-line framing to parse by hand. NDJSON is one `split` on newline in Dart, and each frame is already a typed object.

Chosen over API Gateway's metadata-plus-eight-null-bytes envelope because that format exists to satisfy a gateway we have deliberately removed from this path.

The client must buffer across chunk boundaries — a network chunk can split a line mid-object — so it accumulates until it sees `\n` and parses complete lines only.

### 3. Failures after the first byte need their own frame

Once the response's 200 and headers are on the wire, the status code can no longer express failure. A Bedrock error at token 400 cannot become a 502.

**Decision:** three terminal outcomes, explicit on the wire. `{"type":"end",…}` is success. `{"type":"error","message":…}` is a failure the server recognised. A closed connection with neither is a failure the server did not survive. The client treats a stream lacking a terminal frame as failed — never as a complete short answer, which is the failure mode that would silently present half an answer as the whole one.

The `{"type":"start"}` frame exists so the client can distinguish "stream established, model working" from "still connecting", which is what lets the UI drop the spinner at the right moment.

### 4. The function verifies the Supabase token itself

The Function URL has no JWT authorizer, so `event.requestContext.authorizer.jwt.claims` — what `_get_user_id` reads today — is simply absent. Auth moves into the function.

**Decision:** verify the RS256 access token locally against the project's JWKS (signature, `exp`, `iss`), with the key set fetched once and cached at module scope so warm invocations pay nothing. The signing key is already RSA/RS256 from the original authorizer work, so no Supabase-side change is needed. `sub` from the verified claims becomes the rate-limit identity.

*Alternative considered:* verify by calling Supabase `/auth/v1/user` with the bearer token. Tempting — no new dependencies, and the function already makes a Supabase call per turn for rate limiting. Rejected because it puts an external network round trip on the authentication decision for a publicly-reachable endpoint, and a flaky dependency then forces a choice between failing closed (an outage) and failing open (an open endpoint). Local verification has neither failure mode.

This adds `PyJWT[crypto]` to `requirements.txt` — the first real dependency beyond boto3, taking the package from ~23 KB to a few MB. Acceptable; noted as the one place this change grows the artifact.

`AuthType: NONE` means the endpoint is reachable by anyone, so this verification is the entire security boundary. It gets reviewed as such, and the spec requires rejection before any model call so an unauthenticated flood cannot cost money.

### 5. `Stream<AdvisorEvent>`, with `AdvisorReply` preserved

**Decision:** `AiCoachService.adviseFinance` returns `Stream<AdvisorEvent>`. `AdvisorReply` is unchanged and becomes the payload of the terminal event, so `_runAdvisorTurn`'s `wantsTools` / `assistantContent` / `truncated` contract survives intact and the tool loop keeps working as written.

This is a wider signature change than "make it a stream of strings" because the advisor's turn is not just text — it can end in tool calls, and the loop needs the verbatim assistant turn to replay. A `Stream<String>` would have to smuggle that out of band.

The UI machinery already exists and is proven: `respond()` does `await for (final token in stream)` → `buffer.write` → `_updateLastMessage(…, isStreaming: true)` → `safeNotify()`, including the `isDisposed` check that stops updating when the sheet is dismissed mid-stream. `_runAdvisorTurn` adopts the same shape; the deltas differ, the rendering does not.

### 6. Metering stays once per user-initiated turn

The tool loop calls the endpoint once per hop, so "once per turn" has to be decided server-side. The existing `hop=first|cont` detection via `_carries_tool_results` already does exactly this and is reused unchanged — the rate limit is charged on `hop=first` only.

Metering runs *before* the first delta, so a user over the cap gets the limit message instead of watching a reply start and stop.

## Risks / Trade-offs

- **`AuthType: NONE` exposes the endpoint to the internet** → in-function verification is the only boundary; it must reject before any Bedrock call, and the rejection path gets explicit test coverage. Treat the auth code as security-critical in review, not as plumbing.
- **Streamed responses are billed for the full function duration and are not interrupted when the client disconnects** → a 45s timeout is now genuinely payable, and a user who closes the sheet still pays for the rest of the generation. Keep the timeout at 45s rather than raising it toward the 15-minute maximum just because streaming permits it.
- **Two functions can drift in env config** → deploy both from the same zip in the same CI job, and assert the expected env keys after deploy the way `scripts/check_api_cors.sh` asserts live CORS. The existing memory note that `update-function-configuration --environment` *replaces* the whole map applies twice as much now.
- **LWA is a new dependency in the request path** → the buffered path stays reachable behind the absent-endpoint fallback, so a broken adapter degrades to today's behavior rather than to no advisor.
- **A half-written answer is a new UI state** → without care it reads as either a finished answer or a hard error. The spec pins both: keep the prose, mark it unfinished, offer retry, and exclude it from replay as a completed turn.
- **Chunk-boundary parsing is easy to get subtly wrong** → a split JSON line must be buffered, not dropped or parsed twice. Deserves a unit test with deliberately adversarial chunk splits, including a split inside a multi-byte UTF-8 character.
- **CORS on a Function URL is a second, differently-shaped config** → the earlier CORS outage cost a full debugging session on the gateway; the same trap exists here. Assert it live.
- **Prompt caching interacts with streaming** → `cache_read`/`cache_write` arrive in the streaming usage metadata rather than the response body. The `cost_line` telemetry must be rebuilt from stream events or the caching win becomes unobservable.

## Migration Plan

1. Land the backend behind no client change: build `food-advisor-stream`, its LWA layer, Function URL and CORS; verify with `curl` that deltas arrive incrementally and that an unauthenticated call is rejected.
2. Add the client `Stream<AdvisorEvent>` path behind the `AI_ADVISOR_ENDPOINT` dart-define. Absent define → existing buffered path, so `dev` stays shippable throughout.
3. Enable the define for web first (fastest to deploy and observe), then mobile.
4. Watch `cost_line` for TTFB and for `cache_read` staying non-zero; confirm the 504s stop.
5. Retire the buffered advisor path only after a period with no fallbacks in the wild.

**Rollback:** unset `AI_ADVISOR_ENDPOINT` and rebuild. The buffered path and `food-coach-handler` are untouched throughout, so rollback needs no infrastructure change.

## Open Questions

- ~~Does the Flutter **web** build surface incremental chunks from `http.Client().send()`?~~ **Answered: yes.** `http` 1.6.0's `BrowserClient` uses `fetch` and reads the response through a `ReadableStreamDefaultReader`, pumping chunks out via `Stream.multi` (`browser_client.dart`, `_readStreamBody`) — not the XHR buffer-everything path assumed when this was written. So `Client.send` streams natively on both platforms, no `fetch_client` dependency is needed, one code path serves both, and the "web first" rollout ordering stands.
- Do the four short ops want the same `hop`-aware metering later, or does per-turn metering stay advisor-only?
- Should `test/services/advisor_timeout_test.dart` keep asserting the client timeout exceeds a gateway timeout once the advisor has no gateway, or be rewritten to assert it exceeds the *function* budget?
- Is a second function the long-term shape, or a waypoint until the short ops move to LWA too and the two collapse back into one?
