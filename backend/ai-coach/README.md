# AI Coach Backend

AWS Lambda + Amazon Bedrock endpoint for the AI Coach cloud tier.

## Stack
- **Runtime:** Node.js 20
- **Framework:** AWS SAM (Serverless Application Model)
- **Model:** Amazon Bedrock — Claude Haiku 3 (`anthropic.claude-haiku-20240307-v1:0`)
- **API:** API Gateway HTTP API (POST /coach)

## Prerequisites
- AWS CLI configured (`aws configure`)
- AWS SAM CLI installed (`brew install aws-sam-cli` / `choco install aws-sam-cli`)
- Bedrock Claude Haiku access enabled in your AWS account (us-east-1 by default)

## Deploy

```bash
cd backend/ai-coach
npm install
sam build
sam deploy --guided
```

On first deploy, SAM will prompt for stack name, region, and create an S3 bucket for artifacts.
Copy the `AiCoachApiUrl` output — this goes in your Flutter app as `--dart-define=AI_COACH_ENDPOINT=<url>`.

## Flutter integration

Pass the endpoint at build time:
```bash
flutter run --dart-define=AI_COACH_ENDPOINT=https://xxxx.execute-api.us-east-1.amazonaws.com/coach
```

Or set it in `launch.json`:
```json
"args": ["--dart-define=AI_COACH_ENDPOINT=https://xxxx.execute-api.us-east-1.amazonaws.com/coach"]
```

## Cost estimate (Claude Haiku 3)
| Volume | Input tokens | Output tokens | Cost/month |
|---|---|---|---|
| 1,000 calls/day | ~200 tok/call | ~150 tok/call | ~$2–3 |
| 5,000 calls/day | ~200 tok/call | ~150 tok/call | ~$10–15 |

$100 AWS credit ≈ 20–50 months at 1,000 calls/day.

## Request format
```json
POST /coach
{
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
```

## Response
```json
{ "response": "After 8 hours fasted, break with protein + healthy fat first..." }
```
