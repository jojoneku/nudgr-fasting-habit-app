# Food Logging — Architecture

> **Source of truth for the food logger as of Plan 026 (May 2026).**
> Older specs (`fasting_loop_spec.md`, `rag_food_search_spec.md`, Plans 021/022) describe earlier iterations and may contradict this doc — when in doubt, follow this file.

---

## The pipeline at a glance

```
User chat input ──► personal dict ──► hit ──► log directly (no AI)
                          │ miss
                          ▼
                  candidate pool (alias-aware FTS5)
                          │
            ┌─────────────┴─────────────┐
            ▼ cloud available           ▼ cloud unavailable
   single Bedrock call:           on-device extract → per-item
   - extract items                 hybrid resolve → keyword fallback
   - pick food_id from candidates
   - estimate macros (no match)
            │
            ▼
   commit entries → chat row → persist
```

Two tiers, one path each. The pre-Plan-026 multi-hop pipeline (extract → resolve per-item → disambiguate via cloud) is retired.

---

## Tier 0 — Personal dictionary precedence

The `PersonalFoodDictionary` (`lib/services/personal_food_dictionary.dart`) caches every confidently-resolved entry the user has logged. On every chat input, the presenter checks each detected item against the dict first. If everything hits, **no candidate retrieval, no cloud call**.

Entries auto-promote into the dict when:
- A DB hit scored ≥ 0.75 via `_hybridResolveItem` (existing rule), OR
- A cloud `parseFoodWithCandidates` pick had confidence ≥ 0.8 (Plan 026)

After 2 weeks of normal logging, this is the hot path for most meals.

---

## Tier 1a — Cloud-primary single call (Plan 026)

When `CloudAiCoachService.isAvailable` is true:

1. **Build candidate pool** (`_buildCandidatePool`): FTS5 over the whole input + each NLP-detected fragment. The FTS5 index covers both `name_norm` and `aliases_norm` (Plan 026 §3) with BM25 weights 2:1 favoring name hits. Top-15 deduped candidates.

2. **Single Bedrock call** to `parseFoodWithCandidates` op (lambda_function.py):
   - Sends `{text, candidates: [{food_id, name}, ...]}`
   - Receives `items: [{name, grams, hyde, food_id, confidence, estimated_macros}]`
   - For each item the model either picks a `food_id` from the candidates with confidence ≥ 0.6 OR sets `food_id: null` and supplies `estimated_macros` from its own knowledge

3. **Hydrate**:
   - `food_id` resolved → `_foodDb.getById(id).toFoodEntry(grams)` → `EstimationSource.db`
   - `food_id` null + estimated_macros → synthetic `FoodEntry` → `EstimationSource.aiPerItem`
   - Confidence ≥ 0.8 → auto-promote into personal dict

4. **Commit** via `_commitFoodChat` (shared with Tier 1b).

Latency budget: ~50–100 ms local FTS + ~800–1500 ms Bedrock + ~10 ms hydrate ≈ **~1 second end-to-end**.

Cost: ~$0.0017–$0.0020 per call at Haiku 4.5 pricing.

---

## Tier 1b — On-device fallback

When cloud is unavailable / signed out / disabled / call failed / returned empty:

1. `OnDeviceAiCoachService.extractFoodItems(text)` — Qwen3 0.6B emits items with name/grams/HyDE.
2. If on-device AI unavailable too, `FoodNlpParser.parse(text)` — rule-based fragment splitter.
3. Per item:
   - Personal dict lookup
   - `_hybridResolveItem`: FTS5 (now alias-aware) + optional semantic search + LLM disambiguation
   - Keyword density fallback for unknown foods (low quality but always succeeds)

This path benefits from Plan 026's alias-augmented FTS even though it doesn't use the new cloud op — queries like "fried pork" now match "Pork belly, cooked" lexically through aliases.

---

## Database schema (v10)

```
foods (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT,
  cal REAL NOT NULL,
  protein REAL, carbs REAL, fat REAL,
  name_norm TEXT,          -- densified (lowercase, no punct, no spaces)
  aliases TEXT,            -- comma-joined raw aliases for display
  aliases_norm TEXT        -- per-alias densified, space-separated for trigram FTS
)

foods_fts (FTS5 virtual table)
  - name_norm     (weight 2.0 in BM25 ranking)
  - aliases_norm  (weight 1.0)
  - tokenize: trigram, case_sensitive 0
```

Aliases are generated at build time by `scripts/build_food_aliases.py`, which batches the DB through the local `claude -p` CLI (no API key, no Bedrock cost — uses the developer's Claude Code subscription). See `scripts/README.md` for the run command.

---

## Service interface — `AiCoachService`

| Method | Cloud impl | On-device impl |
|---|---|---|
| `respond` | streaming text | streaming text |
| `extractFoodItems` | text-only, legacy | Qwen3 single-pass |
| `parseFoodWithCandidates` (Plan 026) | **primary food path** | returns null |
| `disambiguateFood` | candidate pick | candidate pick (slower) |
| `estimateMacros` | open-ended | open-ended |

Tier selection is settled in `NutritionPresenter._parseChatAsFood` per call — there is no global "active tier" switch.

---

## Telemetry

- Lambda emits a structured `cost_line` to CloudWatch on every `parseFoodWithCandidates` call with `items_resolved`, `items_estimated`, `input_tokens`, `output_tokens` for budget tracking.
- `_logFeedback` writes local-only `FoodFeedback` rows tagged `fallbackMiss` whenever the keyword-density fallback fires — used to curate the alias list and DB additions.

---

## Files of interest

| Concern | File |
|---|---|
| Pipeline orchestration | `lib/presenters/nutrition_presenter.dart` (`_parseChatAsFood`, `_tryCloudParseFood`, `_buildCandidatePool`) |
| Cloud service | `lib/services/cloud_ai_coach_service.dart` |
| DB access | `lib/services/food_db_service.dart` |
| Match scoring | `lib/utils/food_match_scorer.dart` |
| Personal dict | `lib/services/personal_food_dictionary.dart` |
| Lambda op | `lambda_function.py` (`_parse_food_with_candidates`) |
| Alias generator | `scripts/build_food_aliases.py` |
| DB migration | `scripts/migrate_food_db_v10.py` |
