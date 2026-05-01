# Plan 007 — Calorie Counting v2 (Revised)

**Status:** Awaiting Approval
**Branch:** `feat/calorie-counting-v2`
**Updated:** 2026-04-20 — reassessed against current implementation; pivoted to UI modernization

---

## What's Already Built

All backend work from the original plan is done:

| Layer | Status |
|---|---|
| Models — `FoodEntry`, `DailyNutritionLog`, `MealSlot`, `NutritionGoals`, `TdeeProfile`, `FoodDbEntry`, `FoodTemplate`, `AiMealEstimate` | ✅ Done |
| `FoodDbService` — real SQLite impl with FTS5 + LIKE fallback | ✅ Done |
| `AiEstimationService` — real flutter_gemma impl | ✅ Done |
| `NutritionPresenter` — full API, TDEE, streaks, RPG hooks | ✅ Done |
| `NutritionScreen`, `LogMealSheet`, `AddFoodSheet`, `FoodLibraryScreen`, `NutritionHistoryScreen`, `NutritionSettingsSheet`, `TdeeSetupScreen` | ✅ Done |
| `MealSlot` simplified to single universal "meal" slot | ✅ Done |
| `assets/food_db.sqlite` + build script | ❌ Plan 009 — separate branch |

**What this plan covers:** UI modernization. The product logic is done; the presentation layer needs a redesign.

---

## The Problem

The current UI has two issues:

**1. Gamish/quirky styling throughout:**
- Title: `"ALCHEMY LAB"` with `letterSpacing: 3.0`
- `MdiIcons.flask` in the summary card header
- Section labels in ALL-CAPS gold with `letterSpacing: 1.5`
- `"✦ AI"` tab label in LogMealSheet
- Mode chip: `"SIMPLE"` all-caps with heavy letter spacing
- Gold borders on every card, row, and chip

**2. Happy path is not obvious enough:**
The screen has one FAB but the sheet that opens has two tabs (AI / Search) which forces an immediate mode decision. Most users just want to type something and be done.

---

## Design Direction

**Keep:** Dark background, cyan/purple/gold color tokens, card-based layout, animations.

**Drop:** ALL-CAPS game labels, letter-spacing on body text, flask icons, gold borders on every surface.

**Rule:** Color is for data meaning only — gold = calorie value, cyan = progress, green = goal met. Not decoration.

### Happy Path (< 30 seconds)

```
1. Open Nutrition screen
2. See today's number immediately (big, prominent)
3. Tap "+" FAB
4. Type food name or description → results show instantly
5. Tap item → done
```

The log sheet should feel like a smart search box, not a tabbed form.

---

## UI Changes

### NutritionScreen

| Element | Current | New |
|---|---|---|
| AppBar title | `"ALCHEMY LAB"` · letterSpacing 3 | `"Nutrition"` · normal weight |
| Mode chip | ALL-CAPS gold bordered badge | Small pill, lowercase, muted |
| Summary card header | Flask icon + bold calorie label | Calorie number as hero text (28sp, white) |
| Progress bar | Thin colored bar | Same bar, but no border on the card |
| Section label | `"MEALS"` all-caps gold letterSpacing 1.5 | `"Today"` — regular weight, secondary color |
| Entry rows | Gold bordered container every row | Divider-separated flat rows, no borders |
| FAB | `FloatingActionButton.extended` with icon + "Log Meal" | `FloatingActionButton` with `Icons.add` — simple |
| Quick-add chips | Gold-bordered pills | Filled chips, no border |

**Summary card new layout:**
```
┌─────────────────────────────────┐
│  1,450                          │
│  of 2,000 kcal  ──────────────  │  ← hero number, plain bar, no icon
│                                 │
│  P 85g · C 160g · F 48g        │  ← inline macro row (standard mode only)
└─────────────────────────────────┘
```

### LogMealSheet

| Element | Current | New |
|---|---|---|
| Two tabs (AI / Search) | Splits attention upfront | Single smart input field |
| Input behavior | Two separate flows | Type anything → food DB results appear live; if no match, AI estimate button appears |
| `"✦ AI"` tab | Gamish | Gone |
| Sheet header | Heavy-styled | Clean drag handle, `"Add Food"` title, no decoration |
| Pending items list | Bordered rows | Flat rows with leading calorie badge |
| Save as template | Checkbox row | Toggle row, bottom of sheet |

**New sheet flow:**
```
┌─────── Add Food ──────────────────┐
│  🔍  Search or describe...        │  ← single input, autofocus
│                                   │
│  White rice, cooked    195 kcal + │  ← live DB results
│  White rice, raw       360 kcal + │
│  White bread           265 kcal + │
│                                   │
│  [Estimate with AI]  ← appears if no results or user taps
│                                   │
│  ─── Added ───────────────────    │
│  White rice 150g        195 kcal  │
│  Salmon 120g            220 kcal  │
│  ───────────────────────────────  │
│  Total: 415 kcal                  │
│                                [Log]│
└──────────────────────────────────┘
```

---

## Affected Files

| File | Change |
|---|---|
| `lib/views/nutrition/nutrition_screen.dart` | UI overhaul — title, summary card, section labels, entry rows, FAB, chips |
| `lib/views/nutrition/log_meal_sheet.dart` | Merge AI + Search tabs into single smart input flow |
| `lib/views/nutrition/food_library_screen.dart` | Minor — remove gamish decoration, clean up headers |
| `lib/views/nutrition/nutrition_history_screen.dart` | Minor — clean up headers |
| `lib/views/nutrition/nutrition_settings_sheet.dart` | Minor — clean up section labels |
| `lib/views/nutrition/tdee_setup_screen.dart` | Minor — clean up step labels |

---

## Implementation Order

1. [ ] `NutritionScreen` — title, summary card hero layout, section label, entry rows, FAB, chips
2. [ ] `LogMealSheet` — merge tabs into single smart input; keep all existing logic, change only UI
3. [ ] `FoodLibraryScreen`, `NutritionHistoryScreen`, `NutritionSettingsSheet`, `TdeeSetupScreen` — surface cleanup
4. [ ] UX pass — verify 44×44 touch targets, animation timings, empty states

---

## What This Plan Does NOT Change

- No logic changes — presenter, models, services untouched
- No feature additions — all existing features stay
- Food DB (`assets/food_db.sqlite`) stays as Plan 009
- RPG hooks stay wired as-is

---

## Acceptance Criteria

- [ ] No ALL-CAPS labels with letterSpacing > 1.0 anywhere in nutrition views
- [ ] No `MdiIcons.flask` or game-specific icons in nutrition views
- [ ] `NutritionScreen` title reads "Nutrition"
- [ ] Summary card shows calorie number as hero text without a decorative icon
- [ ] LogMealSheet opens to a single search field (no tab bar)
- [ ] AI estimate option appears contextually when search returns no results
- [ ] All existing functionality (AI estimate, food DB search, templates, TDEE) still works
- [ ] All touch targets ≥ 44×44px
- [ ] No regressions in other screens

*Await approval before writing any code.*
