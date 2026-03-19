# Feature Implementation Plan: Calorie Counting Module (Alchemy Lab)

> Status: DRAFT — awaiting approval
> Created: 2026-03-20

---

## Feature Name
Calorie Counting Module — "Alchemy Lab"

## Goal
Add a calorie tracking module that lets the user log food entries, set a daily calorie goal, and view a daily summary. Integrates with the RPG stats system: hitting your calorie goal awards XP and boosts **VIT** (Vitality) — the stat tied to nutrition and body health. The module appears as a card on the Hub screen ("Alchemy Lab") and pushes to a full-screen experience.

## Spec Reference
No existing spec — create `docs/nutrition_spec.md` as part of this feature.

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/food_entry.dart` | **Create** | Model |
| `lib/models/daily_nutrition_log.dart` | **Create** | Model |
| `lib/models/nutrition_goals.dart` | **Create** | Model |
| `lib/presenters/nutrition_presenter.dart` | **Create** | Presenter |
| `lib/services/storage_service.dart` | Modify — add nutrition keys + methods | Service |
| `lib/views/nutrition/nutrition_screen.dart` | **Create** — main module screen | View |
| `lib/views/nutrition/add_food_sheet.dart` | **Create** — bottom sheet for logging food | View |
| `lib/views/nutrition/nutrition_history_screen.dart` | **Create** — past days log | View |
| `lib/views/hub_screen.dart` | Modify — unlock Alchemy Lab card | View |

*Note: Hub screen changes depend on the nav overhaul plan (`nav-hub-module-architecture.md`) being implemented first.*

---

## Interface Definitions

```dart
// === Model: FoodEntry ===
class FoodEntry {
  final String id;            // uuid
  final String name;          // e.g. "Chicken breast 150g"
  final int calories;         // kcal
  final double? protein;      // grams (optional)
  final double? carbs;        // grams (optional)
  final double? fat;          // grams (optional)
  final DateTime loggedAt;

  const FoodEntry({...});
  factory FoodEntry.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

// === Model: DailyNutritionLog ===
class DailyNutritionLog {
  final String date;              // 'yyyy-MM-dd' key
  final List<FoodEntry> entries;

  int get totalCalories;          // sum of entries
  double get totalProtein;
  double get totalCarbs;
  double get totalFat;

  const DailyNutritionLog({required this.date, required this.entries});
  factory DailyNutritionLog.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
  DailyNutritionLog copyWith({List<FoodEntry>? entries});
}

// === Model: NutritionGoals ===
class NutritionGoals {
  final int dailyCalories;      // default 2000
  final double? proteinGrams;   // optional macro targets
  final double? carbsGrams;
  final double? fatGrams;

  const NutritionGoals({required this.dailyCalories, ...});
  factory NutritionGoals.initial();
  factory NutritionGoals.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
  NutritionGoals copyWith({int? dailyCalories, ...});
}

// === StorageService additions ===
static const String keyNutritionLogs = 'nutritionLogs';
static const String keyNutritionGoals = 'nutritionGoals';

Future<void> saveNutritionLog(DailyNutritionLog log);
Future<DailyNutritionLog> loadTodayNutritionLog();
Future<List<DailyNutritionLog>> loadNutritionHistory();   // last 30 days
Future<void> saveNutritionGoals(NutritionGoals goals);
Future<NutritionGoals> loadNutritionGoals();

// === NutritionPresenter public API ===
class NutritionPresenter extends ChangeNotifier {
  // Constructor
  NutritionPresenter({required StatsPresenter statsPresenter});

  // Getters — all safe for build()
  DailyNutritionLog get todayLog;
  NutritionGoals get goals;
  List<DailyNutritionLog> get history;
  int get todayCalories;                      // shorthand: todayLog.totalCalories
  double get calorieProgress;                 // 0.0–1.0 (can exceed 1.0 for over-goal)
  bool get isGoalMet;                         // todayCalories >= goals.dailyCalories
  String get summaryLabel;                    // "1,450 / 2,000 kcal"

  // Actions
  Future<void> addFoodEntry(FoodEntry entry);
  Future<void> removeFoodEntry(String entryId);
  Future<void> updateGoals(NutritionGoals newGoals);
  Future<void> loadState();

  // RPG hook — called internally when goal is first met each day
  void _onGoalMet();   // awards XP + VIT point via StatsPresenter
}
```

---

## Implementation Order

1. [ ] Create `FoodEntry`, `DailyNutritionLog`, `NutritionGoals` models with `fromJson`/`toJson`
2. [ ] Add storage keys + methods to `StorageService`
3. [ ] Implement `NutritionPresenter` — all logic, no View dependency
4. [ ] Build `NutritionScreen` — daily summary header + scrollable food log list + FAB
5. [ ] Build `AddFoodSheet` — modal bottom sheet with name + calorie fields (macros optional/expandable)
6. [ ] Build `NutritionHistoryScreen` — list of past days with calorie totals
7. [ ] Wire into `HubScreen` — unlock Alchemy Lab card, pass `NutritionPresenter`
8. [ ] UX verification checklist

---

## Screen Layout: NutritionScreen

```
AppBar: "Alchemy Lab"  [history icon]  [settings/goal icon]

─── Daily Summary Card ────────────────────────────
  1,450 / 2,000 kcal
  [████████████░░░░] 72%
  Protein: 85g  Carbs: 160g  Fat: 48g  (if tracked)
───────────────────────────────────────────────────

─── Today's Entries ───────────────────────────────
  [Chicken breast 150g]         320 kcal  [delete]
  [Oats 80g]                    290 kcal  [delete]
  [Banana]                       90 kcal  [delete]
  ...
───────────────────────────────────────────────────

         [FAB: + Log Food]   ← bottom 30%
```

---

## Hub Card Summary
The `ModuleCard` subtitle getter on `NutritionPresenter`:
- Not started today → `"Tap to log meals"`
- In progress → `"1,450 / 2,000 kcal"`
- Goal met → `"Goal reached! ✓"`

---

## RPG Impact

- **XP awarded:** 30 XP the first time daily calorie goal is met each day
- **Stat affected:** +1 VIT point every 7 consecutive days goal is met (weekly streak)
- **Level/streak:** Uses its own consecutive-days streak inside `NutritionPresenter` (separate from fasting streak)
- **Notifications:** Optional — "You haven't logged today" reminder at a user-set time (phase 2)
- **HP mechanic (optional future):** Consistently going way over/under goal could affect HP

---

## Risks

| Risk | Mitigation |
|---|---|
| `StorageService` grows large — each module adds methods | Acceptable for now; a module-scoped storage abstraction can be added later if needed |
| Calorie data only meaningful if user logs consistently — low engagement risk | Keep entry form minimal (name + calories only; macros optional) |
| `NutritionPresenter` needs `StatsPresenter` ref for XP | Same pattern as `FastingPresenter` — pass via constructor |
| Date boundary: entries logged near midnight could land on wrong day | Always key by `DateFormat('yyyy-MM-dd').format(DateTime.now())` at log time |
| No barcode scanner / food database (scope) | Manual entry only for v1; food database is a future enhancement |

---

## UX Verification

- [ ] Primary CTA (+ Log Food FAB) in bottom 30% of screen
- [ ] All touch targets ≥ 44×44px (entry rows, FAB, delete icons)
- [ ] Micro-animations 150–300ms (progress bar fill on add, entry slide-in)
- [ ] No animation > 400ms
- [ ] Calorie summary glanceable in < 1 second from screen open
- [ ] Empty state is clear and actionable ("No entries yet — start logging")

---

## Acceptance Criteria

- [ ] User can add a food entry with name + calories (macros optional)
- [ ] User can delete a food entry
- [ ] Daily calorie progress bar updates immediately on add/delete
- [ ] User can set/change daily calorie goal
- [ ] Goal-met state is clearly visible (color change, icon, label)
- [ ] First time goal is met each day: +30 XP awarded via `StatsPresenter`
- [ ] Hub card subtitle shows live calorie progress
- [ ] Past days viewable in history screen
- [ ] No logic in any `build()` method — all via presenter getters
- [ ] Data persists across app restarts
