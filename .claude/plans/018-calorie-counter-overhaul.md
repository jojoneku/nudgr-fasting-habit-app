# Plan 018 — Calorie Counter Overhaul

**Branch:** `feat/calorie-counting-v2`  
**Date:** 2026-04-20  
**Status:** Awaiting approval

---

## Goal

The calorie logger is functional but friction-heavy. This overhaul rebuilds around three concrete user paths, restores named meal slots, adds inline editing + editable history, upgrades data visualization, and eliminates unnecessary user decisions throughout.

### Core UX principle: reduce decisions, not just taps
Every choice the user doesn't have to make is a UX win. Defaults must be right 80% of the time. Customization exists but doesn't lead.

### The 3 core user paths

| Path | User intent | Target tap count |
|---|---|---|
| A — Quick-log a template | "Same breakfast every day" | ≤ 2 from NutritionScreen |
| B — Search & log from DB | "Chicken breast, 200g" | FAB → search → adjust (optional) → log |
| C — Create / manage templates | "Set up Morning Routine" | Library FAB → name → add items → save |

---

## Root Cause: The Data Bug

`DailyNutritionLog.fromJson` has a **silent squash bug**. After v2 migration it correctly collapses legacy breakfast/lunch/dinner/snack entries into `MealSlot.meal`, but the final `return` statement runs even for data that was _already_ correctly slotted — collapsing every new write to the generic `meal` slot. This must be fixed first.

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/meal_slot.dart` | Modify — add `icon`, `isActive` | Model |
| `lib/models/daily_nutrition_log.dart` | Modify — fix fromJson squash bug | Model |
| `lib/presenters/nutrition_presenter.dart` | Modify — `suggestedSlot`, `editFoodEntry`, `editHistoryEntry` | Presenter |
| `lib/views/nutrition/nutrition_screen.dart` | Rewrite — ring, My Meals panel, slot accordions, inline edit | View |
| `lib/views/nutrition/log_meal_sheet.dart` | Rewrite — slot picker, serving UX, named template save | View |
| `lib/views/nutrition/nutrition_history_screen.dart` | Rewrite — expandable rows, edit in history, better chart | View |
| `lib/views/nutrition/food_library_screen.dart` | Extend — FAB + template creation sheet | View |

No new models. No new storage keys. No new dependencies.

---

## Interface Definitions

### `MealSlot` additions (model — no serialization impact)

```dart
IconData get icon;           // used in slot accordions and pill row
bool isActive(DateTime now); // time-window check for suggestedSlot
```

Time windows:
- `breakfast`: 05:00–10:59
- `lunch`:     11:00–14:59
- `dinner`:    17:00–21:59
- `snack`:     all other hours (including late night, early morning)
- `meal`:      never suggested (legacy only)

### `NutritionPresenter` additions

```dart
// Pure computed getter — no state, no storage
MealSlot get suggestedSlot;

// Edit an entry in today's log
Future<void> editFoodEntry(String entryId, MealSlot slot, FoodEntry updated);

// Edit an entry in a past day's log
Future<void> editHistoryEntry(String date, String entryId, MealSlot slot, FoodEntry updated);

// Delete an entry from a past day's log
Future<void> removeHistoryEntry(String date, String entryId, MealSlot slot);
```

`editFoodEntry` replaces the entry in `_todayLog`, saves, and re-runs `_checkGoalMet` / `_checkProteinGoalMet` / `_checkOvershoot`. `editHistoryEntry` mutates the matching `DailyNutritionLog` in `_history` and saves. No RPG hooks fire for history edits.

---

## Implementation Order

### Step 1 — Fix `DailyNutritionLog.fromJson`

```dart
// BEFORE (buggy — always squashes even clean data)
return DailyNutritionLog(date: ..., meals: {MealSlot.meal: allEntries});

// AFTER — deserialize slot keys faithfully (migration paths unchanged)
final Map<MealSlot, List<FoodEntry>> meals = {};
for (final kv in mealsJson.entries) {
  final slot = MealSlot.fromJson(kv.key);
  final entries = (kv.value as List).map((e) => FoodEntry.fromJson(e)).toList();
  meals[slot] = entries;
}
return DailyNutritionLog(date: json['date'] as String, meals: meals);
```

Migration v1 + v2 paths are unchanged — their output `{MealSlot.meal: allEntries}` is correct and handled by the fixed path.

### Step 2 — Add slot metadata to `MealSlot`

```dart
IconData get icon => switch (this) {
  MealSlot.breakfast => Icons.wb_sunny_outlined,
  MealSlot.lunch =>     Icons.restaurant_outlined,
  MealSlot.dinner =>    Icons.dinner_dining,
  MealSlot.snack =>     Icons.local_cafe_outlined,
  MealSlot.meal =>      Icons.grid_view,
};

bool isActive(DateTime t) => switch (this) {
  MealSlot.breakfast => t.hour >= 5  && t.hour < 11,
  MealSlot.lunch =>     t.hour >= 11 && t.hour < 15,
  MealSlot.dinner =>    t.hour >= 17 && t.hour < 22,
  MealSlot.snack =>     true,  // catch-all
  MealSlot.meal =>      false, // never suggested
};
```

### Step 3 — Add presenter methods

```dart
MealSlot get suggestedSlot {
  final now = DateTime.now();
  for (final s in [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner]) {
    if (s.isActive(now)) return s;
  }
  return MealSlot.snack;
}

Future<void> editFoodEntry(String entryId, MealSlot slot, FoodEntry updated) async {
  final entries = (_todayLog.meals[slot] ?? [])
      .map((e) => e.id == entryId ? updated : e)
      .toList();
  _todayLog = DailyNutritionLog(date: _todayLog.date,
      meals: {..._todayLog.meals, slot: entries});
  notifyListeners();
  await _storage.saveNutritionLog(_todayLog);
  await _checkGoalMet();
  await _checkProteinGoalMet();
  await _checkOvershoot();
}

Future<void> editHistoryEntry(String date, String entryId, MealSlot slot, FoodEntry updated) async {
  final idx = _history.indexWhere((l) => l.date == date);
  if (idx == -1) return;
  final log = _history[idx];
  final entries = (log.meals[slot] ?? [])
      .map((e) => e.id == entryId ? updated : e)
      .toList();
  _history[idx] = DailyNutritionLog(date: date,
      meals: {...log.meals, slot: entries});
  notifyListeners();
  await _storage.saveNutritionHistory(_history);
}

Future<void> removeHistoryEntry(String date, String entryId, MealSlot slot) async {
  final idx = _history.indexWhere((l) => l.date == date);
  if (idx == -1) return;
  _history[idx] = _history[idx].removeEntry(entryId, slot);
  notifyListeners();
  await _storage.saveNutritionHistory(_history);
}
```

### Step 4 — Overhaul `NutritionScreen`

**Layout (top to bottom):**

```
AppBar  "Nutrition"   [history icon]  [settings icon]

─── IF-Sync Banner (conditional) ───────────────────

─── Calorie Ring Card ───────────────────────────────
  CustomPaint ring, 200×200, centered
  • Track ring: 12px wide, AppColors.surface
  • Fill arc: sweeps clockwise to calorieProgress
  • Color: secondary (default) → success (goal met) → danger (>120%)
  • Gradient: SweepGradient from ring start color to fill color for depth
  • Center text stack:
      [large] remaining kcal  (e.g. "842")
      [small] "kcal remaining"  or  "Goal met ✓"
  • Outer label below ring: "X,XXX / Y,XXX kcal · goal"
  • Ring animates with AnimatedContainer duration: 300ms

  Macro strip (3 columns, only if macros tracked):
    P  [thin bar]  Xg      C  [bar]  Xg      F  [bar]  Xg
    Bar is 4px tall, rounded, fills to macro progress
    Color: primary (P) / gold (C) / danger (F)

  Streak pill (if goalStreak > 0):
    "🔥 N-day streak" — right-aligned, textSecondary, 11px

─── My Meals Panel ──────────────────────────────────
  Row: "My Meals" label (textSecondary 11px)   "Manage →" (gold, 11px)
  SizedBox height 96, ListView.builder horizontal
  MealTemplateCard (width 140, full height):
    Container(surface, radius 14, padding 12)
    Row: [slot icon, 14px, textSecondary]  Spacer  [kcal, 11px, gold]
    Text: template.name (13px, white, 2 lines max, ellipsis)
    Tap → addMealFromTemplate(t, t.defaultSlot ?? suggestedSlot) — instant, no confirm
    Long-press → slot picker sheet (for templates without defaultSlot)
  Empty state (no templates): "Tap + in Library to save meals"

─── Slot Accordions ──────────────────────────────────
  [breakfast] [lunch] [dinner] [snack] sections
  Each _SlotSection:
    Header (48px tap target):
      [slot.icon 16px]  [slot.label bold]  Spacer  [Xcal]  [chevron]  [+ 44×44]
    If entries: AnimatedSize list of _EntryRow (with edit + delete)
    If empty: Ghost placeholder row "Log breakfast here" → opens sheet
    Default expanded if has entries today; collapsed if empty.

  Legacy "Uncategorized" section — shown only if MealSlot.meal has entries.

─── Bottom FAB padding ─────────────────────────────

FAB: gold, endFloat, opens LogMealSheet(preselectedSlot: suggestedSlot)
```

**`_EntryRow` — adds edit action:**

```
[~?] [food name          ]  [P Xg · C Xg · F Xg]    [XXX kcal]  [✎ 44×44]  [✕ 44×44]
```

Tap ✎ → opens `_EditEntrySheet` (pre-filled ManualEntrySheet variant):
- Same fields as ManualEntrySheet (name, calories, macros optional)
- "Save changes" button → calls `presenter.editFoodEntry(entryId, slot, updated)`

### Step 5 — Overhaul `LogMealSheet`

**Serving size UX — the core fix:**

Current: 4 chips (50/100/150/200g) + mismatched custom TextField = 5 decisions.

New: **One number, always editable.**

```dart
// _SearchResultRow layout
Row(
  children: [
    Expanded(child: Column(
      children: [
        Text(entry.name),
        Text('$cal kcal · ${_grams.round()}g', style: textSecondary),
      ],
    )),
    // Single gram display — tap opens inline keyboard
    GestureDetector(
      onTap: _focusGrams,
      child: Container(
        width: 64, height: 44,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gramsFocused
              ? AppColors.gold
              : AppColors.textSecondary.withValues(alpha: 0.15)),
        ),
        child: Center(child: Text('${_grams.round()}g',
            style: TextStyle(
              color: _gramsFocused ? AppColors.gold : AppColors.textSecondary,
              fontSize: 12))),
      ),
    ),
    SizedBox(width: 8),
    IconButton(icon: Icon(Icons.add_circle, color: AppColors.gold, size: 28),
        onPressed: () => widget.onAdd(entry.toFoodEntry(_grams))),
  ],
),
// Gram keyboard — only visible when _gramsFocused
AnimatedSize(
  duration: Duration(milliseconds: 200),
  child: _gramsFocused ? TextField(
    autofocus: true,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(hintText: 'Grams', suffix: Text('g')),
    onChanged: ...,
    onSubmitted: (_) => setState(() => _gramsFocused = false),
  ) : SizedBox.shrink(),
),
```

Default is always 100g. No chips. Zero chip-selection decisions. Tap the gram badge to open a numeric keyboard — the subtitle line (`X kcal · P Xg · Xg`) already updates live as grams change, so the badge itself stays minimal (just the number, no repeated calorie display).

**Full sheet layout:**

```
Handle

"Log Food"                              [X close]

─── Slot Pill Row (h: 44) ───────────────────────────
  [☀ Breakfast] [🍽 Lunch] [🌆 Dinner] [☕ Snack]
  Scrollable horizontal. Selected: gold fill, background fg.
  Pre-selected: presenter.suggestedSlot (or preselectedSlot param).

─── Search Field ─────────────────────────────────────
  Autofocus. Same style as before.

─── Content (AnimatedSwitcher 180ms) ─────────────────
  "quick": My Meals (top 5 by useCount) then Recent chips row
  "results": _SearchResultRow list (single gram pill, no chip row)
  "no-results": AI button or unavailable banner + "Add manually"

─── AI State ─────────────────────────────────────────

─── Cart (pinned above actions) ──────────────────────
  Entry rows: [name] · [kcal] [✕]
  Divider
  Total: [XXX kcal gold]   Spacer   [Clear all danger]
  Save row: Switch "Save as meal template"
    → if ON: TextField appears inline for name (autofocus)
       placeholder: "e.g. Morning Routine"

─── Actions ──────────────────────────────────────────
  [✕ cancel 72px]   [Log · XXX kcal → Breakfast  (expanded)]
```

### Step 6 — Rewrite `NutritionHistoryScreen`

**Weekly chart improvements:**

```
_WeeklyChart:
  Container(surface, radius 16, padding 16)
  "7-Day Overview"  [streak badge if any]

  SizedBox(height: 140):
    CustomPaint(_BarChartPainter v2):
      • Bars: RRect with gradient fill (bottom: color @ 60% → top: color @ 100%)
      • Goal met bar: AppColors.gold with glow shadow (color @ 20%, 4px blur)
      • Under-goal bar: AppColors.gold @ 30%
      • Goal line: gold @ 40%, 1px dashed (use Path with dashPattern)
      • Round tops only (radius on top corners only)
      • Bar width: 70% of slot, gap: 30%
      • Animate bars with AnimatedContainer or TweenAnimationBuilder on mount

  Day labels row: Mon/Tue/Wed... with today underlined in gold

  Macro row (below chart, if any log has macros):
    P  C  F  dot-row — 3 colored dots per day column showing relative macro split
    Very subtle, 4px dots, no labels
```

**Expandable history rows:**

```dart
class _HistoryRow extends StatefulWidget { ... }

// Collapsed view (always visible):
Row:
  [date string bold]    Spacer    [XXX kcal gold]  [✓ icon if met]
  [thin ring progress: 8px wide arc, 28×28, same color logic as main ring]
  [macro badges: P•Xg  C•Xg  F•Xg — one line, textSecondary 10px]
  [chevron ▼ right-aligned, animates on expand]

// Expanded view (AnimatedSize):
  Per slot that has entries:
    [slot.icon 14px]  [slot.label 11px textSecondary]
    ...entries:
      [food name]  Spacer  [kcal gold]  [✎ 36×36]  [✕ 36×36]
      [macros if any — textSecondary 10px]
    Divider between slots
  
  "No more editing note" — not shown; editing is allowed

  Expanded actions row:
    [Edit history entries available inline via ✎ buttons]
```

Edit in history: tap ✎ → `_EditEntrySheet` with presenter `editHistoryEntry(log.date, ...)`.  
Delete in history: tap ✕ → `presenter.removeHistoryEntry(log.date, ...)`.

**Empty history:** keep existing design, no change needed.

### Step 7 — Extend `FoodLibraryScreen`

```
FAB (gold, endFloat): opens _NewTemplateSheet

_NewTemplateSheet (80% height modal):
  "New Meal Template"          [X close]
  
  TextField name (autofocus, placeholder "e.g. Morning Routine")
  
  Default slot chips (same pill style as LogMealSheet):
    [☀ Breakfast] [🍽 Lunch] [🌆 Dinner] [☕ Snack]  [— None]
  
  "Items" section  [+ Add item]
    → opens a slim search-only variant of LogMealSheet
       that returns a List<FoodEntry> instead of logging
    Each added item: [name] · [kcal] [✕]
  
  Total kcal footer
  
  [Save Template] gold button, full width 52px
    Validates: name non-empty, ≥1 item → presenter.saveFoodTemplate(...)
    Empty name → show inline error "Add a name for this template"

Library content improvements:
  • Sort within each section by useCount desc
  • Template card: show "Used X times" badge in textSecondary 10px (if useCount > 0)
  • Long-press template → delete confirmation (swipe-to-delete is platform-inconsistent on Android)
```

---

## Data Visualization Summary

| Surface | Before | After |
|---|---|---|
| NutritionScreen summary | Linear progress bar (6px) | Calorie ring (CustomPaint, 200×200, sweep gradient, animated) |
| NutritionScreen macros | 3 row bars (small) | 3 column bars below ring (same, but better color contrast) |
| History chart bars | Flat gold/dim bars | Gradient fill bars, round top corners, subtle glow on goal-met bars |
| History chart goal line | Solid gold @ 40% | Dashed gold @ 40% (more readable at glance) |
| History macro dots | Not present | 3-dot (P/C/F) per-day column below chart |
| History row progress | Thin LinearProgressIndicator | Small arc ring (28×28) + macro text badges |

---

## RPG Impact

No changes to XP, streaks, or HP logic. History edits do **not** re-trigger RPG hooks (retroactive rewards would be gameable). Today edits re-run `_checkGoalMet`, `_checkProteinGoalMet`, `_checkOvershoot` normally.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Existing users' data all in `MealSlot.meal` | Legacy "Uncategorized" accordion shows only when non-empty |
| `suggestedSlot` changes mid-session | Sheet captures slot at open; pill row lets user override |
| Empty template name on save | Inline validation error — log is not blocked |
| History edit on very old entry | No date limit — `editHistoryEntry` works on any date in `_history` |
| `removeHistoryEntry` when only entry in slot | `removeEntry` returns empty list; `DailyNutritionLog` allows empty slots |
| Gram field empty / non-numeric | `double.tryParse` guard; keep previous value if null |
| Ring at 0 calories | Draw empty track only — no arc, center shows full goal |

---

## Acceptance Criteria

### Serving size UX
- [ ] Only ONE gram control visible per search result (no 4-chip row)
- [ ] Default is 100g; tapping the badge opens a numeric keyboard inline
- [ ] All serving-size options removed; custom gram field is the only mechanism

### Inline editing (today)
- [ ] Every `_EntryRow` has an edit (✎) button alongside delete (✕)
- [ ] Edit sheet pre-fills all fields from the existing entry
- [ ] Save calls `presenter.editFoodEntry(entryId, slot, updated)` and closes
- [ ] Calorie ring re-animates to new value after edit

### Editable history
- [ ] History rows are expandable — tap to see all entries by slot
- [ ] Each historical entry has edit (✎) and delete (✕) buttons
- [ ] Edit calls `presenter.editHistoryEntry`; delete calls `presenter.removeHistoryEntry`
- [ ] No RPG hook fires on history edits

### Data visualization
- [ ] Calorie ring replaces linear bar on NutritionScreen summary card
- [ ] Ring color transitions secondary → success → danger based on progress
- [ ] Weekly chart bars have gradient fill and round tops
- [ ] Goal-met bars show gold glow; under-goal bars are dimmed
- [ ] Per-day macro dot row below chart (only if macro data exists)
- [ ] History row collapsed view shows mini arc ring + macro text badges

### Slot & template UX
- [ ] Slot accordions render on NutritionScreen (Breakfast/Lunch/Dinner/Snack)
- [ ] My Meals panel shows templates sorted by useCount; one-tap logs to default slot
- [ ] LogMealSheet slot pill pre-selects by time of day; user can change
- [ ] "Save as template" reveals inline name field; uses user's name, not MM/DD
- [ ] Library FAB opens template creation sheet with name + slot + item add

### Architecture
- [ ] No calculations in `build()` — all via presenter getters/methods
- [ ] `suggestedSlot` is a pure computed getter
- [ ] History edits go through presenter — no direct storage calls in views
