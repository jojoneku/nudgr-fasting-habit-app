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

  /// Human-readable due label ("Due in 3 days", "Overdue by 1 day"), or null
  /// when the bill has no meaningful due date to surface.
  final String? dueLabel;

  const AdvisorBillLine({required this.name, required this.amount, this.dueLabel});
}

/// One expected receivable (money owed TO the user) for the advisor snapshot.
class AdvisorReceivableLine {
  final String name;
  final double amount;

  /// When it's expected ("Jun 28", "ASAP"), or null when undated.
  final String? expectedLabel;

  const AdvisorReceivableLine({
    required this.name,
    required this.amount,
    this.expectedLabel,
  });
}

/// One credit card / line / BNPL account for the advisor snapshot. Gives the
/// advisor per-card visibility instead of a single owed/available total.
class AdvisorCreditLine {
  final String name;

  /// What's currently owed on this card.
  final double owed;

  /// Remaining spending capacity (limit − owed), or null when no limit is set.
  final double? available;

  /// Payment-due label ("Due in 5 days"), or null when no due day configured.
  final String? dueLabel;

  /// Estimated minimum due this cycle, or null when nothing is owed.
  final double? minimumDue;

  const AdvisorCreditLine({
    required this.name,
    required this.owed,
    this.available,
    this.dueLabel,
    this.minimumDue,
  });
}

/// One month's net-worth point for the historical benchmark (past context).
class AdvisorNetWorthPoint {
  final String label;
  final double value;
  const AdvisorNetWorthPoint({required this.label, required this.value});
}

/// One month's income-vs-expense point for the historical benchmark.
class AdvisorMonthFlow {
  final String label;
  final double income;
  final double expense;
  const AdvisorMonthFlow({
    required this.label,
    required this.income,
    required this.expense,
  });
}

/// One savings-goal pocket for the advisor snapshot (progress toward a target).
class AdvisorGoalLine {
  final String name;
  final double saved;

  /// The target to reach, or null when the goal has no target set.
  final double? target;

  const AdvisorGoalLine({required this.name, required this.saved, this.target});
}

/// One liquid account's balance — lets the advisor answer "which account holds
/// what" instead of only a single cash total.
class AdvisorAccountLine {
  final String name;
  final double balance;
  const AdvisorAccountLine({required this.name, required this.balance});
}

/// One budget group's allocated-vs-spent line (Needs / Wants / Savings, etc.).
class AdvisorBudgetGroupLine {
  final String name;
  final double allocated;
  final double spent;
  const AdvisorBudgetGroupLine({
    required this.name,
    required this.allocated,
    required this.spent,
  });
}

/// One active installment / BNPL plan for the advisor snapshot.
class AdvisorInstallmentLine {
  final String name;
  final double monthlyAmount;
  final int remainingMonths;
  final double remainingAmount;
  const AdvisorInstallmentLine({
    required this.name,
    required this.monthlyAmount,
    required this.remainingMonths,
    required this.remainingAmount,
  });
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

  // ── Finance advisor (extended: present money-in, savings, credit detail) ────
  /// Income actually received this month (excludes transfers/reimbursements).
  final double? monthIncome;

  /// Money owed TO the user, still outstanding this month.
  final double? pendingReceivablesTotal;

  /// Total set aside across savings + goal pockets.
  final double? totalSavingsAndGoals;

  /// Per-card credit breakdown (owed / available / due / minimum).
  final List<AdvisorCreditLine> creditLines;

  /// Individual receivables expected this month.
  final List<AdvisorReceivableLine> pendingReceivables;

  // ── Finance advisor (future: next month's known obligations) ────────────────
  /// Recurring bills already scheduled for next month, if any.
  final double? nextMonthBillsTotal;

  /// Receivables expected next month, if any.
  final double? nextMonthReceivablesTotal;

  // ── Finance advisor (past: historical benchmark, year-over-year context) ────
  final List<AdvisorNetWorthPoint> netWorthTrend;
  final List<AdvisorMonthFlow> incomeExpenseTrend;

  // ── Finance advisor (breakdowns: goals, accounts, budget, installments) ─────
  /// Per-goal progress (name, saved, target).
  final List<AdvisorGoalLine> goals;

  /// Per-account liquid cash balances.
  final List<AdvisorAccountLine> liquidAccounts;

  /// Money held for someone else (custodian) — excluded from "your" cash.
  final double? heldForOthers;

  /// Budget allocated vs spent per group.
  final List<AdvisorBudgetGroupLine> budgetGroups;

  /// Sinking-fund / set-aside money still to be funded this month.
  final double? setAsidesRemaining;

  /// Active installment / BNPL plans and this month's total load.
  final List<AdvisorInstallmentLine> installments;
  final double? installmentsMonthlyLoad;

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
    this.monthIncome,
    this.pendingReceivablesTotal,
    this.totalSavingsAndGoals,
    this.creditLines = const [],
    this.pendingReceivables = const [],
    this.nextMonthBillsTotal,
    this.nextMonthReceivablesTotal,
    this.netWorthTrend = const [],
    this.incomeExpenseTrend = const [],
    this.goals = const [],
    this.liquidAccounts = const [],
    this.heldForOthers,
    this.budgetGroups = const [],
    this.setAsidesRemaining,
    this.installments = const [],
    this.installmentsMonthlyLoad,
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
    if (liquidAccounts.isNotEmpty) {
      buf.writeln('  Cash by account:');
      for (final a in liquidAccounts) {
        buf.writeln('    - ${a.name}: ${_peso(a.balance)}');
      }
    }
    if (heldForOthers != null && heldForOthers! > 0) {
      buf.writeln('  Of which held for someone else (not yours to spend): '
          '${_peso(heldForOthers!)}');
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
    if (budgetGroups.isNotEmpty) {
      buf.writeln('Budget by group (spent vs allocated):');
      for (final g in budgetGroups) {
        buf.writeln('  - ${g.name}: ${_peso(g.spent)} of ${_peso(g.allocated)}');
      }
    }
    if (setAsidesRemaining != null && setAsidesRemaining! > 0) {
      buf.writeln('Set-asides still to fund this month (sinking funds): '
          '${_peso(setAsidesRemaining!)}');
    }
    if (monthIncome != null) {
      buf.writeln('Income received this month: ${_peso(monthIncome!)}');
    }
    if (totalSavingsAndGoals != null) {
      buf.writeln('Savings & goals set aside: ${_peso(totalSavingsAndGoals!)}');
    }
    if (goals.isNotEmpty) {
      buf.writeln('Savings goals (saved vs target):');
      for (final g in goals) {
        if (g.target != null && g.target! > 0) {
          final pct = (g.saved / g.target! * 100).clamp(0, 999).round();
          buf.writeln('  - ${g.name}: ${_peso(g.saved)} of '
              '${_peso(g.target!)} ($pct%)');
        } else {
          buf.writeln('  - ${g.name}: ${_peso(g.saved)} saved (no target set)');
        }
      }
    }
    // Credit: prefer the per-card breakdown; fall back to totals when the
    // caller only supplied aggregates.
    if (creditLines.isNotEmpty) {
      buf.writeln('Credit cards / lines (owed vs available capacity):');
      for (final c in creditLines) {
        final parts = <String>['${_peso(c.owed)} owed'];
        if (c.available != null) {
          parts.add('${_peso(c.available!)} available');
        }
        if (c.minimumDue != null) {
          parts.add('min due ${_peso(c.minimumDue!)}');
        }
        if (c.dueLabel != null) parts.add(c.dueLabel!);
        buf.writeln('  - ${c.name}: ${parts.join(', ')}');
      }
      if (totalCreditOwed != null) {
        buf.writeln('  Total owed: ${_peso(totalCreditOwed!)}'
            '${totalCreditAvailable != null ? ', ${_peso(totalCreditAvailable!)} available (unused capacity)' : ''}');
      }
    } else if (totalCreditOwed != null || totalCreditAvailable != null) {
      buf.writeln('Credit cards: ${_peso(totalCreditOwed ?? 0)} owed, '
          '${_peso(totalCreditAvailable ?? 0)} available (unused capacity)');
    }
    if (installments.isNotEmpty) {
      buf.writeln('Installment / BNPL plans (fixed monthly commitments):');
      for (final i in installments) {
        buf.writeln('  - ${i.name}: ${_peso(i.monthlyAmount)}/mo, '
            '${i.remainingMonths} mo left (${_peso(i.remainingAmount)} remaining)');
      }
      if (installmentsMonthlyLoad != null) {
        buf.writeln('  Total installment load this month: '
            '${_peso(installmentsMonthlyLoad!)}');
      }
    }
    if (daysLeftInMonth != null) {
      buf.writeln('Days left in month: $daysLeftInMonth');
    }
    if (outstandingBills.isNotEmpty) {
      buf.writeln('Outstanding bills this month (money going OUT):');
      for (final b in outstandingBills) {
        final due = b.dueLabel != null ? ' (${b.dueLabel})' : '';
        buf.writeln('  - ${b.name}: ${_peso(b.amount)}$due');
      }
      if (outstandingBillsTotal != null) {
        buf.writeln('  Total outstanding: ${_peso(outstandingBillsTotal!)}');
      }
    }
    if (pendingReceivables.isNotEmpty || pendingReceivablesTotal != null) {
      buf.writeln('Receivables this month (money coming IN, owed to you):');
      for (final r in pendingReceivables) {
        final when = r.expectedLabel != null ? ' (${r.expectedLabel})' : '';
        buf.writeln('  - ${r.name}: ${_peso(r.amount)}$when');
      }
      if (pendingReceivablesTotal != null) {
        buf.writeln('  Total incoming: ${_peso(pendingReceivablesTotal!)}');
      }
    }
    if (nextMonthBillsTotal != null || nextMonthReceivablesTotal != null) {
      final parts = <String>[];
      if (nextMonthBillsTotal != null) {
        parts.add('${_peso(nextMonthBillsTotal!)} in scheduled bills');
      }
      if (nextMonthReceivablesTotal != null) {
        parts.add('${_peso(nextMonthReceivablesTotal!)} expected receivables');
      }
      buf.writeln('Next month so far: ${parts.join('; ')}');
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

  /// Prior-period benchmark for year-over-year / trend context. Kept separate
  /// from the live snapshot so the model uses it for perspective, never for
  /// current-liquidity math. Empty string when there's no usable history.
  String financeHistoricalSummary() {
    final buf = StringBuffer();
    if (netWorthTrend.isNotEmpty) {
      final pts =
          netWorthTrend.map((p) => '${p.label} ${_peso(p.value)}').join(', ');
      buf.writeln('Net worth by month (oldest → newest): $pts');
    }
    if (incomeExpenseTrend.isNotEmpty) {
      buf.writeln('Income vs expenses by month:');
      for (final m in incomeExpenseTrend) {
        buf.writeln('  - ${m.label}: ${_peso(m.income)} in / '
            '${_peso(m.expense)} out (net ${_peso(m.income - m.expense)})');
      }
    }
    return buf.toString().trim();
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
