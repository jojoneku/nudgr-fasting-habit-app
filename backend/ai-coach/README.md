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
| Function | `food-advisor-stream` — ap-southeast-1, python3.12, **arm64**, 1024 MB, **120s** |
| Handler | `run.sh`, via `AWS_LAMBDA_EXEC_WRAPPER=/opt/bootstrap` |
| Layer | `arn:aws:lambda:ap-southeast-1:753240598075:layer:LambdaAdapterLayerArm64:28` |
| URL | `https://hwshru3edc3n7clcvv6p57x42u0wivou.lambda-url.ap-southeast-1.on.aws/` |
| Route | `POST /v1/advisor` (everything else 404s — this is not a second coach API) |

### Turning it on

The app reads the URL from `AI_ADVISOR_ENDPOINT`. **Unset, the advisor uses the
old buffered path** — so enabling and rolling back are both one value:

1. Set the `AI_ADVISOR_ENDPOINT` repo secret to
   `https://d117xbrhlnuvq9.cloudfront.net/v1/advisor` (the CloudFront domain,
   not the Function URL — see below).
2. Push to `main`. Clearing the secret rolls back with no code change.

### The wall clock, which is what actually ends a long turn

`max_tokens` is the backstop; **time is the real limit**. The function was set to
45s, and a long answer was still being generated when Lambda killed it. The
stream then stopped with no `end` and no `error` frame — and the app is required
to treat a stream with no terminator as a failure, because the alternative is
presenting half an answer as a whole one. So it wiped the prose already on
screen, re-generated the same long answer into the same 45s ceiling, and did it
three times before giving up. The user saw "Connection hiccup — trying again…"
three times and kept nothing; Bedrock billed all three.

**`ADVISOR_STREAM_BUDGET_SEC` (default 38s)** is what makes that unreachable. It
is a soft deadline inside `advise_finance_stream`: when it is spent the turn
breaks out of the Bedrock stream, appends a line saying it stopped early, and
emits a real `end` frame. The user reads a short answer instead of an error, and
the client has nothing to retry.

The default has to be correct for the timeout the function **actually** has,
which is 45s. A budget above the real timeout is not a budget — the function
dies first and the mechanism never fires. So 38s: enough for a reply written to
the ~900-word budget the prompt states, truncating the overshoots, with ~7s left
to flush the closing frames through the adapter and CloudFront.

#### Raising the ceiling (one-time, needs console or admin CLI)

38s truncates genuinely long answers. To let them finish, raise the function
timeout and the budget **together, in one call** — a budget left at 38 under a
120s timeout just truncates early, and a budget of 100 under a 45s timeout does
nothing at all:

```sh
aws lambda update-function-configuration \
  --function-name food-advisor-stream --region ap-southeast-1 \
  --timeout 120 \
  --environment "Variables={ADVISOR_STREAM_BUDGET_SEC=100,<every existing key>}"
```

⚠️ `--environment` **replaces the whole map**. Read the current one first
(`aws lambda get-function-configuration`) and repeat every existing key, or the
function loses `AWS_LWA_INVOKE_MODE`, `SUPABASE_URL`, the model ids, and the
rest — and dies at boot.

120s is the ceiling because it matches `CloudAiCoachService.advisorTimeoutSeconds`,
the client's own limit, which must stay at or above the function's (a client that
gives up first shows a connection error while the backend is still working
happily). Raise the client first, ship it, then raise this.

**This is not done from CI.** `github-ci-lambda-deploy` is scoped to
`update-function-code`; a `update-function-configuration` call from the deploy
job fails with `AccessDeniedException` and takes the whole job down with it,
smoke test included. That was tried on 2026-09-11 and reverted the same day. To
move it into CI, grant that user `lambda:UpdateFunctionConfiguration` on this
function first.

CloudFront's 60s origin read timeout is **not** a cap on the whole response: it
bounds the gap between packets, and a streaming turn emits deltas continuously.
It is worth re-checking there first if a long turn still dies at ~60s, since
CloudFront's own maximum is 60s without a quota increase.

### Three things that fail silently

- **`AWS_LWA_INVOKE_MODE=response_stream` is required.** Without it the adapter
  buffers and returns an API-Gateway-shaped body with `200` on the outside, so
  every error reads as a success.
- **Wheels must be built for `aarch64`** (`--platform manylinux2014_aarch64`).
  The runner's x86 wheels import fine in CI and die on Lambda.
- **`run.sh` must be LF and mode 0755.** With CRLF it fails at boot with `bad
  interpreter: /bin/bash^M` and nothing in the log explains it. `.gitattributes`
  pins `*.sh`; the packaging step sets the bit.

### Reached through CloudFront, not directly

The account refuses **anonymous** Function URL access: `AuthType: NONE` returns
403 before the request reaches the function, even with a correct resource
policy, and the account is not in an Organization. (It also sits at 10 Lambda
concurrent executions against a default of 1000, which is the same new-account
restricted state.) Flipping the same URL to `AWS_IAM` and sending a signed
request returns 200, so only the anonymous path is refused.

So the Function URL is `AWS_IAM` and a CloudFront distribution fronts it with
Origin Access Control. The app calls CloudFront anonymously; CloudFront
SigV4-signs to the Lambda. Nothing is publicly invokable.

| | |
|---|---|
| Distribution | `E3BTW8ND61SRIT` |
| Domain | `d117xbrhlnuvq9.cloudfront.net` |
| OAC | `E3NOOYYUKZCLJJ` — `lambda` type, sigv4, always sign |
| Endpoint | `https://d117xbrhlnuvq9.cloudfront.net/v1/advisor` |

Configured deliberately: caching **disabled**, compression **off** (it can force
buffering and defeat streaming), origin read timeout **60s** — a per-packet
idle timeout, not a cap on the whole response, so it clears a 120s streaming
turn as long as deltas keep arriving — and origin request policy
`AllViewerExceptHostHeader` — OAC has to
set the Host header it signs against, so forwarding the viewer's would break
every signature.

Two resource-policy statements are required, not one: `lambda:InvokeFunctionUrl`
**and** `lambda:InvokeFunction`, both for `cloudfront.amazonaws.com`, both
scoped by `AWS:SourceArn` to this distribution. With only the first, requests
fail with Lambda's generic "Forbidden" and look identical to the account block.

**The token cannot travel in `Authorization`.** OAC signs origin requests by
*writing* that header — the SigV4 signature goes there — so a Supabase token
placed in it is overwritten at the edge and the advisor sees no token at all,
which surfaces to the user as "your session has expired" on a perfectly good
session. The token therefore rides in **`x-nudgr-authorization`**, beside the
signature rather than in place of it. (OAC's "do not override authorization
header" setting is not a way out: it preserves the viewer header by not signing,
and then Lambda rejects the request instead.)

**The client must send `x-amz-content-sha256`.** CloudFront signs headers but
not the body, and per AWS: *"If you use PUT or POST methods with your Lambda
function URL, your users must compute the SHA256 of the body and include the
payload hash value in the x-amz-content-sha256 header. Lambda doesn't support
unsigned payloads."* Without it the request dies at the edge with a signature
mismatch, surfaced as a 403 that looks nothing like a hashing problem.
`CloudAiCoachService.payloadHash` does this, and its digests are pinned in
`test/services/advisor_payload_hash_test.dart`.

Verified end to end: a response emitted in 10 frames 300ms apart arrived through
CloudFront 300ms apart. **CloudFront passes the stream through without
buffering** — which was the one assumption this whole approach rested on.

If AWS later allows public Function URLs, CloudFront can be dropped: set the URL
back to `AuthType: NONE`, point `AI_ADVISOR_ENDPOINT` at it, and the payload-hash
header becomes an unread extra header.
