# Plan 057 — Hub AI Insights & Nudges

> Status: IMPLEMENTED · Authored: 2026-07-12 · Updated: 2026-07-12
> Related: [docs/ai_coach_spec.md](../../docs/ai_coach_spec.md), [docs/trends_projections_spec.md](../../docs/trends_projections_spec.md), Plans 019 (AI Coach), 027 (Notifications), 045 (Trends)

## Current State (audit findings)

The Hub coach line **is wired, but effectively dormant** for most users:

- `HubCoachLine` renders in the new Hub (`lib/views/hub_screen.dart:298`) and calls
  `AiCoachPresenter.refreshHubNudge()` off the build path.
- `refreshHubNudge()` **no-ops unless the on-device Qwen model is downloaded**
  (`AiCoachPresenter` is constructed with `service: _onDeviceAi` only —
  `lib/views/home_screen.dart:151`). Cloud AI (Bedrock Haiku) is **never used**
  for the Hub nudge, even when the user opted in.
- Without the model, the user only ever sees the static rules-based fallback
  ("Small, consistent choices are how you level up.") — which reads as filler,
  not an insight.
- Context is thin: `_buildContext()` passes fasting + today's nutrition + RPG
  stats. The `monthBudget`/`monthSpent` fields on `AiCoachContext` exist but are
  **never populated**. Quests, activity, weight trend, and finance are invisible
  to the coach.
- Nothing is persisted: no daily brief, no event-triggered nudges, no history,
  no morning notification. The nudge regenerates from scratch on every Hub mount
  and is lost on restart.

## Goal

Turn the dormant coach line into a real **Insight Engine**: a cross-module
"System Analysis" that (1) sees compact markers from every feature — fasting,
nutrition, finance, quests, activity, weight — (2) produces a **morning Daily
Brief** and **event-triggered nudges** (over-eating, overspending, streak at
risk…), and (3) does so at near-zero infra cost by detecting signals with local
rules, hash-gating LLM calls, and using the LLM only to *phrase* what the rules
already found.

RPG framing: the System "scans" the player each morning and issues directives —
this is the Solo Leveling System speaking, which is exactly the app's identity.

## Cost Model — where the efficiency actually comes from

Key insight: **all data is already on-device** (SharedPreferences via
`StorageService`). There is no expensive "requery" of a backend — the costs are
(a) cloud LLM tokens, (b) on-device inference battery/latency, (c) notification
noise. So the "baseline + diff" idea maps to:

1. **Snapshot, not raw data.** A pure `InsightSnapshotBuilder` reduces all
   modules to a compact digest (~40 numeric/enum markers, < 1 KB serialized).
   The LLM never sees raw entries — only the digest. Input tokens stay ~500–800.
2. **Per-domain hash gate (the "diff hash").** The snapshot is split into
   domain sections (fasting / nutrition / finance / quests / activity / body).
   Each section gets a stable content hash, persisted as the *baseline*. On
   refresh: recompute hashes → **if nothing changed, reuse the cached nudge and
   make zero LLM calls**. If sections changed, the prompt lists changed sections
   as "NEW" and unchanged ones in one summary line — the model focuses on the
   delta.
3. **Rules find, LLM phrases.** Trigger detection (over-goal, overspend pace,
   streak risk) is pure Dart — free, instant, works offline. Each trigger ships
   a template fallback string, so the feature is fully functional with **zero
   AI availability**. When a model *is* available, it rewrites the trigger
   payload into one personalized line.
4. **Caps and cooldowns.** Max 1 daily-brief generation/day + per-trigger
   cooldowns (persisted) + hard cap of N cloud calls/day. At Haiku pricing
   (~$0.25/M in, $1.25/M out), 1 brief + 2 nudges/day ≈ **< $0.02/user/month**.
   On-device tier costs nothing.

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/insight_snapshot.dart` | Create | Model |
| `lib/models/insight.dart` | Create | Model |
| `lib/utils/insight_snapshot_builder.dart` | Create | Utils (pure) |
| `lib/utils/insight_triggers.dart` | Create | Utils (pure) |
| `lib/utils/insight_hash.dart` | Create | Utils (pure) |
| `lib/presenters/insights_presenter.dart` | Create | Presenter |
| `lib/presenters/ai_coach_presenter.dart` | Modify (delegate hub nudge to insights; tiered service fallback) | Presenter |
| `lib/services/storage_service.dart` + `local_storage_service.dart` | Modify (new keys) | Service |
| `lib/services/notification_service.dart` | Modify (morning brief notification) | Service |
| `lib/views/widgets/hub/hub_coach_line.dart` | Modify (render Insight, tap → brief sheet, "new" badge) | View |
| `lib/views/widgets/hub/daily_brief_sheet.dart` | Create | View |
| `lib/views/home_screen.dart` | Modify (construct + wire `InsightsPresenter`) | View (composition root) |
| `docs/insights_spec.md` | Create (via `/spec` at build time) | Docs |

## Interface Definitions

```dart
// lib/models/insight_snapshot.dart — immutable digest of app state.
// One section per domain; each section serializes deterministically
// (sorted keys, rounded numbers) so hashing is stable.
class InsightSnapshot {
  final SnapshotSection fasting;    // isFasting, streak, last7CompletionRate, goalHours
  final SnapshotSection nutrition;  // todayCals, goal, 7dAvgCals, 7dFatAvg vs target,
                                    // proteinHitRate7d, adherence7d, logStreak
  final SnapshotSection finance;    // monthSpent, monthBudget, spendPace (spent vs
                                    // day-of-month pro-rata), topOverCategory,
                                    // billsImminentCount, netCashFlow sign
  final SnapshotSection quests;     // dueTodayCount, completionRate7d, hasUrgent
  final SnapshotSection activity;   // stepsToday, steps7dAvg, activeStreak
  final SnapshotSection body;       // latestWeight, weightTrendKgPerWeek (nullable),
                                    // lastLoggedDaysAgo
  final SnapshotSection rpg;        // level, xp, hp, questXpToday

  Map<String, dynamic> toJson();
  String toPromptDigest({Set<String> changedSections}); // compact text for LLM
}

class SnapshotSection {
  final String name;
  final Map<String, Object?> markers;
  String get hash; // stable hash of canonical JSON (insight_hash.dart)
}
```

```dart
// lib/models/insight.dart — a generated insight/nudge, persisted.
enum InsightKind { dailyBrief, nudge }
enum InsightMood { neutral, urgent, positive }
enum InsightSource { rules, onDevice, cloud }

class Insight {
  final String id;
  final InsightKind kind;
  final InsightMood mood;
  final String text;            // one line for nudge; short paragraph for brief
  final String? triggerId;      // which rule fired (null for dailyBrief)
  final DateTime createdAt;
  final InsightSource source;
  // fromJson / toJson
}
```

```dart
// lib/utils/insight_triggers.dart — pure rule engine, no state.
class InsightTrigger {
  final String id;               // e.g. 'nutrition.overGoal', 'finance.spendPace'
  final InsightMood mood;
  final Duration cooldown;       // e.g. 12h for overGoal, 3d for fatTrend
  final String Function(InsightSnapshot) fallbackText; // works with zero AI
  final bool Function(InsightSnapshot) test;
}

/// Evaluate all triggers against [snapshot], honouring [lastFired] cooldowns.
List<InsightTrigger> evaluateTriggers(
  InsightSnapshot snapshot,
  Map<String, DateTime> lastFired,
  DateTime now,
);
```

Initial trigger set (v1):

| id | condition | cooldown |
|---|---|---|
| `nutrition.overGoal` | todayCals > goal × 1.10 | 12 h |
| `nutrition.fatTrend` | 7d fat avg > fat target × 1.25 for ≥ 4 of 7 days | 3 d |
| `nutrition.proteinLow` | proteinHitRate7d < 0.4 with ≥ 5 logged days | 3 d |
| `finance.spendPace` | monthSpent > budget × (dayOfMonth/daysInMonth) × 1.15 | 2 d |
| `finance.categoryBlown` | any category > its budget | 2 d per category |
| `finance.billImminent` | bill due ≤ 48 h (reuses `hasBillImminent`) | 1 d |
| `fasting.streakAtRisk` | streak ≥ 3 and no fast started by usual hour | 1 d |
| `quests.slipping` | completionRate7d < 0.5 with due quests today | 2 d |
| `body.weightStale` | no weight log in ≥ 7 d | 7 d |
| `positive.onFire` | ≥ 3 domains green (goal met / under budget / streaks alive) | 1 d |

```dart
// lib/presenters/insights_presenter.dart
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
    AiCoachService? onDeviceAi,     // phrasing tier 1
    AiCoachService? cloudAi,        // phrasing tier 2 (opt-in gated internally)
    NotificationService? notifications,
  });

  // ── Read surface (Hub) ────────────────────────────────────────────────
  Insight? get current;             // what HubCoachLine shows (nudge > brief)
  Insight? get dailyBrief;          // today's brief, null before generation
  List<Insight> get recent;         // last ~20, for the brief sheet
  bool get hasUnread;               // badge on the coach line
  bool get isGenerating;

  // ── Actions ───────────────────────────────────────────────────────────
  /// Cheap. Rebuild snapshot, compare per-section hashes to the stored
  /// baseline. No changes → return (0 LLM calls). Changes → run triggers,
  /// fire nudges (respecting cooldowns), persist new baseline hashes.
  Future<void> refresh();

  /// Once per calendar day (first refresh after wake). Synthesizes the
  /// brief from the full snapshot + yesterday-vs-today deltas. LLM if
  /// available (on-device → cloud → template), else assembled from
  /// section fallback lines.
  Future<void> generateDailyBriefIfDue();

  void markRead();
}
```

```dart
// StorageService additions
Future<Map<String, String>?> loadInsightBaselineHashes();   // section → hash
Future<void> saveInsightBaselineHashes(Map<String, String>);
Future<List<Insight>> loadInsights();                        // ring buffer ≤ 30
Future<void> saveInsights(List<Insight>);
Future<Map<String, DateTime>?> loadInsightCooldowns();
Future<void> saveInsightCooldowns(Map<String, DateTime>);
Future<DateTime?> loadLastDailyBriefDate();
Future<void> saveLastDailyBriefDate(DateTime);
```

### Morning delivery (no background compute needed)

`flutter_local_notifications` can't run Dart at fire time, so the brief is
**generated lazily and delivered eagerly**:

- A static daily notification at the user's chosen hour (default 07:30):
  *"Your System Analysis is ready — open the Hub."* Scheduled via the existing
  `zonedSchedule` pattern in `NotificationService` (mirrors
  `scheduleWeightReminder`).
- Actual generation happens on **first app resume/open of the day**
  (`generateDailyBriefIfDue()` from `didChangeAppLifecycleState` + Hub mount).
  If the app was used late the previous night, we can pre-generate and put the
  first line directly into the notification body (best-effort enhancement).

### Tier routing (phrasing only)

```
trigger fired / brief due
  → on-device Qwen available?   → 1-shot phrase call (free)
  → else cloud opted-in + JWT?  → 1-shot Haiku call (~1k tokens)
  → else                        → template fallbackText (always works)
```

`AiCoachPresenter.refreshHubNudge()` is retired; `HubCoachLine` reads
`InsightsPresenter.current` instead. The chat coach keeps `AiCoachPresenter`
but its `_buildContext()` also gets the finance fields populated (bug fix) —
and can optionally accept the snapshot digest for richer chat context.

## Implementation Order

1. [x] **Models** — `InsightSnapshot`, `SnapshotSection`, `Insight` (+ `fromJson`/`toJson`, canonical serialization with rounding rules)
2. [x] **Utils** — `insight_hash.dart` (stable hash), `insight_snapshot_builder.dart` (pure builder from presenter values), `insight_triggers.dart` (rule set + cooldown evaluation). Unit tests: hash stability, trigger truth tables, cooldown math
3. [x] **StorageService** — new keys + `LocalStorageService` impl + tests
4. [x] **InsightsPresenter** — refresh/hash-gate flow, daily-brief-if-due, tier routing with template fallback, ring-buffer persistence. Tests with fake services (Null AI + fake storage)
5. [x] **Views** — upgrade `HubCoachLine` (reads `InsightsPresenter`, unread badge, tap target ≥ 44 px) + `DailyBriefSheet` (brief + recent nudges, RPG "System Analysis" framing, theme-aware colors only)
6. [x] **Wiring** — construct in `home_screen.dart` (constructor injection, listens to source presenters with the same debounced-microtask pattern as `HubPresenter`), lifecycle hook for `generateDailyBriefIfDue()`, morning notification schedule + settings toggle
7. [x] **Fixes along the way** — populate `monthBudget`/`monthSpent` in `AiCoachPresenter._buildContext()`; pass cloud service as chat fallback tier
8. [x] **UX verification** — over-goal day shows urgent nudge; unchanged state shows cached line with zero model calls (assert via debug log); brief generates once/day

## RPG Impact

- Brief and nudges are written in the System's voice ("Directive", "Analysis complete").
- No new XP sources in v1 (avoid gaming-by-notification). Optional v2: +5 XP for opening the daily brief, "Analyzed" streak.
- New notification channel: `daily_brief` (respects existing notification settings screen).

## Risks & Edge Cases

- **Model gone mid-generation** — presenter uses `SafeNotifier`/`isDisposed` guard (same pattern as `refreshHubNudge` today); fallback text already rendered, so failure is invisible.
- **Nag fatigue** — cooldowns per trigger + global cap (≤ 2 nudges surfaced/day, priority: urgent > positive > neutral); settings toggle to disable nudges and/or the morning notification.
- **Hash instability** (float jitter → spurious "changes") — canonical serialization rounds all doubles (kcal to int, kg to 0.1, ₱ to int) before hashing; unit-tested.
- **Day boundary / timezone** — "once per day" keyed on local calendar date, same convention as quest resets.
- **Presenters not ready at first Hub mount** (async loads) — `refresh()` is debounced off source-presenter notifications like `HubPresenter._onSourceChanged`; first snapshot naturally settles after loads complete.
- **Cloud cost runaway** — hard daily cap on cloud phrasing calls persisted with the cooldown map; belt-and-braces since triggers are already cooldown-gated.
- **Privacy** — cloud tier receives only the digest (aggregates, no food names, no transaction memos, no account names) and stays behind the existing Cloud AI opt-in.

## Acceptance Criteria

- [x] Hub always shows a meaningful line with **zero AI configured** (rules + templates), and it changes with state (over-goal day ≠ on-track day)
- [x] With unchanged data, re-opening the Hub performs **no model call and no regeneration** (hash gate verified by test)
- [x] Daily Brief generates at most once per local calendar day and survives app restart
- [x] Over-eating and overspending conditions each produce a nudge, at most once per cooldown window
- [x] Cloud tier used only when opted-in + signed in; digest contains no raw entries/memos
- [x] All logic lives in utils/presenters — no calculations in `build()`; views are `ListenableBuilder` only
- [x] Theme-aware colors only in new widgets; tap targets ≥ 44 px
- [x] Unit tests: snapshot hashing, trigger table, cooldowns, once-per-day brief, tier fallback chain

> Note: `quests.slipping` is implemented and unit-tested but stays permanently
> dormant — see [docs/insights_spec.md](../../docs/insights_spec.md#trigger-table)
> — pending a `QuestPresenter` 7-day completion-rate aggregate that doesn't
> exist yet. This is a scoped deviation from the original trigger table, not a
> gap in this plan's own acceptance criteria.
