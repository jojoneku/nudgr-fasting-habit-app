# Plan 033 — Audit: Food Logging & AI-Powered Flow ⭐

> **Status:** Audit findings + phased improvement proposal. **This is the owner's priority area** ("food logging is still not a smooth flow… we want this AI-powered").
> **Severity of domain:** 🟠 High product-impact (accuracy + UX), not a crash risk.
> **One-sentence summary:** There are two divergent logging UIs sharing one matching engine; matcher tuning has hit diminishing returns; the biggest wins now are (1) unifying the flow, and (2) moving *portion + macro estimation* to an LLM instead of hand-coded kcal/g constants.

---

## Current flow map

### Path 1 — Chat feed (modern, primary)
`_ChatInputBar` (`nutrition_screen.dart:1794`) → `_send()` (`:1915`) → `presenter.parseChat()` (`nutrition_presenter.dart:1728`) → `_parseChatAsFood` (`:1756`), a **3-tier cascade**:
- **A — Cloud** (`_tryCloudParseFood`, `:2044`): local FTS5 builds a candidate pool → one Bedrock Haiku call (`parseFoodWithCandidates`) returns `food_id` picks + `estimated_macros` → per-item resolve (personal dict → DB hydrate if conf ≥ 0.70 → cloud macros → keyword bucket).
- **B — On-device single-call** (`_tryLocalParseFood`, `:1917`): Qwen3 0.6B picks a `food_id` from candidates → falls through to hybrid RRF → keyword bucket.
- **C — Legacy on-device** (`:1788`): `extractFoodItems` (HyDE) → per-item `_hybridResolveItem` → keyword bucket.
Then `_commitFoodChat` (`:2455`) writes the entry. Low-confidence picks (< 0.6) render swap chips.

### Path 2 — LogMealSheet (legacy, still wired)
`hub_screen.dart:383` `onLogMeal` → `_showLogMealSheet` (`:542`) → `LogMealSheet` (1762 lines) → the **older** `parseMeal`/`estimateMeal` API (`:1266`, `:1215`) → `FoodNlpParser.parse` → `_resolveDbMatches` → `confirmParsedMeal`. **No cloud tier, no RRF confidence gating.**

### Friction points
1. **Two divergent paths for one task.** Logging via the hub button gets materially worse matching than typing in the chat feed. This is the single biggest "not smooth" driver.
2. **Latency stacking.** Cloud path = candidate FTS + 25s-timeout Bedrock call, serially. On-device Path B is a 30s Qwen call; on failure it falls to Path C — *another* 25s Qwen call + N resolves. Worst case chains two 25–30s model calls before the keyword fallback. No streaming, no optimistic UI — just a spinner.
3. **No confirmation/preview on the chat path.** Items commit immediately; correction is only via swap chips, which appear *only* when confidence < 0.6 and alternatives exist. A confident-wrong match commits silently.
4. **Manual-add & templates are buried** behind two small icon buttons left of the input (`:1966-1979`).

---

## Findings

### 🟠 H1 — Macro estimation falls back to a fixed 15/50/35 split for every DB-miss food
- **Where:** `_macrosFromCalories` (`nutrition_presenter.dart:1462`), `_fillMacros` (`on_device_ai_coach_service.dart:503`); applied at `:1873-1886, 1986, 2189`.
- **Problem:** Any keyword-bucket food gets 15% protein / 50% carb / 35% fat. "Chicken breast" is reported as 50% carbs. Macro totals — a core metric for IF users tracking protein — are systematically wrong for the long tail.
- **Fix:** Attach a coarse macro profile to each `_calorieBucket` (per-bucket P/C/F ratio), especially pure-fat and protein buckets.

### 🟠 H2 — Confidence-gate asymmetry lets low-quality cloud estimates auto-commit *and auto-learn*
- **Where:** `nutrition_presenter.dart:2167` (cloud estimate defaults to `confidence: 0.6` with **no** swap chips, alts `const []` at `:2216`), `:2171-2182` (auto-promotes cloud estimates to the personal dictionary at conf ≥ 0.8).
- **Problem:** On-device DB picks require conf ≥ 0.70, but an open cloud estimate with no DB candidate commits silently *and* a single hallucinated Haiku estimate becomes a permanent "verified" personal-dict entry that bypasses the DB forever (this is the "rice stuck on Sapin-sapin" class of bug).
- **Fix:** Gate auto-learn behind explicit user confirmation, or only auto-learn DB-resolved picks — never open estimates.

### 🟠 H3 — Keyword-density fallback defaults to 1.5 kcal/g for unrecognized foods
- **Where:** `_estimateCalories` (`:1638`) returns `grams * 1.5` on a full miss; default "plate" is 300g → 450 kcal assigned to any unknown word, committed at 0.3 confidence.
- **Fix:** For true misses, route to a cloud estimate or surface an explicit "couldn't estimate — tap to set" state rather than committing a fabricated number.

### 🟡 M1 — `_hybridResolveItem` is "RRF" over a single list; the semantic arm is gone
- **Where:** `nutrition_presenter.dart:1346`. RRF runs over one ranked list (FTS5 only). The Plan 022 semantic/vector arm (`_semanticSearch`) referenced in the comment at `:1334` **does not exist** in the code (likely removed by commit `0c245ea` "remove smart-search and barcode").
- **Problem:** RRF over one list is just `1/(60+rank)`; confidence `top1/(top1+top2)` measures the FTS rank gap, not match quality — which is why false matches slip through with "high" confidence.
- **Fix:** Either restore a real second retriever (embeddings) or rename and recompute confidence from lexical coverage (`FoodMatchScorer` already has that signal). Simplify the now-vestigial HyDE/RRF comments either way.

### 🟡 M2 — Portion units are coarse fixed constants with no learning
- **Where:** `food_unit_converter.dart` — plate=300g, bowl=250g, serving=150g, piece=100g; `_pieceSize` is a brittle order-sensitive `if`-ladder (`:132-172`, note the "eggplant before egg" comment).
- **Problem:** Even a perfect food match can be 2× off on calories because the gram estimate is wrong. This is the dominant error source Plan 029 (photo) calls out.
- **Fix:** Strongest case for AI portion estimation — see proposal Phase 1/3.

### 🟡 M3 — The USDA-canonical guard is duplicated 3× and heuristic
- **Where:** `FoodNlpParser._looksLikeUsdaCanonical` (`:211`), `on_device_ai_coach_service.dart:806`, `nutrition_presenter.dart:2423`. Three near-identical fragile rules → inconsistent behavior across tiers.
- **Fix:** Extract to one shared util.

### 🟡 M4 — Bare-number portion heuristic is wrong for common inputs
- **Where:** `FoodNlpParser` `:158` — bare number ≥ 10 with no unit → grams; < 10 → pieces. So "12 grapes" → 12g; "2 rice" → 2 pieces × piece-size. Low individual severity, high frequency.

### 🟡 M5 — Cloud `extractFoodItems`/`parseFood`/`estimateMacrosForItems` are null stubs
- **Where:** `cloud_ai_coach_service.dart:127, 133, 229` return null; only `parseFoodWithCandidates`, `estimateMacros`, `disambiguateFood` are implemented. So Path C (`extractFoodItems`, `:1791`) can never run on cloud; the cascade comments overstate the cloud fallback.
- **Fix:** Document the real cloud cascade or implement a cloud `extractFoodItems`.

### 🟢 Low
- **L1:** `personal_food_dictionary.prefixSearch` is O(entries×words) run per keystroke (`:71`) — fine at the 500 cap, watch it on typeahead.
- **L2:** FTS5 caps 20 rows; fuzzy rerank pulls 200 via leading-wildcard `LIKE` (`food_db_service.dart:131`) — won't scale.
- **L3:** plural stemming just strips trailing "s" (`:1526`) — "chips"→"chip" breaks the bucket match.

### Data model & multi-user
`assets/food_db.sqlite` (17 MB, ~14k rows) is bundled read-only and copied per-device (`food_db_service.dart:198`), versioned by `_dbFilename` (`food_db_v10`). The personal dict is device-local `SharedPreferences`, capped at 500, **not synced**. Implications: every curation fix needs an app release + full 17 MB re-download; personal dicts don't sync across a user's devices and the rich `_logFeedback` signal can't improve the shared DB. **For multi-user:** serve candidate lookups server-side behind the existing JWT-authed Lambda and sync the personal dict to Supabase; keep bundled SQLite as the offline fallback.

---

## AI-powered food logging proposal (phased)

The matcher tuning (24/62 → 1/62 failures) was heroic but it's whack-a-mole on hand-coded constants. The leverage is in **moving estimation + portioning to an LLM and making the flow conversational + visual.**

### Phase 0 — Unify the flow (no AI; prerequisite)
Retire `LogMealSheet`'s separate `parseMeal` path; make the hub "Log meal" button open/focus the chat feed. One pipeline, one quality bar. Extract the 3 USDA-guard copies (M3) to a shared util. **This alone removes the biggest "not smooth" complaint.**

### Phase 1 — Photo logging (Plan 029, ready to build)
Sound and low-risk — reuses the commit pipeline. Two corrections to fold in: (a) do **not** auto-learn photo estimates to the personal dict (same as H2 — they're the least verified); (b) add the swap-chip path for photo items < 0.6. Directly kills the M2 portion problem for the highest-pain case (composite plates).

### Phase 2 — Conversational disambiguation + smart defaults
In the ambiguous-confidence band, instead of silent-commit or static chips, have the cloud tier ask **one** targeted question ("fried or grilled chicken?") → resolves portion + bucket in one tap. Reuse the finance classifier's `StepClarify`/quick-reply loop (`runFinanceClassifierStep` proves the pattern works).

### Phase 3 — LLM portion + macro estimation as the default for DB misses
Replace the H1/H3 fabricated numbers: when no DB candidate resolves, the cloud `estimatedMacros` becomes the primary source (it already exists); the keyword bucket becomes the **offline-only** fallback, with per-bucket macro profiles so the offline path stops reporting everything as 50% carbs.

### Phase 4 — Learning from corrections (close the loop)
Today swaps learn (`_learnFromEntry`, `:2604`) but the rich `_logFeedback` telemetry (dislike, fallbackMiss, swap) is write-only with no consumer — a "curation backlog" no one reads. Build the loop: feed disliked/missed queries into (a) personal-dict seeding with confirmation, or (b) an offline DB-augmentation job. This is where the personal dictionary becomes genuinely "AI that learns *you*."

---

## Remediation / build order
1. **Phase 0** (unify flow) — biggest UX win, unblocks everything.
2. **H2** (stop auto-learning open estimates) — prevents permanent poisoning; do before scaling AI estimation.
3. **Phase 1** (photo, Plan 029) with the H2/swap-chip corrections.
4. **H1 + H3 + Phase 3** (LLM estimation default + bucket macro profiles).
5. **M1/M3/M4** cleanups; **Phase 2** conversational disambiguation.
6. **Phase 4** + multi-user food-DB/personal-dict server move (coordinate with Plan 030/034).

## Definition of done
- One logging entry point and one matching pipeline.
- No fabricated macro split or 1.5 kcal/g guess silently committed; DB-miss foods get an LLM estimate or an explicit "set portion" prompt.
- Auto-learn only on confirmed/DB-resolved picks.
- Photo logging live; ambiguous items ask one question instead of guessing.
