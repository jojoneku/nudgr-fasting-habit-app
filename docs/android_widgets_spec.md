# Android Home-Screen Widgets Spec

> Implementation plan: `.claude/plans/039-android-home-widgets.md`

## Overview
Native Android home-screen widgets that surface The System's four core loops — **fasting timer,
food logging, expense logging, weight + quests** — at a glance, and let the user fire the
highest-value actions (start/end a fast, complete a quest) without opening the app. This is a
persistent, zero-friction RPG nudge that compounds with notifications. Android first; the Dart
bridge is designed so an iOS WidgetKit extension can be added later without reworking the data layer.

## User Story
As a user, I want my fasting timer, today's calories, spend, weight, and quests on my home screen —
and to start/end a fast or tick off a quest from there — so that The System pulls me back into the
loop without me having to open the app.

## Conceptual Model

### The snapshot boundary (why this design)
All app user-data is stored under a `u/$userId/` prefix that only exists after login. The native
widget process (and the headless isolate that runs inline actions) has **no userId**. Therefore:

- The app is the **single writer**. It pushes a flat, denormalized `WidgetSnapshot` into
  `home_widget`'s own unscoped prefs whenever a presenter changes.
- Widgets are **pure renderers** of that snapshot — they never read app prefs directly.
- On **sign-out** the snapshot is cleared and replaced with an empty/"Sign in" state, so a second
  account on a shared device never sees the first user's data.

### Live fasting without the app running
The fasting elapsed/remaining time is rendered with a **native Android `Chronometer`** bound to
`fastStartMillis` / `targetMillis`. It ticks on its own with the Flutter process killed — the same
mechanism the existing persistent fasting notification uses. All other glance numbers are static
until the app next refreshes the snapshot, with two backstops (no background polling):

- **30-min OS re-render** (`updatePeriodMillis="1800000"`, the system minimum) on the fasting,
  food, quest, and expense widgets — recomputes time-derived rendering (fasting progress %,
  day-rollover check) from the stored snapshot while the app process is dead.
- **Day-rollover staleness guard**: the snapshot carries its build date (`w_date`, local
  `yyyy-MM-dd`). When a provider renders on a later day, day-scoped values reset instead of
  showing yesterday's numbers — food calories/protein render `0` (true for the new day), the
  expense "Today" line hides, and the quest widget shows `—` / "Open app to refresh" with the
  inline ✓ hidden (its quest id belongs to yesterday). A missing `w_date` counts as fresh.

### Inline-action safety rule
A widget tap performs an **inline action** only if it is purely local (no network, no AI, no rich
UI): **start fast, end fast, complete quest**. Everything richer — food parsing (AI), expense
categorisation — **deep-links** into the app instead.

## Data Model
```dart
// lib/models/widget/widget_snapshot.dart — flat, primitives only (round-trips through
// HomeWidget.saveWidgetData<T>()). All formatting/calculation done in Dart; native side renders.
class WidgetSnapshot {
  final bool signedIn;             // false → every widget shows the "Sign in" empty state
  final String snapshotDate;       // 'yyyy-MM-dd' build day — day-rollover staleness guard

  // Fasting
  final bool isFasting;
  final int? fastStartMillis;      // epoch ms — Chronometer base
  final int? targetMillis;         // epoch ms — goal end (countdown variant)
  final int fastingGoalHours;
  final int currentStreak;
  final String fastPhaseLabel;     // precomputed phase name

  // Food
  final int todayCalories;
  final int calorieGoal;
  final int proteinGrams;
  final int? proteinGoal;

  // Expense (currency-formatted in Dart)
  final String monthOutflowLabel;
  final String todayOutflowLabel;

  // Weight (unit-aware, formatted in Dart)
  final String? latestWeightLabel;
  final String? weightDeltaLabel;

  // Quests
  final int questsDoneToday;
  final int questsTotalToday;
  final String? nextQuestLabel;
  final bool hasUrgentQuest;

  const WidgetSnapshot({ /* ... */ });
  factory WidgetSnapshot.empty() => const WidgetSnapshot(signedIn: false, /* zeros */);
  Map<String, Object?> toWidgetData();              // flat key→value for saveWidgetData
  factory WidgetSnapshot.fromPresenters({ /* refs */ }); // builder used by the bridge
}
```

## Presenter / Service API
```dart
// lib/services/widget_bridge_service.dart — NOT a ChangeNotifier; it observes presenters and
// pushes to the native side. Constructor injection only (CLAUDE.md rule #6).
class WidgetBridgeService {
  WidgetBridgeService({
    required StorageService storage,
    required FastingPresenter fasting,
    required NutritionPresenter nutrition,
    required LedgerPresenter ledger,
    required QuestPresenter quests,
  });

  void attach();                      // listen to all 5 presenters (debounced ~500ms push)
  void detach();
  Future<void> pushSnapshot();        // build snapshot → saveWidgetData → updateWidget
  Future<void> clearForSignOut();     // push WidgetSnapshot.empty() + wipe widget.* keys

  static WidgetRoute? parseLaunchUri(Uri? uri);            // nudgr://food, ...
  @pragma('vm:entry-point')
  static Future<void> onInteractiveAction(Uri? uri);       // headless: start/end fast, complete quest
}

enum WidgetRoute { fasting, foodLog, expenseAdd, weightLog, quests }
```

No existing presenter's public API changes — the bridge only **reads** their getters and calls
their existing mutators (`startFast`, `stopFast`, `completeQuest`).

## UI Requirements
Native widgets use `RemoteViews` (not Flutter), so theming is via Android `values/` vs `values-night/`
color resources mirrored from `AppColors` (dark) / `AppColorsLight` (light) — `Theme.of(context)` is
unavailable here (CLAUDE.md rule #7 governs Flutter widgets, not RemoteViews).

- **Glanceability:** primary number(s) + ring/bar readable in < 1 second, no scrolling.
- **States per widget:** Signed-out ("Sign in") / Empty (no data yet) / Populated.
- **Touch targets:** inline action buttons ≥ 44×44px within the RemoteViews layout.
- **Widgets & sizes:**
  - **Fasting** — 2×1 (Chronometer + Start/End) and 2×2 (adds ring, phase, streak).
  - **Food** — calories/goal progress bar + protein chip; tap → `nudgr://food`.
  - **Expense** — month spend (large) + today spend; tap → `nudgr://expense`.
  - **Weight** — 2×2: latest weight + delta; tap → `nudgr://weight`.
  - **Quests** — 2×2: quests done/total + next quest (→ `nudgr://quests`), urgent state in accent;
    inline ✓ complete-next. (Originally shipped combined with Weight; split into two widgets so each
    can be placed/sized independently.)
- **Micro-animations:** native widgets don't animate; in-app screens reached via deep-link keep the
  existing 150–300ms transitions.

## RPG Mechanics
- **XP/HP/streak:** only via existing presenter methods invoked inline — `stopFast()` returns
  `(xp, hp)`, `completeQuest()` returns `(xp, isCritical)`. **No new XP math, no direct `addXp`.**
- **Sync:** inline mutations go through the normal storage path, marking the right `SyncDomain`
  dirty so they sync on next foreground.
- **Notifications:** start/end fast from the widget reschedules/cancels the fasting alarm + persistent
  ticker exactly as the in-app buttons do (reuse the presenter → `NotificationService` flow).

## Storage
- New **device-level / unscoped** `StorageService` keys (must survive without a userId):
  - `widget.lastUserId` — lets the headless isolate re-scope `LocalStorageService`.
  - `widget.pendingActions` — fallback queue (see Edge Cases), drained by AppShell on foreground.
- The widget snapshot itself lives in `home_widget`'s prefs group (`HomeWidget.saveWidgetData`), not
  in `StorageService`.

## Edge Cases
- **App killed:** glance numbers freeze until next app open; only the fasting Chronometer stays live (native).
- **Headless isolate can't rebuild the full presenter graph / no auth session:** build a minimal
  graph (re-scoped `LocalStorageService` → `StatsPresenter` → the one presenter needed). If that proves
  fragile, **fallback**: enqueue the action to `widget.pendingActions`, optimistically update the
  snapshot, and let AppShell apply it on next foreground — never corrupt state.
- **Sign-out on a shared device:** `clearForSignOut()` must wipe `widget.*` and re-render empty.
- **No fast active:** fasting widget shows "Start Fast" CTA, Chronometer hidden.
- **Deep-link cold start vs warm resume:** `singleTop` `MainActivity` handles both (`onNewIntent` + initial intent).

## Acceptance Criteria
- [ ] Four widgets installable from the launcher picker (fasting, food, expense, weight+quests).
- [ ] Widgets reflect an in-app change within ~1s (snapshot push).
- [ ] Fasting Chronometer ticks with the app force-killed.
- [ ] Start/End fast from the widget mutates real state (XP/HP/streak), reschedules the alarm, and
      shows correctly in-app on next open.
- [ ] Food / Expense / Weight taps deep-link to the correct logging entry point.
- [ ] Sign-out clears the snapshot; a second account never sees the first account's data.
- [ ] Dark + light widget backgrounds both legible.
- [ ] `dart format` clean; `WidgetBridgeService` unit test green.
