# Plan 027 — Notification Expansion

## Status
PLANNED

## Goal
Expand `NotificationService` to cover features that currently have zero notification
support: RPG level-up/rank promotion, daily weight log reminder, nutrition calorie-goal
alert, and finance bill/budget reminders.

---

## Current State

### What's covered (complete)
| Feature | Notifications |
|---|---|
| Fasting timer | Persistent timer + milestone alarms (every 2h) + goal-reached |
| Eating window | Persistent timer + hourly countdowns + window-over |
| Quests / Habits | Daily/weekly/biweekly/monthly recurrence + streak-at-risk (9 PM) |
| OTA update | Download-complete one-shot |

### What's missing (this plan)
| Feature | Gap |
|---|---|
| **RPG / Character stats** | `StatsPresenter.addXp()` sets `showLevelUpDialog=true` but fires no push notification |
| **Nutrition – weight** | No reminder to log daily weight (`NutritionPresenter.logWeight()` exists) |
| **Nutrition – calories** | No "daily calorie goal met" alert |
| **Finance – bills** | No unpaid-bills reminder at month start |
| **Finance – budget** | No budget-over-limit warning when spending crosses 80% of limit |

---

## New Notification Channels

Add two channels to `NotificationService` (channel suffix `_v1` to allow future cleanup):

| Constant | Channel ID | Name | Sound | Vibration | Purpose |
|---|---|---|---|---|---|
| `channelIdAchievements` | `achievements_channel_v1` | Character Achievements | Yes | Yes | Level-up, rank promotion |
| `channelIdFinance` | `finance_channel_v1` | Finance Alerts | Yes | No | Bill reminders, budget warnings |

Nutrition alerts reuse `channelIdMilestones` (Fasting & Eating Alerts) — it is already
enabled with sound and vibration and semantically fits "you hit a goal."

---

## Notification ID Allocation

Extend the existing ID map:

| ID / Range | Owner | Trigger |
|---|---|---|
| **500** | StatsPresenter | Level-up |
| **501** | StatsPresenter | Rank promotion (E→D→C→B→A→S) |
| **510** | NutritionPresenter | Daily weight log reminder |
| **511** | NutritionPresenter | Daily calorie goal met |
| **600** | BillsReceivablesPresenter | Monthly unpaid-bills reminder |
| **601–640** | BudgetPresenter | Per-budget over-limit warning (max 40 budgets) |

---

## Chapters

### Chapter 1 — New Channels + ID Constants (NotificationService)

**File:** `lib/services/notification_service.dart`

1. Add `channelIdAchievements`, `channelIdFinance` constants.
2. Register both channels in `init()` alongside existing ones.
3. Add constants: `notifIdLevelUp = 500`, `notifIdRankPromotion = 501`,
   `notifIdWeightReminder = 510`, `notifIdCalorieGoal = 511`,
   `notifIdBillsReminder = 600`.
4. Helper `_budgetWarningId(String budgetId)` → stable int in 601–640 range via
   `budgetId.hashCode % 40 + 601`.

**New public methods:**

```dart
// RPG
Future<void> showLevelUpNotification(int level, String rank);
Future<void> showRankPromotionNotification(String fromRank, String toRank);
Future<void> cancelAchievementNotifications();

// Nutrition
Future<void> scheduleWeightReminder(TimeOfDay time);   // daily recurring
Future<void> cancelWeightReminder();
Future<void> showCalorieGoalNotification(int calories, int goal);

// Finance
Future<void> scheduleBillsReminder(int dayOfMonth);   // monthly recurring
Future<void> cancelBillsReminder();
Future<void> showBudgetWarning(String budgetId, String budgetName,
    double spent, double limit);
Future<void> cancelBudgetWarning(String budgetId);
```

---

### Chapter 2 — RPG Level-Up + Rank Promotion (StatsPresenter)

**File:** `lib/presenters/stats_presenter.dart`

Inject `NotificationService` as optional constructor param (default to singleton).

In `addXp()`, after the level-up while-loop:
```dart
if (showLevelUpDialog) {
  final newRank = rank;  // computed getter
  if (newRank != _previousRank) {
    await _notifications.showRankPromotionNotification(_previousRank, newRank);
  } else {
    await _notifications.showLevelUpNotification(newLevel, newRank);
  }
  _previousRank = newRank;
}
```

Track `_previousRank` as a field initialised in `_init()` from `stats.level`-derived rank.

**Messages:**
- Level-up: `"⚔️ LEVEL UP — Lv. {N} [{Rank}]"` / body `"Your power grows, Shadow."`
- Rank promotion: `"★ RANK PROMOTION — {old} → {new}"` / body `"You have ascended."`

---

### Chapter 3 — Daily Weight Reminder (NutritionPresenter + Settings)

**Files:** `lib/presenters/nutrition_presenter.dart`,
`lib/models/nutrition_goals.dart` (or `StorageService`)

**Design:** The reminder fires daily at a user-configured time. When the user logs weight
that day, `cancelWeightReminder()` then immediately re-schedules it for tomorrow — so it
only appears once per day if not yet logged.

**NutritionGoals model change:**
Add `TimeOfDay? weightReminderTime` (nullable — null means disabled). Serialise as
`"HH:mm"` string.

**NutritionPresenter changes:**
- `setWeightReminder(TimeOfDay? time)` — saves to goals, calls
  `_notifications.scheduleWeightReminder(time)` or `cancelWeightReminder()`.
- After `logWeight()` succeeds, if today's reminder is pending: cancel + reschedule for
  tomorrow (the `scheduleWeightReminder` implementation uses
  `DateTimeComponents.time` so it recurs automatically — just calling
  `cancelWeightReminder()` after logging is enough; re-scheduling happens at next app
  open or on the recurring alarm).

**Default time:** None (opt-in). Expose a toggle + time-picker in
`NutritionSettingsSheet` (existing bottom sheet, Chapter 5).

---

### Chapter 4 — Calorie Goal Notification (NutritionPresenter)

**File:** `lib/presenters/nutrition_presenter.dart`

After a food entry is added (in `addFoodEntry` / `_updateDailyTotals` path), check if
the running calorie total just crossed the daily goal for the first time today:

```dart
if (_todayCalories >= _goals.dailyCalories &&
    !_caloriGoalNotifiedToday) {
  _calorieGoalNotifiedToday = true;
  await _notifications.showCalorieGoalNotification(
      _todayCalories, _goals.dailyCalories);
}
```

`_calorieGoalNotifiedToday` is a transient bool reset each time `_loadTodayLog()` is
called (new day). No persistence needed.

**Message:** `"Daily goal reached 🎯"` / body `"{calories} / {goal} kcal logged today."`

---

### Chapter 5 — Settings UI (NutritionSettingsSheet)

**File:** `lib/views/nutrition/nutrition_settings_sheet.dart`

Add a **"Weight reminder"** row after the macro-goal section:
- Toggle (enabled/disabled)
- When enabled: shows a `ListTile` with a time-picker tap target (uses `showTimePicker`)
- Label: `"Daily weight log reminder"`, subtitle: formatted time or `"Tap to set time"`

No new screen needed — fits within the existing sheet's scrollable content.

---

### Chapter 6 — Finance Bill Reminder (BillsReceivablesPresenter)

**File:** `lib/presenters/bills_receivables_presenter.dart`

Bills in this app are keyed by month string (`"YYYY-MM"`), not a specific due date.
The notification should fire on a configurable day each month (default: day 1).

- Add `scheduleBillsReminder()` call in presenter `load()` if user has any bills and
  the setting is enabled.
- Store `int billReminderDay` in `StorageService` (default `1`).
- Message: `"Bills due this month"` / body: `"{N} unpaid bills totalling {amount}."`

Expose a toggle in the **Treasury Settings** section (or a simple tile in the treasury
drawer — check with designer first).

---

### Chapter 7 — Finance Budget Warning (BudgetPresenter)

**File:** `lib/presenters/budget_presenter.dart`

In `_syncFromLedger()` (called on every ledger change), for each active budget:
```dart
if (spentPercent >= 0.80 && spentPercent < 1.0 &&
    !_warnedBudgets.contains(budget.id)) {
  _warnedBudgets.add(budget.id);
  await _notifications.showBudgetWarning(
      budget.id, budget.categoryName, spent, budget.amount);
}
if (spentPercent < 0.80) {
  _warnedBudgets.remove(budget.id);  // reset so it fires again next period
}
```

`_warnedBudgets` is a `Set<String>` — transient, resets on app restart (acceptable:
next sync re-triggers if still over 80%).

**Messages:** `"Budget alert — {category}"` / body `"{spent} / {limit} spent ({pct}%)."`

---

### Chapter 8 — Tests

**New test file:** `test/presenters/notification_expansion_test.dart`

Mock `NotificationService`. Verify:

| Scenario | Expected call |
|---|---|
| `addXp()` causes level-up | `showLevelUpNotification` called once |
| Level-up crosses rank boundary | `showRankPromotionNotification` called instead |
| `logWeight()` called | `cancelWeightReminder` called |
| `setWeightReminder(time)` called | `scheduleWeightReminder` called with correct time |
| Food entry pushes calories over goal | `showCalorieGoalNotification` called once |
| Food entry added again (already over) | notification not called again same day |
| Budget spending crosses 80% | `showBudgetWarning` called |
| Budget spending drops below 80% | warning cleared from `_warnedBudgets` |

---

## File Change Summary

| File | Change type |
|---|---|
| `lib/services/notification_service.dart` | Add channels, IDs, 8 new methods |
| `lib/presenters/stats_presenter.dart` | Inject NotificationService, fire on level-up |
| `lib/models/nutrition_goals.dart` | Add `weightReminderTime` field |
| `lib/presenters/nutrition_presenter.dart` | Weight reminder scheduling + calorie goal trigger |
| `lib/views/nutrition/nutrition_settings_sheet.dart` | Weight reminder toggle + time picker |
| `lib/presenters/bills_receivables_presenter.dart` | Schedule monthly bill reminder |
| `lib/presenters/budget_presenter.dart` | Budget 80% warning on ledger sync |
| `test/presenters/notification_expansion_test.dart` | New test file |

---

## Open Questions

1. **Weight reminder default time** — 8 AM? Configurable from day 1 or hardcoded first?
2. **Bill reminder day** — Always day 1, or let user pick the day of month?
3. **Budget warning threshold** — 80% is proposed; should it be 80% + 100% (two tiers)?
4. **Rank promotion vs level-up** — Show both rank promotion AND level-up notification if
   they happen simultaneously, or only rank promotion (more dramatic)?
5. **Level-up throttle** — If the user earns many levels at once (e.g., importing old
   data), should we cap notifications at 1 regardless of how many levels were gained?
