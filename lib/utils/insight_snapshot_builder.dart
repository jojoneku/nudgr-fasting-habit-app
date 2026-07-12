import '../models/insight_snapshot.dart';
import 'insight_hash.dart' show roundCurrency, roundKg;

/// Plain-data input to [InsightSnapshotBuilder.build] — one primitive field
/// per marker the Insight Engine understands, grouped by the presenter that
/// owns it. Deliberately presenter-free: the presenter layer (Phase 3) maps
/// its own getters onto this class, which keeps the builder pure and
/// testable without constructing a single presenter or service.
///
/// A field is `null` when its module has no data yet (goal not set, nothing
/// logged, feature not wired in) — the builder drops null markers from the
/// resulting [SnapshotSection] entirely, so `evaluateTriggers` can treat
/// "not loaded" and "not applicable" identically (see insight_triggers.dart).
///
/// Fields the plan asked for but with no backing presenter getter today are
/// intentionally absent from this class — see Plan 057 Phase 1 report for
/// the list (e.g. fasting's 7-day completion rate, nutrition's 7-day fat
/// average, quests' 7-day completion rate).
class InsightSnapshotInputs {
  const InsightSnapshotInputs({
    // ── Fasting — lib/presenters/fasting_presenter.dart ─────────────────
    this.isFasting,
    this.fastingStreak,
    this.fastingGoalHours,

    // ── Nutrition — lib/presenters/nutrition_presenter.dart /
    //    lib/utils/body_composition_calculator.dart ─────────────────────
    this.todayCalories,
    this.effectiveGoal,
    this.sevenDayAvgCalories,
    this.proteinHitRate7d,
    this.loggingConsistency7d,
    this.logStreak,
    this.goalStreak,

    // ── Finance — lib/presenters/treasury_dashboard_presenter.dart /
    //    lib/presenters/budget_presenter.dart ───────────────────────────
    this.monthSpent,
    this.monthBudget,
    this.billImminent,
    this.anyCategoryOverBudget,
    this.netCashFlow,

    // ── Quests — lib/presenters/quest_presenter.dart ────────────────────
    this.questsDueTodayCount,
    this.hasUrgentQuest,

    // ── Activity — lib/presenters/activity_presenter.dart ───────────────
    this.stepsToday,
    this.steps7dAvg,

    // ── Body — lib/presenters/nutrition_presenter.dart (weight log) ─────
    this.latestWeightKg,
    this.daysSinceLastWeightLog,

    // ── RPG — lib/presenters/stats_presenter.dart ────────────────────────
    this.level,
    this.xp,
    this.hp,
  });

  /// FastingPresenter.isFasting
  final bool? isFasting;

  /// FastingPresenter.currentStreak
  final int? fastingStreak;

  /// FastingPresenter.fastingGoalHours
  final int? fastingGoalHours;

  /// NutritionPresenter.todayCalories
  final int? todayCalories;

  /// NutritionPresenter.effectiveGoal
  final int? effectiveGoal;

  /// NutritionPresenter.sevenDayAvgCalories (BodyCompositionCalculator)
  final int? sevenDayAvgCalories;

  /// NutritionPresenter.proteinHitRate7d — null when no protein goal is set.
  final double? proteinHitRate7d;

  /// NutritionPresenter.loggingConsistency7d — fraction of the last 7 days
  /// with at least one entry logged.
  final double? loggingConsistency7d;

  /// NutritionPresenter.logStreak
  final int? logStreak;

  /// NutritionPresenter.goalStreak
  final int? goalStreak;

  /// TreasuryDashboardPresenter.monthTotalOutflow
  final double? monthSpent;

  /// BudgetPresenter.totalAllocated for the current month
  final double? monthBudget;

  /// TreasuryDashboardPresenter.hasBillImminent
  final bool? billImminent;

  /// True when any BudgetPresenter.budgetRows entry `.isOver`.
  final bool? anyCategoryOverBudget;

  /// TreasuryDashboardPresenter.monthNetCashFlow (sign is what the snapshot
  /// keeps; the raw magnitude is not a marker the digest needs).
  final double? netCashFlow;

  /// QuestPresenter.todayActiveQuests.length + todayOverdueQuests.length
  final int? questsDueTodayCount;

  /// QuestPresenter.hasUrgentQuest
  final bool? hasUrgentQuest;

  /// ActivityPresenter.todaySteps
  final int? stepsToday;

  /// Average steps over ActivityPresenter.weeklyLogs (last 7 days).
  final int? steps7dAvg;

  /// NutritionPresenter.latestWeight?.weightKg
  final double? latestWeightKg;

  /// Days between NutritionPresenter.latestWeight?.loggedAt and now.
  final int? daysSinceLastWeightLog;

  /// StatsPresenter.stats.level
  final int? level;

  /// StatsPresenter.stats.currentXp
  final int? xp;

  /// StatsPresenter.stats.currentHp
  final int? hp;
}

/// Pure builder: reduces an [InsightSnapshotInputs] (already-primitive
/// presenter values) into an [InsightSnapshot] the rule engine and prompt
/// digest can consume. Never touches storage, presenters, or
/// `DateTime.now()` directly — [now] is passed in explicitly so a fixed
/// instant makes the output fully deterministic and unit-testable, and so
/// date-derived facts (e.g. "is it past 8pm?") can live in the snapshot
/// instead of `insight_triggers.dart` calling `DateTime.now()` itself.
abstract final class InsightSnapshotBuilder {
  static InsightSnapshot build(InsightSnapshotInputs inputs, DateTime now) {
    return InsightSnapshot(
      fasting: _fastingSection(inputs, now),
      nutrition: _nutritionSection(inputs),
      finance: _financeSection(inputs, now),
      quests: _questsSection(inputs),
      activity: _activitySection(inputs),
      body: _bodySection(inputs),
      rpg: _rpgSection(inputs),
    );
  }

  static SnapshotSection _fastingSection(
    InsightSnapshotInputs i,
    DateTime now,
  ) {
    return SnapshotSection(
      name: 'fasting',
      markers: _dropNulls({
        'isFasting': i.isFasting,
        'streak': i.fastingStreak,
        'goalHours': i.fastingGoalHours,
        // Baked in at build time so insight_triggers.dart's pure `test`
        // functions never need to call DateTime.now() themselves.
        'localHour': now.hour,
      }),
    );
  }

  static SnapshotSection _nutritionSection(InsightSnapshotInputs i) {
    return SnapshotSection(
      name: 'nutrition',
      markers: _dropNulls({
        'todayCalories': i.todayCalories,
        'effectiveGoal': i.effectiveGoal,
        'sevenDayAvgCalories': i.sevenDayAvgCalories,
        'proteinHitRate7d': i.proteinHitRate7d,
        'loggingConsistency7d': i.loggingConsistency7d,
        'logStreak': i.logStreak,
        'goalStreak': i.goalStreak,
      }),
    );
  }

  static SnapshotSection _financeSection(
    InsightSnapshotInputs i,
    DateTime now,
  ) {
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return SnapshotSection(
      name: 'finance',
      markers: _dropNulls({
        'monthSpent':
            i.monthSpent == null ? null : roundCurrency(i.monthSpent!),
        'monthBudget':
            i.monthBudget == null ? null : roundCurrency(i.monthBudget!),
        'billImminent': i.billImminent,
        'anyCategoryOverBudget': i.anyCategoryOverBudget,
        'netCashFlowSign': i.netCashFlow?.sign.toInt(),
        // Baked-in date facts for the spend-pace trigger — same rationale
        // as fasting.localHour above.
        'dayOfMonth': now.day,
        'daysInMonth': daysInMonth,
      }),
    );
  }

  static SnapshotSection _questsSection(InsightSnapshotInputs i) {
    return SnapshotSection(
      name: 'quests',
      markers: _dropNulls({
        'dueTodayCount': i.questsDueTodayCount,
        'hasUrgent': i.hasUrgentQuest,
      }),
    );
  }

  static SnapshotSection _activitySection(InsightSnapshotInputs i) {
    return SnapshotSection(
      name: 'activity',
      markers: _dropNulls({
        'stepsToday': i.stepsToday,
        'steps7dAvg': i.steps7dAvg,
      }),
    );
  }

  static SnapshotSection _bodySection(InsightSnapshotInputs i) {
    return SnapshotSection(
      name: 'body',
      markers: _dropNulls({
        'latestWeightKg':
            i.latestWeightKg == null ? null : roundKg(i.latestWeightKg!),
        'daysSinceLastWeightLog': i.daysSinceLastWeightLog,
      }),
    );
  }

  static SnapshotSection _rpgSection(InsightSnapshotInputs i) {
    return SnapshotSection(
      name: 'rpg',
      markers: _dropNulls({
        'level': i.level,
        'xp': i.xp,
        'hp': i.hp,
      }),
    );
  }

  /// Drops null-valued markers so "no data" and "not applicable" both read
  /// as an absent key — `evaluateTriggers` treats a missing marker as a
  /// clean no-fire rather than a null-check landmine.
  static Map<String, Object?> _dropNulls(Map<String, Object?> markers) {
    final out = <String, Object?>{};
    for (final entry in markers.entries) {
      if (entry.value != null) out[entry.key] = entry.value;
    }
    return out;
  }
}
