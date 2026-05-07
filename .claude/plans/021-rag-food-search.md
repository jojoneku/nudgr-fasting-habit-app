# Plan 021 — RAG-Powered Food Search

> **Status:** Approved 2026-05-07. Spike at step 2 **passed** — `flutter_gemma 0.12.6` ships the full RAG stack (embedding model + vector store + HNSW). This dropped our `VectorStoreService` and replaced it with a thin wrapper over `flutter_gemma`'s built-in `initializeVectorStore` / `addDocumentWithEmbedding` / `searchSimilar` APIs. APK savings unchanged (~50 MB after lib pruning); implementation simpler than originally scoped.


## Goal

Replace the current FTS5+keyword pipeline's "wording-sensitive" matching with **semantic search** so users can log meals in their own words ("creamy yogurt with berries", "leftover adobo", "small bowl of oatmeal") and get the right `food_db.sqlite` entry — even when the wording doesn't match the USDA-style name.

This unlocks the user's stated pain: *"I have a hard time recording food because sometimes it records the wrong food — I have to word the food a certain way."*

**RPG-loop relevance:** Faster, more accurate logging = fewer abandoned entries = stronger `logStreak` = INT XP awards keep firing. Reduces the friction tax on the daily quest of "log every meal."

## Scope

**In:**
- New on-device embedding pipeline (Gemma text embedder via `flutter_gemma`)
- Vector index over `food_db.sqlite` rows (food name + category)
- Hybrid retrieval: semantic top-k → optional LLM re-rank → FTS5 fallback
- Background one-time indexing on first launch (resumable, with progress UI)
- Integration into existing `_resolveOneDbItem` path in `NutritionPresenter`

**Out (deferred):**
- Food vision (camera → calories) — Plan 022
- Cloud-hosted embeddings — not needed; on-device works
- Embedding personal `food_library` templates or chat history

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/services/embedding_service.dart` | **Create** | Service |
| `lib/services/vector_store_service.dart` | **Create** | Service |
| `lib/services/food_semantic_search_service.dart` | **Create** | Service |
| `lib/services/food_db_service.dart` | Modify (expose `getAllForIndex`) | Service |
| `lib/services/storage_service.dart` | Modify (add index-progress keys) | Service |
| `lib/services/local_storage_service.dart` | Modify (impl new keys) | Service |
| `lib/services/ai_coach_service.dart` | Modify (add `disambiguateFood`) | Service |
| `lib/services/on_device_ai_coach_service.dart` | Modify (impl `disambiguateFood`) | Service |
| `lib/services/cloud_ai_coach_service.dart` | Modify (impl `disambiguateFood`) | Service |
| `lib/services/null_ai_coach_service.dart` | Modify (return null) | Service |
| `lib/models/food_search_candidate.dart` | **Create** | Model |
| `lib/models/index_progress.dart` | **Create** | Model |
| `lib/presenters/nutrition_presenter.dart` | Modify (`_resolveOneDbItem` adds semantic step) | Presenter |
| `lib/presenters/settings_presenter.dart` | Modify (expose index status / "rebuild index" action) | Presenter |
| `lib/main.dart` | Modify (DI wiring + first-launch indexing kickoff) | Wiring |
| `lib/views/...` (nutrition input, settings) | Minor (progress badge, "Indexing… 23%" hint) | View |
| `test/services/embedding_service_test.dart` | **Create** | Test |
| `test/services/vector_store_service_test.dart` | **Create** | Test |
| `test/services/food_semantic_search_service_test.dart` | **Create** | Test |
| `test/presenters/nutrition_presenter_semantic_test.dart` | **Create** | Test |
| `pubspec.yaml` | Add `sqlite3_flutter_libs` (for sqlite-vec) **OR** plain `sqflite` + naive cosine | Config |
| `android/app/build.gradle.kts` | `packagingOptions` — keep gemma-embedding/vector-store/chunker, exclude rest | Config |
| `docs/rag_food_search_spec.md` | **Create** | Spec |

## Interface Definitions

### Models

```dart
// lib/models/food_search_candidate.dart
class FoodSearchCandidate {
  final FoodDbEntry entry;
  final double score;          // cosine similarity ∈ [-1, 1] (typically [0, 1])
  final SearchSource source;   // semantic | fts5 | personal_dict
  const FoodSearchCandidate({
    required this.entry,
    required this.score,
    required this.source,
  });
}

enum SearchSource { semantic, fts5, personalDict }

// lib/models/index_progress.dart
class IndexProgress {
  final int indexed;
  final int total;
  final bool isComplete;
  final String? lastFoodId;
  final DateTime? completedAt;
  const IndexProgress({
    required this.indexed,
    required this.total,
    required this.isComplete,
    this.lastFoodId,
    this.completedAt,
  });
  double get fraction => total == 0 ? 0 : indexed / total;
}
```

### Services

```dart
// lib/services/embedding_service.dart
class EmbeddingService {
  Future<void> init();          // loads MediaPipe text embedder via flutter_gemma
  bool get isReady;
  int get vectorDim;            // e.g. 384 for the Gemma embedder we ship
  Future<List<double>> embed(String text);
  Future<List<List<double>>> embedBatch(List<String> texts);
  Future<void> dispose();
}

// lib/services/vector_store_service.dart
class VectorStoreService {
  Future<void> init({required int vectorDim});
  Future<void> upsert(String foodId, List<double> vector);
  Future<void> upsertBatch(Map<String, List<double>> entries);
  Future<List<({String foodId, double score})>> search(
    List<double> query, { int k = 10 });
  Future<int> count();
  Future<void> clear();
  Future<void> dispose();
}

// lib/services/food_semantic_search_service.dart
class FoodSemanticSearchService {
  FoodSemanticSearchService({
    required EmbeddingService embedder,
    required VectorStoreService vectorStore,
    required FoodDbService foodDb,
  });

  bool get isReady;                          // both embedder and store ready
  bool get isIndexing;
  IndexProgress get progress;
  Stream<IndexProgress> get progressStream;

  /// One-time pipeline; safe to call repeatedly (resumes from last id).
  Future<void> buildIndex({void Function(IndexProgress)? onProgress});

  /// Returns top-k candidates ordered by descending score.
  Future<List<FoodSearchCandidate>> search(String query, {int k = 5});
}

// AiCoachService addition
abstract class AiCoachService {
  // ... existing ...

  /// Re-rank [candidates] against [userQuery]. Returns the best candidate's
  /// food_id and a confidence ∈ [0, 1], or null if model unavailable / fails.
  /// Implementations should keep the prompt small (top-5 candidates, names only).
  Future<({String foodId, double confidence})?> disambiguateFood(
    String userQuery,
    List<FoodSearchCandidate> candidates,
  );
}

// StorageService additions
abstract class StorageService {
  // ... existing ...
  Future<IndexProgress> loadFoodIndexProgress();
  Future<void> saveFoodIndexProgress(IndexProgress progress);
  Future<void> clearFoodIndexProgress();
}
```

### Presenter integration

```dart
// In NutritionPresenter — replace _resolveOneDbItem with:
Future<FoodDbEntry?> _resolveOneDbItem(
  ParsedFoodItem item, { String? altName }) async {

  // Step 1 — semantic top-k (NEW)
  if (_semanticSearch.isReady) {
    final candidates = await _semanticSearch.search(item.name, k: 5);
    if (candidates.isNotEmpty && candidates.first.score >= _semanticHighConfidence) {
      return candidates.first.entry; // strong vector match — ship it
    }
    if (candidates.isNotEmpty && _ai.isAvailable) {
      // Step 2 — LLM re-rank ambiguous candidates (NEW, optional)
      final rerank = await _ai
          .disambiguateFood(item.name, candidates)
          .timeout(const Duration(seconds: 5))
          .catchError((_) => null);
      if (rerank != null && rerank.confidence >= _llmConfidence) {
        final hit = candidates.firstWhere(
          (c) => c.entry.id == rerank.foodId,
          orElse: () => candidates.first,
        );
        return hit.entry;
      }
    }
  }

  // Step 3 — fall back to existing FTS5 + scoring (UNCHANGED)
  return _resolveOneDbItemFts5(item, altName: altName);
}

static const _semanticHighConfidence = 0.80; // tune empirically
static const _llmConfidence = 0.70;
```

## Data Pipeline — How embeddings get built

We **cannot** ship pre-computed embeddings in the asset (the runtime MediaPipe Gemma text embedder is what defines vector compatibility, and we don't have a build-host equivalent without major CI work). So:

**First-launch indexing:**

1. App boot completes → `main.dart` schedules `FoodSemanticSearchService.buildIndex()` in the background after the first frame.
2. `EmbeddingService.init()` loads the embedder (heavy — runs on isolate).
3. `FoodDbService.getAllForIndex()` streams rows in pages of 500.
4. For each page, `EmbeddingService.embedBatch([name, name, ...])` produces vectors.
5. `VectorStoreService.upsertBatch(...)` persists.
6. Progress saved every page → `IndexProgress(indexed=N, total=T, lastFoodId=X)`.
7. UI shows a non-blocking banner: *"Indexing food database — 1,234 / 28,000. Search will improve when complete."*
8. If the app is killed mid-index, next launch resumes from `lastFoodId`.

**Priority order:**
- Foods referenced by `personal_food_dictionary` first (user's actual vocab)
- Foods seen in `recentFoods` next
- Then alphabetical for the long tail

**When to rebuild:**
- App version bump that changes `food_db.sqlite` (versioned filename `food_db_v4.sqlite` already does this) → clear index + re-build
- Embedding model version change → same
- User-triggered "Rebuild search index" in Settings (debug aid)

## Query Pipeline

```
user types "creamy yogurt with berries"
        ↓
NutritionPresenter.parseChat()
        ↓
FoodNlpParser.parse() ──▶ ParsedFoodItem(name="creamy yogurt with berries", grams=...)
        ↓
NutritionPresenter._resolveOneDbItem(item)
        │
        ├─ PersonalFoodDictionary.lookup("creamy yogurt with berries")  → miss
        │
        ├─ FoodSemanticSearchService.search("creamy yogurt with berries", k=5)
        │     ├─ EmbeddingService.embed(query)            → [0.12, -0.04, ...]
        │     ├─ VectorStoreService.search(qVec, k=5)     → [(id1, 0.84), (id2, 0.79), ...]
        │     └─ FoodDbService.getById(id) for each       → List<FoodSearchCandidate>
        │
        ├─ if top score ≥ 0.80 → return immediately
        ├─ else if AI available → disambiguateFood(query, candidates)
        │     LLM prompt: "Which food best matches 'creamy yogurt with berries'?
        │                 1. Yogurt, plain, whole milk
        │                 2. Yogurt, vanilla, low fat
        │                 3. ...
        │                 Reply with JSON: {id: 'X', confidence: 0.0-1.0}"
        │
        └─ else → FTS5 fallback path (existing _resolveOneDbItemFts5)
        ↓
FoodEntry built with macros, confidence, estimationSource
```

## Fallback Behaviour

| Condition | Behaviour |
|---|---|
| Index not yet built | Skip semantic step, use existing FTS5 path. UI shows "Smart search ready in ~2 min". |
| Embedder load fails | Disable semantic permanently for the session, log warning, fall back to FTS5. |
| Semantic returns empty | Fall through to FTS5. |
| Semantic top score `< 0.80` AND LLM unavailable | Use FTS5 result if better; otherwise top semantic candidate at confidence 0.5 (flagged for user review). |
| LLM re-rank fails / times out | Use top semantic candidate at confidence 0.6. |
| All paths miss | Existing keyword density bucket fallback (unchanged). |

The user **never** sees "no match" — there's always a graceful degradation chain.

## Migration

- **No schema changes** to existing `food_db.sqlite` (asset stays read-only).
- **New writable DB** at `${appDocs}/food_embeddings.sqlite` — created lazily.
- **No user data migration needed** — additive feature. Existing chat messages, food log, and personal dictionary stay untouched.
- On first launch after this ships, the user sees the indexing banner. If they uninstall + reinstall, indexing happens again (acceptable).

## Implementation Order

1. [ ] **Spec** — write `docs/rag_food_search_spec.md` covering UX states (idle / indexing / ready / failed), thresholds, and acceptance.
2. [ ] **Verify embedder API** — spike a 50-line script that calls flutter_gemma's text-embedder API for a single string. If the package doesn't expose it cleanly, decide between: (a) MethodChannel binding to MediaPipe directly, or (b) abandon RAG and use FTS5 + LLM re-rank only. **Gating decision.**
3. [ ] **Models** — `FoodSearchCandidate`, `IndexProgress`.
4. [ ] **StorageService** — add the three index-progress methods and a fake for tests.
5. [ ] **EmbeddingService** — implement + unit test (mock the underlying plugin).
6. [ ] **VectorStoreService** — start with **naive in-memory cosine** (load all vectors at startup, brute-force search). 28k × 384 floats ≈ 43 MB RAM — acceptable for v1. Defer `sqlite_vec` integration unless we hit perf issues.
7. [ ] **FoodDbService.getAllForIndex()** — paged iterator over `foods` table.
8. [ ] **FoodSemanticSearchService** — orchestration, progress, resumable build.
9. [ ] **AiCoachService.disambiguateFood** — implement on `OnDeviceAiCoachService`, stub on `NullAiCoachService`, mirror on `CloudAiCoachService` if cloud is enabled.
10. [ ] **NutritionPresenter integration** — modify `_resolveOneDbItem` per the snippet above. Keep existing path intact behind `if (_semanticSearch.isReady)`.
11. [ ] **DI wiring** — construct services in `main.dart`, pass into `NutritionPresenter`.
12. [ ] **First-launch kickoff** — schedule `buildIndex` on the first frame after auth completes. Don't block the UI.
13. [ ] **Settings UI** — index status badge + "Rebuild" button (uses existing settings patterns).
14. [ ] **Nutrition input UI hint** — small "🔍 Smart search active" badge when ready; "Indexing 23%" when not.
15. [ ] **Tests** — unit tests for each service in isolation (StorageService fake, mock InferenceModel, real EmbeddingService with a tiny vector-dim test mode).
16. [ ] **Integration test** — log "creamy yogurt with berries" → asserts a yogurt entry is selected.
17. [ ] **APK lib pruning** — `android/app/build.gradle.kts` `packagingOptions` excludes Gecko + image-gen + MediaPipe-vision libs. Verify build still passes + AI features still work.
18. [ ] **UX verification** — load the build on a physical mid-range Android, time first-launch indexing, time per-query latency, screenshot light + dark mode.

**Gate after step 2.** If `flutter_gemma` doesn't expose embeddings cleanly, we re-plan as "FTS5 + LLM re-rank only" (drops the embedding lib too, cuts another 17 MB).

## Testing Strategy

| Test | Layer | Approach |
|---|---|---|
| `EmbeddingService` produces stable vectors | Service | Real plugin, fixed input → fixed-length vector, deterministic dim |
| `VectorStoreService` upsert + search round-trip | Service | In-memory store, cosine of identical vector returns score ≈ 1.0 |
| `VectorStoreService` resumability | Service | Insert N, simulate restart, assert state restored |
| `FoodSemanticSearchService` index progress | Service | Mock `FoodDbService` returns 3 rows, assert progress 0/3 → 3/3 |
| `FoodSemanticSearchService.search` k limit | Service | Insert 20 rows, search, assert exactly k results |
| `NutritionPresenter._resolveOneDbItem` semantic hit | Presenter | Mock semantic returns `[(yogurt, 0.85)]` → presenter returns yogurt entry |
| `NutritionPresenter._resolveOneDbItem` semantic low-conf → FTS5 | Presenter | Mock semantic 0.6, mock FTS5 returns valid entry → returns FTS5 entry |
| `NutritionPresenter._resolveOneDbItem` LLM re-rank picks #2 | Presenter | Mock semantic returns 5, mock AI picks index 2 → returns index 2 entry |
| Disambiguation timeout doesn't crash | Presenter | Mock AI hangs → after 5 s, presenter falls through to top semantic |
| Integration: smart food log | E2E | Full chain: chat input → real services → expected food id |

## RPG Impact

- **No changes** to XP / level / streak math. The RPG-loop relevance is *removing friction* on the existing `logStreak` quest, not adding new currency.
- The "smart search active" badge gets a tiny "✨" icon — consistent with the System aesthetic but not a new mechanic.
- One small behavioural change: because `_learnFromEntry` already learns confident matches into `personal_food_dictionary`, semantic-search hits at confidence ≥ 0.6 will populate the dict faster, so the user's per-meal latency drops over time (good).

## APK Size Impact

| Lib | Before (MB) | After Plan 021 | After Plan 021 + lib pruning |
|---|---|---|---|
| `libllm_inference_engine_jni.so` | 27.4 | keep | keep |
| `liblitertlm_jni.so` | 20.2 | keep | keep |
| `libgemma_embedding_model_jni.so` | 17.0 | **keep (now used)** | keep |
| `libgecko_embedding_model_jni.so` | 17.0 | keep | **drop** |
| `libtext_chunker_jni.so` | 9.4 | **keep (now used)** | keep |
| `libsqlite_vector_store_jni.so` | 7.5 | conditional¹ | conditional¹ |
| `libmediapipe_tasks_vision_jni.so` | 14.3 | keep | **drop** |
| `libmediapipe_tasks_vision_image_generator_jni.so` | 14.0 | keep | **drop** |
| `libimagegenerator_gpu.so` | 10.4 | keep | **drop** |
| `libflutter.so` | 11.1 | keep | keep |
| `libapp.so` | 10.2 | keep | keep |
| **Total `lib/` (uncompressed)** | **~158** | **~158** | **~104 (–34%)** |
| **APK total** | **~156** | **~156** | **~115** |

¹ `libsqlite_vector_store_jni.so` only kept if we choose the sqlite-vec route in step 6. With the naive in-memory cosine v1 we can drop it for another 7.5 MB savings → APK ~107 MB.

**Net:** with naive cosine + lib pruning, we land ~**107 MB** — under the 100 MB AAB threshold once Play splits per-arch and uses zip alignment. Still need an AAB build, not a fat APK, to actually clear the Play Store gate.

## Performance Targets

| Metric | Target | Notes |
|---|---|---|
| First-launch index time (28k rows) | ≤ 5 min on Pixel 6 / mid-range | run in isolate, no UI block |
| Steady-state query latency (semantic + LLM rerank) | ≤ 600 ms p50 | 200 ms embed + 50 ms cosine + 350 ms LLM |
| Steady-state query latency (semantic only, high conf) | ≤ 250 ms p50 | embed + cosine only |
| RAM for vector store (in-memory v1) | ≤ 50 MB | 28k × 384 × 4 B = 43 MB |
| Cold-start hit on app boot | ≤ +200 ms | EmbeddingService.init() lazy until first query |

Mitigations if we miss:
- **Index too slow:** reduce vector dim (use a smaller embedder), or only embed top 5k most-common foods.
- **Query too slow:** drop LLM re-rank step on low-end devices (gate on `Build.MODEL` or RAM heuristic).
- **RAM too high:** swap naive cosine for `sqlite_vec` (re-introduces the 7.5 MB lib).

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| `flutter_gemma` doesn't expose text-embedder API in Dart | **Gating spike at step 2.** Fall back to "FTS5 + LLM re-rank only" plan. |
| Embedding model download on first run is huge (.task file) | If the embedder model isn't bundled, we'd add 50–150 MB to first-launch download. Confirm during spike whether it's bundled or downloaded — if downloaded, surface progress UI just like the LLM. |
| Indexing kills battery / heats device | Throttle: max 60 s of CPU per minute. Pause when battery saver is on. |
| Vector store corruption on crash mid-write | Use SQLite transactions per page; resume from `lastFoodId`. |
| Semantic returns wrong category (e.g. "milk" → "soy milk drink") | LLM re-rank is the safety net. Also keep `FoodMatchScorer.isLearnableMatch` gate before writing to personal dict. |
| Embeddings stale after `food_db_v4` → `food_db_v5` | Versioned by `embedding_model_version` + `food_db_version` keys; mismatch triggers re-index. |
| Existing `food_db.sqlite` rows have inconsistent `name` formatting (USDA-style verbose strings) | Embed `name + " (" + category + ")"` to give the embedder more signal; tune in spec. |
| User logs while indexing is at 1% | Falls back to FTS5 — same UX as today. Banner sets expectation. |
| Multi-language inputs (Tagalog: "kanin", "isda") | Gemma embedder is multilingual but with English bias. Test specifically; if poor, embed both `name` and `category` and add a small Tagalog-English food alias table. |

## Acceptance Criteria

- [ ] Logging "creamy yogurt with berries" returns a yogurt-category entry (not a generic "berries" entry, not "no match").
- [ ] Logging "leftover adobo" returns a chicken/pork adobo entry.
- [ ] Logging "small bowl of oatmeal" returns an oatmeal entry, with grams ≈ 150 g (existing NLP behaviour preserved).
- [ ] First-launch indexing completes within 5 min on a Pixel 6-class device, with non-blocking UI.
- [ ] Steady-state per-item resolution adds ≤ 400 ms over the existing path (p50).
- [ ] App still builds + runs with `packagingOptions` excluding Gecko + image-gen + vision libs.
- [ ] All existing nutrition tests still pass.
- [ ] New tests cover EmbeddingService, VectorStoreService, FoodSemanticSearchService, and the presenter integration paths.
- [ ] Light + dark mode screenshots of the new UI affordances.
- [ ] No hardcoded `AppColors.X` in new widgets.
- [ ] No calculations in `build()`; all derived state via presenter getters.

---

*Approve this plan before any implementation begins. The step-2 spike result will likely refine sections 6 and the size table.*
