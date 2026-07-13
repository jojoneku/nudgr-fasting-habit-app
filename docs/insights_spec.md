# Hub AI Insights & Nudges Spec

> Status: IMPLEMENTED · Authored: July 12, 2026 · Plan: [.claude/plans/057-hub-ai-insights-nudges.md](../.claude/plans/057-hub-ai-insights-nudges.md)
> Related: [ai_coach_spec.md](ai_coach_spec.md), [trends_projections_spec.md](trends_projections_spec.md)

## Overview

The Hub coach line used to be dormant filler — a static string shown unless the
on-device model happened to be downloaded, fed by a thin, single-domain
context. The **Insight Engine** replaces it with a real cross-module "System
Analysis": a compact digest of fasting, nutrition, finance, quests, activity,
body, and RPG state that (1) always shows something meaningful with zero AI
configured, (2) generates a once-daily **Daily Brief**, and (3) fires
event-triggered **nudges** (over-goal, overspend, streak at risk, ...).

### Cost model

The whole design exists to keep this near-zero cost:

1. **Rules find, LLM phrases.** Trigger detection (`insight_triggers.dart`) is
   pure Dart, runs instantly offline, and ships a template `fallbackText` for
   every trigger — the feature is fully functional with **zero AI
   availability**. When a model is available, it only rewrites the already-
   detected directive into one personalized line; it never decides *what*
   fired.
2. **Snapshot, not raw data.** `InsightSnapshotBuilder` reduces every source
   presenter to a `InsightSnapshot` of ~20-30 rounded, JSON-primitive markers
   (well under 1 KB serialized). The LLM only ever sees `toPromptDigest()` —
   never food names, transaction memos, or account names.
2. **Per-section hash gate.** Each `SnapshotSection` carries a stable FNV-1a
   content hash (`insight_hash.dart`). `InsightsPresenter.refresh()` recomputes
   all seven hashes and compares them to the persisted baseline; if nothing
   changed, it returns immediately — **no trigger evaluation, no LLM call, no
   storage write**. This is asserted directly in
   `test/presenters/insights_presenter_test.dart` ("unchanged hashes → no eval,
   no writes, no service calls").
3. **Caps and cooldowns.** Every trigger has its own cooldown (12h–7d); at most
   2 nudges are *surfaced* per local calendar day regardless of how many fire;
   at most 6 cloud phrasing calls per day (`_kMaxCloudCallsPerDay`); the daily
   brief generates at most once per local calendar day. On-device phrasing
   costs nothing; cloud phrasing is capped and opt-in only.

## User Story

As a player, I want the Hub to surface a real, changing observation about my
day — not filler — so a glance at the top of the Hub tells me what The System
noticed and what to do about it, with or without an AI model installed.

## Data Model

### `lib/models/insight_snapshot.dart`

```dart
class SnapshotSection {
  final String name;                    // 'fasting' | 'nutrition' | 'finance' |
                                         // 'quests' | 'activity' | 'body' | 'rpg'
  final Map<String, Object?> markers;   // int/double/bool/String only; null
                                         // markers are dropped, never stored
  String get hash;                      // hashMarkers(markers) — insight_hash.dart
  Map<String, dynamic> toJson();
  factory SnapshotSection.fromJson(Map<String, dynamic> json);
}

class InsightSnapshot {
  final SnapshotSection fasting, nutrition, finance, quests, activity, body, rpg;
  List<SnapshotSection> get sections;          // fixed order, all 7
  Map<String, String> get sectionHashes;        // name → hash, the diff baseline
  Map<String, dynamic> toJson();
  factory InsightSnapshot.fromJson(Map<String, dynamic> json);
  String toPromptDigest({Set<String> changedSections = const {}});
  // one line per domain, e.g. "Finance [NEW]: billImminent=true, monthSpent=1200"
}
```

### `lib/models/insight.dart`

```dart
enum InsightKind { dailyBrief, nudge }
enum InsightMood { neutral, urgent, positive }
enum InsightSource { rules, onDevice, cloud }

class Insight {
  final String id;              // ring-buffer key, e.g. "<micros>-<counter>-<triggerId|brief>"
  final InsightKind kind;
  final InsightMood mood;
  final String text;             // one line (nudge) or short paragraph (brief)
  final String? triggerId;       // which InsightTrigger.id fired; null for dailyBrief
  final DateTime createdAt;
  final InsightSource source;    // which tier actually phrased the text
  Insight copyWith({...});
  Map<String, dynamic> toJson();
  factory Insight.fromJson(Map<String, dynamic> json);
}
```

Both models round-trip through `fromJson`/`toJson`; `Insight` is persisted in a
30-entry ring buffer (`_kMaxInsights`), `InsightSnapshot` itself is never
persisted (only its per-section hashes are).

## Snapshot Markers Table

Built by `InsightSnapshotBuilder.build(InsightSnapshotInputs, DateTime now)`
(`lib/utils/insight_snapshot_builder.dart`), which is the only place raw
presenter values are mapped onto primitive markers. Fields with no backing
presenter getter today are **omitted from `InsightSnapshotInputs` entirely**
(not merely null) — see the "Deviations" note under Trigger Table.

| Section | Marker | Data source getter | Rounding |
|---|---|---|---|
| fasting | `isFasting` | `FastingPresenter.isFasting` | — |
| fasting | `streak` | `FastingPresenter.currentStreak` | — |
| fasting | `goalHours` | `FastingPresenter.fastingGoalHours` | — |
| fasting | `localHour` | baked in from `now.hour` (builder param, not a presenter) | — |
| nutrition | `todayCalories` | `NutritionPresenter.todayCalories` | — |
| nutrition | `effectiveGoal` | `NutritionPresenter.effectiveGoal` | — |
| nutrition | `sevenDayAvgCalories` | `NutritionPresenter.sevenDayAvgCalories` (null when nutrition history is empty) | — |
| nutrition | `sevenDayAvgFatGrams` | `NutritionPresenter.sevenDayAvgFatGrams` | rounded to whole grams |
| nutrition | `fatTargetGrams` | `NutritionPresenter.fatTargetGrams` | rounded to whole grams |
| nutrition | `proteinHitRate7d` | `NutritionPresenter.proteinHitRate7d` | — |
| nutrition | `loggingConsistency7d` | `NutritionPresenter.loggingConsistency7d` | — |
| nutrition | `logStreak` | `NutritionPresenter.logStreak` | — |
| nutrition | `goalStreak` | `NutritionPresenter.goalStreak` | — |
| finance | `monthSpent` | `TreasuryDashboardPresenter.monthTotalOutflow` | `roundCurrency` (nearest whole unit) |
| finance | `monthBudget` | `BudgetPresenter.totalAllocated` | `roundCurrency` |
| finance | `billImminent` | `TreasuryDashboardPresenter.hasBillImminent` | — |
| finance | `anyCategoryOverBudget` | any `BudgetPresenter.budgetRows` entry `.isOver` | — |
| finance | `netCashFlowSign` | `TreasuryDashboardPresenter.monthNetCashFlow.sign` | sign only, not magnitude |
| finance | `dayOfMonth` | baked in from `now.day` | — |
| finance | `daysInMonth` | baked in (`DateTime(now.year, now.month+1, 0).day`) | — |
| quests | `dueTodayCount` | `QuestPresenter.todayActiveQuests.length + todayOverdueQuests.length` | — |
| quests | `hasUrgent` | `QuestPresenter.hasUrgentQuest` | — |
| activity | `stepsToday` | `ActivityPresenter.todaySteps` | — |
| activity | `steps7dAvg` | average of `ActivityPresenter.weeklyLogs` steps | rounded to whole steps |
| body | `latestWeightKg` | `NutritionPresenter.latestWeight?.weightKg` | `roundKg` (1 decimal) |
| body | `daysSinceLastWeightLog` | days between `latestWeight.loggedAt` and now | — |
| rpg | `level` | `StatsPresenter.stats.level` | — |
| rpg | `xp` | `StatsPresenter.stats.currentXp` | — |
| rpg | `hp` | `StatsPresenter.stats.currentHp` | — |

Markers with a `null` source value are dropped from the section's `markers`
map entirely (`InsightSnapshotBuilder._dropNulls`), so `evaluateTriggers`
treats "not loaded yet" and "not applicable" identically — a clean no-fire
rather than a null-check landmine.

## Trigger Table

`lib/utils/insight_triggers.dart` — 10 pure `InsightTrigger`s, each with a
`test(InsightSnapshot)`, a `cooldown`, and a `fallbackText` that always
produces a complete System-voice line from snapshot data alone.
`evaluateTriggers(snapshot, lastFired, now)` returns every trigger whose
condition currently holds **and** is out of cooldown; the caller ranks and caps
(urgent > positive > neutral, ≤ 2 surfaced/day).

| id | condition | cooldown | status |
|---|---|---|---|
| `nutrition.overGoal` | `todayCalories > effectiveGoal × 1.10` | 12 h | active |
| `nutrition.fatTrend` | `sevenDayAvgFatGrams > fatTargetGrams × 1.25` | 3 d | active |
| `nutrition.proteinLow` | `proteinHitRate7d < 0.4` with ≥ 5 of last 7 days logged (approximated from `loggingConsistency7d × 7`) | 3 d | active |
| `finance.spendPace` | `monthSpent > monthBudget × (dayOfMonth/daysInMonth) × 1.15` | 2 d | active |
| `finance.categoryBlown` | `anyCategoryOverBudget` | 2 d | active |
| `finance.billImminent` | `billImminent` (bill due ≤ 48h) | 1 d | active |
| `fasting.streakAtRisk` | `streak ≥ 3 && !isFasting && localHour ≥ 20` | 1 d | active (simplified — no "usual start hour" data; uses fixed 8pm local-hour cutoff instead) |
| `quests.slipping` | `completionRate7d < 0.5 && dueTodayCount > 0` | 2 d | **dormant** — wired into the table per spec, but `completionRate7d` has no backing `QuestPresenter` getter yet (no rolling 7-day quest-completion-rate aggregate exists). `test` always returns `false` until that marker is added. |
| `body.weightStale` | `daysSinceLastWeightLog ≥ 7` | 7 d | active |
| `positive.onFire` | ≥ 3 of {calorie goal met, under budget, fasting streak ≥ 3, steps ≥ 7d avg} are green | 1 d | active |

## Presenter API

`lib/presenters/insights_presenter.dart` — `InsightsPresenter extends
ChangeNotifier with SafeNotifier`. Constructor injection only; `_fasting`,
`_stats`, `_quests` are required, `_nutrition`/`_treasury`/`_budget`/`_activity`
are optional (nullable — a missing source presenter just means its markers are
absent from the snapshot), `_onDeviceAi`/`_cloudAi` are optional phrasing
tiers, and `clock` is an injectable `DateTime Function()` for deterministic
tests.

```dart
class InsightsPresenter extends ChangeNotifier with SafeNotifier {
  InsightsPresenter({
    required StorageService storage,
    required FastingPresenter fasting,
    required StatsPresenter stats,
    required QuestPresenter quests,
    NutritionPresenter? nutrition,
    TreasuryDashboardPresenter? treasury,
    BudgetPresenter? budget,
    ActivityPresenter? activity,
    AiCoachService? onDeviceAi,
    AiCoachService? cloudAi,
    DateTime Function()? clock,
  });

  // ── Read surface (Hub) ────────────────────────────────────────────────────
  Insight? get current;      // today's nudge > today's brief > most recent > null
  Insight? get dailyBrief;   // today's brief only, null before generation
  List<Insight> get recent;  // ring buffer, most-recent-first, ≤ 30
  bool get hasUnread;        // true when recent.first is newer than the read watermark
  bool get isGenerating;
  bool get isInitialized;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  Future<void> init();       // loads persisted state; call once before refresh()

  // ── Actions ───────────────────────────────────────────────────────────────
  Future<void> refresh();                    // hash-gated; see Cost model
  Future<void> generateDailyBriefIfDue();     // once per local calendar day
  void markRead();                           // clears hasUnread, persists watermark
}
```

`refresh()` is also driven automatically: the constructor subscribes to every
non-null source presenter's `notifyListeners`, and a burst of source changes
coalesces into a single `Future.microtask`-debounced `refresh()` call (same
pattern as `HubPresenter._onSourceChanged`) — asserted in
`insights_presenter_test.dart`'s "debounce" group.

## Tier Routing

Phrasing only — rules always decide *what* fired; the tier chain decides how
the sentence is *worded*.

```
trigger fired / brief due
  → on-device AI available? → 1-shot phrase call (free), timeout 20s
      → non-empty response → InsightSource.onDevice
  → cloud AI available AND under daily cap (6/day)? → 1-shot phrase call
      → non-empty response → InsightSource.cloud
  → template fallbackText() (or _templateBrief() for the brief)
      → InsightSource.rules  (always succeeds, never throws)
```

Implemented in `InsightsPresenter._phrase()` / `_collect()`. Any exception,
timeout, empty stream, or disposal during a tier's call falls through to the
next tier rather than surfacing an error — asserted directly in the "tier
routing" test group (`on-device empty → falls through to cloud`, `on-device
error → falls through to cloud`, `cloud daily cap exhausted → rules
fallback`). The daily brief uses `_kBriefInstruction` (2–3 sentence morning
briefing); nudges use `_kNudgeInstruction` (max 22 words, rewrites the
trigger's own `fallbackText` as the "directive to rewrite").

`AiCoachPresenter.refreshHubNudge()` has been **retired** — `HubCoachLine` now
reads `InsightsPresenter.current` exclusively. As a Phase-1 fix-along-the-way,
`AiCoachPresenter._buildContext()` now populates `monthBudget` /
`monthSpent` (previously always `null`), so the chat coach's finance context
works regardless of the Insight Engine.

## Storage Keys

`StorageService` (abstract) + `LocalStorageService` (SharedPreferences impl),
`lib/services/storage_service.dart` / `lib/services/local_storage_service.dart`:

| Key constant | SharedPreferences key | Type | Purpose |
|---|---|---|---|
| `keyInsightBaselineHashes` | `insight_baseline_hashes` | `Map<String, String>` (JSON) | Per-section hash baseline for the diff gate |
| `keyInsights` | `insights` | `List<Insight>` (JSON) | Ring buffer, ≤ 30, most-recent-first |
| `keyInsightCooldowns` | `insight_cooldowns` | `Map<String, DateTime>` (JSON) | Per-trigger last-fired timestamps, plus the reserved `_lastRead` watermark key |
| `keyLastDailyBriefDate` | `last_daily_brief_date` | `DateTime` (JSON) | Local calendar date of the last-generated brief |

```dart
Future<Map<String, String>?> loadInsightBaselineHashes();
Future<void> saveInsightBaselineHashes(Map<String, String> hashes);
Future<List<Insight>> loadInsights();
Future<void> saveInsights(List<Insight> insights);
Future<Map<String, DateTime>?> loadInsightCooldowns();
Future<void> saveInsightCooldowns(Map<String, DateTime> cooldowns);
Future<DateTime?> loadLastDailyBriefDate();
Future<void> saveLastDailyBriefDate(DateTime date);
```

All four keys are included in the user-scoped export/import key list
(`local_storage_service.dart`) alongside the other Plan-057-adjacent keys, so
insights travel with account backup/restore like the rest of user data.

## Notification Behavior

`flutter_local_notifications` can't run Dart at fire time, so delivery is
**scheduled statically, generated lazily**:

- `NotificationService.scheduleDailyBriefReminder(TimeOfDay time)` schedules a
  daily `zonedSchedule` (channel `daily_brief` / "System Analysis", notif id
  `512`, `AndroidScheduleMode.alarmClock`, `DateTimeComponents.time` so it
  repeats daily) with a fixed body: *"Your morning briefing awaits in the
  Hub."* It does **not** contain the brief's actual text — the brief itself is
  generated on next app open/resume, not at notification-fire time.
  `cancelDailyBriefReminder()` cancels it.
- Actual generation happens via `InsightsPresenter.generateDailyBriefIfDue()`,
  called from `home_screen.dart` in two places: once after the first-frame
  I/O sequence (`_insightsPresenter.init()` then `generateDailyBriefIfDue()`),
  and again on every `AppLifecycleState.resumed` transition alongside
  `_insightsPresenter.refresh()`. Both calls are fire-and-forget and
  hash-gated/once-per-day respectively, so resuming repeatedly costs nothing
  once the day's work is done.
- `NotificationPreferences` (`lib/models/notification_preferences.dart`) adds
  `bool dailyBriefEnabled` (default `false`) and `TimeOfDay dailyBriefTime`
  (default `07:30`), persisted as `dailyBriefEnabled` / `dailyBriefHour` /
  `dailyBriefMinute` JSON keys with backward-compatible defaults for old
  profiles.
- `NotificationSettingsSheet` wires the toggle: enabling calls
  `scheduleDailyBriefReminder`, disabling calls `cancelDailyBriefReminder`,
  changing the time re-schedules if already enabled, and re-enabling
  notifications globally (master toggle) re-arms the daily brief reminder
  alongside the weight and bills reminders if it was previously on.

## Edge Cases

- **Model unavailable/errors mid-generation** — `_phrase()`/`_collect()` catch
  every exception and fall through to the next tier, ending at the always-
  available template `fallbackText`; `SafeNotifier`/`isDisposed` guards mean a
  disposed presenter never calls `notifyListeners` after teardown.
- **Nag fatigue** — per-trigger cooldowns (12h–7d) plus a hard cap of 2 nudges
  surfaced per local calendar day (`_kMaxNudgesPerDay`), ranked urgent >
  positive > neutral; the notification toggle lets a user disable the daily
  brief reminder independently of in-app nudges (there is no separate
  in-app nudge on/off switch in v1 — nudges are always evaluated, only their
  daily notification companion is toggleable).
- **Hash instability** — all currency values round via `roundCurrency` (nearest
  whole unit), kg via `roundKg` (1 decimal), grams via `.round()`, before
  hashing — asserted by `insight_hash_test.dart`'s "collapses jitter" tests.
- **Day boundary / timezone** — "once per day" and cooldown-day math both key
  off local calendar date (`year`/`month`/`day` equality via
  `_isSameLocalDay`), consistent with the quest-reset convention elsewhere in
  the app.
- **Source presenters not ready at first Hub mount** — `refresh()` before
  `init()` completes just sets `_refreshRequestedBeforeInit = true` and runs
  once `init()` finishes loading persisted state; subsequent calls are driven
  by the debounced source-presenter listeners, so the first real snapshot
  settles naturally after async loads complete.
- **Cloud cost runaway** — `_kMaxCloudCallsPerDay = 6`, counted from today's
  cloud-sourced insights in the ring buffer; once exhausted, phrasing falls
  straight to the rules template for the rest of the day (verified by the
  "cloud daily cap exhausted → rules fallback" test).
- **Privacy** — the digest sent to any AI tier is `toPromptDigest()`: rounded
  aggregate markers only (kcal, kg, currency amounts, booleans, counts) — never
  food names, transaction memos, or account names.
- **Missing data sources** — `nutrition`/`treasury`/`budget`/`activity` are all
  nullable constructor params; when absent, their markers are simply missing
  from the snapshot and every trigger that needs them cleanly returns `false`
  rather than throwing.

## Acceptance Criteria

- [x] Hub always shows a meaningful line with zero AI configured (rules +
      templates), and it changes with state (over-goal day ≠ on-track day) —
      `insights_presenter_test.dart` "tier routing: on-device unavailable +
      cloud unavailable → rules fallback"
- [x] With unchanged data, re-opening the Hub performs no model call and no
      regeneration — `insights_presenter_test.dart` "hash gate: unchanged
      hashes → no eval, no writes, no service calls"
- [x] Daily Brief generates at most once per local calendar day and survives
      app restart — `insights_presenter_test.dart` "daily brief" group +
      "lifecycle: init loads persisted insights (survives restart)"
- [x] Over-eating and overspending conditions each produce a nudge, at most
      once per cooldown window — `insight_triggers_test.dart`
      (`nutrition.overGoal`, `finance.spendPace`, `finance.categoryBlown`,
      `finance.billImminent` groups) + `insights_presenter_test.dart`
      "cooldowns" group
- [x] Cloud tier used only when opted-in (constructor-injected `cloudAi`) +
      available, and only when under the daily cap; digest contains no raw
      entries/memos — `insights_presenter_test.dart` "cloud daily cap
      exhausted → rules fallback"
- [x] All logic lives in utils/presenters — no calculations in `build()`;
      views are `ListenableBuilder`-driven (`HubCoachLine`, `DailyBriefSheet`)
- [x] Theme-aware colors only in new widgets (`Theme.of(context).colorScheme`,
      `context.appColors`); tap targets ≥ 44 px (`HubCoachLine`'s
      `BoxConstraints(minHeight: 44)`, `DailyBriefSheet`'s `_DirectiveRow`
      `minHeight: 44`)
- [x] Unit tests: snapshot hashing (`insight_hash_test.dart`), trigger table
      (`insight_triggers_test.dart`), cooldowns + once-per-day brief + tier
      fallback chain (`insights_presenter_test.dart`)
- [ ] `quests.slipping` fires in practice — dormant pending a `QuestPresenter`
      7-day completion-rate aggregate (see Trigger Table); the trigger,
      cooldown, and dormancy itself are unit-tested
      (`insight_triggers_test.dart` "always-dormant triggers" group), but the
      condition can never hold with today's data sources
