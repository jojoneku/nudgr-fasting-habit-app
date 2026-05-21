# Plan 026 — Robust Food Logging: Alias-Augmented DB + Cloud-First Runtime

> **Status:** Draft v2, awaiting approval.
> **Scope:** Replace flaky FTS-only resolution with a 2-tier robust pipeline.
> **Cost posture:** Build-time generation runs through the local `claude -p` CLI (your Claude Code subscription) — **zero API keys, zero Bedrock spend on one-time work**. Bedrock is reserved for per-user runtime calls only.
> **Changes from v1:** Dropped the embedding tier — alias-augmented FTS + cloud LLM covers the same ground without 43 MB of vectors+ONNX. Build-time generation uses `claude -p` instead of the Anthropic API.

---

## 1. Why this exists

| Pain | Example | Fix |
|---|---|---|
| FTS5 is purely lexical | "fried pork" → no match for "Pork belly, cooked" | **Tier 0:** alias column with synonyms + descriptive phrases |
| Out-of-DB foods fail or get keyword-density macros | "ostrich liver" | **Tier 1:** cloud single-call estimates macros when no candidate matches |
| Pipeline is fragmented across 3+ round-trips | extract → resolve → disambiguate | **Tier 1:** one Bedrock call does everything |

**Dropped from v1:** the on-device embedding tier (MiniLM + bundled vectors). Reasons:
- Adds ~43 MB to the app.
- Requires either Python+torch at build time or a separate ONNX path.
- Aliases cover lexical variants; cloud LLM covers semantic gaps when online; the residual gap (semantic queries while fully offline) is small enough to defer.
- If offline UX measurably suffers post-launch, we add it back as a Plan 027.

---

## 2. Where the work happens

| Asset | Generator | Cost |
|---|---|---|
| Food aliases (~8–12 per entry × ~14k = ~140k strings) | **`claude -p` CLI** via Python `subprocess` | $0 (your Claude Code subscription) |
| Runtime extract + resolve + estimate | **Bedrock Haiku 4.5** (existing Lambda) | ~$0.0017/call |

No `ANTHROPIC_API_KEY`. No Bedrock for one-time work. No Python ML stack. The build script is plain Python stdlib + `sqlite3`.

---

## 3. Architecture

```
┌────────────────── BUILD TIME (local, run-once) ──────────────────┐
│                                                                  │
│  scripts/build_food_aliases.py                                   │
│     for batch in chunks(food_db, 50):                            │
│         resp = subprocess.run(["claude", "-p", prompt])          │
│         write scripts/data/aliases_shards/batch_NNNN.json        │
│     merge all shards → assets/data/food_aliases.json             │
│                                                                  │
│  scripts/migrate_food_db_v10.py                                  │
│     read v9 sqlite + aliases.json                                │
│     write assets/food_db_v10.sqlite with `aliases` column +      │
│     FTS5 index on (name_norm, aliases)                           │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼ bundled into APK / IPA
┌──────────────────────────── RUNTIME ─────────────────────────────┐
│                                                                  │
│  Query: "fried pork and rice"                                    │
│                                                                  │
│  ┌─ Personal dict lookup (per item) ─────────────────────────┐   │
│  │ If every item is in dict → log immediately, skip cloud   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │ miss                              │
│                              ▼                                   │
│  ┌─ Tier-0 candidate retrieval (FTS5 alias-aware) ───────────┐   │
│  │ Search name_norm + aliases → top-10 candidates           │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│         ┌────────────────────┴────────────────────┐              │
│         ▼ cloud available                         ▼ offline      │
│  ┌─────────────────────┐               ┌────────────────────┐    │
│  │ Tier-1: single      │               │ Tier-2: highest    │    │
│  │ Bedrock Haiku call  │               │ scoring candidate  │    │
│  │ - extract items     │               │ if score >= 0.7;   │    │
│  │ - pick food_id from │               │ else NLP estimate  │    │
│  │   candidates        │               │ via keyword bucket │    │
│  │ - estimate macros   │               │                    │    │
│  │   when no match     │               │                    │    │
│  └─────────────────────┘               └────────────────────┘    │
│                                                                  │
│  Auto-promote: when Tier-1 returns confidence ≥ 0.8 for an       │
│  off-DB food, save the entry into the personal dictionary so     │
│  future logs skip the cloud call.                                │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 4. Data formats

### `assets/data/food_aliases.json`

```json
{
  "1001": [
    "fried chicken breast",
    "grilled chicken breast",
    "baked chicken breast",
    "chicken fillet",
    "boneless chicken",
    "white meat chicken"
  ],
  "3005": [
    "fried pork",
    "lechon kawali",
    "crispy pork",
    "liempo",
    "pork belly fried",
    "deep fried pork belly",
    "pork belly cooked",
    "roast pork belly"
  ]
}
```

Aliases include **both** synonyms (alternate names) and short descriptive phrases users actually type. PH-specific names are first-class via few-shot in the prompt.

### `assets/food_db_v10.sqlite` schema delta from v9

```sql
ALTER TABLE foods ADD COLUMN aliases TEXT DEFAULT '';

DROP TABLE foods_fts;
CREATE VIRTUAL TABLE foods_fts USING fts5(
  name_norm, aliases,
  content='foods',
  content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 1'
);
INSERT INTO foods_fts(rowid, name_norm, aliases)
  SELECT rowid, name_norm, aliases FROM foods;
```

Aliases stored as comma-joined string; FTS5 tokenizes them.

---

## 5. The aliasing prompt

```
You are augmenting a food database with colloquial aliases and descriptive
phrases that users naturally type when logging meals.

For each food below, output 8-12 short phrases that someone might type to
mean that food. Include:
- Direct synonyms (e.g., "fried pork" for pork belly)
- Common cooking variations (fried/grilled/baked when applicable)
- Filipino names where natural (kanin, adobo, sinigang, etc.)
- Brief descriptive phrases (e.g., "creamy chicken pasta" for alfredo)
- Common misspellings only if very frequent

DO NOT include:
- The original name verbatim (it's already indexed)
- Hyper-specific brand names
- Aliases that would collide with a fundamentally different food
  (e.g., don't tag "chicken" as alias for pork)

Foods to alias:
[
  {"id": "1001", "name": "Chicken Breast, Cooked", "category": "Poultry"},
  ...50 entries...
]

Output STRICT JSON only, no markdown, no preamble:
{
  "1001": ["alias 1", "alias 2", ...],
  ...
}
```

Few-shot one PH and one Western example inline so the model commits to the style.

---

## 6. Implementation phases

Each phase is a separate PR targeting `dev`.

### Phase 1 — Aliasing script

- `scripts/build_food_aliases.py`
  - Reads all rows from `assets/food_db.sqlite`
  - Batches of 50 entries
  - For each batch, calls `subprocess.run(["claude", "-p", prompt], ...)` with 120s timeout
  - Parses JSON; retries once on parse failure with a "JSON only, no markdown" reminder
  - Writes shard `scripts/data/aliases_shards/batch_NNNN.json` after each successful batch
  - Resumable: skips batches whose shard exists
  - Final step: merges all shards → `assets/data/food_aliases.json`
  - Validation: every DB id has ≥6 aliases; no duplicate aliases across entries (collision warning)
  - `--dry-run` flag to test on first 100 entries
- `scripts/data/aliases_shards/` added to `.gitignore` (only the merged file is committed)
- `scripts/README.md` updated with run instructions

**Acceptance:** Run on first 100 entries, manually inspect for quality. Then full run. `food_aliases.json` checked in.

### Phase 2 — DB v10 with aliases column

- `scripts/migrate_food_db_v10.py`
  - Reads v9 sqlite + `food_aliases.json`
  - Writes `assets/food_db_v10.sqlite` with the schema delta from §4
  - Sanity tests: `SELECT name FROM foods_fts WHERE foods_fts MATCH 'fried pork'` returns "Pork belly, cooked"
- `lib/services/food_db_service.dart`
  - Asset constant bumped: `food_db_v9.sqlite` → `food_db_v10.sqlite`
  - FTS query updated to also weight `aliases` column
  - Match scorer: alias hit weighted slightly less than name hit (so "Chicken Breast" beats "Chicken Wing aliased as chicken breast" for query "chicken breast")
- `pubspec.yaml` updated; old v9 asset removed
- Tests: new `food_db_service_alias_test.dart` with cases "fried pork", "kanin", "creamy chicken pasta"

**Acceptance:** Tests green. Offline app build, log "fried pork" → resolves to Pork belly, cooked.

### Phase 3 — Lambda single-call op

- `lambda_function.py` adds `parseFoodWithCandidates`:
  ```
  Request: { op, payload: { text, candidates: [{food_id, name}, ...] } }
  Response: { items: [{
    name, grams, hyde,
    food_id, confidence,                          // when matched from candidates
    estimated_macros: { calories, protein_g, carbs_g, fat_g }  // when food_id is null
  }] }
  ```
- Prompt instructs: pick `food_id` ≥ 0.6 confidence; otherwise set `food_id: null` AND populate `estimated_macros` from your own knowledge with confidence based on item ambiguity
- Enable **Bedrock Anthropic prompt caching** for the system prompt + instructions (~400 cached tokens, 90% input discount)
- Existing ops left in place — no break for any current caller

**Acceptance:** `curl` with mocked candidates for "fried pork and rice" returns 2 items with food_ids. `curl` with "ostrich liver" + empty candidates returns 1 item with `food_id: null` + sensible macros.

### Phase 4 — Pipeline cutover

- `lib/models/extracted_food_item.dart` adds `resolvedFoodId`, `resolverConfidence`, `estimatedMacros`
- `lib/services/ai_coach_service.dart` interface adds `parseFoodWithCandidates(...)`
- `lib/services/cloud_ai_coach_service.dart` implements it
- `lib/services/on_device_ai_coach_service.dart` + `null_ai_coach_service.dart` return null
- `lib/presenters/nutrition_presenter.dart` `_parseChatAsFood`:
  - **Step 1: personal dict precedence.** Quick-parse text into noun chunks; for each chunk hit `_personalDict`. If 100% hit rate, log directly, skip everything else.
  - **Step 2: candidate pool.** Run FTS (now alias-aware) over the whole text + each noun chunk; dedupe; take top-10.
  - **Step 3a (cloud on):** Single `parseFoodWithCandidates` call. For each returned item:
    - `food_id` present → hydrate via `_foodDb.getById`, `estimationSource = cloudAi`
    - `food_id: null` + `estimated_macros` → synthetic `FoodEntry` with cloud macros, `estimationSource = cloudAi`
    - **Auto-promote:** confidence ≥ 0.8 → add to personal dictionary (with the cloud-returned macros)
  - **Step 3b (cloud off):** Use existing `_ai.extractFoodItems` → per-item alias-aware FTS resolve → fall through to keyword-density bucket for unknowns

**Acceptance:** Cloud on:
- "fried pork and rice" logs in ~1s, both items resolved.
- "ostrich liver" logs with cloud macros, `cloudAi` source.
- Second log of "ostrich liver" hits personal dict, no cloud call.

Cloud off:
- "fried pork" resolves via alias FTS.
- "ostrich liver" gets keyword-density estimate (lower quality, but logs).

### Phase 5 — Polish

- `lib/views/settings_screen.dart` — copy explaining what Cloud AI does for food logging
- `docs/food_logging.md` — single source of truth describing both tiers; supersedes scattered notes in older specs
- Lambda CloudWatch — structured log line per call: `{user_id, op, items_resolved, items_estimated, cached_tokens, total_tokens}` for cost monitoring
- Retire Plan 022's older 6-step resolver code paths that are now dead

---

## 7. Cost & latency

### Build-time (one-time, your machine + your subscription)

| Step | Cost | Time |
|---|---:|---|
| Aliasing via `claude -p` | $0 (subscription) | ~30–60 min (280 batches × ~10s each) |
| DB v10 migration | $0 | seconds |
| **Total** | **$0** | **~1 hour** |

If your subscription rate-limits across that many calls, the script's resumability means you re-run later and it picks up where it left off.

### Per-user runtime

| Scenario | Latency | Cost (per log) |
|---|---|---:|
| Personal dict hit (repeat foods, common case after 2 wks) | ~50 ms | $0 |
| Cloud on, in-DB food | ~1.0 s | ~$0.0017 |
| Cloud on, out-of-DB food | ~1.2 s | ~$0.0020 |
| Cloud off, in-DB food (alias hit) | ~80 ms | $0 |
| Cloud off, out-of-DB food (keyword fallback) | ~80 ms | $0 |

At 30 logs/day × 30% routed to cloud: ~$0.46/month per active user.

---

## 8. File inventory

| File | Phase | Action |
|---|---|---|
| `scripts/build_food_aliases.py` | 1 | New |
| `scripts/data/aliases_shards/` | 1 | New (gitignored) |
| `assets/data/food_aliases.json` | 1 | New (committed) |
| `scripts/migrate_food_db_v10.py` | 2 | New |
| `assets/food_db_v10.sqlite` | 2 | New (committed) |
| `assets/food_db_v9.sqlite` | 2 | Delete |
| `lib/services/food_db_service.dart` | 2 | Version bump + alias-aware FTS query |
| `lib/utils/food_match_scorer.dart` | 2 | Weight alias hits |
| `lambda_function.py` | 3 | Add `parseFoodWithCandidates` op + caching |
| `lib/models/extracted_food_item.dart` | 4 | Add fields |
| `lib/services/ai_coach_service.dart` | 4 | New interface method |
| `lib/services/cloud_ai_coach_service.dart` | 4 | Implement new op |
| `lib/services/on_device_ai_coach_service.dart` | 4 | Stub null |
| `lib/services/null_ai_coach_service.dart` | 4 | Stub null |
| `lib/presenters/nutrition_presenter.dart` | 4 | Rewrite `_parseChatAsFood` |
| `lib/views/settings_screen.dart` | 5 | Copy update |
| `docs/food_logging.md` | 5 | New consolidated doc |
| `pubspec.yaml` | 2 | Asset swap |
| `.gitignore` | 1 | Add shard dir |

---

## 9. Decisions made

1. **No semantic embedding tier.** Aliasing + cloud LLM is enough. Reconsider only if offline UX measurably bad.
2. **Build-time generation via `claude -p` CLI.** No API keys, no Bedrock for one-time work. Uses your subscription.
3. **Auto-promote cloud estimates to personal dict** at confidence ≥ 0.8. First cloud log of "ostrich liver" becomes free for that user forever.
4. **Personal dict lookup runs first**, before candidate retrieval and before cloud, to skip everything for repeat foods.
5. **Aliases include descriptive phrases**, not just synonyms — covers free-form text offline.
6. **Existing `flutter_gemma` + on-device embedder + vector store is deprecated** but left in place for now. Phase 5 cleanup or Plan 027 removes it. Not on the critical path.

---

## 10. Open items

1. **Subscription rate limits during alias generation** — if `claude -p` throttles at high batch volume, the script is resumable. Worst case takes 2 sessions. Acceptable.
2. **Alias quality QA.** Plan a 30-min manual review of ~50 random alias sets post-Phase-1 before committing. Flag and regen any obviously wrong sets (mismatches, hallucinations).
3. **What confidence band for auto-promote?** Starting at 0.8. Revisit if users complain about "wrong" foods sticking in their dict — if so, tighten to 0.9 + require user confirmation on first log.
4. **Old food_db versions left in users' app data dir.** `food_db_service.init` already replaces on version bump; confirm v9 cleanup happens (delete stale .sqlite from documents dir).

---

## 11. Non-goals

- On-device semantic embeddings.
- Image-based food logging.
- Streaming cloud responses.
- Multi-region Lambda failover.
- Per-user model fine-tuning. Personal dict is the only personalization.
- Live DB updates from cloud — DB ships with releases.
