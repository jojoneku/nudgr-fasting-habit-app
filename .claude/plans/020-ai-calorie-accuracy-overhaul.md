# Plan 020 — AI Calorie Accuracy Overhaul

**Branch:** `feat/ai-calorie-accuracy`
**Date:** 2026-04-29
**Status:** Awaiting approval
**Depends on:** Plan 018 (calorie counter overhaul), Plan 010 (local AI), Plan 009 (food DB)

---

## Goal

Make AI-driven calorie tracking trustworthy. Today the pipeline silently logs entries with calories that bear no relationship to the portion the user typed, lets a 0.6B model overwrite explicit gram values, and has no memory of past corrections. After this overhaul:

1. **No silent unit-scale bugs** — calories always match grams.
2. **The AI assists, never overrides** explicit user input.
3. **DB matching is precise** — typing "potato" never returns "potato chips".
4. **Unknown foods improve over time** via a personal dictionary that learns from user corrections.
5. **The user sees how an estimate was reached** (DB / AI / keyword / your own correction).

### Non-goals

- Switching the on-device model (kept as Qwen3 0.6B for now).
- Cloud-based food recognition (image input).
- Restructuring meal slots, history UI, or templates — that's Plan 018's domain.
- New nutrition goals or coaching features — Plan 019's domain.

---

## Root Causes Fixed by This Plan

| # | Bug | Severity | Where |
|---|---|---|---|
| 1 | AI macro estimate stores raw `ai.calories` next to user's grams without scaling | 🔴 critical | `nutrition_presenter.dart:826-837` |
| 2 | AI normalize unconditionally overwrites NLP-extracted grams, even when user said `100g` | 🔴 critical | `nutrition_presenter.dart:728-736` |
| 3 | "Single AI item → blind assign" fallback assigns unrelated macros | 🔴 critical | `nutrition_presenter.dart:821` |
| 4 | FTS5 prefix-match only on last token (`chicken adobo*` not `chicken* adobo*`) | 🟠 high | `food_db_service.dart:64` |
| 5 | DB scoring rewards substring hits same as whole-word hits | 🟠 high | `nutrition_presenter.dart:574-581` |
| 6 | AI normalize prompt expands names ("milo" → "milo chocolate drink") which hurts DB lookup | 🟠 high | `on_device_ai_coach_service.dart:539-557` |
| 7 | `_findAiItem` substring match misassigns macros across multi-item meals | 🟠 high | `nutrition_presenter.dart:799-823` |
| 8 | AI confidence parsed but never used | 🟠 high | `on_device_ai_coach_service.dart:458` |
| 9 | Tier 2 vs Tier 3 estimates are indistinguishable to user | 🟡 medium | `food_entry.dart` |
| 10 | Macro prompt receives names without grams — model can't compute portion-aware values | 🟡 medium | `nutrition_presenter.dart:758` |
| 11 | Filipino dish bucket calibration off ~2-3× (longganisa, adobo, tocino) | 🟡 medium | `nutrition_presenter.dart:617-655` |
| 12 | No personal dictionary — every retyped food re-runs the full pipeline | 🟡 medium | new |
| 13 | Egg example in `_foodParsePrompt` teaches model 120g for 2 eggs (real: ~100g) | 🟢 low | `on_device_ai_coach_service.dart:577` |
| 14 | No AI cache — same input retyped re-runs Qwen3 | 🟢 low | new |

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/food_entry.dart` | Modify — add `EstimationSource` enum + field | Model |
| `lib/models/estimation_source.dart` | New — enum + UI helpers | Model |
| `lib/models/personal_food_entry.dart` | New — `{key, name, kcalPer100g, protein, carbs, fat, hits, lastUsedAt}` | Model |
| `lib/services/personal_food_dictionary.dart` | New — lookup + write through StorageService | Service |
| `lib/services/storage_service.dart` | Modify — `loadPersonalDict`, `savePersonalDict` interface | Service |
| `lib/services/storage_service_impl.dart` (or current impl) | Modify — implement above keys | Service |
| `lib/services/food_db_service.dart` | Modify — multi-token prefix FTS query | Service |
| `lib/services/on_device_ai_coach_service.dart` | Modify — prompts (strip not expand, locale, grams in macro), LRU cache | Service |
| `lib/services/ai_coach_service.dart` (interface) | Modify — `estimateMacrosForItems(List<{name, grams}>)` | Service |
| `lib/presenters/nutrition_presenter.dart` | Major modify — pipeline rewrite (see below) | Presenter |
| `lib/utils/food_match_scorer.dart` | New — extracted + improved `_dbMatchScore`, `_findAiItem` | Utils |
| `lib/views/nutrition/chat_food_bubble.dart` | Modify — show source badge, confirm chip on low-confidence | View |
| `lib/views/nutrition/edit_food_sheet.dart` | Modify — on save, write to personal dict | View |
| `assets/local_dishes.json` | New — keyword density table (replaces hardcoded buckets) | Asset |
| `pubspec.yaml` | Modify — register `assets/local_dishes.json` | Config |
| `test/presenters/nutrition_presenter_test.dart` | Extend — pipeline path tests | Test |
| `test/services/personal_food_dictionary_test.dart` | New | Test |
| `test/utils/food_match_scorer_test.dart` | New | Test |

No new dependencies. No breaking schema changes — `FoodEntry.fromJson` defaults `estimationSource` to `db` for legacy entries (which is the safest assumption since legacy `aiEstimated:false` entries came from DB).

---

## Interface Definitions

### `EstimationSource` enum (`lib/models/estimation_source.dart`)
```dart
enum EstimationSource {
  db,             // exact USDA / bundled DB hit — trusted
  personalDict,   // user has confirmed this food before — most trusted
  aiPerItem,      // AI macro estimate, scaled by user grams
  keywordDensity, // assets/local_dishes.json fallback, scaled by grams
  userManual;     // typed in by user directly via edit sheet — most trusted

  bool get isTrusted => switch (this) {
        db || personalDict || userManual => true,
        aiPerItem || keywordDensity => false,
      };

  String get badge => switch (this) {
        db => 'DB',
        personalDict => 'You',
        aiPerItem => 'AI',
        keywordDensity => '~',
        userManual => 'Set',
      };
}
```

### `FoodEntry` additions (`lib/models/food_entry.dart`)
- Add `final EstimationSource estimationSource;` (defaults `db` for legacy fromJson)
- Add `final double? confidence;` (0.0–1.0, only set for `aiPerItem`)
- `aiEstimated` getter is preserved as `estimationSource == EstimationSource.aiPerItem || estimationSource == EstimationSource.keywordDensity` for backward compat with views.

### `PersonalFoodEntry` (`lib/models/personal_food_entry.dart`)
```dart
class PersonalFoodEntry {
  final String key;          // lowercased, normalized name (search key)
  final String name;          // display name as user typed it
  final double kcalPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final int hits;             // increments each time used
  final DateTime lastUsedAt;
}
```

### `PersonalFoodDictionary` (`lib/services/personal_food_dictionary.dart`)
```dart
class PersonalFoodDictionary {
  Future<void> init();
  PersonalFoodEntry? lookup(String name);          // O(1), case-insensitive, normalized
  Future<void> upsert(PersonalFoodEntry entry);    // increments hits if exists
  Future<void> remove(String key);
  List<PersonalFoodEntry> all();                   // for settings/debug screen
}
```
Backed by `StorageService.loadPersonalDict() / savePersonalDict(List<PersonalFoodEntry>)`. Stored as a single JSON list — bounded at ~500 entries via LRU eviction on `lastUsedAt` (more than enough for a personal vocab; one user logs maybe 50–100 distinct foods).

### `AiCoachService.estimateMacrosForItems` (replaces `estimateMacros`)
```dart
Future<List<AiItemEstimate>?> estimateMacrosForItems(
  List<({String name, double grams})> items,
);
```
- One call, batched, but the prompt now includes grams per item AND uses indexed JSON (same trick as normalize) so output alignment is verifiable.
- Returns one estimate per input item, in order. Returns `null` on length mismatch (caller falls back to keyword density).

### `food_match_scorer.dart` (extracted utils)
```dart
class FoodMatchScorer {
  static int dbScore(FoodDbEntry entry, String query);
  static AiItemEstimate? findAiItem(
    AiMealEstimate estimate, String name, {required double minScore}
  );
}
```

---

## New Pipeline (`_parseChatAsFood` rewrite)

```
1. NLP parse → ParsedFoodItem(name, grams, isExact)
   └─ isExact = !item.isEstimated  (i.e. user gave a unit like "100g")

2. AI normalize (best-effort, optional)
   ├─ For each item: keep parsed.grams if isExact == true
   └─ Adopt ai.name only if it scores ≥ threshold against parsed.name
       (Levenshtein OR shared-token-ratio ≥ 0.5)
       Otherwise → keep NLP name. Never silently rename to unrelated food.

3. Personal dictionary lookup (NEW — runs FIRST after normalize)
   └─ if hit → build entry directly with EstimationSource.personalDict.
              Skip DB + AI for this item entirely.

4. DB lookup (only items not resolved by personal dict)
   ├─ Query FTS5 with all-token prefix: `chicken* adobo*`
   ├─ Run query with both NLP name AND AI-normalized name (if different)
   ├─ Score with FoodMatchScorer.dbScore (whole-word > substring)
   └─ Require score > 0 for a match. No "best of bad options".

5. AI macro estimate (only items still unresolved, AI available)
   ├─ Send {name, grams} per item, indexed JSON, single batched call
   ├─ Reject response if length ≠ input length
   ├─ For each item: find AI item via FoodMatchScorer.findAiItem with minScore=2
   │  (NO "single AI item ⇒ blind assign" fallback)
   ├─ If AI returned per-100g values (heuristic: calories < 50 for grams >= 100),
   │  scale by grams/100. Otherwise trust as-is.
   └─ Set EstimationSource.aiPerItem, confidence from response.

6. Keyword density fallback (last resort)
   └─ Load assets/local_dishes.json on first use. Lookup by keyword.
       calories = grams * kcalPer100g / 100.
       EstimationSource.keywordDensity, confidence = 0.3.

7. Confidence gate (NEW)
   └─ If estimationSource is aiPerItem OR keywordDensity:
       expose `needsConfirmation: confidence < 0.6` flag on the chat bubble.
       The entry is still logged immediately (don't break the fast path),
       but the bubble shows a "Tap to confirm" chip.
       Tapping → opens edit sheet pre-filled.

8. On user edit/confirm of a food entry:
   └─ PersonalFoodDictionary.upsert(
        key: normalize(name),
        kcalPer100g: edited.calories * 100 / edited.grams,
        ... macros similarly ...
      )
   Personal dict thus learns from every correction automatically.
```

---

## Implementation Stages

Each stage is independently mergeable. **Suggested PR cadence: one PR per stage.**

### Stage 1 — Critical correctness bugs (P0, ~half day)
**Goal:** stop logging wrong calories. Smallest possible diff.

- **S1.1** `_aiItemToFoodEntry`: scale `ai.calories` by `parsed.grams / 100` when AI was given grams-less input. After Stage 5 the prompt sends grams, but for now this is the safer interpretation.
- **S1.2** `_parseChatAsFood`: when adopting AI normalize output, keep `nlpResult.items[i].grams` if `!nlpResult.items[i].isEstimated`. Only adopt `ai.grams` when NLP couldn't determine an exact gram value.
- **S1.3** `_findAiItem`: remove the `if (best == null && estimate.items.length == 1) return estimate.items.first;` line.
- **S1.4** Fix `_foodParsePrompt` egg example: `120` → `100`.

**Files:** `nutrition_presenter.dart`, `on_device_ai_coach_service.dart`.
**Tests:** add 4 unit tests asserting each bug is fixed.
**Done when:** logging "200g longganisa" with no DB hit produces `~740 kcal`, not `~370 kcal`.

---

### Stage 2 — DB matching precision (P0, ~half day)
**Goal:** typing `potato` returns `potato`, not `potato chips`. Typing `chick adobo` finds `chicken adobo`.

- **S2.1** `food_db_service.dart` — tokenize FTS query, prefix every token:
  ```dart
  final terms = query.trim().split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .map((t) => '${t.replaceAll('"', '""')}*')
      .join(' ');
  ```
- **S2.2** Extract `_dbMatchScore` and `_pickBestDbMatch` into new `lib/utils/food_match_scorer.dart`. Improve scoring:
  - Whole-word match: +5 (current substring-only +3)
  - Substring (non-word-boundary): +1 (down from +3)
  - Exact name match: keep +1000
  - Strengthen verbosity penalty: split on `[,\s\-]+` not just space
- **S2.3** In `_resolveOneDbItem`, run search twice when AI normalized to a different name: once with NLP name, once with AI name. Score-merge candidates.

**Files:** `food_db_service.dart`, `nutrition_presenter.dart` (delegate to scorer), `food_match_scorer.dart` (new).
**Tests:** `food_match_scorer_test.dart` — `potato → "potato, raw"` (not chips), `chick adobo → "chicken adobo"`, `skim milk → "milk, nonfat"`.

---

### Stage 3 — Estimation source visibility (P1, ~half day)
**Goal:** users can see where every calorie number came from.

- **S3.1** Add `EstimationSource` enum + field on `FoodEntry`. Backward-compatible `fromJson` (defaults `db` if `aiEstimated:false`, `aiPerItem` if `aiEstimated:true`).
- **S3.2** Update all `FoodEntry` construction sites in `nutrition_presenter.dart` to set the correct source (`_buildEntry` → `db` or `keywordDensity`, `_aiItemToFoodEntry` → `aiPerItem`).
- **S3.3** Add `confidence` field on `FoodEntry`, propagated from `AiMealEstimate.confidence`.
- **S3.4** Update `chat_food_bubble.dart` — show small badge from `EstimationSource.badge`. Style:
  - `db`, `personalDict`, `userManual` → muted neutral chip
  - `aiPerItem`, `keywordDensity` → amber chip with tap-to-confirm if `confidence < 0.6`

**Files:** `food_entry.dart`, `estimation_source.dart` (new), `nutrition_presenter.dart`, `chat_food_bubble.dart`, presenter tests.
**Tests:** widget test asserts badge text matches source for all 5 sources.

---

### Stage 4 — Personal food dictionary (P1, ~1 day)
**Goal:** every user correction makes future predictions perfect for that food.

- **S4.1** Define `PersonalFoodEntry` model (`personal_food_entry.dart`) with fromJson/toJson.
- **S4.2** Define `PersonalFoodDictionary` service. Internal map keyed by normalized name (`name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ')`). LRU eviction at 500 entries.
- **S4.3** Extend `StorageService` interface with `loadPersonalDict() → Future<List<PersonalFoodEntry>>` and `savePersonalDict(list)`. Implement in current impl.
- **S4.4** Wire into `NutritionPresenter` constructor. Initialize on `init()`.
- **S4.5** Add lookup step in `_parseChatAsFood` BEFORE DB lookup. If hit, build `FoodEntry` directly with `EstimationSource.personalDict` and skip DB/AI for that item.
- **S4.6** On `editFoodEntry` / `editChatFoodItem`, after the user saves a manual correction, call `dict.upsert(...)`. Compute per-100g from `entry.calories * 100 / entry.grams`.
- **S4.7** Settings/debug: add a screen to view/clear personal dict. (Stretch — can skip if Plan 018's settings doesn't have a host yet.)

**Files:** all listed under Affected Files for personal dict.
**Tests:** `personal_food_dictionary_test.dart` — lookup, upsert increments hits, LRU eviction, persist round-trip. Presenter test: editing an entry populates the dict; next log of same name short-circuits.

**Why this is the highest-leverage stage:** for any food the user logs twice, accuracy after the first correction becomes 100%. Filipino dishes that USDA doesn't have at all are no longer second-class citizens.

---

### Stage 5 — Better prompts + per-item AI calls (P1, ~half day)
**Goal:** AI sees grams; AI can't misalign multi-item meals.

- **S5.1** Rewrite `_normalizePrompt` — change rule 1 from "expand brand to descriptive" to "strip brand, keep concise generic name (matches a USDA-style entry like 'milk, nonfat')". Update examples accordingly.
- **S5.2** Add a locale hint at top of normalize + macro prompts: `'User cuisine context: Filipino + Western mix. Common dishes: adobo, sinigang, kare-kare, tocino, longganisa, pancit. Prefer concise generic names.'` (Configurable via SharedPreferences in future, for now hardcoded since user memory says PH user.)
- **S5.3** Add `estimateMacrosForItems(List<{name, grams}>)` to `AiCoachService` interface and implement in `OnDeviceAiCoachService`. New prompt sends indexed JSON `[{i:0, n:"longganisa", g:200}, ...]`, expects response with same indices. Reject on length mismatch.
- **S5.4** Replace `_ai.estimateMacros(unresolvedNames.join(', '))` in `_parseChatAsFood` with `_ai.estimateMacrosForItems(...)`.
- **S5.5** Replace `_findAiItem` substring matching with a strict index-based lookup (item `i` ↔ AI response `i`). Old `findAiItem` becomes unused — delete.

**Files:** `on_device_ai_coach_service.dart`, `ai_coach_service.dart`, `nutrition_presenter.dart`, `ai_meal_estimate.dart` (no change but document new contract).
**Tests:** mock `AiCoachService` to return shuffled / wrong-length responses, assert presenter falls through to keyword density safely.

---

### Stage 6 — Calibration table + AI cache (P2, ~half day)
**Goal:** when AI fails, the keyword fallback is at least roughly right; same input never re-runs the model.

- **S6.1** Create `assets/local_dishes.json`:
  ```json
  {
    "version": 1,
    "kcal_per_100g": {
      "longganisa": 370,
      "tocino": 280,
      "tapa": 220,
      "adobo": 175,
      "sinigang": 60,
      "kare-kare": 180,
      "pancit": 180,
      "lumpia": 230,
      "sisig": 280,
      "lechon": 380
    },
    "buckets": {
      "oils_fats": { "kcal_per_g": 7.5, "keywords": ["oil","butter","ghee","lard","margarine"] },
      "nuts_seeds": { "kcal_per_g": 5.5, "keywords": ["nut","almond","peanut","cashew","seed","buto"] },
      ... (rest of current buckets)
    }
  }
  ```
  - Specific dishes match first; buckets are fallback.
- **S6.2** `_estimateCalories` reads from this JSON (cache parsed map at presenter init). Remove hardcoded list.
- **S6.3** Add LRU cache (size 50) keyed on lowercased input string in `OnDeviceAiCoachService` — caches both `normalizeFoodInput` and `estimateMacrosForItems` results. In-memory only (resets on app restart). Avoids re-running 0.6B model on retyped foods.

**Files:** `local_dishes.json` (new), `pubspec.yaml`, `nutrition_presenter.dart`, `on_device_ai_coach_service.dart`.
**Tests:** assert `longganisa` 200g produces ~740 kcal (within ±5%); cache hit returns same result instance.

---

## Test Plan

### Unit tests
- `food_match_scorer_test.dart` — 12 cases covering whole-word vs substring, transforming-word penalty, verbose-name penalty, exact match.
- `personal_food_dictionary_test.dart` — lookup, upsert, hits increment, LRU eviction, persist round-trip.
- `nutrition_presenter_test.dart` — extend with one test per pipeline tier:
  1. DB hit → `EstimationSource.db`, calories from DB scaled by grams.
  2. Personal dict hit → `EstimationSource.personalDict`, skips DB/AI.
  3. AI hit (mocked) → `EstimationSource.aiPerItem`, calories scaled by grams.
  4. Keyword fallback → `EstimationSource.keywordDensity`, longganisa 200g ≈ 740 kcal.
  5. User stated `100g chicken` — AI normalize must NOT change grams to 150g.
  6. AI returns 1 item for 3 inputs → all 3 still get individual handling (no blind assign).

### Integration / widget tests
- `chat_food_bubble_test.dart` — renders correct badge for each source.
- Manual: edit a food entry's calories, log same food next day, see `personalDict` badge.

### Manual QA scenarios (the Tagalog test set)
| Input | Expected source | Expected calories (~) |
|---|---|---|
| `200g chicken breast` | `db` | 330 |
| `2 cups rice` | `db` (rice, white, cooked) | ~520 |
| `150g longganisa` | `keywordDensity` (or `aiPerItem` if model has it) | ~555 |
| `1 bowl sinigang na baboy` | `aiPerItem` or `keywordDensity` | depends on grams |
| `milo 30g` | `db` (cocoa beverage powder) or `aiPerItem` | ~115 |
| Re-log `150g longganisa` after editing it once to 555 kcal | `personalDict` | exactly 555 |

---

## Migration / Rollout

- No DB schema change. New `food_entry.dart` field is optional with backward-compatible default.
- Personal dict stored under new SharedPreferences key — no migration of existing entries (they don't carry per-100g info reliably).
- Each stage is feature-flag-free; rolled out by merging.
- After Stage 4 ships, retroactively: on app start, scan last 30 days of non-AI-estimated entries (i.e. user-confirmed or DB-resolved) and seed the personal dict from them. Optional one-time job.

---

## Risk & Mitigation

| Risk | Mitigation |
|---|---|
| Personal dict pollution from typos (`chickn` saves as a separate key) | Normalize key aggressively; cap dict at 500 entries with LRU; settings screen lets user prune |
| AI prompt rewrite hurts an unrelated path | All prompts in one file; only `parseFood` + `normalize` + `macro` change; coaching prompts untouched |
| Stage 1 calorie scaling double-counts if AI prompt later sends grams | Scaling logic flags `_aiResponseAssumedPer100g` based on whether prompt included grams. After Stage 5, flag is `false` and scaling skipped |
| LRU cache returns stale food data after a DB schema bump | Cache is in-memory only — clears on app restart |
| Existing users see new badges — UI noise | Match the existing `aiEstimated` `~` prefix style; small subtle chip; don't redesign the bubble |

---

## Out of Scope (explicit deferrals)

- Image-based food recognition.
- Cloud sync of personal dictionary (rolls in with Plan 015 full cloud sync).
- Voice input for food logging.
- Barcode scanning.
- Recipe / multi-component meal builder beyond what Plan 018 already provides.
- Switching to a larger on-device model — revisit if Stage 1–6 leaves accuracy below acceptable.

---

## Summary

Stages 1–2 fix the silent correctness bugs (no more 2× calorie errors, DB returns the right item).
Stages 3–4 make the pipeline self-improving (user sees source; corrections persist forever).
Stages 5–6 round out prompts, prevent multi-item misalignment, and recalibrate the last-resort fallback.

Total: ~3-4 days of focused work, six independently mergeable PRs. The biggest accuracy unlock is **Stage 4 (personal dictionary)** — after a few weeks of normal use, every food the user logs regularly resolves with 100% accuracy regardless of what's in USDA.
