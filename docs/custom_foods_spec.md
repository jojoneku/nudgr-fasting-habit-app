# Custom Foods Spec

## Overview

Let users **define their own foods once** — a homemade wheat bread, a protein
shake recipe, a portioned meal-prep container — with macros entered on a
**per-100g _or_ per-serving** basis, then log them later just by typing their
name. There is **no separate "My Foods" screen to manage**. A custom food folds
directly into the two systems the food logger already uses:

1. The **personal food dictionary** (`PersonalFoodDictionary`) — the per-100g
   lookup tier that already runs *before* the USDA food DB. A user-defined food
   becomes a first-class, **pinned** entry here.
2. The **AI candidate pool** — user-defined foods are injected as candidates
   into the cloud/on-device parse, so "2 slices of my wheat bread" resolves to
   the user's verified macros instead of an AI guess.

This reuses the existing scaling math (`FoodDbEntry.toFoodEntry(grams)` does
`grams / 100`) and the existing pipeline (`docs/food_logging.md`). The only
genuinely new surface is an **explicit "teach this food" entry point** (since
the user knows the recipe up front and shouldn't have to log-then-correct to
get it remembered) and **per-serving input** on top of the per-100g storage
that already exists.

### Design constraint (from the user)
> "It should be included in the DB / added to the knowledge base for the AI, so
> I don't need to click somewhere for my foods."

Therefore: **storage is always normalized to per-100g** (the pipeline's lingua
franca). Per-serving is an *input mode* and *display affordance*, not a second
storage format. Reuse is automatic via name resolution — never a dedicated tab.

---

## User Story

As someone who eats homemade and meal-prepped food whose macros I already know,
I want to define a food once (per 100g or per serving) and have the app
remember it, so that logging "150g wheat bread" or "2 slices of my bread" later
auto-scales my verified macros without me re-doing the arithmetic every time —
keeping my daily calorie/macro tracking (and fasting-window XP) accurate.

---

## Data Model

Extend the existing `PersonalFoodEntry` rather than introducing a parallel model
— this keeps user-defined foods on the exact same lookup path as auto-learned
ones. New fields are additive and optional, so existing persisted JSON
round-trips unchanged.

```dart
// lib/models/personal_food_entry.dart  (EXTENDED — new fields marked ★)
class PersonalFoodEntry {
  final String key;                 // normalized name (existing)
  final String name;
  final double kcalPer100g;         // canonical storage — always per 100g
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final int hits;
  final DateTime lastUsedAt;

  // ★ Provenance — distinguishes a deliberately-defined food from one the
  //   pipeline auto-promoted. user-defined entries are PINNED (never evicted
  //   by the 500-entry cap) and are injected into the AI candidate pool.
  final PersonalFoodSource source;  // autoLearned | userDefined

  // ★ Optional serving metadata. Present when the user defined the food
  //   per-serving (or set a serving size). Lets the UI offer "1 slice" quick
  //   quantities and lets the parser map "N slices" → N * servingGrams.
  //   When null, the food is gram-only (per-100g, like today).
  final double? servingGrams;       // e.g. 40g per slice
  final String? servingLabel;       // e.g. "slice", "cup", "scoop", "container"

  const PersonalFoodEntry({
    required this.key,
    required this.name,
    required this.kcalPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.hits = 1,
    required this.lastUsedAt,
    this.source = PersonalFoodSource.autoLearned,  // back-compat default
    this.servingGrams,
    this.servingLabel,
  });

  bool get isUserDefined => source == PersonalFoodSource.userDefined;
  bool get hasServing => servingGrams != null && servingGrams! > 0;

  /// Scale to a logged quantity. Mirrors FoodDbEntry.toFoodEntry so the rest
  /// of the pipeline is unchanged.
  FoodEntry toFoodEntry(double grams) {
    final f = grams / 100.0;
    return FoodEntry(
      id: FoodEntry.generateId(),
      name: name,
      calories: (kcalPer100g * f).round(),
      protein: proteinPer100g != null ? proteinPer100g! * f : null,
      carbs: carbsPer100g != null ? carbsPer100g! * f : null,
      fat: fatPer100g != null ? fatPer100g! * f : null,
      grams: grams,
      estimationSource: EstimationSource.personalDict,
      loggedAt: DateTime.now(),
    );
  }

  factory PersonalFoodEntry.fromJson(Map<String, dynamic> json) =>
      PersonalFoodEntry(
        key: json['key'] as String,
        name: json['name'] as String,
        kcalPer100g: (json['kcalPer100g'] as num).toDouble(),
        proteinPer100g: (json['proteinPer100g'] as num?)?.toDouble(),
        carbsPer100g: (json['carbsPer100g'] as num?)?.toDouble(),
        fatPer100g: (json['fatPer100g'] as num?)?.toDouble(),
        hits: json['hits'] as int? ?? 1,
        lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
        source: PersonalFoodSource.fromJson(json['source'] as String?),
        servingGrams: (json['servingGrams'] as num?)?.toDouble(),
        servingLabel: json['servingLabel'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'kcalPer100g': kcalPer100g,
        'proteinPer100g': proteinPer100g,
        'carbsPer100g': carbsPer100g,
        'fatPer100g': fatPer100g,
        'hits': hits,
        'lastUsedAt': lastUsedAt.toIso8601String(),
        'source': source.name,            // omit-safe: fromJson defaults
        'servingGrams': servingGrams,
        'servingLabel': servingLabel,
      };
}

enum PersonalFoodSource {
  autoLearned,
  userDefined;

  static PersonalFoodSource fromJson(String? raw) =>
      raw == 'userDefined' ? userDefined : autoLearned;
}
```

### Per-serving → per-100g conversion (input helper, lives in the presenter)
When the user picks "per serving" mode and enters serving macros + serving grams:
```dart
kcalPer100g    = servingKcal    / servingGrams * 100;
proteinPer100g = servingProtein / servingGrams * 100;   // etc.
// servingGrams + servingLabel are retained for quick-log + parser hints.
```
`EstimationSource.personalDict` **already exists** in
`lib/models/estimation_source.dart` — it badges as **"You"**, is `isTrusted`,
and is wired into `fromJson` and the badge-color extension. So custom foods get
correct trusted-source labelling for free; no enum change needed.

---

## Presenter API

Two surfaces. `PersonalFoodDictionary` (service) gains a user-defined-aware
upsert + pinning; `NutritionPresenter` exposes the define/edit/delete actions
the UI calls and wires custom foods into the candidate pool.

```dart
// lib/services/personal_food_dictionary.dart  (EXTENDED)
class PersonalFoodDictionary {
  // Existing: lookup(), prefixSearch(), all(), upsert(), remove(), clearAll()

  /// Define or overwrite a deliberate user food. Always per-100g at rest;
  /// callers convert from per-serving first. Marked userDefined → PINNED.
  Future<void> defineFood({
    required String name,
    required double kcalPer100g,
    double? proteinPer100g,
    double? carbsPer100g,
    double? fatPer100g,
    double? servingGrams,
    String? servingLabel,
  });

  /// User-defined entries only, newest first — for the editor list & AI pool.
  List<PersonalFoodEntry> userDefined();

  // _evictIfNeeded() updated: never evict source == userDefined.
}
```

```dart
// lib/presenters/nutrition_presenter.dart  (EXTENDED)
class NutritionPresenter extends ChangeNotifier {
  // — Define / manage (called from the log sheet's inline "save my food" flow) —
  Future<void> defineCustomFood({
    required String name,
    required MacroBasis basis,        // per100g | perServing
    required double kcal,             // interpreted per `basis`
    double? protein, double? carbs, double? fat,
    double? servingGrams,             // required when basis == perServing
    String? servingLabel,
  });
  Future<void> deleteCustomFood(String name);
  List<PersonalFoodEntry> get customFoods;   // for an inline editor list

  // — Log an existing custom food at a chosen quantity —
  Future<void> logCustomFood(PersonalFoodEntry food, {required double grams});

  // — Pipeline hook: custom foods seed the candidate pool so the AI knows them.
  //   Called inside _buildCandidatePool (see Integration below).
  List<PersonalFoodEntry> candidateCustomFoods(String text);
}

enum MacroBasis { per100g, perServing }
```

### Pipeline integration (the "AI knows my foods" part)
- **Tier 0 (already works):** `PersonalFoodDictionary.lookup()` runs before the
  food DB. A defined food named "wheat bread" resolves with zero AI cost the
  moment it's typed. No change needed beyond the food existing in the dict.
- **`_buildCandidatePool` (`nutrition_presenter.dart`):** prepend
  `candidateCustomFoods(text)` (prefix/alias match over user-defined entries) to
  the FTS5 candidates sent to `parseFoodWithCandidates`. This is how
  "2 slices of my homemade bread" — which Tier 0's exact-key lookup misses —
  still maps to the user's macros: the model picks the injected candidate, and
  `servingGrams` lets it convert "2 slices" → grams.
- **Auto-promotion unchanged:** confident DB/cloud hits keep upserting as
  `autoLearned`. A later `defineFood` on the same key **upgrades** it to
  `userDefined` (pins it, applies verified macros).

---

## UI Requirements

No standalone "My Foods" tab. Entry points live where the user already is:

1. **Inline "Save as my food" in manual entry** (`add_food_sheet.dart` /
   `_ManualEntrySheet`): a basis toggle — **`Per serving` | `Per 100g`** — and,
   when populated, a "Save so I can reuse this" switch. Saving calls
   `defineCustomFood`. Logging and defining are one action.
2. **Quantity step when reused:** when a custom food resolves (typed name or
   search row), show the existing grams field + quick pills. If `hasServing`,
   pills become serving-aware: **`1 ${servingLabel}` · `2` · `100g`** mapping
   slices→grams. Reuses the search-row scaler already in `log_meal_sheet.dart`.
3. **Lightweight editor (reachable, not foregrounded):** Settings → "Your foods"
   lists `customFoods` with edit/delete. This is management, not the logging
   path — logging never requires opening it. (Sits next to the existing
   "Reset learned foods" control.)

- **Thumb zone:** basis toggle + Save/Log primary button in the bottom 30% of
  the sheet (sheets already bottom-anchored).
- **States:** Loading (none — local) / Empty ("No custom foods yet — save one
  from a manual entry") / Populated (list with `densityLabel` + serving) /
  Error (invalid macros → inline validation, see Edge Cases).
- **Glanceability:** a resolved custom food shows a "your food" badge
  (`EstimationSource.personalDict`) so the user instantly trusts the numbers.
- **Micro-animations:** basis toggle crossfade 200ms; "Saved ✓" confirmation
  chip fades in 150ms then auto-dismisses.

---

## RPG Mechanics

- **XP awarded:** small one-time **+15 XP the first time a food is defined**
  (`source` transitions to `userDefined`), framed as "Recipe catalogued."
  Re-defining/editing the same food awards nothing (no farming).
- **No new level-up condition.** Logging a custom food earns the **normal meal
  XP** through the existing log path — custom foods must not pay double.
- **Streak logic:** unaffected. Custom foods feed the same daily-log totals that
  drive fasting/nutrition streaks; accuracy *improves* streak integrity but the
  streak rules don't change.

---

## Storage

- **No new top-level key.** User-defined foods persist in the **existing**
  personal-dict store via `StorageService.savePersonalDict` /
  `loadPersonalDict`. New fields (`source`, `servingGrams`, `servingLabel`) are
  additive in the per-entry JSON shown above.
- **Migration:** none required. Absent `source` → `autoLearned` (back-compat);
  absent serving fields → gram-only food (today's behavior).
- **XP-awarded ledger:** to keep the +15 XP one-time, persist nothing new —
  derive "already awarded" from `source == userDefined` already existing at
  define time (if it was userDefined before this call, skip the award).

---

## Edge Cases

- **Per-serving with zero/blank serving grams:** block save — can't derive
  per-100g. Inline error "Enter the weight of one serving."
- **kcal ≤ 0:** existing `upsert` already no-ops; surface as validation in the
  define flow rather than silently dropping.
- **Macros exceed calories sanity check:** if `4*protein + 4*carbs + 9*fat`
  wildly exceeds entered kcal (>20% over), warn (non-blocking) — recipe inputs
  are often rough.
- **Name collides with a USDA DB food (e.g. "wheat bread"):** intended — Tier 0
  dict precedence means the user's definition wins. Document this so it's not
  read as a bug.
- **Editing a food already logged today:** past `FoodEntry` rows are immutable
  snapshots and do **not** retroactively change; only future logs use new
  macros. (Consistent with templates today.)
- **Per-serving food logged by grams (or vice-versa):** both always work —
  storage is per-100g, so grams scale directly and servings scale via
  `servingGrams`.
- **500-entry cap:** user-defined entries are pinned and excluded from eviction;
  only `autoLearned` entries are evicted. Guard against a pathological all-pinned
  dict (unlikely at human scale) by still allowing manual delete.
- **Reset learned foods:** must offer to **preserve user-defined** foods (they're
  deliberate, not noise). Either scope the reset to `autoLearned` or confirm.

---

## Acceptance Criteria

- [ ] User can define a food with name + kcal + optional protein/carbs/fat on a
      **per-100g** basis and save it.
- [ ] User can define a food on a **per-serving** basis (serving grams + label);
      it is stored normalized to per-100g with serving metadata retained.
- [ ] After defining "wheat bread", typing it in the food chat resolves to the
      user's macros via Tier 0 with **no AI/network call**.
- [ ] Logging the food at a quantity (grams **or** servings) **auto-scales**
      kcal and macros correctly (per-100g math).
- [ ] "N slices of my bread" routed through the AI parser resolves to the user's
      food because it's injected into the candidate pool (not an AI guess).
- [ ] Custom foods are **never** evicted by the 500-entry cap; auto-learned ones
      still are.
- [ ] A resolved custom food is badged as the user's own food in the log UI.
- [ ] Defining a brand-new food awards **+15 XP once**; editing it awards none;
      logging it awards only the normal meal XP.
- [ ] Editing a custom food does not mutate already-logged entries.
- [ ] Existing persisted personal-dict JSON loads unchanged (new fields optional).
- [ ] No standalone "My Foods" tab in the primary nav; management lives in
      Settings and logging never requires visiting it.
