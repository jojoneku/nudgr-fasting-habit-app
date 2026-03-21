# Feature Plan: Calorie Counting v2 — Alchemy Lab Enhanced

> Status: DRAFT — awaiting approval
> Created: 2026-03-20
> Supersedes: `002-calorie-counting-module.md` — implement this plan directly; skip 002 entirely.
> Depends on: Plan 001 (Nav Hub) — HubScreen must exist before wiring the Alchemy Lab card (step 19)

---

## Goal

Expand the Alchemy Lab (calorie module) from a basic food log into a full nutrition companion. Three pillars:

1. **Tracking Modes** — Simple (calories only), Macro (full breakdown), IF-Sync (eating-window-aware), TDEE (dynamic goal from body stats)
2. **Smart Logging** — Recent foods quick-add, custom food library, meal templates
3. **Deeper RPG integration** — Protein → STR, consistent logging → INT, over-eating penalty → HP

These additions make calorie tracking feel like a deliberate system inside the Solo Leveling world rather than a generic food diary.

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/food_entry.dart` | **Create** (from plan 002) | Model |
| `lib/models/daily_nutrition_log.dart` | **Create** (from plan 002) | Model |
| `lib/models/nutrition_goals.dart` | **Create** — extended with mode + TDEE fields | Model |
| `lib/models/food_template.dart` | **Create** — saved food / meal template | Model |
| `lib/models/tdee_profile.dart` | **Create** — body stats for dynamic goal | Model |
| `lib/presenters/nutrition_presenter.dart` | **Create** — extended API | Presenter |
| `lib/services/storage_service.dart` | Modify — add nutrition keys | Service |
| `lib/views/nutrition/nutrition_screen.dart` | **Create** — main screen with mode switcher | View |
| `lib/views/nutrition/add_food_sheet.dart` | **Create** — smart log sheet | View |
| `lib/views/nutrition/food_library_screen.dart` | **Create** — saved foods + meal templates | View |
| `lib/views/nutrition/nutrition_history_screen.dart` | **Create** — weekly trend + history | View |
| `lib/views/nutrition/tdee_setup_screen.dart` | **Create** — TDEE profile wizard | View |
| `lib/views/nutrition/nutrition_settings_sheet.dart` | **Create** — mode + goal settings | View |

---

## Interface Definitions

```dart
// ─── Enums ───────────────────────────────────────────────────────────────────

enum TrackingMode {
  simple,   // calories only — minimal UI, beginner-friendly
  macro,    // calories + protein/carbs/fat
  ifSync,   // IF-Sync: eating window from FastingPresenter gates logging
  tdee,     // dynamic goal calculated from TdeeProfile
}

enum ActivityLevel { sedentary, lightlyActive, moderatelyActive, veryActive }

// ─── Model: FoodEntry (from plan 002, unchanged) ─────────────────────────────
class FoodEntry {
  final String id;
  final String name;
  final int calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final DateTime loggedAt;
  // ...fromJson/toJson
}

// ─── Model: DailyNutritionLog (from plan 002, unchanged) ─────────────────────
class DailyNutritionLog {
  final String date;            // 'yyyy-MM-dd'
  final List<FoodEntry> entries;
  int get totalCalories;
  double get totalProtein;
  double get totalCarbs;
  double get totalFat;
  // ...fromJson/toJson/copyWith
}

// ─── Model: NutritionGoals (EXTENDED) ────────────────────────────────────────
class NutritionGoals {
  final TrackingMode mode;       // NEW — drives UI and validation
  final int dailyCalories;       // manual goal (simple/macro/ifSync modes)
  final double? proteinGrams;    // macro mode targets
  final double? carbsGrams;
  final double? fatGrams;
  final bool overshootPenaltyEnabled; // NEW — HP penalty when >120% of goal
  // ...fromJson/toJson/copyWith
}

// ─── Model: TdeeProfile (NEW) ────────────────────────────────────────────────
class TdeeProfile {
  final double weightKg;
  final double heightCm;
  final int ageYears;
  final String sex;              // 'male' | 'female'
  final ActivityLevel activityLevel;
  final String goal;             // 'cut' | 'maintain' | 'bulk'

  int get bmr;                   // Mifflin-St Jeor formula
  int get tdee;                  // bmr × activityLevel multiplier
  int get targetCalories;        // tdee adjusted for goal (cut: -300, bulk: +250)
  // ...fromJson/toJson/copyWith
}

// ─── Model: FoodTemplate (NEW) ───────────────────────────────────────────────
class FoodTemplate {
  final String id;
  final String name;
  final bool isMeal;              // false = single food; true = group (meal)
  final List<FoodEntry> entries;  // single entry for food, multiple for meal
  final int useCount;             // for sorting "most used" in quick-add
  // ...fromJson/toJson/copyWith
}

// ─── StorageService additions ─────────────────────────────────────────────────
static const String keyNutritionLogs    = 'nutritionLogs';
static const String keyNutritionGoals   = 'nutritionGoals';
static const String keyTdeeProfile      = 'tdeeProfile';
static const String keyFoodLibrary      = 'foodLibrary';       // NEW
static const String keyNutritionStreak  = 'nutritionStreak';   // NEW

Future<void>                 saveNutritionLog(DailyNutritionLog log);
Future<DailyNutritionLog>    loadTodayNutritionLog();
Future<List<DailyNutritionLog>> loadNutritionHistory();        // last 30 days
Future<void>                 saveNutritionGoals(NutritionGoals goals);
Future<NutritionGoals>       loadNutritionGoals();
Future<void>                 saveTdeeProfile(TdeeProfile profile);   // NEW
Future<TdeeProfile?>         loadTdeeProfile();                      // NEW
Future<void>                 saveFoodLibrary(List<FoodTemplate> lib); // NEW
Future<List<FoodTemplate>>   loadFoodLibrary();                      // NEW
Future<void>                 saveNutritionStreak(int days);           // NEW
Future<int>                  loadNutritionStreak();                   // NEW

// ─── NutritionPresenter public API (EXTENDED) ────────────────────────────────
class NutritionPresenter extends ChangeNotifier {
  NutritionPresenter({
    required StatsPresenter statsPresenter,
    required FastingPresenter fastingPresenter,  // NEW — for IF-Sync mode
    required StorageService storage,
  });

  // ── Core state ────────────────────────────────
  DailyNutritionLog  get todayLog;
  NutritionGoals     get goals;
  List<DailyNutritionLog> get history;         // last 30 days
  TdeeProfile?       get tdeeProfile;

  // ── Calorie getters ───────────────────────────
  int    get todayCalories;
  int    get effectiveGoal;     // dailyCalories OR tdee targetCalories by mode
  double get calorieProgress;   // 0.0–1.0+ (clamp to 1.2 max for display)
  bool   get isCalorieGoalMet;
  bool   get isOverGoal;        // >effectiveGoal (used for penalty check)
  String get summaryLabel;      // "1,450 / 2,000 kcal"

  // ── Macro getters (macro mode) ────────────────
  double get todayProtein;
  double get todayCarbs;
  double get todayFat;
  double get proteinProgress;   // 0.0–1.0
  double get carbsProgress;
  double get fatProgress;
  bool   get isProteinGoalMet;

  // ── IF-Sync getters ───────────────────────────
  bool   get isEatingWindowOpen;    // delegates to fastingPresenter
  String get windowStatusLabel;     // "Eating window open" / "Fasting — log disabled"

  // ── Streak ────────────────────────────────────
  int    get logStreak;             // consecutive days with ≥1 entry
  bool   get streakGoalUnlocked;    // streak reached 7-day milestone today

  // ── Food library ──────────────────────────────
  List<FoodTemplate> get recentFoods;   // last 10 unique foods logged (most recent first)
  List<FoodTemplate> get savedTemplates; // user's saved foods + meals

  // ── Actions ───────────────────────────────────
  Future<void> addFoodEntry(FoodEntry entry);
  Future<void> removeFoodEntry(String entryId);
  Future<void> updateGoals(NutritionGoals newGoals);
  Future<void> saveTdeeProfile(TdeeProfile profile);
  Future<void> saveFoodTemplate(FoodTemplate template);
  Future<void> deleteFoodTemplate(String templateId);
  Future<void> addMealTemplate(FoodTemplate meal);   // adds all entries at once
  Future<void> loadState();

  // ── Internal RPG hooks ────────────────────────
  void _onCalorieGoalMet();   // +30 XP → StatsPresenter
  void _onProteinGoalMet();   // +15 XP + STR nudge (macro mode only)
  void _onWeeklyStreakMet();  // +1 VIT point
  void _onOvershootPenalty(); // -5 HP (if enabled in goals)
  void _onLogStreakUpdate();  // awards INT XP at 7/14/30-day milestones
}
```

---

## Mode Descriptions

### Simple Mode (default)
Calories only. Minimal UI — just a number, a progress bar, and a food list. Ideal for beginners.
- Goal: fixed `dailyCalories`
- Add food: name + calories only
- RPG reward: +30 XP on goal met

### Macro Mode
Full nutritional breakdown. Progress bars for protein, carbs, fat alongside calories.
- Goal: `dailyCalories` + optional per-macro targets
- Add food: name + calories + protein/carbs/fat
- RPG rewards: +30 XP calorie goal, +15 XP protein goal → STR nudge

### IF-Sync Mode
Eating-window-aware logging. The FAB and entry form are disabled during the fasting window. A status banner shows window state.
- Goal: fixed `dailyCalories`
- Behavior: `addFoodEntry()` throws if `!isEatingWindowOpen`; view disables FAB accordingly
- RPG reward: +30 XP + extra +10 XP "Perfect Window Discipline" bonus when goal is met entirely within eating window

### TDEE Mode
Dynamic daily goal computed from body stats. User fills in `TdeeProfile` once via a setup wizard.
- Goal: `tdeeProfile.targetCalories` (overrides `dailyCalories`)
- Setup: weight, height, age, sex, activity level, goal (cut/maintain/bulk)
- Recalculates automatically when profile is updated
- RPG reward: +30 XP goal met; deficit streaks give bonus VIT XP

---

## Screen Layouts

### NutritionScreen
```
AppBar: "Alchemy Lab"  [mode chip]  [history icon]  [settings icon]

─── Mode Banner (IF-Sync only) ────────────────────────────────
  [🟢 Eating window open — log freely]
  [🔴 Fasting — logging paused until 12:00 PM]
────────────────────────────────────────────────────────────────

─── Daily Summary Card ─────────────────────────────────────────
  1,450 / 2,000 kcal          (Simple/IF-Sync/TDEE)
  [████████████░░░░] 72%

  Macro mode adds:
  P: 85/130g  ██████░  C: 160/200g  ████████░  F: 48/55g  ████████░
────────────────────────────────────────────────────────────────

─── Quick-Add Recent Foods ──────────────────────────────────────
  [Chicken breast]  [Oats 80g]  [Banana]  [+ Library]
  (horizontal scrollable chips)
────────────────────────────────────────────────────────────────

─── Today's Entries ─────────────────────────────────────────────
  [Chicken breast 150g]       320 kcal   protein: 48g   [delete]
  [Oats 80g]                  290 kcal                   [delete]
  ...
────────────────────────────────────────────────────────────────

              [FAB: + Log Food]   ← bottom 30%
```

### AddFoodSheet (bottom sheet)
```
─── Add Food ───────────────────────────────────────────────────
  [Search or enter food name...]          ← autocomplete from library

  Calories  [____]

  ▼ Add macros (optional, macro mode auto-expands)
    Protein [__]g   Carbs [__]g   Fat [__]g

  [Save to library  □]    ← checkbox to save as template

  [Cancel]                          [Log Food]
────────────────────────────────────────────────────────────────
```

### FoodLibraryScreen
```
AppBar: "Food Library"  [+ New Template]

─── Recent (last 10) ────────────────────────────────────────────
  [Chicken breast]  320 kcal   [+ Add]
  [Oats 80g]        290 kcal   [+ Add]
─────────────────────────────────────────────────────────────────

─── Saved Foods ──────────────────────────────────────────────────
  [Banana]           90 kcal   [+ Add]  [edit]  [delete]
─────────────────────────────────────────────────────────────────

─── Meal Templates ───────────────────────────────────────────────
  [Breakfast Stack]  610 kcal   3 items   [+ Add All]  [edit]  [delete]
─────────────────────────────────────────────────────────────────
```

### TdeeSetupScreen (wizard, 3 steps)
```
Step 1/3: Body Stats
  Weight [___] kg   Height [___] cm   Age [___]   Sex [M / F]

Step 2/3: Activity
  ○ Sedentary  ○ Lightly Active  ○ Moderately Active  ○ Very Active

Step 3/3: Goal
  ○ Cut (lose weight, –300 kcal)
  ○ Maintain
  ○ Bulk (gain muscle, +250 kcal)

  → Your target: 1,850 kcal / day
  [Confirm]
```

### NutritionHistoryScreen
```
AppBar: "Nutrition History"

─── Weekly Chart ────────────────────────────────────────────────
  Bar chart: Mon–Sun vs. goal line
────────────────────────────────────────────────────────────────

─── Past Days List ──────────────────────────────────────────────
  Mar 19  1,780 kcal  [Goal met ✓]   [tap to expand entries]
  Mar 18  1,420 kcal  [Under goal]
  Mar 17    980 kcal  [Under goal]
────────────────────────────────────────────────────────────────
```

---

## Implementation Order

1. [ ] Extend `NutritionGoals` — add `mode`, `overshootPenaltyEnabled` fields
2. [ ] Create `TdeeProfile` model — Mifflin-St Jeor math in pure getters
3. [ ] Create `FoodTemplate` model — `isMeal`, `entries`, `useCount`
4. [ ] Add new `StorageService` keys + methods (`tdeeProfile`, `foodLibrary`, `nutritionStreak`)
5. [ ] Implement base `NutritionPresenter` (plan 002 core: add/remove/goals/storage)
6. [ ] Add TDEE mode to presenter (`effectiveGoal` resolver)
7. [ ] Add IF-Sync mode to presenter (`isEatingWindowOpen` delegate + guard on `addFoodEntry`)
8. [ ] Add macro progress getters + protein RPG hook
9. [ ] Add food library logic (recent foods, save/delete templates, `addMealTemplate`)
10. [ ] Add log streak tracking + `_onLogStreakUpdate` INT rewards
11. [ ] Add overshoot HP penalty logic + `_onOvershootPenalty`
12. [ ] Build `NutritionScreen` with mode switcher chip + quick-add row
13. [ ] Build `AddFoodSheet` — search/autocomplete from library, macro section, save toggle
14. [ ] Build `FoodLibraryScreen` — recent + saved foods + meal templates
15. [ ] Build `TdeeSetupScreen` — 3-step wizard, shows calculated target on confirm
16. [ ] Build `NutritionHistoryScreen` — weekly bar chart + past day list
17. [ ] Build `NutritionSettingsSheet` — mode selector, goal editor, penalty toggle
18. [ ] Wire `FastingPresenter` ref into `NutritionPresenter` constructor (IF-Sync mode)
19. [ ] Wire navigation from HubScreen Alchemy Lab card
20. [ ] UX verification checklist

---

## RPG Impact

| Trigger | Reward | Stat | Notes |
|---|---|---|---|
| Calorie goal met (first time today) | +30 XP | — | All modes |
| Protein goal met (first time today) | +15 XP | STR nudge | Macro mode only |
| Perfect eating-window meal (IF-Sync) | +10 XP bonus | — | Goal met entirely in window |
| 7-day calorie goal streak | +1 VIT point | VIT | All modes |
| 7/14/30-day logging streak | +20/+40/+80 XP | INT | Logs ≥1 entry/day |
| Overshoot >120% of goal (if enabled) | –5 HP | — | Toggleable in settings |

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| IF-Sync: user hasn't set a fasting schedule yet | `isEatingWindowOpen` returns `true` by default if no active fast; show onboarding nudge |
| TDEE wizard incomplete (user backs out mid-wizard) | Don't save partial profile; TDEE mode stays unavailable until wizard is completed |
| Overshoot penalty surprising/demoralizing new users | Default `overshootPenaltyEnabled = false`; opt-in only |
| Food library grows unbounded | Cap saved templates at 50; warn user before cap is reached |
| `addMealTemplate` partial failure (some entries invalid) | Validate all entries before inserting any; atomic operation |
| Date boundary near midnight | Always key by `DateFormat('yyyy-MM-dd').format(DateTime.now())` at log time |
| TDEE math varies by formula | Document chosen formula (Mifflin-St Jeor); add a note to UI so user understands the estimate |

---

## Acceptance Criteria

- [ ] User can switch between Simple / Macro / IF-Sync / TDEE modes from settings
- [ ] Simple mode shows only calorie progress; Macro mode adds three macro bars
- [ ] IF-Sync mode: FAB is disabled during fasting window; banner shows window state
- [ ] TDEE mode: completing the wizard sets `effectiveGoal` to calculated target
- [ ] Recent foods chip row shows last 10 unique logged items; tapping one opens pre-filled sheet
- [ ] User can save a food or meal template to the library
- [ ] User can add all items from a meal template in one tap
- [ ] `_onCalorieGoalMet` fires exactly once per day across app restarts
- [ ] `_onProteinGoalMet` fires in macro mode when protein target is first hit
- [ ] 7-day streak awards +1 VIT via `StatsPresenter`
- [ ] Overshoot penalty is opt-in and defaults off
- [ ] Weekly bar chart renders in history screen with correct goal line
- [ ] No logic in any `build()` method — all via presenter getters
- [ ] Data persists across app restarts
- [ ] All touch targets ≥ 44×44px
- [ ] All animations 150–300ms, none > 400ms
