# Plan 022 — Food Logging Overhaul

> Status: ACTIVE
> Created: 2026-05-08
> Supersedes parts of: Plan 021 (RAG Food Search)

## Goal

Replace the brittle 6-layer chat-logging pipeline with a 3-layer pipeline that's seamless when confident and offers a one-tap confirm chip when uncertain. Expand the bundled food DB to give the matcher more to work with.

## Non-goals

- USDA Branded import (440 MB, ~zero PH brands — manual curation handles PH better)
- Open Food Facts integration (future chunk)
- Barcode scanning (future)

## Chunk 1 — DB expansion

### 1.1 Add Foundation Foods import

`scripts/import_usda_fdc.py` already pulls SR Legacy + FNDDS. Add the Foundation Foods URL (`FoodData_Central_foundation_food_csv_2025-04-24.zip`, ~3 MB) with `data_type = foundation_food`. Same parser, same nutrient-id fallback (Foundation may use either ID scheme — already handled).

### 1.2 Name-level deduplication in build script

After merging curated + USDA datasets, normalize each entry name (lowercase, strip commas/parens, collapse whitespace) and group. For each group, keep the **highest-priority** entry by source: curated > Foundation > SR Legacy > FNDDS. Curated wins on collision because it represents your overrides.

```python
PRIORITY = {"curated": 0, "foundation": 1, "sr_legacy": 2, "fndds": 3}
```

Print a dedup summary: `N groups had duplicates, kept M, dropped K`. Verify a handful manually.

### 1.3 PH brands curation (~200 entries)

Add to `CURATED_FOODS` in `scripts/build_food_db.py`. Cover:

- **Dairy**: Bear Brand (powdered, whole, fortified), Alaska (evaporated, condensed, sweetened), Birch Tree (full cream, low fat), Magnolia (milk, butter, cheese), Carnation Evaporated, Cowhead, Anchor PH, Eden Cheese
- **Instant noodles**: Lucky Me Pancit Canton (Original, Chilimansi, Sweet & Spicy, Kalamansi), Lucky Me Beef Mami, Chicken Mami, Special Beef, Special Chicken, Curlee Curl, Maggi Magic Sarap variants, Nissin Cup Noodles PH, Payless Xtra Big
- **Snacks**: Pillows, Boy Bawang (Cornick Adobo, Garlic, BBQ), Clover Chips (Cheese, BBQ, Sour Cream), Piattos, Nova, Chippy, Mr. Chips, V-Cut, Tortillos, Skyflakes, Fudgee Bar, Cream-O, Hany, Cloud 9, Choco Mucho, Chocnut, Flat Tops
- **Beverages**: C2 Apple/Lemon/Lemon Honey, Zest-O Orange/Apple, Tang sachet, Eight O'Clock, Funchum, Coca-Cola PH 200/355/500ml, Royal Tru Orange, Sarsi, Mountain Dew PH, Sprite PH, Pepsi PH, Coke Zero PH
- **Bread**: Gardenia (White, Wheaten, Wholesome White, Pandesal), Julie's Bakeshop loaf, Pinoy Tasty
- **Canned/preserved**: Argentina Corned Beef, Purefoods Corned Beef, Mega Sardines (Tomato, Hot, Spanish), Century Tuna (Hot & Spicy, Flakes in Oil, Lite, Mediterranean), Hunt's Pork & Beans, Pampanga's Best Tocino, Tender Juicy Hotdog, San Marino Tuna, Spam PH variants
- **Condiments/seasoning**: Datu Puti Soy/Vinegar/Patis, Silver Swan Soy, UFC Banana Ketchup, Jufran, Knorr Beef/Chicken Cube, Mama Sita Sinigang/Kare-kare/Mechado/Adobo Mix, Lily's Peanut Butter
- **Restaurant items per 100g or per piece**:
  - **McDo PH**: Big Mac, Quarter Pounder, McChicken, Chickenjoy 1pc, McSpaghetti, Cheeseburger, Hot Fudge Sundae, McRice
  - **Jollibee**: Yumburger, Champ, Aloha Yumburger, Spaghetti regular, Chickenjoy 1pc/2pc/Bucket, Chicken Sandwich, Burger Steak, Palabok, Yum Fries reg
  - **Mang Inasal**: Chicken Inasal Paa PM/PH/PHD, Pecho, Sisig, Halo-Halo Espesyal
  - **Chowking**: Chao Fan, Wonton Mami, Halo-Halo Espesyal, Chinese-style Fried Chicken, Lauriat
  - **Greenwich**: Pizza Hawaiian Overload slice, Lasagna Supreme, Spaghetti Bolognese
  - **KFC PH**: Hot & Crispy 1pc, Original 1pc, Mashed Potato
  - **Andoks/Senor Pedros**: Lechon Manok 1/4, Liempo
  - **Goldilocks**: Ensaymada, Pichi-Pichi, Bibingka Especial, Polvoron, Cheese Roll, Mocha Chiffon Slice
  - **Red Ribbon**: Black Forest slice, Mango Cake slice
  - **Mary Grace**: Cheese Rolls, Ensaymada
- **Beer/spirits**: San Miguel Pale Pilsen 330ml, San Mig Light, Red Horse, Tanduay Light, Ginebra San Miguel, Emperador Light
- **Coffee/3-in-1**: Nescafé 3-in-1 Original, Kopiko Brown, Great Taste White Original, Blend 45
- **Pasalubong/regional**: Hopia Mongo (Eng Bee Tin), Otap Cebu, Polvoron Goldilocks, Bagoong Alamang, Tinapa, Tocino Pampanga's Best, Longganisa Pampanga, Lucban Longganisa
- **Local chocolates/sweets**: Goya bars, Hany, Flat Tops, Chocnut, Cloud 9, Whammos, Tira-Tira

Per-100g values sourced from manufacturer nutrition panels where available, otherwise estimated from comparable USDA entries with a ±10% margin noted in commit message.

### 1.4 Run combined import

Single `python scripts/import_usda_fdc.py` run produces ~14,800 rows after dedup, ~3.5 MB asset.

## Chunk 2 — Matcher refactor

### 2.1 New flow

```
Personal Dict cache         ← instant, exact, learned
    │ miss
    ▼
LLM tool call (one inference)
    log_food({items: [{name, grams, hyde_description}]})
    │
    ▼
Hybrid search per item
    FTS5(name)  +  embedding(hyde_description)
    └──→ Reciprocal Rank Fusion → top-5
    │
    ▼
Confidence gate
    ├── top-1 score >> #2  → auto-commit (seamless)
    └── ambiguous          → render chip with top-3, user taps
```

### 2.2 Confidence gating (the seamless part)

Compute `confidence = score(top1) − score(top2)` after RRF fusion. Auto-commit when:

- `confidence >= 0.20` (clear winner), OR
- `top1` is from personal dict (always trusted), OR
- `top1.name` is an exact (case-insensitive, punctuation-insensitive) match for the LLM's `name`

Otherwise render up to 3 chips with the food name + macro preview. Tap to commit. The chip stays in the chat row; the Food Entry already exists in today's log under the auto-pick (so no friction to keep it). Tapping a different chip swaps and updates the log.

This way the UX is **seamless when confident**, **one-tap when not** — zero confirmation friction for foods you've already logged or that match cleanly.

### 2.3 Code surgery

**`OnDeviceAiCoachService`** — add `extractFoodItems(text)` using Qwen native tool calling. Returns `[{name, grams, hyde_description}]` from one inference. Keep existing `parseFood` for back-compat during migration but mark deprecated.

**`FoodDbService`** — add `hybridSearch(name, hyde, k)` returning RRF-fused top-k. Internal: parallel FTS5 query on `name` and embedding query on `hyde`, fuse via `score = Σ 1/(60+rank)`.

**`NutritionPresenter`** — replace `_handleChatInput`'s 6-step pipeline with the 3-step flow. Delete `_resolveOneDbItem`, `_resolveViaSemantic`, `_resolveViaFts5`, AI normalize step, AI macro estimate step. Keyword-density `_macrosFromCalories` stays as last-ditch unknown-food fallback.

**`FoodMatchScorer`** — delete `pickBest`, `isLearnableMatch`, `_score`. Keep `isReasonableNormalization` only if used elsewhere (probably can delete too). RRF rank replaces all of this.

**Chat row UI** — add a "candidates" sub-row that renders when `entry.confidence < threshold`. Each chip shows food name + kcal. Tap swaps the entry. Personal dict learns the swap.

### 2.4 No-AI fallback path

If `_ai.isAvailable == false`:
1. Personal Dict
2. Existing `FoodNlpParser.parse()` (rule-based) for name + grams
3. FTS5 search on the parsed name only (no HyDE)
4. RRF degenerate (single-source rank) → confidence gate → same chip UX

Same UX, no AI, slightly worse recall on edge cases. Acceptable degradation.

## Out of scope this round

- Rebuilding the embedding index from scratch on DB upgrade (existing incremental top-up handles new entries — embeddings of UNCHANGED rows stay valid)
- Per-row "edit grams" UI on already-logged items (separate UX work)
- Server-side fallback for missing foods (cloud LLM macro estimation)

## Risk / migration

- Embedding index will incrementally embed ~14k new entries on next launch when the embedder is installed. Slow but background.
- Personal dictionary entries from old pipeline still apply — they're keyed by normalized food name, source-agnostic.
- DB version bumped to v6 already; will copy fresh asset on next launch.

## Done when

- "kefir milk", "rolled oats", "iced tea", "soy protein isolate" all auto-commit to the right entries
- Truly ambiguous queries show 3 chips you can tap
- No silent wrong-matches (the failure mode now is "you tap a chip", not "you logged the wrong food")
- ~80% of typical chat inputs resolve in one inference
