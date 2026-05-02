# Plan 017d — Nutrition Module Redesign

> Depends on **017** (tokens + theme) and **017W** (widget library) being merged.

## Goal

Apply the design system across every nutrition screen and sheet. Macros, calorie ring, food library, meal logging, history, and TDEE setup all share the same primitives.

---

## Files Touched

| File | Action |
|---|---|
| `lib/views/nutrition/nutrition_screen.dart` | Layout rewrite — `AppPageScaffold`, `AppCard`, `AppSection` |
| `lib/views/nutrition/food_library_screen.dart` | Search + list using `AppTextField`, `AppSelectableTile`, `AppEmptyState` |
| `lib/views/nutrition/nutrition_history_screen.dart` | List of past days as `AppListTile`s, grouped sections |
| `lib/views/nutrition/tdee_setup_screen.dart` | Stepper using `AppSegmentedControl` + `AppPrimaryButton` |
| `lib/views/nutrition/add_food_sheet.dart` | Wrap with `AppBottomSheet` |
| `lib/views/nutrition/log_meal_sheet.dart` | Wrap with `AppBottomSheet`; uses `AppSelectableTile` for food picker |
| `lib/views/nutrition/nutrition_settings_sheet.dart` | Wrap with `AppBottomSheet` |

---

## UX Direction

### Daily Summary (top of `nutrition_screen`)
- `AppCard` (elevated)
- Left half: calorie ring (theme-aware version of partial ring) showing eaten / target
- Right half: three macro `AppLinearProgress` bars — Protein, Carbs, Fat — with `AppNumberDisplay` value chips
- Below the card: row of `AppStatPill`s — TDEE, deficit/surplus, fiber, water (if tracked)

### Day Picker
- `AppDayChipRow` for selecting which day's nutrition to show — replaces the existing custom `_DayChip` row
- Above the daily summary card, full-width
- Today is highlighted with a subtle accent border; selected day gets filled primary

### Today's Meals
- `AppSection` "Today"
- List of `AppListTile`s (one per meal entry):
  - Leading: `AppIconBadge` (meal type) or food image
  - Title: food name
  - Subtitle: portion + macros summary
  - Trailing: kcal in DM Mono
  - Long-press → `AppActionSheet` with Edit / Duplicate / Delete (delete marked `isDestructive`)
- Empty state: `AppEmptyState` "Nothing logged yet" + CTA "Add a meal"

### FAB
- Replace any custom FAB with theme-default M3 FAB ("Add meal" → opens `add_food_sheet`)

### Food Library
- Top: `AppTextField` search with leading magnifier icon
- Filter chips below using `AppSegmentedControl` (All / Custom / Recent / Favorites)
- List: `AppSelectableTile` rows — name, brand, kcal/100g
- Empty / no-results: `AppEmptyState`

### History Screen
- Grouped `AppListTile`s by week, headers via `AppSection`
- Tile shows date, total kcal, status badge ("Hit target" / "Over" / "Under") via `AppBadge`

### TDEE Setup
- Multi-step using a single screen with `AppSegmentedControl` for activity level, `AppTextField` for height/weight/age
- Result card: `AppCard` with computed TDEE in `AppNumberDisplay`
- Confirm with `AppPrimaryButton`

---

## Design-System Widgets Consumed

`AppPageScaffold` · `AppCard` · `AppSection` · `AppDayChipRow` · `AppLinearProgress` · `AppNumberDisplay` · `AppStatPill` · `AppListTile` (with `onDelete` for swipe-to-delete on meals) · `AppSelectableTile` · `AppTextField` · `AppSegmentedControl` · `AppPrimaryButton` · `AppBottomSheet` · `AppActionSheet` (long-press menus) · `AppEmptyState` · `AppBadge` · `AppIconBadge` (meal-type leading icons)

---

## Acceptance Criteria

- [ ] No hardcoded colors in any nutrition view
- [ ] All sheets render via `AppBottomSheet` with consistent drag handle + header
- [ ] Macro bars use `AppLinearProgress`, not custom containers
- [ ] Numeric kcal/macros use DM Mono via `AppNumberDisplay`
- [ ] Both light and dark modes render correctly
- [ ] Empty states present on every list screen
- [ ] Touch targets ≥ 44×44px

---

## Out of Scope

- AI calorie estimation logic (separate module)
- Adding new macro types
- Backend/database schema changes
