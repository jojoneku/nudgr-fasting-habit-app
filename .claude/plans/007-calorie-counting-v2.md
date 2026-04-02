# Feature Plan: Calorie Counting v2 — Alchemy Lab Enhanced

> Status: DRAFT — awaiting approval
> Created: 2026-03-20
> Updated: 2026-03-21 — added local food DB, meal-level logging, AI estimation, friction overhaul
> Supersedes: `002-calorie-counting-module.md` — implement this plan directly; skip 002 entirely.
> Depends on: Plan 001 (Nav Hub) — HubScreen must exist before wiring the Alchemy Lab card (step 22)

---

## Goal

Expand the Alchemy Lab (calorie module) from a basic food log into a full nutrition companion. Four pillars:

1. **Low-friction logging** — local food DB (grams → auto-calories), meal-level grouping, AI free-text fallback, recent foods quick-add
2. **Tracking Modes** — Simple (AI-assisted), Macro (full breakdown), IF-Sync (eating-window-aware), TDEE (dynamic goal from body stats)
3. **Smart Logging** — meal templates, food library, one-tap repeat meals
4. **Deeper RPG integration** — Protein → STR, consistent logging → INT, over-eating penalty → HP

The north star: **logging a meal should take < 30 seconds**.

---

## Friction-Reduction Strategy

### Problem
Users eating rice + fish + veggies for lunch had to:
- Log 3 separate entries
- Know the calorie count of each item
- Repeat this every day

### Solution Stack

| Layer | Mechanism | When used |
|---|---|---|
| Food DB | Bundled SQLite (Open Food Facts subset, ~8MB) | User searches a known food, enters grams |
| Meal grouping | Log multiple items under one meal (Breakfast/Lunch/Dinner/Snack) | Any multi-item meal |
| Meal templates | Save a meal → one-tap re-log next time | Repeat meals |
| AI estimation | On-device small model (free-text → calorie estimate) | Unknown food, quick rough log |
| Recent foods | Last 10 unique items as quick-add chips | Common single items |

### Simple Mode revised flow
1. User taps `+ Log Meal` → picks meal slot (Lunch)
2. Types `"rice, fish, mixed veggies, medium plate"` into AI field
3. System responds: *"~420 kcal estimated — rice 180, fish 160, veggies 80"*
4. User confirms or adjusts individual items
5. Done — one interaction, one tap to confirm

### Accurate flow (food DB)
1. User taps `+ Add Item` inside a meal
2. Searches "white rice" → selects "White rice, cooked"
3. Types `150g` → calories auto-fill (195 kcal)
4. Repeats for fish, veggies → meal total shown
5. `[Save as template]` → next time, one tap logs the whole meal

---

## Local Food Database

- **Source:** Open Food Facts (filtered subset) or USDA FoodData Central
- **Format:** SQLite bundled as a Flutter asset, loaded via `sqflite`
- **Size target:** ≤ 10MB compressed
- **Schema:** `food_db` table — `id`, `name`, `calories_per_100g`, `protein_per_100g`, `carbs_per_100g`, `fat_per_100g`, `category`
- **Search:** FTS5 full-text search on `name` — fast prefix matching
- **Fallback:** If item not found → offer AI estimate or manual entry

---

## AI Estimation (On-Device)

- **Model:** Small on-device LLM via `flutter_gemma` (Gemma 2B) or `llama_cpp_dart`
- **Input:** Free-text meal description — `"medium bowl of rice, grilled salmon fillet, side of broccoli"`
- **Output:** Structured JSON — `{ total: 520, items: [{ name, calories }, ...] }`
- **Accuracy:** ±20–30% — communicated to user with a `~` prefix and confidence indicator
- **UX framing:** Fits Solo Leveling aesthetic — *"System analyzing meal composition..."*
- **Offline:** Fully offline after model download (~300MB, one-time on first use)
- **Fallback:** If model not downloaded → show manual entry only, prompt to download

---

## Meal-Level Logging

### MealSlot enum
```dart
enum MealSlot { breakfast, lunch, dinner, snack }
```

### How it changes DailyNutritionLog
```dart
class DailyNutritionLog {
  final String date;
  final Map<MealSlot, List<FoodEntry>> meals;  // CHANGED: keyed by meal slot

  int get totalCalories;
  int caloriesForSlot(MealSlot slot);
  List<FoodEntry> entriesForSlot(MealSlot slot);
  // ...fromJson/toJson/copyWith
}
```

### NutritionScreen layout change
Each meal slot is a collapsible section with its own subtotal, rather than a flat list.

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/food_entry.dart` | **Create** | Model |
| `lib/models/daily_nutrition_log.dart` | **Create** — meal-slot keyed | Model |
| `lib/models/nutrition_goals.dart` | **Create** — mode + TDEE fields | Model |
| `lib/models/food_template.dart` | **Create** — saved food / meal template | Model |
| `lib/models/tdee_profile.dart` | **Create** — body stats for dynamic goal | Model |
| `lib/models/food_db_entry.dart` | **Create** — local DB food record | Model |
| `lib/presenters/nutrition_presenter.dart` | **Create** — extended API | Presenter |
| `lib/services/storage_service.dart` | Modify — add nutrition keys | Service |
| `lib/services/food_db_service.dart` | **Create** — SQLite food DB search | Service |
| `lib/services/ai_estimation_service.dart` | **Create** — on-device LLM wrapper | Service |
| `lib/views/nutrition/nutrition_screen.dart` | **Create** — meal-slot sections, mode switcher | View |
| `lib/views/nutrition/log_meal_sheet.dart` | **Create** — meal slot + items + AI field | View |
| `lib/views/nutrition/add_food_sheet.dart` | **Create** — food DB search + grams input | View |
| `lib/views/nutrition/food_library_screen.dart` | **Create** — saved foods + meal templates | View |
| `lib/views/nutrition/nutrition_history_screen.dart` | **Create** — weekly trend + history | View |
| `lib/views/nutrition/tdee_setup_screen.dart` | **Create** — TDEE profile wizard | View |
| `lib/views/nutrition/nutrition_settings_sheet.dart` | **Create** — mode + goal settings | View |
| `assets/food_db.sqlite` | **Add** — bundled food database | Asset |

---

## Interface Definitions

```dart
// ─── Enums ───────────────────────────────────────────────────────────────────

enum TrackingMode { simple, macro, ifSync, tdee }
enum ActivityLevel { sedentary, lightlyActive, moderatelyActive, veryActive }
enum MealSlot { breakfast, lunch, dinner, snack }

// ─── Model: FoodEntry ────────────────────────────────────────────────────────
class FoodEntry {
  final String id;
  final String name;
  final int calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? grams;          // NEW — stored for reference
  final bool aiEstimated;       // NEW — flag for ~estimated entries
  final DateTime loggedAt;
  // ...fromJson/toJson
}

// ─── Model: DailyNutritionLog ─────────────────────────────────────────────────
class DailyNutritionLog {
  final String date;
  final Map<MealSlot, List<FoodEntry>> meals;   // CHANGED

  int get totalCalories;
  double get totalProtein;
  double get totalCarbs;
  double get totalFat;
  int caloriesForSlot(MealSlot slot);
  List<FoodEntry> entriesForSlot(MealSlot slot);
  // ...fromJson/toJson/copyWith
}

// ─── Model: NutritionGoals ────────────────────────────────────────────────────
class NutritionGoals {
  final TrackingMode mode;
  final int dailyCalories;
  final double? proteinGrams;
  final double? carbsGrams;
  final double? fatGrams;
  final bool overshootPenaltyEnabled;   // default false
  // ...fromJson/toJson/copyWith
}

// ─── Model: TdeeProfile ───────────────────────────────────────────────────────
class TdeeProfile {
  final double weightKg;
  final double heightCm;
  final int ageYears;
  final String sex;               // 'male' | 'female'
  final ActivityLevel activityLevel;
  final String goal;              // 'cut' | 'maintain' | 'bulk'

  int get bmr;                    // Mifflin-St Jeor
  int get tdee;                   // bmr × activity multiplier
  int get targetCalories;         // tdee adjusted (cut: -300, bulk: +250)
  // ...fromJson/toJson/copyWith
}

// ─── Model: FoodTemplate ─────────────────────────────────────────────────────
class FoodTemplate {
  final String id;
  final String name;
  final bool isMeal;
  final MealSlot? defaultSlot;    // NEW — suggested slot when quick-adding
  final List<FoodEntry> entries;
  final int useCount;
  // ...fromJson/toJson/copyWith
}

// ─── Model: FoodDbEntry ──────────────────────────────────────────────────────
class FoodDbEntry {
  final String id;
  final String name;
  final double caloriesPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final String? category;

  FoodEntry toFoodEntry(double grams);   // converts by weight
}

// ─── FoodDbService ────────────────────────────────────────────────────────────
class FoodDbService {
  Future<void> init();                                       // open SQLite asset
  Future<List<FoodDbEntry>> search(String query);           // FTS5 prefix search
  Future<FoodDbEntry?> getById(String id);
}

// ─── AiEstimationService ─────────────────────────────────────────────────────
class AiEstimationService {
  bool get isModelAvailable;
  Future<void> downloadModel();                             // one-time ~300MB
  Future<AiMealEstimate> estimate(String description);      // free-text → estimate
}

class AiMealEstimate {
  final int totalCalories;
  final List<AiItemEstimate> items;
  final double confidence;          // 0.0–1.0
}

class AiItemEstimate {
  final String name;
  final int calories;
  final double? protein;
  final double? carbs;
  final double? fat;
}

// ─── StorageService additions ─────────────────────────────────────────────────
static const String keyNutritionLogs    = 'nutritionLogs';
static const String keyNutritionGoals   = 'nutritionGoals';
static const String keyTdeeProfile      = 'tdeeProfile';
static const String keyFoodLibrary      = 'foodLibrary';
static const String keyNutritionStreak  = 'nutritionStreak';

Future<void>                    saveNutritionLog(DailyNutritionLog log);
Future<DailyNutritionLog>       loadTodayNutritionLog();
Future<List<DailyNutritionLog>> loadNutritionHistory();
Future<void>                    saveNutritionGoals(NutritionGoals goals);
Future<NutritionGoals>          loadNutritionGoals();
Future<void>                    saveTdeeProfile(TdeeProfile profile);
Future<TdeeProfile?>            loadTdeeProfile();
Future<void>                    saveFoodLibrary(List<FoodTemplate> lib);
Future<List<FoodTemplate>>      loadFoodLibrary();
Future<void>                    saveNutritionStreak(int days);
Future<int>                     loadNutritionStreak();

// ─── NutritionPresenter public API ───────────────────────────────────────────
class NutritionPresenter extends ChangeNotifier {
  NutritionPresenter({
    required StatsPresenter statsPresenter,
    required FastingPresenter fastingPresenter,
    required StorageService storage,
    required FoodDbService foodDb,
    required AiEstimationService aiEstimation,
  });

  // ── Core state ────────────────────────────────
  DailyNutritionLog       get todayLog;
  NutritionGoals          get goals;
  List<DailyNutritionLog> get history;
  TdeeProfile?            get tdeeProfile;

  // ── Calorie getters ───────────────────────────
  int    get todayCalories;
  int    get effectiveGoal;
  double get calorieProgress;
  bool   get isCalorieGoalMet;
  bool   get isOverGoal;
  String get summaryLabel;
  int    caloriesForSlot(MealSlot slot);

  // ── Macro getters ─────────────────────────────
  double get todayProtein;
  double get todayCarbs;
  double get todayFat;
  double get proteinProgress;
  double get carbsProgress;
  double get fatProgress;
  bool   get isProteinGoalMet;

  // ── IF-Sync ───────────────────────────────────
  bool   get isEatingWindowOpen;
  String get windowStatusLabel;

  // ── Streak ────────────────────────────────────
  int    get logStreak;
  bool   get streakGoalUnlocked;

  // ── Food library ──────────────────────────────
  List<FoodTemplate> get recentFoods;
  List<FoodTemplate> get savedTemplates;

  // ── AI ────────────────────────────────────────
  bool   get isAiAvailable;
  bool   get isAiEstimating;
  AiMealEstimate? get lastEstimate;

  // ── Actions ───────────────────────────────────
  Future<void> addFoodEntry(FoodEntry entry, MealSlot slot);        // CHANGED
  Future<void> removeFoodEntry(String entryId, MealSlot slot);      // CHANGED
  Future<void> addMealFromTemplate(FoodTemplate meal, MealSlot slot);
  Future<void> updateGoals(NutritionGoals newGoals);
  Future<void> saveTdeeProfile(TdeeProfile profile);
  Future<void> saveFoodTemplate(FoodTemplate template);
  Future<void> deleteFoodTemplate(String templateId);
  Future<void> estimateMeal(String description);                     // NEW
  Future<void> confirmAiEstimate(List<AiItemEstimate> items, MealSlot slot); // NEW
  Future<void> loadState();

  // ── Internal RPG hooks ────────────────────────
  void _onCalorieGoalMet();
  void _onProteinGoalMet();
  void _onWeeklyStreakMet();
  void _onOvershootPenalty();
  void _onLogStreakUpdate();
}
```

---

## Mode Descriptions

### Simple Mode (default)
Calories only. Two input paths:
- **AI path:** Free-text description → on-device estimate → user confirms/tweaks
- **Search path:** Type food name → food DB results → enter grams → auto-fill

RPG reward: +30 XP on goal met

### Macro Mode
Full nutritional breakdown. Progress bars for protein, carbs, fat alongside calories.
Both AI and search paths available; macros auto-filled from DB or AI estimate.

RPG rewards: +30 XP calorie goal, +15 XP protein goal → STR nudge

### IF-Sync Mode
Eating-window-aware. FAB disabled during fasting window. Status banner shows window state.
`addFoodEntry()` throws if `!isEatingWindowOpen`.

RPG reward: +30 XP + +10 XP "Perfect Window Discipline" bonus

### TDEE Mode
Dynamic goal from `TdeeProfile`. User completes 3-step wizard once.
`effectiveGoal` = `tdeeProfile.targetCalories`.

RPG reward: +30 XP goal met; deficit streaks give bonus VIT XP

---

## Screen Layouts

### NutritionScreen
```
AppBar: "Alchemy Lab"  [mode chip]  [history icon]  [settings icon]

─── Mode Banner (IF-Sync only) ────────────────────────────────────
  [🟢 Eating window open — log freely]
  [🔴 Fasting — logging paused until 12:00 PM]
────────────────────────────────────────────────────────────────────

─── Daily Summary Card ─────────────────────────────────────────────
  1,450 / 2,000 kcal
  [████████████░░░░] 72%

  Macro mode adds:
  P: 85/130g  ██████░  C: 160/200g  ████████░  F: 48/55g  ████████░
────────────────────────────────────────────────────────────────────

─── Quick-Add Recent Foods ──────────────────────────────────────────
  [Chicken breast]  [Oats 80g]  [Banana]  [+ Library]
────────────────────────────────────────────────────────────────────

─── Breakfast  ·  420 kcal ─────────────────────── [+ Add] [v] ────
  [Oats 80g]              290 kcal  [delete]
  [Banana]                 90 kcal  [delete]
  [Coffee, black]          40 kcal  [delete]

─── Lunch  ·  610 kcal ─────────────────────────── [+ Add] [v] ────
  [~Rice, fish, veggies]  410 kcal  [~AI] [delete]
  [Orange juice 250ml]    110 kcal  [delete]
  [Bread roll]             90 kcal  [delete]

─── Dinner  ·  ── ──────────────────────────────── [+ Add] [v] ────
  (empty — tap + Add)

─── Snacks  ·  ── ──────────────────────────────── [+ Add] [v] ────
  (empty)
────────────────────────────────────────────────────────────────────

              [FAB: + Log Meal]   ← bottom 30%
```

### LogMealSheet (replaces AddFoodSheet as primary entry point)
```
─── Log Meal ───────────────────────────────────────────────────────
  Meal: [Breakfast ▾]  [Lunch ▾]  [Dinner ▾]  [Snack ▾]

  ── AI Quick-Log ─────────────────────────────────────────────────
  [Describe your meal...                              ] [Estimate]
  "rice, grilled fish, mixed veggies, medium plate"
  → System analyzing meal composition...
  → ~420 kcal  (rice 180 · fish 160 · veggies 80)   [Confirm] [Edit]

  ── Or search & add items ────────────────────────────────────────
  [Search food...                  ]
    White rice, cooked    [150g ▸ 195 kcal]  [+ Add]
    Brown rice, cooked    [150g ▸ 216 kcal]  [+ Add]

  ── Items added ──────────────────────────────────────────────────
  White rice, cooked  150g   195 kcal  [×]
  Salmon, grilled     120g   220 kcal  [×]
  ────────────────────────────────────────────────────────────
  Total: 415 kcal

  [Save as template  □]
  [Cancel]                                         [Log Meal]
────────────────────────────────────────────────────────────────────
```

### FoodLibraryScreen
```
AppBar: "Food Library"  [+ New Template]

─── Recent (last 10) ─────────────────────────────────────────────
  [Chicken breast]  320 kcal   [+ Add]
  [Oats 80g]        290 kcal   [+ Add]

─── Saved Foods ──────────────────────────────────────────────────
  [Banana]           90 kcal   [+ Add]  [edit]  [delete]

─── Meal Templates ───────────────────────────────────────────────
  [Lunch Usual]      610 kcal   3 items   [+ Add All]  [edit]  [delete]
  [Breakfast Stack]  420 kcal   3 items   [+ Add All]  [edit]  [delete]
```

### TdeeSetupScreen (3-step wizard)
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

─── Past Days ───────────────────────────────────────────────────
  Mar 19  1,780 kcal  [Goal met ✓]   [tap to expand]
  Mar 18  1,420 kcal  [Under goal]
  Mar 17    980 kcal  [Under goal]
────────────────────────────────────────────────────────────────
```

---

## Implementation Order

1. [ ] Create `FoodEntry`, `FoodDbEntry`, `FoodTemplate`, `TdeeProfile` models
2. [ ] Create `DailyNutritionLog` with `Map<MealSlot, List<FoodEntry>> meals`
3. [ ] Create `NutritionGoals` with mode + overshoot flag
4. [ ] Create `AiMealEstimate` / `AiItemEstimate` models
5. [ ] Implement `FoodDbService` — init SQLite asset, FTS5 search, `toFoodEntry(grams)`
6. [ ] Implement `AiEstimationService` — model availability check, download, estimate → JSON parse
7. [ ] Add new `StorageService` keys + methods
8. [ ] Implement base `NutritionPresenter` — add/remove/goals/storage with meal slots
9. [ ] Add TDEE mode (`effectiveGoal` resolver)
10. [ ] Add IF-Sync mode (eating window guard on `addFoodEntry`)
11. [ ] Add macro progress getters + protein RPG hook
12. [ ] Add AI estimation flow (`estimateMeal` → `confirmAiEstimate`)
13. [ ] Add food library logic (recent foods, save/delete templates, `addMealTemplate`)
14. [ ] Add log streak tracking + `_onLogStreakUpdate` INT rewards
15. [ ] Add overshoot HP penalty logic
16. [ ] Build `NutritionScreen` with collapsible meal-slot sections
17. [ ] Build `LogMealSheet` — AI field + food DB search + items list + meal slot picker
18. [ ] Build `FoodLibraryScreen`
19. [ ] Build `TdeeSetupScreen`
20. [ ] Build `NutritionHistoryScreen` — weekly bar chart + past day list
21. [ ] Build `NutritionSettingsSheet`
22. [ ] Wire navigation from HubScreen Alchemy Lab card
23. [ ] UX verification checklist

---

## RPG Impact

| Trigger | Reward | Stat | Notes |
|---|---|---|---|
| Calorie goal met (first time today) | +30 XP | — | All modes |
| Protein goal met (first time today) | +15 XP | STR nudge | Macro mode only |
| Perfect eating-window meal (IF-Sync) | +10 XP bonus | — | Goal met entirely in window |
| 7-day calorie goal streak | +1 VIT point | VIT | All modes |
| 7/14/30-day logging streak | +20/+40/+80 XP | INT | Logs ≥1 entry/day |
| Overshoot >120% of goal (if enabled) | –5 HP | — | Toggleable, default off |

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| AI model not downloaded | Default to search+manual; prompt one-time download on first visit |
| AI estimate is wildly off | Show `~` prefix + confidence bar; user can edit any item before confirming |
| Food DB item not found | Fall back to AI estimate or manual entry; suggest saving as custom food |
| `DailyNutritionLog` migration from flat list → meal slots | Write migration in `StorageService.loadTodayNutritionLog()` — assign legacy entries to `MealSlot.snack` |
| IF-Sync: no active fasting schedule set | `isEatingWindowOpen` returns `true` by default; show onboarding nudge |
| TDEE wizard backed out mid-flow | Don't save partial profile; TDEE mode unavailable until complete |
| Overshoot penalty demoralizing new users | Default `overshootPenaltyEnabled = false`; opt-in only |
| Food library grows unbounded | Cap saved templates at 50; warn before cap |
| `addMealTemplate` partial failure | Validate all entries before inserting any; atomic operation |
| Date boundary near midnight | Always key by `DateFormat('yyyy-MM-dd').format(DateTime.now())` |
| AI model size (~300MB) concerns | One-time download, stored locally; clearly communicate size before download |

---

## Acceptance Criteria

- [ ] User can describe a meal in free text → AI estimates calories per item → user confirms in one tap
- [ ] User can search a food by name → enter grams → calories auto-fill from local DB
- [ ] Entries are grouped by meal slot (Breakfast / Lunch / Dinner / Snack) with per-slot subtotals
- [ ] User can save a logged meal as a template and re-log it in one tap next time
- [ ] User can switch between Simple / Macro / IF-Sync / TDEE modes from settings
- [ ] IF-Sync mode: FAB disabled during fasting window; banner shows window state
- [ ] TDEE mode: completing wizard sets `effectiveGoal` to calculated target
- [ ] AI-estimated entries are marked with `~` indicator
- [ ] `_onCalorieGoalMet` fires exactly once per day across app restarts
- [ ] 7-day streak awards +1 VIT via `StatsPresenter`
- [ ] Overshoot penalty is opt-in and defaults off
- [ ] Weekly bar chart renders correctly in history screen
- [ ] No logic in any `build()` method — all via presenter getters
- [ ] Data persists across app restarts (including meal-slot structure)
- [ ] All touch targets ≥ 44×44px
- [ ] All animations 150–300ms, none > 400ms
- [ ] Logging a known meal takes < 30 seconds (template re-log)
- [ ] Logging a new meal via AI takes < 30 seconds end-to-end
