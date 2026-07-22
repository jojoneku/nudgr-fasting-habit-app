import '../models/insight.dart';
import '../models/insight_snapshot.dart';

/// One rule in the v1 trigger table (Plan 057). Pure: [test] and
/// [fallbackText] read only the given [InsightSnapshot] — no I/O, no
/// `DateTime.now()`. Any date/time fact a trigger needs (e.g. "is it past
/// 8pm?") is already baked into the snapshot by `InsightSnapshotBuilder`, so
/// [test] never has to reach for the wall clock itself.
///
/// When a trigger's markers are missing from the snapshot (its module has
/// no data yet, or the plan asked for a marker with no backing presenter
/// getter — see Plan 057 Phase 1 report), [test] returns `false` so the
/// trigger cleanly no-fires instead of throwing or guessing.
class InsightTrigger {
  const InsightTrigger({
    required this.id,
    required this.mood,
    required this.cooldown,
    required this.test,
    required this.fallbackText,
  });

  /// Stable id, e.g. `'nutrition.overGoal'` — used as the cooldown map key
  /// and persisted alongside the fired [Insight].
  final String id;

  final InsightMood mood;

  /// Minimum time between two fires of this trigger.
  final Duration cooldown;

  /// True when this trigger's condition currently holds.
  final bool Function(InsightSnapshot snapshot) test;

  /// Template one-liner used when zero AI is configured/available — written
  /// in plain, everyday language. Always produces a complete, sensible line
  /// from snapshot data alone.
  final String Function(InsightSnapshot snapshot) fallbackText;
}

num? _num(Map<String, Object?> markers, String key) => markers[key] as num?;

bool? _bool(Map<String, Object?> markers, String key) => markers[key] as bool?;

final List<InsightTrigger> _kTriggers = <InsightTrigger>[
  InsightTrigger(
    id: 'nutrition.overGoal',
    mood: InsightMood.urgent,
    cooldown: const Duration(hours: 12),
    test: (s) {
      final cals = _num(s.nutrition.markers, 'todayCalories');
      final goal = _num(s.nutrition.markers, 'effectiveGoal');
      if (cals == null || goal == null || goal <= 0) return false;
      return cals > goal * 1.10;
    },
    fallbackText: (s) {
      final cals = _num(s.nutrition.markers, 'todayCalories') ?? 0;
      final goal = _num(s.nutrition.markers, 'effectiveGoal') ?? 0;
      final over = (cals - goal).round();
      return 'You\'re about $over kcal over your goal today — might be a good '
          'time to call it a night on eating.';
    },
  ),
  InsightTrigger(
    id: 'nutrition.fatTrend',
    mood: InsightMood.neutral,
    cooldown: const Duration(days: 3),
    // Active as of Plan 057 Phase 3: NutritionPresenter now exposes
    // `sevenDayAvgFatGrams` (rolling 7-day average) and `fatTargetGrams`
    // (daily fat goal), both baked into the nutrition section by
    // InsightSnapshotBuilder. Fires when the 7-day fat average has run
    // > 25% over target.
    test: (s) {
      final avg = _num(s.nutrition.markers, 'sevenDayAvgFatGrams');
      final target = _num(s.nutrition.markers, 'fatTargetGrams');
      if (avg == null || target == null || target <= 0) return false;
      return avg > target * 1.25;
    },
    fallbackText: (s) => 'Your fat intake has been high for a few days — try '
        'easing up on fried and fatty foods this week.',
  ),
  InsightTrigger(
    id: 'nutrition.proteinLow',
    mood: InsightMood.neutral,
    cooldown: const Duration(days: 3),
    test: (s) {
      final rate = _num(s.nutrition.markers, 'proteinHitRate7d');
      final consistency = _num(s.nutrition.markers, 'loggingConsistency7d');
      if (rate == null) return false;
      // "≥5 logged days" out of the last 7 — approximated from the logging
      // consistency fraction (no distinct logged-day counter in the digest).
      final loggedDays7 = ((consistency ?? 0) * 7).round();
      return rate < 0.4 && loggedDays7 >= 5;
    },
    fallbackText: (s) => 'Protein has come up short most days this week — try '
        'to work a protein source into your next meal.',
  ),
  InsightTrigger(
    id: 'finance.spendPace',
    mood: InsightMood.urgent,
    cooldown: const Duration(days: 2),
    test: (s) {
      final spent = _num(s.finance.markers, 'monthSpent');
      final budget = _num(s.finance.markers, 'monthBudget');
      final day = _num(s.finance.markers, 'dayOfMonth');
      final daysInMonth = _num(s.finance.markers, 'daysInMonth');
      if (spent == null ||
          budget == null ||
          budget <= 0 ||
          day == null ||
          daysInMonth == null ||
          daysInMonth <= 0) {
        return false;
      }
      final expectedPace = budget * (day / daysInMonth) * 1.15;
      return spent > expectedPace;
    },
    fallbackText: (s) => 'Your spending is running ahead of budget for this '
        'point in the month — worth easing off the extras.',
  ),
  InsightTrigger(
    id: 'finance.categoryBlown',
    mood: InsightMood.urgent,
    cooldown: const Duration(days: 2),
    test: (s) => _bool(s.finance.markers, 'anyCategoryOverBudget') ?? false,
    fallbackText: (s) => 'At least one budget category is over this month — '
        'worth a quick look before it adds up.',
  ),
  InsightTrigger(
    id: 'finance.billImminent',
    mood: InsightMood.urgent,
    cooldown: const Duration(days: 1),
    test: (s) => _bool(s.finance.markers, 'billImminent') ?? false,
    fallbackText: (s) => 'You have a bill due within 48 hours — good to pay '
        'it before it\'s overdue.',
  ),
  InsightTrigger(
    id: 'fasting.streakAtRisk',
    mood: InsightMood.urgent,
    cooldown: const Duration(days: 1),
    // No "usual start hour" data exists, so the condition is simplified per
    // Plan 057 Phase 1 scope: streak alive, not currently fasting, and it's
    // already evening local time. `localHour` is baked into the snapshot by
    // InsightSnapshotBuilder from the `now` passed to it — this test never
    // touches the wall clock itself.
    test: (s) {
      final streak = _num(s.fasting.markers, 'streak');
      final isFasting = _bool(s.fasting.markers, 'isFasting');
      final hour = _num(s.fasting.markers, 'localHour');
      if (streak == null || isFasting == null || hour == null) return false;
      return streak >= 3 && !isFasting && hour >= 20;
    },
    fallbackText: (s) {
      final streak = (_num(s.fasting.markers, 'streak') ?? 0).round();
      return 'Your $streak-day fasting streak is at risk — starting tonight\'s '
          'fast now keeps it going.';
    },
  ),
  InsightTrigger(
    id: 'quests.slipping',
    mood: InsightMood.neutral,
    cooldown: const Duration(days: 2),
    // No 7-day quest-completion-rate marker exists yet — QuestPresenter
    // exposes per-quest streaks and today's buckets but no rolling 7-day
    // completion rate (see Plan 057 Phase 1 report). Wired into the table
    // per spec; stays dormant until a data source is added.
    test: (s) {
      final rate = _num(s.quests.markers, 'completionRate7d');
      final due = _num(s.quests.markers, 'dueTodayCount');
      if (rate == null || due == null) return false;
      return rate < 0.5 && due > 0;
    },
    fallbackText: (s) => 'Your tasks have slipped a bit this week — finishing '
        'today\'s list will help you get back on track.',
  ),
  InsightTrigger(
    id: 'body.weightStale',
    mood: InsightMood.neutral,
    cooldown: const Duration(days: 7),
    test: (s) {
      final days = _num(s.body.markers, 'daysSinceLastWeightLog');
      if (days == null) return false;
      return days >= 7;
    },
    fallbackText: (s) => 'You haven\'t logged your weight in over a week — a '
        'quick step on the scale keeps your trend accurate.',
  ),
  InsightTrigger(
    id: 'positive.onFire',
    mood: InsightMood.positive,
    cooldown: const Duration(days: 1),
    test: (s) {
      var green = 0;

      final cals = _num(s.nutrition.markers, 'todayCalories');
      final goal = _num(s.nutrition.markers, 'effectiveGoal');
      if (cals != null && goal != null && goal > 0 && cals <= goal) green++;

      final spent = _num(s.finance.markers, 'monthSpent');
      final budget = _num(s.finance.markers, 'monthBudget');
      if (spent != null && budget != null && budget > 0 && spent <= budget) {
        green++;
      }

      final streak = _num(s.fasting.markers, 'streak');
      if (streak != null && streak >= 3) green++;

      final steps = _num(s.activity.markers, 'stepsToday');
      final stepsAvg = _num(s.activity.markers, 'steps7dAvg');
      if (steps != null && stepsAvg != null && steps >= stepsAvg) green++;

      return green >= 3;
    },
    fallbackText: (s) => 'Three or more areas are on track today — great '
        'work, keep it up!',
  ),
];

/// The full v1 trigger table, exposed read-only for callers/tests that need
/// to inspect every trigger directly (e.g. assert on trigger ids/cooldowns).
List<InsightTrigger> get allInsightTriggers => List.unmodifiable(_kTriggers);

/// Evaluate all v1 triggers against [snapshot], honouring [lastFired]
/// cooldowns (trigger id → the last time it fired). [now] drives cooldown
/// math only — every trigger's own condition reads purely from [snapshot]
/// (see [InsightTrigger.test]). Returns triggers whose condition currently
/// holds AND are out of cooldown; callers decide display priority/ordering
/// (e.g. urgent > positive > neutral, capped per Plan 057's nag-fatigue
/// rule) — this function doesn't rank, it just filters.
List<InsightTrigger> evaluateTriggers(
  InsightSnapshot snapshot,
  Map<String, DateTime> lastFired,
  DateTime now,
) {
  final fired = <InsightTrigger>[];
  for (final trigger in _kTriggers) {
    if (!trigger.test(snapshot)) continue;
    final last = lastFired[trigger.id];
    if (last != null && now.difference(last) < trigger.cooldown) continue;
    fired.add(trigger);
  }
  return fired;
}
