# Plan 025 — Cloud Haiku as Primary Food-Logger AI

> **Status:** Draft, awaiting approval.
> **Scope:** Food logger only (chat → entries). Finance logger out of scope; mirrored later.
> **Builds on:** Plan 024 (Bedrock Haiku 4.5 on AWS Lambda is live; `CloudAiCoachService` already implements `extractFoodItems`, `disambiguateFood`, `estimateMacros`, `respond`).

---

## 1. Why this exists

Plan 024 wired Bedrock end-to-end and shipped Phases 1–3 (commit `cc6219c`). But the food logger only uses cloud as a **side-path**:

- `NutritionPresenter._parseChatAsFood` at `lib/presenters/nutrition_presenter.dart:1256` calls **`_ai.extractFoodItems(text)`** — `_ai` is hard-bound to the **on-device** service in `lib/views/home_screen.dart:133` (`aiCoach: _onDeviceAi`).
- The cloud field (`_cloudAi`) is only invoked inside `_resolveViaSemantic` at line 1017 for disambiguation, and never for extraction or macro estimation.

User intent: **when cloud is available, Haiku should be the primary AI for food logging, with the local food DB used as context so Haiku can resolve directly to `food_id` instead of just returning free-text item names.** On-device Qwen3 stays as the fallback when cloud is unavailable or fails.

---

## 2. The "food DB as context" decision

Dumping all ~14k entries into Haiku's context is a non-starter (latency + token cost + every call pays). Two viable strategies:

**A. Two-call: extract → resolve.** Cloud extracts items, client runs FTS per item, second cloud call resolves each item against its top-K candidates. Clean but doubles latency + cost.

**B. Single-call with client-side FTS pre-pass.** Client runs a coarse FTS sweep on the raw text (or on quick noun chunks from `FoodNlpParser`) to assemble ~5–15 candidate foods *for the whole utterance*, sends `{text, candidates}` to Haiku. Haiku returns extracted items, each annotated with `food_id` chosen from the candidate set (or `null` if no candidate fits). One round-trip, ~700–1100 input tokens. **Recommended.**

Strategy B keeps the bundled DB authoritative (Haiku can't hallucinate `food_id`s), keeps cost in line with Plan 024's $0.001–$0.002/call math, and gracefully degrades — if FTS returns nothing useful, Haiku still emits items with `food_id: null` and the existing hybrid resolver picks up.

---

## 3. New Lambda op: `parseFoodWithCandidates`

Add a fifth op to `lambda_function.py` alongside the existing four. Keep current ops untouched — they remain useful for legacy paths and on-device fallback parity.

**Request:**
```json
{
  "op": "parseFoodWithCandidates",
  "payload": {
    "text": "two eggs and a cup of brown rice",
    "candidates": [
      { "food_id": "usda_123", "name": "Egg, whole, cooked, hard-boiled" },
      { "food_id": "usda_124", "name": "Egg, whole, raw, fresh" },
      { "food_id": "usda_801", "name": "Rice, brown, long-grain, cooked" },
      ...
    ]
  }
}
```

**Response:**
```json
{
  "items": [
    {
      "name": "egg, hard-boiled",
      "grams": 100,
      "hyde": "two whole hard-boiled eggs, plain",
      "food_id": "usda_123",
      "confidence": 0.92
    },
    {
      "name": "brown rice, cooked",
      "grams": 195,
      "hyde": "one cup cooked brown rice, plain",
      "food_id": "usda_801",
      "confidence": 0.88
    }
  ]
}
```

**Prompt shape (constant in handler):**
```
Extract food items from: "<text>"

Candidate foods from the user's database (pick from these when one matches):
- id: usda_123, name: Egg, whole, cooked, hard-boiled
- id: usda_801, name: Rice, brown, long-grain, cooked
...

For each item, reply with ONLY valid JSON:
{"items":[{"name":"...","grams":<num>,"hyde":"...","food_id":"<id or null>","confidence":<0..1>}]}
- Use 100g default when quantity is unclear.
- Set food_id to null if no candidate is a clear match (confidence < 0.6).
- hyde is a descriptive phrase for downstream semantic search.
```

Token budget: ~700 input (text + 10 candidates × ~12 tokens), ~250 output → ~$0.0018/call at Haiku 4.5 pricing. Within Plan 024's envelope.

---

## 4. Flutter side — pipeline changes

### 4.1 New service method

`lib/services/ai_coach_service.dart` — add to the abstract interface:
```dart
Future<List<ExtractedFoodItem>?> parseFoodWithCandidates(
  String text,
  List<FoodSearchCandidate> candidates,
);
```

- `CloudAiCoachService`: implement — POST `parseFoodWithCandidates`, map `food_id` into a new optional field on `ExtractedFoodItem`.
- `OnDeviceAiCoachService`: return `null` (keep the existing `extractFoodItems` path as the on-device fallback — no need to teach Qwen the candidate-picking trick).
- `NullAiCoachService`: return `null`.

### 4.2 Extend `ExtractedFoodItem`

`lib/models/extracted_food_item.dart` — add:
```dart
final String? resolvedFoodId;   // populated by cloud's parseFoodWithCandidates
final double? resolverConfidence;
```

Keep defaults `null` so on-device + NLP fallbacks stay unchanged.

### 4.3 Reroute `_parseChatAsFood`

`lib/presenters/nutrition_presenter.dart:1256` — restructure Layer 1:

```
if (_cloudAi?.isAvailable ?? false):
    candidates = await _buildFtsCandidatePool(text, max: 12)
    items = await _cloudAi.parseFoodWithCandidates(text, candidates)
    // items may carry resolvedFoodId — skip hybrid resolve for those
elif _ai.isAvailable:
    items = await _ai.extractFoodItems(text)   // existing path
else:
    items = FoodNlpParser.parse(text)          // existing fallback

// Layer 2: per item
for item in items:
    if item.resolvedFoodId != null and confidence ≥ 0.6:
        entry = FoodDbEntry from foodDb.getById(resolvedFoodId)
        confidence band = high → log directly
    else:
        run existing personal-dict → hybrid FTS+semantic → estimate path
```

New helper `_buildFtsCandidatePool(String text, {int max})`:
- Pulls noun-chunks via `FoodNlpParser.tokens(text)` (already exists) or splits on conjunctions.
- For each chunk, calls `_foodDb.search(chunk)` and takes top 3.
- Deduplicates by `food_id`, caps at `max`.
- Total time budget: 50–80 ms; FTS5 is fast.

### 4.4 Failure handling

- Cloud call throws / returns null → fall through to `_ai.extractFoodItems` (current behavior).
- Cloud returns items but `food_id: null` → existing hybrid resolver handles that item normally.
- Both fail → existing `FoodNlpParser` path.

No new error UX; cloud failure is silent (matches current pattern at line 1273).

### 4.5 Telemetry / source tagging

`FoodEntry.estimationSource` — confirm the enum has a `cloudAi` variant; populate it when the entry came from `resolvedFoodId`. Used downstream for chip rendering + future cost dashboards.

---

## 5. Files touched

| File | Change |
|------|--------|
| `lambda_function.py` | Add `_parse_food_with_candidates` handler + dispatch line |
| `lib/services/ai_coach_service.dart` | New abstract `parseFoodWithCandidates` |
| `lib/services/cloud_ai_coach_service.dart` | Implement op + JSON mapping |
| `lib/services/on_device_ai_coach_service.dart` | Stub returns `null` |
| `lib/services/null_ai_coach_service.dart` | Stub returns `null` |
| `lib/models/extracted_food_item.dart` | Add `resolvedFoodId`, `resolverConfidence` |
| `lib/presenters/nutrition_presenter.dart` | New `_buildFtsCandidatePool`; reroute Layer 1 in `_parseChatAsFood`; consume `resolvedFoodId` in Layer 2 |
| `lib/services/food_db_service.dart` | Confirm `getById(String)` exists; add if missing (~10 lines) |
| `test/presenters/nutrition_presenter_test.dart` | New tests: cloud-available path, cloud-fail fallback, food_id=null fallback |
| `docs/plan_022_food_logging.md` (or sibling) | Append "Plan 025 addendum" describing the cloud-primary branch |

No new dart-defines, no new env vars on Lambda, no schema changes.

---

## 6. Implementation phases

| Phase | Scope | Outcome |
|-------|-------|---------|
| **A — Lambda op** | Add `parseFoodWithCandidates` to `lambda_function.py`, redeploy zip | `curl` with mocked candidates returns valid JSON |
| **B — Dart contract** | Extend interface + `ExtractedFoodItem`; cloud impl; stubs on on-device/null | `flutter analyze` clean; cloud unit test hits a mocked HTTP server |
| **C — Pipeline reroute** | `_buildFtsCandidatePool` + reroute Layer 1; wire `resolvedFoodId` into Layer 2 commit path | Manually logging "two eggs and rice" with cloud on shows `cloudAi` source + correct DB rows |
| **D — Tests + telemetry** | Presenter tests; `estimationSource` tagging; minimal `debugPrint` cost line per call | Tests green; logs confirm cloud-vs-fallback routing |
| **E — Polish** | Settings copy update (mention "cloud handles parsing when enabled"); doc the new flow in `docs/` | Ship behind the existing `useCloudAi` toggle |

Phases A–C = MVP, ~1 day. D–E = ~half a day.

---

## 7. Open questions

1. **Candidate pool size.** Start at 10 (covers ~3 noun-chunks × top-3). Tune if Haiku misses obvious matches because the right candidate wasn't in the pool.
2. **Multi-language / Pinoy spellings.** The existing FTS pool already handles "kanin" / "adobo" via `food_db_v9.sqlite` normalization. No special handling needed; rely on the FTS pre-pass.
3. **Personal dictionary precedence.** Should personal-dict lookups happen *before* the cloud call (skipping cloud entirely when every item is in the dict), or *after*? **Recommend before** — saves a cloud call for habitual foods and matches the Plan 022 "instant, max confidence" intent.
4. **Streaming.** Out of scope — single round-trip JSON keeps the UX simple. Revisit if median latency > 2s.
5. **Budget cap interaction.** Plan 024 §2 reserves a daily per-user cap. Confirm the cap counter increments for `parseFoodWithCandidates` the same as other ops (it will, since cap is per request not per op).

---

## 8. Non-goals

- Replacing the on-device tier — it's the fallback and the offline story.
- Finance logger cloud routing — same pattern applies but tracked separately once this lands.
- Image-based food logging.
- Streaming partial parses.
- New auth / new endpoints / new infra. Plan 025 is purely a routing + prompt change on top of Plan 024.
