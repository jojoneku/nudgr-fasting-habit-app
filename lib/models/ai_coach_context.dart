enum AiCoachEntryPoint {
  nutrition,
  fasting,
  stats,
  treasury,
  general,
  financeAdvisor
}

/// One category's budget line for the advisor snapshot (burn-rate diagnostic).
class AdvisorCategoryLine {
  final String name;

  /// Target/allocated budget for the month, or null when the category has no
  /// budget set (the advisor must not invent one).
  final double? target;

  /// Actual spend this month (transfers already excluded upstream).
  final double actual;

  const AdvisorCategoryLine({
    required this.name,
    this.target,
    required this.actual,
  });
}

/// One outstanding bill for the advisor snapshot.
class AdvisorBillLine {
  final String name;
  final double amount;
  const AdvisorBillLine({required this.name, required this.amount});
}

/// Snapshot of app state passed to the AI model as context.
/// All fields are optional — populate only what's relevant for the entry point.
class AiCoachContext {
  final AiCoachEntryPoint entryPoint;

  // ── Nutrition ──────────────────────────────────────────────────────────────
  final int? todayCalories;
  final int? calorieGoal;
  final double? todayProtein;
  final double? todayCarbs;
  final double? todayFat;

  // ── Fasting ────────────────────────────────────────────────────────────────
  final bool isFasting;
  final int? elapsedFastMinutes;
  final int? fastingGoalHours;
  final int fastingStreak;

  // ── RPG ───────────────────────────────────────────────────────────────────
  final int playerLevel;
  final int playerXp;
  final int playerHp;

  // ── Finance (basic — also used by the RPG coach) ────────────────────────────
  final double? monthBudget;
  final double? monthSpent;

  // ── Finance advisor (rich snapshot; source of numeric truth) ────────────────
  final double? forecastedNetBalance;
  final double? netWorth;
  final double? totalLiquidCash;
  final double? monthNetCashFlow;

  /// Savings rate this month as a percentage (0–100), or null if unknown.
  final double? savingsRatePct;
  final double? totalCreditAvailable;
  final double? totalCreditOwed;
  final double? outstandingBillsTotal;
  final int? daysLeftInMonth;
  final List<AdvisorCategoryLine> topCategories;
  final List<AdvisorBillLine> outstandingBills;

  const AiCoachContext({
    required this.entryPoint,
    this.todayCalories,
    this.calorieGoal,
    this.todayProtein,
    this.todayCarbs,
    this.todayFat,
    this.isFasting = false,
    this.elapsedFastMinutes,
    this.fastingGoalHours,
    this.fastingStreak = 0,
    this.playerLevel = 1,
    this.playerXp = 0,
    this.playerHp = 100,
    this.monthBudget,
    this.monthSpent,
    this.forecastedNetBalance,
    this.netWorth,
    this.totalLiquidCash,
    this.monthNetCashFlow,
    this.savingsRatePct,
    this.totalCreditAvailable,
    this.totalCreditOwed,
    this.outstandingBillsTotal,
    this.daysLeftInMonth,
    this.topCategories = const [],
    this.outstandingBills = const [],
  });

  /// Human-readable summary injected into the RPG coach system prompt.
  String toPromptSummary() {
    final buf = StringBuffer();

    buf.writeln('=== Player Status ===');
    buf.writeln('Level $playerLevel | XP $playerXp | HP $playerHp');
    buf.writeln('Fasting streak: $fastingStreak days');

    if (isFasting && elapsedFastMinutes != null) {
      final h = elapsedFastMinutes! ~/ 60;
      final m = elapsedFastMinutes! % 60;
      buf.writeln(
          'Currently fasting: ${h}h ${m}m / ${fastingGoalHours ?? 16}h goal');
    } else {
      buf.writeln('Not currently fasting.');
    }

    if (todayCalories != null) {
      buf.writeln('=== Today\'s Nutrition ===\n'
          'Calories: $todayCalories / ${calorieGoal ?? '?'} kcal\n'
          'Protein: ${todayProtein?.toStringAsFixed(1) ?? '?'}g | '
          'Carbs: ${todayCarbs?.toStringAsFixed(1) ?? '?'}g | '
          'Fat: ${todayFat?.toStringAsFixed(1) ?? '?'}g');
    }

    if (monthBudget != null && monthSpent != null) {
      buf.writeln('=== Finance ===\n'
          'Budget: ${_peso(monthBudget!)} | '
          'Spent: ${_peso(monthSpent!)}');
    }

    return buf.toString().trim();
  }

  /// PHP-formatted financial snapshot for the financial-advisor op. This is the
  /// model's ONLY source of numeric truth — figures are pre-computed by the
  /// Treasury presenters so the model reproduces rather than derives them.
  String financeSnapshotSummary() {
    final buf = StringBuffer();

    if (totalLiquidCash != null) {
      buf.writeln('Total liquid cash: ${_peso(totalLiquidCash!)}');
    }
    if (forecastedNetBalance != null) {
      buf.writeln('Forecasted ending cash this month (after bills & budgets): '
          '${_peso(forecastedNetBalance!)}');
    }
    if (netWorth != null) buf.writeln('Net worth: ${_peso(netWorth!)}');
    if (monthNetCashFlow != null) {
      buf.writeln('Net cash flow this month: ${_peso(monthNetCashFlow!)}');
    }
    if (savingsRatePct != null) {
      buf.writeln(
          'Savings rate this month: ${savingsRatePct!.toStringAsFixed(0)}%');
    }
    if (monthBudget != null && monthSpent != null) {
      final remaining = monthBudget! - monthSpent!;
      buf.writeln('Budget this month: ${_peso(monthSpent!)} spent of '
          '${_peso(monthBudget!)} target (${_peso(remaining)} remaining)');
    }
    if (totalCreditOwed != null || totalCreditAvailable != null) {
      buf.writeln('Credit cards: ${_peso(totalCreditOwed ?? 0)} owed, '
          '${_peso(totalCreditAvailable ?? 0)} available (unused capacity)');
    }
    if (daysLeftInMonth != null) {
      buf.writeln('Days left in month: $daysLeftInMonth');
    }
    if (outstandingBills.isNotEmpty) {
      buf.writeln('Outstanding bills this month:');
      for (final b in outstandingBills) {
        buf.writeln('  - ${b.name}: ${_peso(b.amount)}');
      }
      if (outstandingBillsTotal != null) {
        buf.writeln('  Total outstanding: ${_peso(outstandingBillsTotal!)}');
      }
    }
    if (topCategories.isNotEmpty) {
      buf.writeln('Top spending categories (actual vs target this month):');
      for (final c in topCategories) {
        final line = c.target == null
            ? '${_peso(c.actual)} spent (no budget set)'
            : '${_peso(c.actual)} of ${_peso(c.target!)} target';
        buf.writeln('  - ${c.name}: $line');
      }
    }

    final s = buf.toString().trim();
    return s.isEmpty ? '(no financial data available)' : s;
  }
}

/// Format a peso amount with a thousands separator and no decimals:
/// 1234.5 → '₱1,235', -800 → '-₱800'.
String _peso(double v) {
  final neg = v < 0;
  final digits = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return '${neg ? '-' : ''}₱$b';
}
