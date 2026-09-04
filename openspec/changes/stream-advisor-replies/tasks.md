## Status

Code is implemented and verified; infrastructure is not created yet, so nothing
is live. `flutter analyze` and `dart format` clean, full suite 1785 passing.

Two gaps worth knowing before this ships, both called out on their tasks below:

- **The auth helper has no test yet.** It is the entire security boundary for an
  `AuthType: NONE` endpoint, and PyJWT is not installed in this environment
  (`pip install` unavailable), so §2.2/§2.4 could not be executed here. Do not
  create the Function URL until they are.
- **The arm64 wheel check (§2.1) did not run** for the same reason.

Verified against real Bedrock through `advise_finance_stream` itself:

| case | ttfb | total | cache_read | cache_write |
|---|---|---|---|---|
| cold | 2.30s | 7.40s | 0 | 6,670 |
| warm | **1.55s** | 9.39s | **6,670** | 21 |

Prompt caching survives the streaming call, and a `tool_use` turn reassembled
its `input_json_delta` fragments into valid JSON
(`{'amount': 1500, 'pocket': 'Emergency Fund'}`).

---

## 1. Answer the blocking question first

- [x] 1.1 Spike whether a Flutter **web** build surfaces incremental chunks from `http.Client().send()`, or whether the browser shim buffers the whole body. Throwaway page against any chunked endpoint; verify by timestamping the first and last chunk. Record the answer in design.md's Open Questions — it decides whether web needs a separate `fetch`-based reader and whether "web first" rollout ordering survives.

## 2. In-function authentication (security boundary — lands before anything is reachable)

- [ ] 2.1 Add `PyJWT[crypto]` to `backend/ai-coach/requirements.txt`; confirm the built zip still installs clean on `python3.12`/arm64. **(dependency added; the arm64 wheel check did not run — pip unavailable here)**
- [ ] 2.2 Add a `_verify_supabase_token(token)` helper: fetch the project JWKS once, cache it at module scope, verify RS256 signature + `exp` + `iss`, return claims or raise. Unit-test against a valid token, an expired one, one signed by a foreign key, a malformed one, and an absent one. **(written as `verify_supabase_token`; TESTS STILL OWED — no local PyJWT, and this is the whole security boundary)**
- [ ] 2.3 Teach `_get_user_id` a Function-URL path: prefer gateway authorizer claims when present, fall back to verified-token claims. Existing gateway behavior must be unchanged — assert with a test using a synthetic API Gateway event. **(implemented; the synthetic-event test is still owed)**
- [ ] 2.4 Reject unauthenticated requests with 401 **before** any Bedrock call or rate-limit spend. Test that a 401 path performs no model invocation. **(implemented in `app.py`; test still owed)**

## 3. Streaming handler

- [x] 3.1 Add the ASGI entrypoint that LWA fronts, routing `POST /v1/advisor` to the advisor op only. Other ops must return 404 here — this function is not a second general coach API.
- [x] 3.2 Rewrite `_advise_finance` onto `invoke_model_with_response_stream`, yielding NDJSON frames: `start`, then `delta` per text chunk, then `end` carrying `tool_calls` / `assistant_content` / `truncated` / `usage`. Keep the existing prompt assembly, clipping, `_enforce_alternation` and both `cache_control` breakpoints from PR #608 untouched.
- [x] 3.3 Emit `{"type":"error"}` for a failure after the first byte, and make sure a mid-stream exception cannot close the connection silently without a terminal frame.
- [x] 3.4 Rebuild the `cost_line` log from stream events — `latency_ms`, `in_tokens`, `out_tokens`, `cache_read`, `cache_write`, `stop`, `tools`, `calls`, `hop` — plus a new time-to-first-token figure. Verify `cache_read` is still non-zero on a warm second turn; if it is not, the caching win has been lost and 3.2 is wrong.
- [x] 3.5 Charge the daily rate limit on `hop=first` only, before the first delta, reusing `_carries_tool_results`. Test that a three-hop turn counts one unit and that an over-cap caller gets the limit with no deltas sent.

## 4. Infrastructure (hand-managed — no CloudFormation stack exists)

- [ ] 4.1 Create `food-advisor-stream` in ap-southeast-1: python3.12, arm64, 1024 MB, 45s timeout, same env map as `food-coach-handler`, and the additive Bedrock IAM policy. Record every value in the memory note — nothing here is in a template.
- [ ] 4.2 Attach the arm64 Lambda Web Adapter layer for ap-southeast-1 and confirm the function still responds to a plain buffered invoke.
- [ ] 4.3 Create the Function URL with `InvokeMode: RESPONSE_STREAM`, `AuthType: NONE`, and CORS mirroring `backend/ai-coach/cors.json` — both Firebase origins, `authorization` + `content-type` named explicitly, never a wildcard.
- [ ] 4.4 Verify by `curl` that deltas arrive incrementally (timestamp first vs last byte), that a 40s+ answer completes, and that an unauthenticated call gets 401.
- [ ] 4.5 Extend CI `deploy_lambda` to deploy both functions from the same zip in the same job, and add a live post-deploy assertion of the Function URL's CORS + env keys, in the spirit of `scripts/check_api_cors.sh`.

## 5. Client transport

- [x] 5.1 Add `AdvisorEvent` (`start` / `delta` / `end` / `error`) with `AdvisorReply` unchanged as the `end` payload. Unit-test `fromJson` for each frame type.
- [x] 5.2 Change `AiCoachService.adviseFinance` to `Stream<AdvisorEvent>`; update the on-device and null tiers to keep throwing `AiCoachException`, and regenerate `test/mocks.mocks.dart`.
- [x] 5.3 Implement the NDJSON reader in `CloudAiCoachService` on `http.Client().send()` against a new `AI_ADVISOR_ENDPOINT` dart-define. Buffer across chunk boundaries; test adversarial splits including one inside a JSON object and one inside a multi-byte UTF-8 character.
- [x] 5.4 Treat a stream that ends without a terminal frame as a failure, never as a complete short answer. Test explicitly — this is the failure mode that would present half an answer as the whole one.
- [x] 5.5 Keep the buffered path as the fallback when `AI_ADVISOR_ENDPOINT` is empty, so a build without the define behaves exactly as today. Test both branches.

## 6. Presenter and UI

- [x] 6.1 Rework `_runAdvisorTurn` to consume deltas the way `respond()` already does — accumulate, `_updateLastMessage(…, isStreaming: true)`, `safeNotify()`, and honour `isDisposed` so a dismissed sheet stops updating mid-stream.
- [x] 6.2 Resolve the tool loop from the `end` event, replaying `assistantContent` verbatim. Confirm prose written alongside tool calls still displays before the tools run, and that the hop limit still reports honestly.
- [ ] 6.3 Add the unfinished-turn state: partial prose stays on screen, marked unfinished, with a retry affordance — not replaced by a red error bar, and not marked as a finished assistant turn. Widget-test the three end states (complete / unfinished / failed-before-first-delta). **(state + all three end cases covered at presenter level in `test/presenters/advisor_streaming_test.dart`; the retry AFFORDANCE itself is not built — it lands with the retry/edit change)**
- [x] 6.4 Rewrite `test/services/advisor_timeout_test.dart`: with no gateway on the advisor path, the assertion becomes about the function budget, not a gateway timeout. Update the comment to say why, so the next reader is not misled by the old reasoning.

## 7. Roll out

- [ ] 7.1 Enable `AI_ADVISOR_ENDPOINT` for the web build; watch `cost_line` for time-to-first-token, for `cache_read` staying non-zero, and for the 504s stopping.
- [ ] 7.2 Enable it for mobile once web is clean for a few days.
- [ ] 7.3 Re-run the 24h latency query and confirm `over30s` failures are gone rather than merely rarer.
- [ ] 7.4 Update the `project_ai_coach_lambda_target` memory with the second function, its Function URL, the LWA layer ARN, and the auth model — none of it is in a template, and the note is the only record.
- [ ] 7.5 Retire the buffered advisor path only after a period with no fallbacks in the wild; leave `food-coach-handler` untouched either way.
