# Plan 034 — Audit: AI & Backend Infrastructure

> **Status:** Audit findings + remediation plan.
> **Severity of domain:** 🔴 High — an unauthenticated, unthrottled cloud endpoint is a direct billing/abuse exposure; the IaC does not match what's deployed, so the security posture is unverifiable.
> **One-sentence summary:** The AI tier abstraction is clean, but the backend has duplicate/divergent Lambda sources, IaC that describes a runtime that isn't deployed, no endpoint auth, no rate limiting, and several health-safety gaps in prompt handling.

---

## Architecture assessment

`AiCoachService` (`lib/services/ai_coach_service.dart`) is a clean interface with three impls — `NullAiCoachService` (canned), `OnDeviceAiCoachService` (Qwen3 0.6B via flutter_gemma), `CloudAiCoachService` (Lambda → Bedrock Claude Haiku). Implementations honor the interface consistently. **But tier selection is split and inconsistent:**
- **Chat** (`AiCoachPresenter`) only ever uses on-device — it imports only Null/OnDevice, `setTier()` is never called, the cloud service is never injected. So the "Cloud AI" toggle has **no effect on chat**, only on food parsing.
- **Food parsing** (`NutritionPresenter`) is cloud-primary with on-device/keyword fallback (`nutrition_presenter.dart:1768, 2044`). This path is solid.

---

## Findings

### 🔴 SEV-1 — Cloud endpoint has no auth, no JWT verification, no rate limiting
- **Where:** `backend/ai-coach/lambda_function.py:12-34` (== deployed `lambda.zip`).
- **Problem:** `lambda_handler` reads `op`/`payload` and dispatches straight to Bedrock. Zero auth. Plan 024 specified "Verify Supabase JWT (jose, JWKS)" and a `DAILY_CAP` — **neither implemented.** The client (`cloud_ai_coach_service.dart:58-64`) sends a Supabase Bearer token and its doc comment claims the Lambda's authorizer rejects unauthenticated calls — **false.**
- **Impact:** If the API Gateway is open (see SEV-2, it almost certainly is), anyone with the URL can invoke Bedrock Haiku on the owner's AWS account unlimited — unbounded, adversary-controlled billing, plus it processes prompts with user PII.
- **Fix:** Verify the Supabase JWT in-Lambda (signature vs JWKS, `aud`/`exp`) **or** a real API Gateway JWT authorizer (issuer = Supabase). Add a per-user daily cap (DynamoDB counter on `sub`). Return 401/429. *(Also tracked as C4 in Plan 030 — it's the top security risk.)*

### 🔴 SEV-1 — IaC (`template.yaml`) doesn't match what's deployed
- **Where:** `backend/ai-coach/template.yaml:7,21,43`.
- **Problem:** Template declares `Runtime: nodejs20.x`, `Handler: handler.handler` — but `handler.js` is a 2-line tombstone and the real artifact is Python. It also sets `DefaultAuthorizer: AWS_IAM`, which requires SigV4-signed requests; the client sends a plain Bearer token, which AWS_IAM would reject with 403. Since the cloud path demonstrably works, the live API Gateway is **not** running this template — it was deployed manually, auth almost certainly NONE. Template last touched in the original Qwen commit (`3b2b752`), never updated after the Node→Python pivot; README still says Node 20 / us-east-1 while code pins `ap-southeast-1`.
- **Impact:** No trustworthy source of truth for how the endpoint is secured. Combined with SEV-1 above, the likely reality is an open HTTP API in front of an unauthenticated Lambda.
- **Fix:** Rewrite `template.yaml` for `python3.12` + `lambda_function.lambda_handler`, add the Supabase JWT authorizer, correct region/model, redeploy from IaC so the live config is reproducible.

### 🔴 SEV-2 — Duplicate / divergent Lambda source; the repo-root copy is stale
- **Where:** root `lambda_function.py` (16 036 B) vs `backend/ai-coach/lambda_function.py` (19 385 B).
- **Problem:** `backend/ai-coach/lambda_function.py` is byte-identical to the deployed `lambda.zip`; the **root copy is the older version**, missing the macro fallback safety net (`_normalize_parsed_items`) and the single-item explicit-gram override (`_extract_single_explicit_grams`). `handler.js` is a tombstone; `package.json` still declares the Node SDK + `main: handler.js`.
- **Impact:** A maintainer editing/deploying the obvious top-level `lambda_function.py` ships a regression.
- **Fix:** Delete the root `lambda_function.py`, `handler.js`, and the Node `package.json` (replace with Python `requirements.txt`). Single source under `backend/ai-coach/`. **Don't commit `lambda.zip` — build it in CI.**

### 🟠 SEV-3 — `respond` op can send Bedrock a non-alternating / assistant-first message list → 502
- **Where:** `lambda_function.py:379-383`, `cloud_ai_coach_service.dart:108-114`.
- **Problem:** The client forwards full history mapped to user/assistant roles; the Lambda filters empties but doesn't enforce strict alternation starting with `user`. Bedrock rejects non-alternating lists with a ValidationException → 502. (Currently the cloud `respond` is unreachable from the chat UI per the architecture note, but the code path exists.)
- **Fix:** Coalesce consecutive same-role turns; drop any leading assistant message.

### 🟠 SEV-3 — Cloud failure is silent/degrading and falls through to a ~2 kcal/g fabricated estimate
- **Where:** `lambda_function.py:285-293` (`_normalize_parsed_items` synthesizes `kcal = grams * 2.0` + 15/50/35 split), `cloud_ai_coach_service.dart:80-89`. On-device `_fillMacros` does the same (`on_device_ai_coach_service.dart:503-518`).
- **Problem:** For a **health app**, silently logging a fabricated calorie figure with no "rough estimate" disclaimer is a data-quality/trust risk. The `_macro_fallback` flag is computed then stripped before returning.
- **Fix:** Propagate the fallback flag and surface fabricated/low-confidence estimates distinctly in the UI, and/or drop confidence into a band that forces user confirmation. (Ties to Plan 033 H1/H3.)

### 🟠 SEV-3 — Prompt injection: user food text / chat interpolated into prompts unescaped
- **Where:** `lambda_function.py:77,141,332`; on-device `on_device_ai_coach_service.dart:258,542,594`.
- **Problem:** User text is concatenated directly into prompts. Crafted input can steer JSON output (e.g. inflate calories) or steer the chat `respond` path toward unsafe health advice. Blast radius for parsing is limited because `food_id` is validated against the candidate set client-side, but injected macro values and intent-flipping remain real for a health app.
- **Fix:** Keep server-side allow-list validation of all returned ids; clamp macro outputs to sane ranges; add a safety guardrail to the coaching system prompt (no medical/dosage advice; defer to professionals). Consider Bedrock structured-output / tool-use to avoid free-form JSON parsing.

### 🟡 SEV-4 — No server-side request-size or candidate clamp; cost is client-trusted
- **Where:** `lambda_function.py:132` does `candidates[:15]` but doesn't bound `text` length; `max_tokens` up to 1024.
- **Fix:** Bound input length; enforce the SEV-1 daily cap.

---

## On-device model notes
- Qwen3 0.6B `.litertlm` (~586 MB) pulled from a HuggingFace `resolve/main` URL (`on_device_ai_coach_service.dart:32-33`), gated → needs the HF token (Plan 030 H2). **Direct download with no CDN, no integrity check, no version pin** — if the repo moves/changes, downloads break silently for new users.
- `ai_estimation_service.dart` is an apparently **dead/legacy** second model stack (Gemma 3 1B IT, ~700 MB, `litert-community/Gemma3-1B-IT`). Two download stacks coexist — confirm `AiEstimationService` is wired anywhere; if not, remove it.
- Init/compat handling is reasonable (GPU→CPU fallback; OpenCL/litert error strings flip `_deviceIncompatible`, `_loadModel:102-126`) but the substring-match on error text is brittle across plugin versions. A 0.6B int model + 4096 context risks OOM on low-end Android (handled by failing to "incompatible" rather than crashing, assuming the plugin throws).

## Scalability / cost
Architecturally fine (stateless Lambda + Haiku; boto3 client is module-level so connections reuse). README's ~$2–15/mo estimate is plausible *if access were controlled* — but with no auth and no rate limit (SEV-1), cost is unbounded and adversary-controlled.

---

## Remediation order
1. **SEV-1 (auth + rate limit)** — the one fix that closes the billing exposure.
2. **SEV-1 (IaC) + SEV-2 (source dedup)** — make deployment reproducible and delete the stale root copy / Node leftovers; build `lambda.zip` in CI.
3. **SEV-3 health-safety** — propagate the fallback flag, clamp macros, add the coaching safety guardrail.
4. **SEV-3 (respond alternation)** + decide chat's tier story (wire cloud into `AiCoachPresenter` or document that "Cloud AI" only affects food parsing).
5. **SEV-4** clamps; remove the dead `AiEstimationService`; pin/verify the model download.

## Definition of done
- The endpoint rejects unauthenticated calls and enforces a per-user daily cap.
- `template.yaml` deploys the actual Python Lambda + authorizer; `lambda.zip` is CI-built, not committed.
- One Lambda source of truth; no Node leftovers, no stale root copy.
- Fabricated estimates are visibly flagged; macros clamped; coaching prompt has a safety guardrail.
