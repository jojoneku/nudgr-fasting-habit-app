# AI Coach Spec

## Overview
A hybrid AI coaching system accessible from any screen in The System. The AI Coach replaces
the hallucination-prone Gemma 1B macro estimator with a lean, accurate pipeline:
**rule-based NLP parser → food DB lookup → Qwen3 0.6B on-device → AWS Bedrock cloud**.

The coach surfaces as a persistent chat bottom sheet. Depending on entry point, it switches
context automatically — food logging assistant, fasting coach, RPG stat advisor, or finance
analyst. One model, one interface, used everywhere.

## User Story
As a player, I want to talk to my AI Coach from anywhere in the app so that I get accurate
nutrition logging, fasting insights, and RPG-flavored health advice without leaving my flow.

## Data Model

```dart
// lib/models/ai_chat_message.dart
enum AiChatRole { user, assistant, system }

class AiChatMessage {
  final String id;
  final AiChatRole role;
  final String text;
  final DateTime timestamp;
  final bool isStreaming; // true while token stream is in progress

  const AiChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.isStreaming = false,
  });

  factory AiChatMessage.fromJson(Map<String, dynamic> json) => AiChatMessage(
        id: json['id'] as String,
        role: AiChatRole.values.byName(json['role'] as String),
        text: json['text'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  AiChatMessage copyWith({String? text, bool? isStreaming}) => AiChatMessage(
        id: id,
        role: role,
        text: text ?? this.text,
        timestamp: timestamp,
        isStreaming: isStreaming ?? this.isStreaming,
      );
}
```

```dart
// lib/models/ai_coach_context.dart
// Snapshot of app state passed to the model as system context.
enum AiCoachEntryPoint { nutrition, fasting, stats, treasury, general }

class AiCoachContext {
  final AiCoachEntryPoint entryPoint;

  // Nutrition snapshot (nullable — only populated from nutrition entry)
  final int? todayCalories;
  final int? calorieGoal;
  final double? todayProtein;
  final double? todayCarbs;
  final double? todayFat;

  // Fasting snapshot
  final bool isFasting;
  final int? elapsedFastMinutes;
  final int? fastingGoalHours;
  final int fastingStreak;

  // RPG snapshot
  final int playerLevel;
  final int playerXp;
  final int playerHp;

  // Finance snapshot (nullable)
  final double? monthBudget;
  final double? monthSpent;

  const AiCoachContext({
    required this.entryPoint,
    this.todayCalories,
    this.calorieGoal,
    this.todayProtein,
    this.todayCarbs,
    this.todayFat,
    required this.isFasting,
    this.elapsedFastMinutes,
    this.fastingGoalHours,
    required this.fastingStreak,
    required this.playerLevel,
    required this.playerXp,
    required this.playerHp,
    this.monthBudget,
    this.monthSpent,
  });
}
```

```dart
// lib/models/food_parse_result.dart
// Output of FoodNlpParser — structured items before DB lookup.
class ParsedFoodItem {
  final String rawText;   // original fragment e.g. "2 cups rice"
  final String name;      // normalized e.g. "rice"
  final double grams;     // resolved quantity in grams
  final bool isEstimated; // true if unit→gram conversion was heuristic

  const ParsedFoodItem({
    required this.rawText,
    required this.name,
    required this.grams,
    required this.isEstimated,
  });
}

class FoodParseResult {
  final List<ParsedFoodItem> items;
  final bool usedModel; // false = rule-based, true = Qwen3 fallback

  const FoodParseResult({required this.items, required this.usedModel});
}
```

## Service Interface

```dart
// lib/services/ai_coach_service.dart
abstract class AiCoachService {
  /// Whether the service is ready to respond (model loaded / network reachable).
  bool get isAvailable;

  /// Download progress 0–100. Null if not downloading.
  int? get downloadProgress;

  /// Trigger model download (on-device impl only; no-op for cloud).
  Future<void> downloadModel({void Function(int progress)? onProgress});

  /// Stream a response token-by-token given conversation [messages] and [context].
  Stream<String> respond({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
  });

  /// Extract structured food items from a natural language [description].
  /// Returns null if the description cannot be parsed as a food query.
  Future<FoodParseResult?> parseFood(String description);

  void dispose();
}
```

### Implementations

| Class | Path | Notes |
|---|---|---|
| `NullAiCoachService` | `lib/services/null_ai_coach_service.dart` | Returns canned responses — used before download |
| `OnDeviceAiCoachService` | `lib/services/on_device_ai_coach_service.dart` | Qwen3 0.6B via `flutter_gemma` |
| `CloudAiCoachService` | `lib/services/cloud_ai_coach_service.dart` | HTTP → AWS Lambda → Bedrock Claude Haiku |

## Presenter API

```dart
// lib/presenters/ai_coach_presenter.dart
class AiCoachPresenter extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────
  List<AiChatMessage> get messages => List.unmodifiable(_messages);
  bool get isResponding => _isResponding;
  bool get isModelAvailable => _service.isAvailable;
  int? get downloadProgress => _service.downloadProgress;
  AiCoachTier get activeTier => _activeTier; // onDevice | cloud
  String? get errorMessage => _errorMessage;

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Open a session scoped to [entryPoint]. Clears history and sets context.
  void openSession(AiCoachEntryPoint entryPoint);

  /// Send a user message. Handles food parsing, DB lookup, and model response.
  Future<void> send(String text);

  /// Trigger model download (on-device tier).
  Future<void> downloadModel();

  /// Switch between tiers (user opt-in required for cloud).
  void setTier(AiCoachTier tier);

  /// Clear chat history.
  void clearHistory();
}
```

## Food Logging Pipeline (replaces `AiEstimationService`)

```
User types: "had 2 cups rice and chicken adobo"
          ↓
FoodNlpParser.parse(text)           // regex → [{name:"rice", grams:240}, {name:"chicken adobo", grams:150}]
          ↓
FoodDbService.search(name) × N      // FTS5 lookup for each item
          ↓
   found? → FoodDbEntry.toFoodEntry(grams)   // real macros ✅
   not found? → Qwen3 fallback → parse again → DB retry → AI estimate last resort
          ↓
AiCoachPresenter posts confirmation message
User confirms → NutritionPresenter.addEntry()
```

## UI Requirements

### AiChatSheet (`lib/views/widgets/ai_chat_sheet.dart`)
- **Trigger:** Floating action button in `AppShell`, or "Ask Coach" button in any screen
- **Layout:** DraggableScrollableSheet — snap to 50% (preview) or 90% (full chat)
- **Bubble style:** User bubbles right-aligned (Primary `#00E5FF` tint), assistant left-aligned (Surface `#1C2128`)
- **Streaming:** Assistant bubble renders tokens live as they stream in; typing indicator (3-dot pulse) while waiting for first token
- **Thumb zone:** Text input field always in bottom 30%. Send button 48×48px minimum.
- **States:**
  - `modelNotDownloaded` — "Download AI Coach (~586MB)" prompt with progress bar
  - `loading` — shimmer placeholder bubbles
  - `chat` — live message list
  - `error` — inline error chip with retry

### Micro-animations
| Trigger | Animation | Duration |
|---|---|---|
| New message bubble appears | Slide up + fade in | 200ms |
| Send button press | Scale 0.95 → 1.0 | 150ms |
| Typing indicator dots | Staggered bounce | 300ms loop |
| Sheet snap | Spring curve | 350ms |
| Tier switch | Crossfade badge | 250ms |

### Entry Point Context Labels
| Entry Point | Sheet header | System prompt persona |
|---|---|---|
| Nutrition | "Nutrition Scan 🍱" | Food parser + macro analyst |
| Fasting | "Fast Commander ⚡" | Fasting phase coach |
| Stats | "Shadow Monarch 👁" | RPG advisor, XP strategist |
| Treasury | "Ledger Protocol 💰" | Finance analyst |
| General | "The System 🖥" | General wellness coach |

## AWS Backend

### Infrastructure
- **AWS Lambda** (Node.js 20) — stateless function, 512MB RAM, 30s timeout
- **API Gateway** (HTTP API) — HTTPS endpoint, API key auth
- **Amazon Bedrock** — Claude Haiku 3 model (`anthropic.claude-haiku-20240307-v1:0`)
- **Secrets Manager** — stores Bedrock credentials

### Lambda Request/Response
```json
// POST /coach
// Headers: x-api-key: <key>
{
  "context": { ...AiCoachContext },
  "messages": [ { "role": "user|assistant", "text": "..." } ],
  "stream": true
}
// Response: text/event-stream (SSE)
data: token\n\n
data: [DONE]\n\n
```

### Budget
- Lambda free tier: 1M requests/month free
- Bedrock Claude Haiku 3: ~$0.25/1M input + $1.25/1M output tokens
- API Gateway HTTP: ~$1/1M requests
- **Estimated: $2–5/month at 1,000 calls/day → $100 lasts ~20 months**

### Files
- `backend/ai-coach/handler.js` — Lambda function
- `backend/ai-coach/template.yaml` — SAM deployment template
- `backend/ai-coach/package.json`

## RPG Mechanics
- **XP awarded:** +10 XP per food item logged via AI Coach (same as manual log)
- **Bonus XP:** +25 XP for logging a full meal (≥3 items in one message)
- **Coach Streak:** Consecutive days with ≥1 AI Coach interaction tracked separately
- **Achievement:** "First Contact" — first ever message sent to the coach

## Storage
New `StorageService` keys:
| Key | Type | Purpose |
|---|---|---|
| `aiCoachTier` | `String` | `"onDevice"` or `"cloud"` |
| `aiCoachCloudOptIn` | `bool` | User consented to cloud tier |
| `aiCoachHistory` | `List<AiChatMessage>` JSON | Last 50 messages persisted |
| `aiCoachDownloaded` | `bool` | Whether Qwen3 model is on device |

## Edge Cases
- **Offline + cloud tier selected:** Fall back to on-device silently; show "offline mode" badge
- **Model not downloaded + offline:** Use `NullAiCoachService` canned responses; prompt to download when online
- **Food not in DB:** Qwen3 generates macro estimate with `aiEstimated: true` flag; confidence shown in UI
- **Partial parse:** "some rice" → parser defaults to 100g serving; user can edit before confirming
- **Cloud API timeout (>10s):** Show error chip, offer retry or switch to on-device
- **Token limit exceeded:** Trim oldest messages from context, keeping system prompt + last 10 exchanges
- **User sends non-food text in nutrition mode:** Coach responds naturally; still offers to log if food is mentioned

## Acceptance Criteria
- [ ] `AiCoachService` is an abstract interface; concrete impl is swappable without touching Presenters
- [ ] Food typed in chat is parsed, DB-looked-up, and confirmed before logging — no hallucinated macros
- [ ] Qwen3 0.6B model download is triggered only on first coach open, not at app startup
- [ ] Chat sheet is accessible from all 5 screens (hub, stats, nutrition, fasting, treasury)
- [ ] Entry point context switches system prompt automatically
- [ ] Streaming tokens render live in the assistant bubble
- [ ] Cloud tier requires explicit user opt-in before any data leaves the device
- [ ] AWS Lambda returns streamed SSE response; app renders tokens progressively
- [ ] Offline fallback works without crashing
- [ ] `AiEstimationService` (Gemma 1B) is fully removed after Phase 2 is stable
- [ ] All new models have `fromJson`/`toJson`
- [ ] Touch targets ≥ 44×44px; input field in bottom 30% of sheet
