## Why

Nudgy shows **"The advisor had a hiccup on our end"** partway through longer conversations. The Lambda is not failing — it finishes at 34s, 38s, 43s — but `food-coach-api` is an HTTP API, and an HTTP API's **maximum integration timeout is 30 seconds and cannot be increased** (AWS quota table: "Can be increased: No"). The gateway returns 504 at 30s, the client maps that non-200 to the hiccup string, and a fully-generated, fully-billed answer is discarded.

Measured over 24h on `food-coach-handler`: `turns=20 avg=19.7s max=43.4s over30s=5 (25%)`. Prompt caching (PR #608) and the 128→1024 MB memory bump bought headroom under the ceiling, but the ceiling is structural: the advisor is one blocking `invoke_model` behind a gateway that will never wait longer than 30s. A long enough conversation still crosses it.

Streaming removes the wall rather than raising it. Bytes start flowing in 1–2s, so a 45s answer is no longer a failure — and the user watches the reply arrive instead of a 20-second spinner. The generic chat path already renders incremental tokens this way; only the advisor path buffers.

## What Changes

- The `adviseFinance` op moves off the HTTP API onto a **Lambda Function URL with `InvokeMode: RESPONSE_STREAM`**, reached by a new `AI_ADVISOR_ENDPOINT` dart-define. Every other op (`respond`, `classifyFinance`, `parseFoodFromImage`, `parseFoodWithCandidates`) stays on `food-coach-api` untouched — they all finish well inside 30s and there is no reason to put them at risk.
- The handler keeps Python. Streaming is enabled with the **Lambda Web Adapter** layer (arm64, matching the function's architecture) wrapping the existing module in an ASGI app, so all prompt assembly, clipping, alternation enforcement, snapshot handling and the tool catalogue are reused rather than ported to another language.
- `_advise_finance` switches from `invoke_model` to **`invoke_model_with_response_stream`**, emitting text deltas as they arrive and a terminating metadata frame carrying the structured tail: `tool_calls`, `assistant_content`, `truncated`, and the `cost_line` usage numbers.
- **BREAKING (internal transport):** `AiCoachService.adviseFinance` returns `Stream<AdvisorEvent>` instead of `Future<AdvisorReply>`. `AdvisorReply` survives as the terminal event's payload, so the tool loop in `AiCoachPresenter._runAdvisorTurn` keeps its `wantsTools` / `assistantContent` contract. Callers must consume the stream; a partial stream that never terminates is an error, not an empty answer.
- **Authentication moves into the function.** A Function URL has no JWT authorizer, so `AuthType: NONE` plus in-function verification of the Supabase RS256 access token against the project JWKS replaces `event.requestContext.authorizer.jwt.claims`. Unverified requests get 401 before any Bedrock call.
- CORS for the advisor moves to the Function URL's own CORS config, mirroring `backend/ai-coach/cors.json` (the two Firebase origins, `authorization` + `content-type` named explicitly), and gets the same live assertion treatment as `scripts/check_api_cors.sh`.
- Mid-stream failures become a distinct, non-alarming state: a stream that dies after partial text keeps the text already shown and appends a retry affordance, rather than replacing a half-written answer with a red error bar.

## Non-goals

- **Not migrating the other ops.** `food-coach-api`, its JWT authorizer, its CORS config and the four short ops are out of scope. This change adds a second front door for one op; it does not replace the first.
- **Not migrating to a REST API.** REST APIs did gain response streaming (Nov 2025) with integration timeouts up to 15 minutes, but they have no built-in JWT authorizer — that is HTTP-API-only — so it trades this problem for a Lambda authorizer plus a full gateway migration.
- **Not porting the advisor to Node.js.** Native streaming without an adapter is real, but duplicating prompt assembly and the tool loop in a second language is a larger and more fragile change than adding a layer.
- **Not a client-side typewriter animation.** Animating an already-complete reply fixes nothing: the 30s 504 still happens, and the wait gets longer. Only real token delivery counts.
- **Not raising `ADVISOR_MAX_TOKENS`.** `stop=end_turn` throughout the logs — the ceiling was never the constraint. Streaming may make a higher ceiling *safe* later; that is a separate decision with its own cost.
- **Not touching prompt caching.** PR #608 stands as-is; the two cache breakpoints apply identically to the streaming call.
- **Not removing the buffered path.** It stays reachable so the op degrades to today's behavior if a build ships without `AI_ADVISOR_ENDPOINT`.

## Capabilities

### New Capabilities
- `advisor-streaming-transport`: How an advisor turn is delivered — the Function URL, the streaming envelope and its terminating metadata frame, in-function JWT verification, CORS, rate-limit accounting across a streamed turn, and what the client must do when a stream ends early.

### Modified Capabilities
- `ai-financial-advisor`: Delivery becomes incremental. The reply is rendered as it is produced, the tool loop resolves from a terminal event rather than a completed response body, and a turn is no longer required to finish inside 30s. The data-grounding contract, the tool-proposal rules and the daily cap are unchanged in substance — the cap must still meter one unit per user-initiated turn, now across a streamed multi-hop turn.

## Impact

**Backend** — `backend/ai-coach/lambda_function.py` (`_advise_finance` streaming rewrite; `_get_user_id` gains a Function-URL path), a new ASGI entrypoint, `requirements.txt` (JWT verification deps), `template.yaml`, `backend/ai-coach/cors.json`, and `.github/workflows/ci.yml` (`deploy_lambda` must publish the layer + Function URL config, and the CORS check must cover the new origin).

**Infrastructure** — a Function URL on `food-coach-handler` with `InvokeMode: RESPONSE_STREAM` and `AuthType: NONE`; the Lambda Web Adapter layer (arm64, ap-southeast-1). No CloudFormation stack exists, so this is hand-managed and must be written down in the design. `Timeout` (45s) becomes a real budget rather than a number nothing could reach.

**Client** — `lib/services/ai_coach_service.dart` (signature), `lib/services/cloud_ai_coach_service.dart` (chunked read via `http.Client().send()`, new endpoint constant, mid-stream error mapping), `lib/services/local_ai_coach_service.dart` and any null tier (must still throw), `lib/models/advisor_reply.dart` (event wrapper), `lib/presenters/ai_coach_presenter.dart` (`_runAdvisorTurn` consumes deltas and calls `_updateLastMessage(isStreaming: true)` like `respond` already does), and `test/mocks.mocks.dart` regeneration.

**Tests** — `test/services/advisor_timeout_test.dart` asserts the client timeout exceeds any gateway timeout; its reasoning changes once the advisor has no gateway. New coverage needed for delta accumulation, a terminal frame carrying tool calls, and a stream that dies mid-answer.

**Cost** — streamed responses are billed for the full function duration and are *not* interrupted when the client disconnects, so a 45s timeout is now genuinely payable. Worth stating in the design.
