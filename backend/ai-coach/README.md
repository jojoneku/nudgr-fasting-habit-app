# AI Coach Backend

AWS Lambda + Amazon Bedrock endpoint for the AI Coach cloud tier.

## Stack
- **Runtime:** Python 3.12 (`lambda_function.lambda_handler`)
- **Framework:** AWS SAM (Serverless Application Model)
- **Region:** `ap-southeast-1`
- **Model:** Amazon Bedrock — Claude Haiku 3 (`anthropic.claude-haiku-20240307-v1:0`)
- **API:** API Gateway HTTP API (POST /coach) with a Supabase JWT authorizer
- **Auth:** API Gateway verifies the Supabase JWT (issuer = `https://<ref>.supabase.co/auth/v1`, audience = `authenticated`). Unauthenticated calls are rejected with 401.
- **Rate limiting:** per-user daily cap enforced via the Supabase `increment_ai_usage` RPC (see `docs/supabase_migration.sql`). No AWS-side datastore — the Lambda forwards the caller's Bearer token to PostgREST over HTTPS. Returns 429 when the cap is exceeded.

## Prerequisites
- AWS CLI configured (`aws configure`)
- AWS SAM CLI installed (`brew install aws-sam-cli` / `choco install aws-sam-cli`)
- Bedrock Claude Haiku access enabled in your AWS account (`ap-southeast-1`)
- The rate-limit table + RPC applied to your Supabase project (run `docs/supabase_migration.sql` in the Supabase SQL editor)

## Deploy

```bash
cd backend/ai-coach
sam build
sam deploy --guided \
  --parameter-overrides \
    SupabaseProjectRef=<your-project-ref> \
    SupabaseAnonKey=<your-anon-key> \
    DailyCap=100
```

On first deploy, SAM will prompt for stack name, region (`ap-southeast-1`), and create an S3 bucket for artifacts.
Copy the `AiCoachApiUrl` output — this goes in your Flutter app as `--dart-define=AI_COACH_ENDPOINT=<url>`.

> CI (`deploy_lambda` in `.github/workflows/ci.yml`) only updates function **code** on changes under `backend/ai-coach/`. Provisioning auth, env vars, and the API/authorizer requires a full `sam deploy` (the parameters above) at least once.

## Flutter integration

Pass the endpoint at build time:
```bash
flutter run --dart-define=AI_COACH_ENDPOINT=https://xxxx.execute-api.ap-southeast-1.amazonaws.com/coach
```

Or set it in `launch.json`:
```json
"args": ["--dart-define=AI_COACH_ENDPOINT=https://xxxx.execute-api.ap-southeast-1.amazonaws.com/coach"]
```

The client must send the current Supabase access token as `Authorization: Bearer <jwt>` — the authorizer rejects calls without it.

## Cost estimate (Claude Haiku 3)
| Volume | Input tokens | Output tokens | Cost/month |
|---|---|---|---|
| 1,000 calls/day | ~200 tok/call | ~150 tok/call | ~$2–3 |
| 5,000 calls/day | ~200 tok/call | ~150 tok/call | ~$10–15 |

$100 AWS credit ≈ 20–50 months at 1,000 calls/day. The per-user `DailyCap` bounds worst-case spend against abuse.

## Request format
```json
POST /coach
Authorization: Bearer <supabase-jwt>
{
  "op": "respond",
  "payload": {
    "context": {
      "entryPoint": "nutrition",
      "isFasting": true,
      "elapsedFastMinutes": 480,
      "fastingGoalHours": 16,
      "fastingStreak": 5,
      "playerLevel": 7,
      "playerXp": 2400,
      "playerHp": 85,
      "todayCalories": 1200,
      "calorieGoal": 1800
    },
    "messages": [
      { "role": "user", "text": "What should I eat to break my fast?" }
    ]
  }
}
```

Supported `op` values: `respond`, `parseFoodWithCandidates`, `disambiguateFood`, `extractFoodItems`, `estimateMacros`.

## Response
```json
{ "response": "After 8 hours fasted, break with protein + healthy fat first..." }
```

## The streaming advisor (`food-advisor-stream`)

`adviseFinance` runs on a **second function** with its own front door, because
the HTTP API in front of `food-coach-handler` cannot stream: its maximum
integration timeout is 30 seconds and AWS does not allow that to be raised. A
turn that took 43s finished in Lambda, was billed in full by Bedrock, and was
then discarded as a 504 the app reported as "the advisor had a hiccup on our
end". The other four ops stay on the HTTP API — they finish well inside 30s.

| | |
|---|---|
| Function | `food-advisor-stream` — ap-southeast-1, python3.12, **arm64**, 1024 MB, 45s |
| Handler | `run.sh`, via `AWS_LAMBDA_EXEC_WRAPPER=/opt/bootstrap` |
| Layer | `arn:aws:lambda:ap-southeast-1:753240598075:layer:LambdaAdapterLayerArm64:28` |
| URL | `https://hwshru3edc3n7clcvv6p57x42u0wivou.lambda-url.ap-southeast-1.on.aws/` |
| Route | `POST /v1/advisor` (everything else 404s — this is not a second coach API) |

### Turning it on

The app reads the URL from `AI_ADVISOR_ENDPOINT`. **Unset, the advisor uses the
old buffered path** — so enabling and rolling back are both one value:

1. Set the `AI_ADVISOR_ENDPOINT` repo secret to the URL above, with `/v1/advisor`.
2. Push to `main`. Clearing the secret rolls back with no code change.

### Three things that fail silently

- **`AWS_LWA_INVOKE_MODE=response_stream` is required.** Without it the adapter
  buffers and returns an API-Gateway-shaped body with `200` on the outside, so
  every error reads as a success.
- **Wheels must be built for `aarch64`** (`--platform manylinux2014_aarch64`).
  The runner's x86 wheels import fine in CI and die on Lambda.
- **`run.sh` must be LF and mode 0755.** With CRLF it fails at boot with `bad
  interpreter: /bin/bash^M` and nothing in the log explains it. `.gitattributes`
  pins `*.sh`; the packaging step sets the bit.

### Known blocker: anonymous access is refused

`AuthType: NONE` currently returns **403 before reaching the function**. The
resource policy is correct, the account is not in an Organization, and flipping
the same URL to `AWS_IAM` with a SigV4-signed request returns 200 and the app's
real response — so only the anonymous path is refused. The account also sits at
**10 Lambda concurrent executions** (default 1000), which is the same
new-account restricted state.

Needs AWS Support to allow public Function URLs on account `806880856566`. Until
then, leave `AI_ADVISOR_ENDPOINT` unset: pointing the app at a 403 makes every
advisor turn fail, which is worse than the timeout it replaces.
