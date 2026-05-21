# Plan 024 — Cloud AI for Food Logging (AWS Bedrock)

> **Status:** Draft, awaiting approval.
> **Use case (Phase 1):** Cloud-assisted food logging — extraction, disambiguation, macro estimation.
> **Stack:** Flutter app → API Gateway (HTTP API) → Lambda (Python or Node) → Amazon Bedrock.
> **Auth:** Supabase JWT validated inside Lambda (no Cognito).
> **Budget posture:** Balanced model that stretches a $100 Bedrock credit pool across months.

---

## 1. Why this exists

`CloudAiCoachService` already exists in `lib/services/cloud_ai_coach_service.dart` — it expects an
`AI_COACH_ENDPOINT` dart-define and POSTs JSON to it. Today only `respond()` (chat) is wired;
all food-related methods return `null`. The on-device Qwen3 0.6B path already handles
food extraction, disambiguation, and macro estimation (Plan 022). The cloud tier is meant
to be the **higher-quality fallback / opt-in upgrade** when:

- On-device model failed to download (low-end device, no storage).
- On-device disambiguation confidence is below `_llmConfidence = 0.70`
  (see `docs/rag_food_search_spec.md`).
- User explicitly toggles "Cloud AI" in Settings.

We are **not** replacing on-device. Cloud is an additive tier.

---

## 2. Model selection + cost estimation

Bedrock on-demand pricing, `ap-southeast-1` (Singapore), as of 2026-05. Per-request math assumes:
**~700 input tokens** (system prompt + 5 RAG candidates + user query)
+ **~200 output tokens** (structured JSON).

> **Note:** Claude Haiku 3.5 was retired by Anthropic when **Haiku 4.5** launched (Oct 2025). The Bedrock console now exposes Haiku 3 (legacy) and Haiku 4.5 (current).

| Model                        | $/1M in | $/1M out | Per call | $100 buys      | Quality verdict |
|------------------------------|--------:|---------:|---------:|---------------:|-----------------|
| **Amazon Nova Micro**        |  $0.035 |   $0.14  | $0.000053 | ~1.9M calls   | Cheapest. OK for plain disambiguation, weaker on macro estimation. |
| **Amazon Nova Lite**         |  $0.06  |   $0.24  | $0.000090 | ~1.1M calls   | Strong price/quality. Solid for structured JSON. |
| **Claude Haiku 3**           |  $0.25  |   $1.25  | $0.000425 | ~235k calls   | Legacy. Cheapest Claude. JSON adherence weaker than 4.5. |
| **Claude Haiku 4.5** ⭐      |  $1.00  |   $5.00  | $0.001700 | ~59k calls    | **Recommended.** Latest Haiku. Best JSON / tool-use for structured food parsing. |
| **Claude Sonnet 4.5**        |  $3.00  |  $15.00  | $0.005100 | ~19k calls    | Overkill for this — reserve for chat-coach replies if we expand later. |
| **Llama 3.1 8B Instruct**    |  $0.22  |   $0.22  | $0.000198 | ~505k calls   | Cheap, but JSON adherence weaker than Claude/Nova. |

### Solo-dev realistic usage

Assume **30 food logs/day**, of which **~30% are routed to cloud** (rest handled by on-device
+ FTS5 + personal dictionary). That's **~9 cloud calls/day = ~270/month**.

| Model              | Monthly cost @ 270 calls | $100 lasts |
|--------------------|-------------------------:|-----------:|
| Nova Micro         | $0.014                   | ~600 yrs   |
| Nova Lite          | $0.024                   | ~340 yrs   |
| Haiku 3             | $0.11                    | ~75 yrs    |
| Haiku 4.5          | $0.46                    | ~18 yrs    |
| Sonnet 4.5         | $1.38                    | ~6 yrs     |

**Decision: start with Claude Haiku 4.5.** Cost is trivial at our volume ($0.46–$5/month even at ceiling), and the JSON/tool-use upgrade over Haiku 3 means fewer parse failures = fewer wasted retry calls + cleaner UX. Keep model name in a Lambda env var (`BEDROCK_MODEL_ID`) so we can flip to Haiku 3 or Nova Lite without redeploying.

### Free tier coverage at this volume

| Service              | Free tier                                  | Our usage @ 100/day  | Out-of-pocket |
|----------------------|--------------------------------------------|----------------------|---------------|
| Lambda               | 1M req + 400k GB-s/month, forever         | ~3k req, ~50 GB-s    | $0            |
| API Gateway (HTTP)   | 1M calls/month, **first 12 months only**   | ~3k calls            | $0 (yr 1), ~$0.003 (yr 2+) |
| DynamoDB on-demand   | 25 GB + 25 R/WCU, forever                  | <1 MB, <100 ops      | $0            |
| CloudWatch Logs      | 5 GB ingest, forever                       | <100 MB              | $0            |
| **Bedrock inference**| **No free tier**                          | 900–3,000 calls      | **$1.22–$4.08/month** |

**Net:** with the $100 credit pool, total out-of-pocket is **$0 until 2027-04-15** (AWS Free Plan credit expiry). Projected credit burn over those 11 months: $11–44 of $100. After expiry, ~$1–4/month real dollars (assuming the account is upgraded to Paid Plan to keep the AWS resources running).

**Decision milestone — early 2027:** before credits expire, evaluate (a) actual usage + quality lift vs. on-device Qwen3, (b) whether to upgrade to Paid Plan ($1–4/month) or tear down (`sam delete`) and revert to on-device-only.

### Guardrails (hard caps)

- **AWS Budgets alert** at $5, $25, $50 of the $100 credit pool.
- **API Gateway throttle:** burst 5, rate 2 req/s (per route).
- **Lambda concurrency reservation:** 5.
- **Per-user soft cap:** 200 cloud calls/day, enforced in Lambda via DynamoDB counter.

---

## 3. Architecture

```
Flutter app
  └─ CloudAiCoachService (existing)
       │ POST https://<api>.execute-api.ap-southeast-1.amazonaws.com/v1/coach
       │ Authorization: Bearer <Supabase JWT>
       │ Body: { op, payload, context }
       ▼
API Gateway (HTTP API, JWT authorizer optional — see §4)
       ▼
Lambda  (food-coach-handler)
   ├─ Verify Supabase JWT (jose lib, JWKS from Supabase)
   ├─ Rate-limit check (DynamoDB: user_id → daily_count, TTL 24h)
   ├─ Switch on `op`:
   │     respond            → Bedrock InvokeModel (Haiku 4.5, streaming)
   │     extractFoodItems   → Bedrock + JSON schema enforcement
   │     disambiguateFood   → Bedrock + candidates context
   │     estimateMacros     → Bedrock + portion heuristics
   └─ Return { response | items | foodId+confidence | macros }
       ▼
Amazon Bedrock — anthropic.claude-haiku-4-5 (confirm exact model ID in console)
```

### Why not Cognito

Auth is already Supabase. Adding a Cognito Identity Pool just to mint AWS creds would
mean two auth systems. Cheaper to validate the **Supabase JWT** server-side in Lambda
(Supabase exposes JWKS at `<SUPABASE_URL>/auth/v1/keys`).

---

## 4. Request contract

Single endpoint, dispatched by `op`. Lets us reuse the existing
`CloudAiCoachService` HTTP code with minimal change.

```json
POST /v1/coach
Authorization: Bearer <supabase_jwt>
Content-Type: application/json

{
  "op": "extractFoodItems" | "disambiguateFood" | "estimateMacros" | "respond",
  "context": { ...AiCoachContext fields... },
  "payload": {
    // op-specific
  }
}
```

Response shape per op:

| op                | Response body                                                          |
|-------------------|------------------------------------------------------------------------|
| respond           | `{ "response": "<text>" }`                                             |
| extractFoodItems  | `{ "items": [{ name, grams, hyde }, ...] }`                            |
| disambiguateFood  | `{ "foodId": "...", "confidence": 0.0–1.0 }`                           |
| estimateMacros    | `{ "calories", "protein_g", "carbs_g", "fat_g" }`                      |

Errors always `{ "error": "<machine_code>", "message": "<human>" }` with appropriate HTTP status.

---

## 5. Lambda implementation notes

- **Runtime:** Python 3.12. `boto3` already includes Bedrock client. Add `python-jose[cryptography]` for JWT verify.
- **Cold start:** ~700 ms for first call in a region; acceptable for our request volume.
- **Streaming:** API Gateway HTTP API does **not** stream by default. For Phase 1, return non-streaming. Streaming chat is a Phase 2 upgrade via Lambda Function URLs + `awslambda.streamifyResponse`.
- **Prompt templates** live as constants in the Lambda — versioned alongside the food DB.
- **Bedrock model ID** comes from `BEDROCK_MODEL_ID` env var so we can switch models without redeploy.
- **JSON enforcement:** use Claude's tool-use feature with a schema, or `<json>` tagged stop-sequences.

---

## 6. Flutter side changes

| File                                       | Change                                                                |
|--------------------------------------------|-----------------------------------------------------------------------|
| `lib/services/cloud_ai_coach_service.dart` | Implement `extractFoodItems`, `disambiguateFood`, `estimateMacros`; add `op` to payload; pass Supabase JWT via `AuthService` |
| `lib/services/auth_service.dart`           | Expose `String? get currentAccessToken` (Supabase already manages refresh) |
| `lib/presenters/nutrition_presenter.dart`  | When confidence band hits LLM rerank and `useCloudAi` setting is on, call cloud disambiguation before on-device |
| `lib/presenters/settings_presenter.dart`   | Add `useCloudAi` toggle (default off until endpoint configured) |
| `lib/views/settings_view.dart`             | Toggle UI under "AI Coach" section, with "$ small monthly cost" note |
| `.env.example`                             | Add `AI_COACH_ENDPOINT=` placeholder |

Build command becomes:
```bash
flutter build apk --dart-define=AI_COACH_ENDPOINT=https://xyz.execute-api.ap-southeast-1.amazonaws.com/v1/coach
```

---

## 7. Infra deliverables (one-time AWS setup)

Stored as **IaC** — Terraform or AWS SAM. Recommend SAM for fewer moving parts.

```
infra/
  template.yaml          # SAM template
  src/coach_handler/
    handler.py
    prompts.py
    bedrock_client.py
    supabase_jwt.py
    requirements.txt
  README.md              # deploy instructions
```

Resources created:
1. **Bedrock model access** — Haiku 4.5 in `ap-southeast-1` (Singapore — closest region to PH, ~50–80 ms latency). The legacy "Model access" console page is retired; access auto-enables on first invocation. For Anthropic models, expect a one-time use-case form at first invoke. Fallback region: `ap-northeast-1` (Tokyo, ~100 ms) if Haiku 4.5 isn't yet available in Singapore.
2. **DynamoDB table** `coach_rate_limits` — PK `user_id`, attr `count`, TTL `expires_at`.
3. **Lambda** `food-coach-handler` — 512 MB, 30 s timeout, env vars: `BEDROCK_MODEL_ID`, `SUPABASE_URL`, `SUPABASE_JWT_AUD`, `DAILY_CAP`.
4. **IAM role** for Lambda — `bedrock:InvokeModel` on the specific model ARN, `dynamodb:GetItem/UpdateItem` on the table.
5. **API Gateway HTTP API** — single route `POST /v1/coach`, CORS for app origin (mobile uses no CORS, but keep loose for future web build).
6. **AWS Budgets** — $5/$25/$50/$90 email alerts to `eljon.blantucas@alphaus.cloud`.
7. **CloudWatch log group** — 7-day retention to stay in free tier.

---

## 8. Implementation phases

| Phase | Scope | Outcome |
|-------|-------|---------|
| **0 — Setup** | Bedrock model access, AWS profile, SAM CLI installed | Can `sam deploy` an empty stack |
| **1 — Lambda MVP** | Handler that does **disambiguateFood** only, Supabase JWT verify, rate limiter, deployed behind API Gateway | Curl + JWT returns valid response |
| **2 — Flutter wire-up** | `CloudAiCoachService.disambiguateFood` implemented; settings toggle; nutrition presenter routes to cloud when on-device confidence < 0.70 | Real device logs a tricky food via cloud |
| **3 — Extend ops** | Add `extractFoodItems` + `estimateMacros` handlers, prompts, schemas | Feature parity with on-device tier |
| **4 — Hardening** | DynamoDB rate-limit; budget alerts; structured logging; one-pager runbook | Ready to ship to other users |
| **5 — (Optional) Streaming chat** | Migrate `respond` to Function URL streaming for the coach chat | Token-by-token replies |

Phase 1+2 is the **minimum viable cloud AI** — ~1–2 days of work.

---

## 9. Open questions

1. **Region:** `ap-southeast-1` (Singapore) chosen for ~50–80 ms latency from PH. Confirm Haiku 4.5 is listed in this region during Phase 0 — otherwise fall back to `ap-northeast-1` (Tokyo, ~100 ms).
2. **Telemetry:** Do we want per-op latency/cost logging into a Supabase table for offline analysis? Or CloudWatch only?
3. **Failure UX:** If cloud is down and user enabled cloud-only mode, fall back to on-device silently or surface a banner?
4. **PII:** Food descriptions can contain incidental personal info. Confirm we're OK sending to Bedrock (AWS does not train on Bedrock data, but worth documenting in privacy section).

---

## 10. Non-goals for this plan

- Replacing the on-device tier.
- Cloud chat-coach streaming (deferred to Phase 5).
- Multi-region failover.
- Image-based food logging (still on the on-device roadmap separately).
- Migrating auth off Supabase.
