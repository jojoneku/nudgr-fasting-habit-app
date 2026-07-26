# Community Shared Food Database — Spec (DRAFT, not approved)

> **Status:** Design proposal for review. **Do not implement** until the data-quality / abuse / privacy model below is signed off.
> Phase 1 (personal custom foods) has shipped — see "Prerequisite" below. This spec covers **Phase 2 only**: sharing user-contributed foods to *all* users.
> Sibling precedent: [grocery_community_prices_spec.md](grocery_community_prices_spec.md) — the same shape (opt-in, anonymized, server-aggregated, read-only clients) applied to grocery prices. Reuse its infrastructure decisions where possible.

## 🎯 Objective

Let users *optionally* contribute foods they're confident about (a packaged product's label, a home recipe's per-100g macros) to a shared pool, so the next person who searches for that food finds it even though it isn't in the bundled USDA/Filipino DB. This grows coverage over time without shipping a new app build.

This is **not** a replacement for the bundled food DB or personal foods. Resolution order is unchanged and community data is only a **fallback**:

```
Personal dictionary  >  Bundled food DB  >  Community pool  >  AI estimate / unknown
    (your own)            (~14k, curated)     (crowd, fuzzy)
```

## ✅ Prerequisite (already shipped) — Personal custom foods (Phase 1)

- New foods a user creates go into `PersonalFoodDictionary` (per-100g density), via `NutritionPresenter.addCustomFood`.
- UI: Food Library → **My Foods** → **Add** → `AddCustomFoodSheet` (per-serving *or* per-100g input, normalized to per-100g).
- These entries already sync **per-user** (private) through the existing Supabase sync. **No entry is shared with anyone else today.** That sharing is exactly what this spec proposes to add — behind an explicit opt-in.

## ⚖️ Why this is risky (and the constraints that follow)

| Risk | Constraint it forces |
|---|---|
| **Data quality** — one person's "chocolate bar = 5 kcal/100g" poisons everyone's search; branded vs generic vs recipe all differ | Clients never see a single raw contribution. They see a **server-aggregated canonical row** (median per-100g macros, sample count). Contributions outside a sane band (e.g. kcal not in `[0, 900]`/100g, macros not reconcilable with kcal via 4/4/9) are rejected server-side |
| **Abuse / poisoning** — a public writable table invites garbage, spam, and offensive names | **No raw client writes.** Contributions go through a server-side **edge function** that validates, normalizes the name, profanity-filters, rate-limits per device token, and rejects outliers before it touches the pool |
| **Privacy** — food logs are personal | Contribution is strictly **opt-in** (off by default). The public row stores **no `user_id`, no device id**. Opting out stops future contributions immediately |
| **Trust** — clients must not read others' raw, unaggregated entries | Clients `SELECT` only an **aggregates/canonical** view (median macros, count, confidence, updated-at) — never individual contributions |
| **Moderation** — bad data still slips through | A **report** path flags a canonical entry; repeated flags `suppress` it pending review. Outlier rejection (drop values outside 1.5×IQR per macro) runs on every write |

## 🧱 Data model (Supabase)

Two tables + one view (all new; **manual migration**, per the deploy workflow — mirror `grocery` migration `053`):

- `community_food_contributions` — write-only via edge function. Columns: `id`, `food_key` (normalized name, see `SearchNormalize.dense`), `display_name`, `kcal_100g`, `protein_100g`, `carbs_100g`, `fat_100g`, `source` (`label` | `recipe`), `created_at`. **No user identity.** RLS: no direct client `INSERT`/`SELECT`.
- `community_food_canonical` — server-maintained rollup per `food_key`: `display_name`, `kcal_100g` (median), `protein_100g`, `carbs_100g`, `fat_100g`, `sample_count`, `confidence` (derived from count + agreement), `updated_at`, `suppressed` (bool). RLS: client `SELECT` allowed (read-only), no write.
- Edge function `submit-community-food` — validates payload, macro-vs-kcal reconciliation, profanity-checks name, rate-limits per device token, inserts a contribution, recomputes the canonical row with outlier rejection.

## 🔄 Flow

1. **Contribute (opt-in):** in `AddCustomFoodSheet`, when community sharing is on, saving also fires the edge function with `{food_key, display_name, kcal_100g, macros, source}`. Fire-and-forget, anonymized. (A checkbox on the sheet — "also share this anonymously" — makes the opt-in per-save and explicit.)
2. **Consume:** extend the resolution pipeline in `NutritionPresenter`/`FoodDbService`. After personal-dict and bundled-DB miss, query `community_food_canonical` by `food_key`. If a healthy entry exists (`sample_count ≥ N`, not `suppressed`), offer it as a `remembered`-style hit, visually tagged **community** with its sample size.
3. **Report:** long-press a community result to flag it; repeated flags suppress the canonical row.

Personal > bundled > community. Community values never overwrite a personal or bundled entry.

## 🔌 Integration options for "consume"

`FoodDbService` today wraps a **read-only bundled SQLite asset** (`assets/food_db.sqlite`) — it has no network path. Two ways to fold community data in:

- **(A) Live query** — hit `community_food_canonical` over the network as a fourth resolver, cache results locally. Fresh, but adds latency + an online dependency to search.
- **(B) Periodic bake** — a job rolls vetted canonical rows into the next bundled-DB asset shipped via the existing OTA/asset update path ([ota_update_spec.md](ota_update_spec.md)). Slower to propagate, but keeps search fully offline and lets a human gate what goes in.

**(B) is the safer default** — it keeps the curated-DB quality bar and offline guarantee, and turns "grow the DB for all users" into a reviewed pipeline rather than a live public write surface.

## 📱 UX

- **Settings toggle:** "Contribute my foods to the community (anonymous)" — default **off**, with a one-line privacy explainer. Plus the per-save checkbox in the sheet.
- Community results are visually distinct (a small **community** chip + sample size) so the user knows the source and confidence, and can down-weight a low-`n` estimate.

## ⛔ Out of scope / open questions

- **Branded vs generic vs recipe** collision on the same `food_key` (a specific bar vs "chocolate"). May need brand/barcode as part of the key.
- Barcode capture to key packaged goods reliably (ties into the existing food-photo flow).
- Whether to contribute to **Open Food Facts** instead of self-hosting — pro: shared ecosystem, real barcodes; con: less control, PH coverage gaps. Worth evaluating before building a bespoke pool.
- Anti-abuse hardening (device attestation) if spam becomes real.
- Cost/scale of edge-function invocations + canonical recomputation.

## 📋 Recommendation

Personal custom foods (Phase 1) already covers the *individual* "save a food I'm confident about" need with **zero** abuse/privacy/moderation surface. Treat this community layer as a **separate, explicitly-approved project**, and prefer **option (B) periodic bake** so shared data still clears the bundled-DB quality bar. Before building either, decide whether a **curated bundled expansion** (we grow `food_db.sqlite` ourselves from vetted sources) delivers most of the coverage win without standing up a public write path at all.
