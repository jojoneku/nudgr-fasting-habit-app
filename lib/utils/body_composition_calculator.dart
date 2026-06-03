import 'dart:math';

import '../models/body_measurement_entry.dart';
import '../models/daily_nutrition_log.dart';
import '../models/dashboard_status.dart';
import '../models/meal_slot.dart';
import '../models/nutrition_goals.dart';
import '../models/tdee_profile.dart';
import '../models/weight_entry.dart';
import 'body_fat_calculator.dart' as bfcalc;

/// Pure body-composition & dashboard analytics.
///
/// Extracted from `NutritionPresenter` (Plan 035 A1 / Plan 036 Phase 1). All
/// methods are static and side-effect-free — they read the data lists passed in
/// and return computed values, with no presenter state, I/O, or notification.
/// This makes the cut/bulk/recomp/maintain status math and the trend
/// calculations unit-testable in isolation.
abstract final class BodyCompositionCalculator {
  // ── Weight ─────────────────────────────────────────────────────────────────

  static double? weightDelta(List<WeightEntry> weightLog) {
    if (weightLog.length < 2) return null;
    return weightLog.last.weightKg - weightLog[weightLog.length - 2].weightKg;
  }

  static WeightTrendDirection weightTrend(List<WeightEntry> weightLog) {
    if (weightLog.length < 4) return WeightTrendDirection.insufficient;
    final entries = weightLog.length >= 14
        ? weightLog.sublist(weightLog.length - 14)
        : weightLog;
    final half = entries.length ~/ 2;
    final firstAvg =
        entries.sublist(0, half).fold(0.0, (s, e) => s + e.weightKg) / half;
    final secondAvg =
        entries.sublist(half).fold(0.0, (s, e) => s + e.weightKg) /
            (entries.length - half);
    final delta = secondAvg - firstAvg;
    if (delta < -0.1) return WeightTrendDirection.down;
    if (delta > 0.1) return WeightTrendDirection.up;
    return WeightTrendDirection.stable;
  }

  // ── Waist / measurements ─────────────────────────────────────────────────────

  static double? waistDelta(List<BodyMeasurementEntry> measurementLog) {
    final waistEntries =
        measurementLog.where((e) => e.waistCm != null).toList();
    if (waistEntries.length < 2) return null;
    return waistEntries.last.waistCm! -
        waistEntries[waistEntries.length - 2].waistCm!;
  }

  static MeasurementTrendDirection waistTrend(
      List<BodyMeasurementEntry> measurementLog) {
    final entries = measurementLog.where((e) => e.waistCm != null).toList();
    if (entries.length < 4) return MeasurementTrendDirection.insufficient;
    final recent =
        entries.length >= 14 ? entries.sublist(entries.length - 14) : entries;
    final half = recent.length ~/ 2;
    final firstAvg =
        recent.sublist(0, half).map((e) => e.waistCm!).reduce((a, b) => a + b) /
            half;
    final secondAvg =
        recent.sublist(half).map((e) => e.waistCm!).reduce((a, b) => a + b) /
            (recent.length - half);
    final diff = secondAvg - firstAvg;
    if (diff < -0.5) return MeasurementTrendDirection.down;
    if (diff > 0.5) return MeasurementTrendDirection.up;
    return MeasurementTrendDirection.stable;
  }

  static bool hasWaistChartData(List<BodyMeasurementEntry> measurementLog) =>
      measurementLog.where((e) => e.waistCm != null).length >= 2;

  static double? totalWaistChangeCm(List<BodyMeasurementEntry> measurementLog) {
    final entries = measurementLog.where((e) => e.waistCm != null).toList();
    if (entries.length < 2) return null;
    return entries.last.waistCm! - entries.first.waistCm!;
  }

  static bool hasMeasurementExtraSites(BodyMeasurementEntry? latest) {
    if (latest == null) return false;
    return latest.neckCm != null ||
        latest.hipsCm != null ||
        latest.chestCm != null ||
        latest.bicepCm != null ||
        latest.thighCm != null;
  }

  // ── Body fat ───────────────────────────────────────────────────────────────

  /// Both BF% estimates: US Navy (measurement-based) and BMI (profile-based).
  static ({double? navy, double? bmi}) bodyFatEstimates({
    TdeeProfile? profile,
    BodyMeasurementEntry? latest,
  }) {
    if (profile == null) return (navy: null, bmi: null);

    double? navy;
    if (latest != null && latest.waistCm != null && latest.neckCm != null) {
      navy = bfcalc.estimateBodyFatPercent(
        sex: profile.sex,
        heightCm: profile.heightCm,
        waistCm: latest.waistCm!,
        neckCm: latest.neckCm!,
        hipsCm: latest.hipsCm,
      );
    }

    final bmi = bfcalc.estimateBodyFatPercentBmi(
      sex: profile.sex,
      heightCm: profile.heightCm,
      weightKg: profile.weightKg,
      ageYears: profile.ageYears,
    );

    return (navy: navy, bmi: bmi);
  }

  /// Average of Navy + BMI estimates; falls back to whichever is available.
  static double? estimatedBodyFatPercent({
    TdeeProfile? profile,
    BodyMeasurementEntry? latest,
  }) {
    final est = bodyFatEstimates(profile: profile, latest: latest);
    final navy = est.navy;
    final bmi = est.bmi;
    if (navy != null && bmi != null) return (navy + bmi) / 2;
    return navy ?? bmi;
  }

  /// Per-entry Navy BF% history for the trend chart.
  /// Only entries that have both waist and neck measurements are included.
  static List<({DateTime date, double bf})> bodyFatHistory({
    TdeeProfile? profile,
    required List<BodyMeasurementEntry> measurementLog,
  }) {
    if (profile == null) return const [];
    final result = <({DateTime date, double bf})>[];
    for (final e in measurementLog) {
      if (e.waistCm == null || e.neckCm == null) continue;
      final bf = bfcalc.estimateBodyFatPercent(
        sex: profile.sex,
        heightCm: profile.heightCm,
        waistCm: e.waistCm!,
        neckCm: e.neckCm!,
        hipsCm: e.hipsCm,
      );
      if (bf != null) result.add((date: e.loggedAt, bf: bf));
    }
    return result;
  }

  static bool hasBodyFatChartData({
    TdeeProfile? profile,
    required List<BodyMeasurementEntry> measurementLog,
  }) =>
      bodyFatHistory(profile: profile, measurementLog: measurementLog).length >=
      2;

  /// Formatted body-fat range label ("12–15%", "~14%", or "—").
  static String bodyFatRangeLabel({
    TdeeProfile? profile,
    BodyMeasurementEntry? latest,
  }) {
    final est = bodyFatEstimates(profile: profile, latest: latest);
    final navy = est.navy;
    final bmi = est.bmi;
    if (navy != null && bmi != null) {
      final lo = min(navy, bmi).toStringAsFixed(0);
      final hi = max(navy, bmi).toStringAsFixed(0);
      return lo == hi ? '~$lo%' : '$lo–$hi%';
    } else if (navy != null || bmi != null) {
      return '~${(navy ?? bmi)!.toStringAsFixed(0)}%';
    }
    return '—';
  }

  // ── 7-day stats ──────────────────────────────────────────────────────────────

  static int sevenDayAvgCalories(List<DailyNutritionLog> history) {
    final days = history.take(7).where((l) => l.totalCalories > 0).toList();
    if (days.isEmpty) return 0;
    return (days.fold(0, (s, l) => s + l.totalCalories) / days.length).round();
  }

  static double? proteinHitRate7d({
    required NutritionGoals goals,
    required List<DailyNutritionLog> history,
  }) {
    final goal = goals.proteinGrams;
    if (goal == null || goal <= 0) return null;
    final days = history.take(7).toList();
    if (days.isEmpty) return null;
    final hits = days.where((l) => l.totalProtein >= goal).length;
    return hits / days.length;
  }

  static double loggingConsistency7d(List<DailyNutritionLog> history) {
    final days = history.take(7).toList();
    if (days.isEmpty) return 0.0;
    return days.where((l) => l.totalCalories > 0).length / days.length;
  }

  // ── Dashboard status ───────────────────────────────────────────────────────

  static DashboardStatus dashboardStatus({
    required List<DailyNutritionLog> history,
    TdeeProfile? profile,
    required NutritionGoals goals,
    required List<WeightEntry> weightLog,
    required List<BodyMeasurementEntry> measurementLog,
  }) {
    final loggedDays = history.take(7).where((l) => l.totalCalories > 0).length;
    if (loggedDays < 3) {
      return const DashboardStatus(
        label: GoalStatusLabel.needsMoreData,
        headline: 'Needs more data',
        detail: 'Log at least 3 days to see your goal status',
      );
    }

    final avg = sevenDayAvgCalories(history);

    if (profile == null || goals.mode != TrackingMode.standard) {
      return DashboardStatus(
        label: GoalStatusLabel.onTrack,
        headline: 'Tracking active',
        detail: '7-day avg $avg kcal',
      );
    }

    final target = profile.targetCalories;
    final phr = proteinHitRate7d(goals: goals, history: history);
    final delta = avg - target;
    final sign = delta >= 0 ? '+' : '';
    final detail = '7-day avg $avg kcal · $sign$delta vs target';

    return switch (profile.goal) {
      'cut' => _cutStatus(avg, target, phr, detail, weightLog, measurementLog),
      'bulk' => _leanGainStatus(avg, target, phr, detail),
      'recomp' => _recompStatus(avg, target, phr, detail),
      _ => _maintainStatus(avg, target, phr, detail),
    };
  }

  static DashboardStatus _cutStatus(
    int avg,
    int target,
    double? phr,
    String detail,
    List<WeightEntry> weightLog,
    List<BodyMeasurementEntry> measurementLog,
  ) {
    if (avg < target - 200) {
      return DashboardStatus(
        label: GoalStatusLabel.tooAggressive,
        headline: 'Too aggressive',
        detail: detail,
      );
    }
    if (avg > target + 100) {
      return DashboardStatus(
        label: GoalStatusLabel.tooHigh,
        headline: 'Too high',
        detail: detail,
      );
    }
    if (phr != null && phr < 0.5) {
      return DashboardStatus(
        label: GoalStatusLabel.lowProtein,
        headline: 'Low protein',
        detail: detail,
      );
    }
    // possibleRecomp: in-band calories + stable weight + ≥14 entries
    if (weightLog.length >= 14 &&
        weightTrend(weightLog) == WeightTrendDirection.stable) {
      final waist = waistTrend(measurementLog);
      if (waist == MeasurementTrendDirection.down) {
        return const DashboardStatus(
          label: GoalStatusLabel.possibleRecomp,
          headline: 'Recomp confirmed',
          detail:
              'Waist trending down while weight holds — recomp confirmed. Keep going.',
        );
      }
      if (waist == MeasurementTrendDirection.insufficient) {
        return const DashboardStatus(
          label: GoalStatusLabel.possibleRecomp,
          headline: 'Possible recomp',
          detail:
              'Weight stable despite deficit — log body measurements to confirm recomp.',
        );
      }
      return const DashboardStatus(
        label: GoalStatusLabel.possibleRecomp,
        headline: 'Possible recomp',
        detail:
            'Weight stable despite deficit — if you\'re training, this may be recomp. Body measurements would confirm.',
      );
    }
    return DashboardStatus(
      label: GoalStatusLabel.onTrack,
      headline: 'On track',
      detail: detail,
    );
  }

  static DashboardStatus _leanGainStatus(
      int avg, int target, double? phr, String detail) {
    if (avg < target - 100) {
      return DashboardStatus(
        label: GoalStatusLabel.notEnoughSurplus,
        headline: 'Not enough surplus',
        detail: detail,
      );
    }
    if (avg > target + 200) {
      return DashboardStatus(
        label: GoalStatusLabel.tooHigh,
        headline: 'Too high',
        detail: detail,
      );
    }
    if (phr != null && phr < 0.6) {
      return DashboardStatus(
        label: GoalStatusLabel.lowProtein,
        headline: 'Low protein',
        detail: detail,
      );
    }
    return DashboardStatus(
      label: GoalStatusLabel.onTrack,
      headline: 'On track',
      detail: detail,
    );
  }

  static DashboardStatus _recompStatus(
      int avg, int target, double? phr, String detail) {
    if (avg < target - 200) {
      return DashboardStatus(
        label: GoalStatusLabel.tooAggressive,
        headline: 'Too aggressive',
        detail: detail,
      );
    }
    if (avg > target + 200) {
      return DashboardStatus(
        label: GoalStatusLabel.tooHigh,
        headline: 'Too high',
        detail: detail,
      );
    }
    if (phr != null && phr < 0.65) {
      return DashboardStatus(
        label: GoalStatusLabel.lowProtein,
        headline: 'Low protein',
        detail: detail,
      );
    }
    return DashboardStatus(
      label: GoalStatusLabel.onTrack,
      headline: 'On track',
      detail: detail,
    );
  }

  static DashboardStatus _maintainStatus(
      int avg, int target, double? phr, String detail) {
    if (avg > target + 150) {
      return DashboardStatus(
        label: GoalStatusLabel.tooHigh,
        headline: 'Too high',
        detail: detail,
      );
    }
    if (avg < target - 150) {
      return DashboardStatus(
        label: GoalStatusLabel.notEnoughSurplus,
        headline: 'Too low',
        detail: detail,
      );
    }
    if (phr != null && phr < 0.4) {
      return DashboardStatus(
        label: GoalStatusLabel.lowProtein,
        headline: 'Low protein',
        detail: detail,
      );
    }
    return DashboardStatus(
      label: GoalStatusLabel.onTrack,
      headline: 'On track',
      detail: detail,
    );
  }

  // ── KPI / trend labels ───────────────────────────────────────────────────────

  static String primaryKpiLabel(String? activeGoal) => switch (activeGoal) {
        'cut' => 'Average deficit',
        'bulk' => 'Surplus adherence',
        'recomp' => 'Calorie stability',
        _ => 'Calorie stability',
      };

  static String secondaryKpiLabel(String? activeGoal) => switch (activeGoal) {
        'cut' => 'Protein compliance',
        'bulk' => 'Protein support',
        'recomp' => 'Protein compliance',
        _ => 'Protein consistency',
      };

  static String weightTrendLabel(
          String? activeGoal, WeightTrendDirection direction) =>
      switch ((activeGoal, direction)) {
        ('cut', WeightTrendDirection.down) => 'Trending down ↓',
        ('cut', WeightTrendDirection.stable) => 'Weight stable',
        ('cut', WeightTrendDirection.up) => 'Trending up ↑',
        ('bulk', WeightTrendDirection.up) => 'Trending up ↑',
        ('bulk', WeightTrendDirection.stable) => 'Weight stable',
        ('bulk', WeightTrendDirection.down) => 'Trending down ↓',
        _ => 'Weight stable',
      };
}
