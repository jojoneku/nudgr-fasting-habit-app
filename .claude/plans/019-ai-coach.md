# Plan 019 — AI Coach

**Branch:** `feat/ai-coach`  
**Status:** Ready to implement  
**Spec:** [docs/ai_coach_spec.md](../../docs/ai_coach_spec.md)

---

## Problem

The current `AiEstimationService` uses a 700MB Gemma 3 1B model that hallucinates macros from
training data. We need a smarter, lighter, extensible AI Coach that:
- Uses the real food DB for accurate macros (no hallucination)
- Presents as a chat UI accessible from any screen
- Supports on-device (Qwen3 0.6B) + cloud (AWS Bedrock) tiers
- Can handle nutrition, fasting, gamification, and finance coaching

---

## Architecture

```
AiCoachService (abstract interface)
   ├── NullAiCoachService      → canned responses (before download)
   ├── OnDeviceAiCoachService  → Qwen3 0.6B via flutter_gemma (~586MB, downloaded on demand)
   └── CloudAiCoachService     → HTTP → AWS Lambda → Amazon Bedrock Claude Haiku

AiCoachPresenter (ChangeNotifier — root level, injected everywhere)
   ├── Builds AiCoachContext from all module presenters
   ├── Manages List<AiChatMessage>
   ├── Selects tier (on-device vs cloud)
   └── Drives AiChatSheet

AiChatSheet (DraggableScrollableSheet — accessible from every screen via AppShell FAB)
```

---

## Phases

### Phase 1 — Abstract Interface + Models
- `lib/services/ai_coach_service.dart` — abstract `AiCoachService`
- `lib/services/null_ai_coach_service.dart` — canned stub
- `lib/models/ai_chat_message.dart` — `AiChatMessage`, `AiChatRole`
- `lib/models/ai_coach_context.dart` — `AiCoachContext`, `AiCoachEntryPoint`
- `lib/models/food_parse_result.dart` — `FoodParseResult`, `ParsedFoodItem`

### Phase 2 — Rule-Based Food Parser + DB Chat
- `lib/utils/food_nlp_parser.dart` — regex-based item extractor
- `lib/utils/food_unit_converter.dart` — "1 cup" → grams lookup table
- Wire into `NutritionPresenter` — replaces `AiEstimationService.estimate()`
- Food chat works fully offline with zero model download

### Phase 3 — On-Device Qwen3 0.6B
- `lib/services/on_device_ai_coach_service.dart`
- Swap flutter_gemma model: Gemma 1B → Qwen3 0.6B (`ModelType.qwen`)
- Two system prompts: `food_parser` (structured JSON) + `coach` (natural language)
- Download triggered on first AI Coach open only

### Phase 4 — AWS Cloud Tier
- `backend/ai-coach/handler.js` — Lambda → Bedrock Claude Haiku, SSE streaming
- `backend/ai-coach/template.yaml` — SAM deployment
- `lib/services/cloud_ai_coach_service.dart` — HTTP SSE client
- Endpoint stored via `--dart-define=AI_COACH_ENDPOINT=<url>`
- `AiCoachPresenter` auto-selects: cloud if online + opted in, else on-device

### Phase 5 — Chat UI
- `lib/presenters/ai_coach_presenter.dart` — full state machine
- `lib/views/widgets/ai_chat_sheet.dart` — DraggableScrollableSheet, bubble UI, streaming
- Context-aware persona per entry point (Nutrition / Fasting / Stats / Treasury / General)
- FAB wired in `lib/views/home_screen.dart`
- Remove `AiEstimationService` (Gemma 1B) entirely

---

## Key Files

| New | Path |
|---|---|
| Abstract interface | `lib/services/ai_coach_service.dart` |
| Null impl | `lib/services/null_ai_coach_service.dart` |
| On-device impl | `lib/services/on_device_ai_coach_service.dart` |
| Cloud impl | `lib/services/cloud_ai_coach_service.dart` |
| Presenter | `lib/presenters/ai_coach_presenter.dart` |
| Context model | `lib/models/ai_coach_context.dart` |
| Message model | `lib/models/ai_chat_message.dart` |
| Parse result | `lib/models/food_parse_result.dart` |
| NLP parser | `lib/utils/food_nlp_parser.dart` |
| Unit converter | `lib/utils/food_unit_converter.dart` |
| Chat sheet | `lib/views/widgets/ai_chat_sheet.dart` |
| Lambda handler | `backend/ai-coach/handler.js` |
| SAM template | `backend/ai-coach/template.yaml` |

| Modified | Change |
|---|---|
| `lib/services/ai_estimation_service.dart` | Removed after Phase 2 stable |
| `lib/presenters/nutrition_presenter.dart` | Use `FoodNlpParser` + `AiCoachService` |
| `lib/views/home_screen.dart` | Add `AiCoachPresenter` + chat FAB |

---

## AWS Budget ($100 starter)

- Lambda: free tier covers ~1M requests/month
- Bedrock Claude Haiku 3: ~$0.25/1M input + $1.25/1M output tokens
- API Gateway HTTP: ~$1/1M requests
- **~$2–5/month at 1,000 calls/day → $100 lasts 20–50 months**

---

## Notes
- Cloud tier requires explicit user opt-in — no data leaves device by default
- Cloud tier = future monetization hook (free = on-device, pro = cloud)
- `AiEstimationService` stays until Phase 2 is verified stable, then deleted
