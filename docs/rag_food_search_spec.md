# RAG Food Search — Spec

> **Status:** Active. Implementation tracked in [.claude/plans/021-rag-food-search.md](../.claude/plans/021-rag-food-search.md).

## Problem

Logging food today depends on the user phrasing entries the way `food_db.sqlite` indexes them. "Creamy yogurt with berries" misses; "yogurt" hits. Users either learn the trick or give up — both kill the `logStreak` quest.

## Goal

Replace wording-sensitive matching with **on-device semantic search** so meals can be logged in natural language and still resolve to the right `food_db` entry.

## Non-Goals

- Cloud embeddings or hosted vector DB
- Food vision (camera → calories) — deferred to Plan 022
- Embedding the user's chat history or finance data
- Replacing the existing FTS5 path — semantic is added in front, FTS5 stays as fallback

## User Experience

### States

| State | Trigger | UX |
|---|---|---|
| **idle** | Embedding model not yet downloaded | Settings shows "Smart food search — Download (~75 MB)". Logging works via existing FTS5 path. |
| **downloading** | User taps Download | Progress in Settings. Banner on the nutrition input: "Setting up smart search…". Logging unaffected. |
| **indexing** | Model installed; first index build running | Banner on nutrition input: "Indexing food database — 1,234 / 28,000". Search uses FTS5 in the meantime. |
| **ready** | Index ≥ 95% built | Subtle "✨ Smart search" badge near the input affordance. Per-query latency unchanged from user POV; results just match the right food. |
| **failed** | Embedder load fails (incompatible device) | Silent disable for the session. Logging falls through to FTS5. No user-facing error. |

### Confidence thresholds

| Threshold | Value | Behaviour |
|---|---|---|
| `_semanticHighConfidence` | `0.80` cosine | Top semantic candidate ships immediately (skip LLM rerank). |
| `_semanticAcceptable` | `0.55` cosine | Top-k passed to LLM rerank. Below this we treat as "no semantic match" and fall through. |
| `_llmConfidence` | `0.70` | If LLM rerank returns ≥ this, we use the picked candidate. |
| `_topK` | `5` | How many semantic candidates we feed to the LLM rerank. |

These are **starting values** — tune empirically against the user's real food entries during UX verification.

### Resolution chain (per-item, in order)

1. **Personal dictionary** — already-confirmed foods (unchanged).
2. **Semantic top-k** — embed query, ANN search via `flutter_gemma.searchSimilar(topK=5)`.
   - If top score ≥ `0.80` → return top hit, confidence 0.85.
3. **LLM rerank** — if top semantic score in `[0.55, 0.80)`, pass top-5 candidates + user query to Gemma. Pick best.
   - If LLM confidence ≥ `0.70` → return picked, confidence 0.75.
   - Else fall through.
4. **FTS5 + scoring** — existing `_resolveOneDbItemFts5` path, unchanged.
5. **Per-item AI macro estimate** — existing fallback for foods not in any DB.
6. **Keyword density buckets** — existing last-resort.

The user **never** sees "no match." Latency is bounded at every step.

## Indexing Pipeline

### What we embed

For each row in `food_db.sqlite`, embed the string:

```
"<name> (<category>)"
```

This gives the embedder both lexical and categorical signal. Examples:

```
"Yogurt, plain, whole milk (Dairy and Egg Products)"
"Adobo, chicken, with sauce (Pinoy Dishes)"
"Bread, whole wheat (Baked Products)"
```

### Build trigger

- First launch *after* the embedder is installed → kicked off after first frame, in an isolate (post-frame callback).
- App version bump that bumps `food_db_v4` → `food_db_v5` → clear and rebuild.
- User-triggered "Rebuild search index" in Settings (debug + recovery).

### Resumability

- Progress saved every page (500 rows): `IndexProgress(indexed, total, lastFoodId)`.
- On restart: resume from `lastFoodId`. No re-embedding.
- Persisted via `StorageService` (SharedPreferences key `nutrition.foodIndexProgress`).

### Priority order

1. Foods in `personal_food_dictionary` first (user's actual vocabulary).
2. Foods in `recentFoods` (last 30 days of entries).
3. Alphabetical for the long tail.

The user's most-logged foods become semantically searchable within seconds; the long tail finishes over the next few minutes.

### Throttling

- Embedding runs in a background isolate, batched 32 at a time.
- Pause when battery saver is on.
- Pause when foreground priority is critical (active LLM chat in progress).

## Vector Store

We use **flutter_gemma's built-in vector store** (`initializeVectorStore`, `addDocumentWithEmbedding`, `searchSimilar`). HNSW is enabled (`enableHnsw = true`) for O(log n) ANN search.

### Path

`${appDocs}/food_vectors.sqlite` (separate from `food_db_v4.sqlite` — we never write to the read-only food asset).

### Document schema

| Field | Value |
|---|---|
| `id` | `food.id` (USDA FDC id, string) |
| `content` | `"<name> (<category>)"` — what we embedded |
| `embedding` | `List<double>` (768 dims for `embeddingGemma300M`) |
| `metadata` | JSON: `{"name": "...", "category": "...", "cal": 250, "protein": ..., "carbs": ..., "fat": ...}` |

We hydrate `FoodSearchCandidate` from the metadata; we **don't** re-query `food_db` per result (it's redundant and slow).

## Embedding Model

**Default:** `embeddingGemma300M4bit` — 75 MB, 768 dims, multilingual.

Why 4-bit:
- 2-bit (38 MB) loses too much fidelity for the cuisine variety in `food_db`.
- 8-bit (150 MB) doubles the download for marginal quality gain.
- Multilingual matters — the user logs Tagalog terms ("kanin", "isda") and Filipino dishes ("adobo", "sinigang").

The embedder model file is **downloaded separately** from the LLM. It's gated on HuggingFace, so we reuse the existing `HF_TOKEN` from `.env`.

## Acceptance Criteria

- [ ] Logging "creamy yogurt with berries" returns a yogurt-category entry.
- [ ] Logging "leftover adobo" returns a chicken/pork adobo entry.
- [ ] Logging "small bowl of oatmeal" returns an oatmeal entry, grams ≈ 150 g (existing NLP behaviour preserved).
- [ ] Logging "kanin" returns rice (multilingual signal works).
- [ ] First-launch indexing completes within 5 min on a Pixel 6-class device, with non-blocking UI.
- [ ] Steady-state per-item resolution adds ≤ 400 ms over the existing path (p50).
- [ ] All existing nutrition tests still pass.
- [ ] New tests cover EmbeddingService, FoodSemanticSearchService, and the presenter integration paths.
- [ ] Light + dark mode screenshots of the new UI affordances (indexing banner, ready badge, settings entry).
- [ ] No hardcoded `AppColors.X` / `AppColorsLight.X` in new widgets.
- [ ] No calculations in `build()`; all derived state via presenter getters.
