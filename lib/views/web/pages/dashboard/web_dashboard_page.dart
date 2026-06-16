import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../../../utils/app_radii.dart';
import '../../widgets/web_widgets.dart';

/// Web Dashboard page (Plan 050-A) — desktop redesign mirroring the Claude
/// Design "Treasury Dashboard" reference. All numbers come from
/// [TreasuryDashboardPresenter]; layout-only logic lives here, never math.
class WebDashboardPage extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const WebDashboardPage({super.key, required this.presenter});

  /// Below this width the two content columns stack into one.
  static const double _twoColMin = 920;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (presenter.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!presenter.hasAccounts) {
          return const _EmptyState();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(WebInsets.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PositionRow(presenter: presenter),
              const SizedBox(height: WebInsets.xl),
              _MonthEndOutlookRow(presenter: presenter),
              const SizedBox(height: WebInsets.xl),
              _NetWorthTrendCard(presenter: presenter),
              const SizedBox(height: WebInsets.xl),
              _ContentColumns(presenter: presenter, minWidth: _twoColMin),
            ],
          ),
        );
      },
    );
  }
}

// ===========================================================================
// 1 — Position row (4 stat tiles)
// ===========================================================================

class _PositionRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _PositionRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = presenter;
    final net = p.netWorth;
    final delta = p.monthNetCashFlow;
    final deltaSign = delta >= 0 ? '↑ ' : '↓ ';

    final tiles = <Widget>[
      WebStatTile(
        label: 'Net Position',
        value: formatPeso(net),
        sub: '$deltaSign${formatPeso(delta.abs())} this month',
        icon: Icons.attach_money_rounded,
        emphasize: true,
        accent: true,
      ),
      WebStatTile(
        label: 'Liquid Cash',
        value: formatPeso(p.totalLiquidCash),
        sub: 'Spendable across accounts',
        icon: Icons.account_balance_wallet_outlined,
      ),
      WebStatTile(
        label: 'Total Assets',
        value: formatPeso(p.totalAssets),
        sub: 'Cash, savings & goals',
        icon: Icons.savings_outlined,
      ),
      WebStatTile(
        label: 'Current Obligations',
        value: formatPeso(p.currentObligations),
        sub: 'Unpaid bills + budgeted expenses',
        icon: Icons.receipt_long_outlined,
        valueColor: cs.error,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1040
            ? 4
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        return _GridFlow(columns: cols, spacing: WebInsets.lg, children: tiles);
      },
    );
  }
}

// ===========================================================================
// 1b — Month-End Outlook (the 4 forecast tiles moved out of Cash Flow)
// ===========================================================================

class _MonthEndOutlookRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _MonthEndOutlookRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = presenter;
    final budgetSavingsDue = p.monthUnpaidBills + p.totalBudgetRemaining;

    final tiles = <Widget>[
      WebStatTile(
        label: 'Upcoming Bills',
        value: formatPeso(p.monthUnpaidBills),
        sub: 'Unpaid this month',
        icon: Icons.receipt_long_outlined,
      ),
      WebStatTile(
        label: 'To Receive',
        value: formatPeso(p.pendingReceivables),
        sub: 'Money owed to you',
        icon: Icons.south_rounded,
      ),
      WebStatTile(
        label: 'Budget / Savings Due',
        value: formatPeso(budgetSavingsDue),
        sub: 'Still to set aside',
        icon: Icons.savings_outlined,
      ),
      WebStatTile(
        label: 'Proj. Month-End Cash',
        value: formatPeso(p.forecastedNetBalance),
        sub: 'After bills & savings',
        icon: Icons.flag_outlined,
        valueColor: p.forecastedNetBalance >= 0 ? cs.tertiary : cs.error,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.only(bottom: WebInsets.md, left: WebInsets.xs),
          child: Text('Month-End Outlook',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 1040
                ? 4
                : constraints.maxWidth >= 560
                    ? 2
                    : 1;
            return _GridFlow(
                columns: cols, spacing: WebInsets.lg, children: tiles);
          },
        ),
      ],
    );
  }
}

// ===========================================================================
// 2 — Net Worth Trend
// ===========================================================================

class _NetWorthTrendCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _NetWorthTrendCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final trend = presenter.netWorthTrend();

    if (trend.length < 2) {
      return WebCard(
        title: 'Net Worth Trend',
        description: 'Your overall position',
        trailing: WebBadge(
          formatPeso(presenter.netWorth),
          tone: WebBadgeTone.info,
          icon: Icons.trending_up_rounded,
        ),
        child: const _CardEmpty(
          icon: Icons.show_chart_rounded,
          text: 'Your net-worth trend will appear as months accrue.',
        ),
      );
    }

    final diff = trend.last.value - trend.first.value;
    final up = diff >= 0;

    return WebCard(
      title: 'Net Worth Trend',
      description: 'Your overall position',
      trailing: WebBadge(
        '${up ? '↑ ' : '↓ '}${formatPesoCompact(diff.abs())} (${trend.length} mo)',
        tone: up ? WebBadgeTone.success : WebBadgeTone.danger,
        icon: up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
      ),
      child: WebLineChart(
        values: trend.map((p) => p.value).toList(),
        bottomLabels: trend.map((p) => p.label).toList(),
        area: true,
        leftLabelFormat: formatPesoCompact,
        height: 200,
      ),
    );
  }
}

// ===========================================================================
// 3 — Two responsive content columns
// ===========================================================================

class _ContentColumns extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final double minWidth;
  const _ContentColumns({required this.presenter, required this.minWidth});

  @override
  Widget build(BuildContext context) {
    // Cash Flow leads the left column (matches the Claude reference's top-left
    // placement) so income/expenses/savings-rate + the month-end sub-stats are
    // the first thing after the position row and net-worth trend.
    final left = <Widget>[
      _CashFlowCard(presenter: presenter),
      _BudgetHealthCard(presenter: presenter),
      _AccountsCard(presenter: presenter),
    ];
    final right = <Widget>[
      _IncomeExpensesCard(presenter: presenter),
      _DailySpendingCard(presenter: presenter),
      _WhereMoneyGoesCard(presenter: presenter),
      _SavingsGoalsCard(presenter: presenter),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _interleaveStacked([...left, ...right]),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Stack(children: left)),
            const SizedBox(width: WebInsets.xl),
            Expanded(child: _Stack(children: right)),
          ],
        );
      },
    );
  }

  List<Widget> _interleaveStacked(List<Widget> cards) {
    final out = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      if (i > 0) out.add(const SizedBox(height: WebInsets.xl));
      out.add(cards[i]);
    }
    return out;
  }
}

class _Stack extends StatelessWidget {
  final List<Widget> children;
  const _Stack({required this.children});

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(const SizedBox(height: WebInsets.xl));
      spaced.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: spaced,
    );
  }
}

// ===========================================================================
// Income vs Expenses
// ===========================================================================

class _IncomeExpensesCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _IncomeExpensesCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ie = presenter.incomeExpenseTrend();

    if (ie.length < 2) {
      return const WebCard(
        title: 'Income vs Expenses',
        description: 'Monthly comparison',
        child: _CardEmpty(
          icon: Icons.bar_chart_rounded,
          text: 'Your income vs expenses trend will appear as months accrue.',
        ),
      );
    }

    return WebCard(
      title: 'Income vs Expenses',
      description: 'Monthly comparison',
      child: WebBarPairChart(
        groups:
            ie.map((m) => (label: m.label, a: m.income, b: m.expense)).toList(),
        aColor: cs.tertiary,
        // A solid brand color for the expense series — onSurfaceVariant is a
        // text role and reads as a weak gray fill against gridlines, especially
        // in light mode. (T2)
        bColor: cs.primary,
        leftLabelFormat: formatPesoCompact,
        height: 220,
      ),
    );
  }
}

// ===========================================================================
// Budget Health
// ===========================================================================

class _BudgetHealthCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _BudgetHealthCard({required this.presenter});

  static const _groups = [
    BudgetGroup.nonNegotiables,
    BudgetGroup.livingExpense,
    BudgetGroup.variableOptional,
    BudgetGroup.savings,
  ];

  static const _labels = {
    BudgetGroup.nonNegotiables: 'Non-Negotiables',
    BudgetGroup.livingExpense: 'Living Expenses',
    BudgetGroup.variableOptional: 'Variable / Optional',
    BudgetGroup.savings: 'Savings',
  };

  WebBadge _status(double ratio) {
    if (ratio >= 1.0) return const WebBadge('Over', tone: WebBadgeTone.danger);
    if (ratio >= 0.85) {
      return const WebBadge('Watch', tone: WebBadgeTone.warning);
    }
    return const WebBadge('On track', tone: WebBadgeTone.success);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final allocated = presenter.budgetAllocatedByGroup;
    final spent = presenter.budgetSpentByGroup;
    final totalAlloc = presenter.totalBudgetAllocated;
    final totalSpent = presenter.totalBudgetSpent;
    final totalLeft = presenter.totalBudgetRemaining;

    final active = _groups
        .where((g) => (allocated[g] ?? 0) > 0 || (spent[g] ?? 0) > 0)
        .toList();

    final usedPct = totalAlloc > 0
        ? '${(totalSpent / totalAlloc * 100).toStringAsFixed(1)}%'
        : '0%';

    if (active.isEmpty) {
      return WebCard(
        title: 'Budget Health',
        description: monthLabel(presenter.currentMonth),
        child: const _CardEmpty(
          icon: Icons.pie_chart_outline_rounded,
          text: 'No budget set for this month yet',
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < active.length; i++) {
      final g = active[i];
      final alloc = allocated[g] ?? 0;
      final spnt = spent[g] ?? 0;
      final ratio = alloc > 0 ? (spnt / alloc) : 0.0;
      final left = (alloc - spnt).clamp(0.0, double.infinity);
      final pct = alloc > 0 ? (spnt / alloc * 100).round() : 0;
      final dot = _groupColor(cs, g, ratio);
      if (i > 0) rows.add(const SizedBox(height: WebInsets.lg));
      rows.add(WebBudgetRow(
        dotColor: dot,
        name: _labels[g]!,
        spent: formatPeso(spnt),
        target: formatPeso(alloc),
        progress: ratio.clamp(0.0, 1.0),
        status: _status(ratio),
        sub: '${formatPeso(left)} left · $pct%',
        barColor: dot,
      ));
    }

    return WebCard(
      title: 'Budget Health',
      description:
          '${monthLabel(presenter.currentMonth)} · $usedPct of ${formatPeso(totalAlloc)} used',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          const SizedBox(height: WebInsets.lg),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: WebInsets.md),
          Row(
            children: [
              Text('TOTAL',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  )),
              const Spacer(),
              Text(
                '${formatPeso(totalSpent)} / ${formatPeso(totalAlloc)} · ${formatPeso(totalLeft)} left',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _groupColor(ColorScheme cs, BudgetGroup g, double ratio) {
    if (ratio >= 1.0) return cs.error;
    if (ratio >= 0.85) return cs.secondary;
    return switch (g) {
      BudgetGroup.nonNegotiables => cs.primary,
      BudgetGroup.livingExpense => cs.tertiary,
      BudgetGroup.variableOptional => cs.secondary,
      BudgetGroup.savings => cs.primary,
    };
  }
}

// ===========================================================================
// Accounts
// ===========================================================================

class _AccountsCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _AccountsCard({required this.presenter});

  IconData _icon(FinancialAccount a) => switch (a.category) {
        AccountCategory.bank => Icons.account_balance_outlined,
        AccountCategory.ewallet => Icons.phone_android_outlined,
        AccountCategory.cash => Icons.payments_outlined,
        AccountCategory.creditCard => Icons.credit_card_outlined,
        AccountCategory.creditLine => Icons.credit_score_outlined,
        AccountCategory.bnpl => Icons.shopping_bag_outlined,
        _ => Icons.account_balance_wallet_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final liquid = presenter.liquidAccounts;
    final credit = presenter.creditAccounts;
    final held = presenter.heldAmountByAccountId;

    final accounts = [...liquid, ...credit];
    if (accounts.isEmpty) {
      return const WebCard(
        title: 'Accounts',
        description: 'Liquid balances & credit available',
        child: _CardEmpty(
          icon: Icons.account_balance_wallet_outlined,
          text: 'No accounts yet',
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < accounts.length; i++) {
      final a = accounts[i];
      if (i > 0) {
        rows.add(Divider(
            height: WebInsets.xl,
            color: cs.outlineVariant.withValues(alpha: 0.35)));
      }
      final isCredit = a.isLiability;
      final shownHeld = held[a.id] ?? 0;
      final value =
          isCredit ? (a.availableCredit ?? a.balance) : (a.balance - shownHeld);
      rows.add(Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(_icon(a), size: 18, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: WebInsets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (isCredit)
                  Text('Available limit',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Text(
            formatPeso(value),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isCredit ? cs.primary : cs.onSurface,
            ),
          ),
          if (isCredit) ...[
            const SizedBox(width: WebInsets.sm),
            const WebBadge('Credit', tone: WebBadgeTone.info),
          ],
        ],
      ));
    }

    return WebCard(
      title: 'Accounts',
      description: 'Liquid balances & credit available',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          const SizedBox(height: WebInsets.lg),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: WebInsets.md, vertical: WebInsets.sm),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                Text('LIQUID CASH',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    )),
                const Spacer(),
                Text(formatPeso(presenter.totalLiquidCash),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Daily Spending
// ===========================================================================

class _DailySpendingCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _DailySpendingCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final days = presenter.last7DaysSpending;
    final total = days.fold<double>(0, (s, d) => s + d.amount);
    final values = days.map((d) => d.amount).toList();
    final labels = [
      for (final d in days) '${d.date.month}/${d.date.day}',
    ];
    final hasData = total > 0;

    return WebCard(
      title: 'Daily Spending',
      description:
          hasData ? 'Last 7 days · ${formatPeso(total)} total' : 'Last 7 days',
      child: hasData
          ? WebLineChart(
              values: values,
              bottomLabels: labels,
              area: false,
              leftLabelFormat: formatPesoCompact,
              minY: 0,
              height: 200,
            )
          : const _CardEmpty(
              icon: Icons.show_chart_rounded,
              text: 'No spending recorded in the last 7 days',
            ),
    );
  }
}

// ===========================================================================
// Cash Flow
// ===========================================================================

class _CashFlowCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _CashFlowCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = presenter;
    final income = p.monthTotalInflow;
    final expenses = p.monthTotalOutflow;
    final net = p.monthNetCashFlow;
    final rate = p.savingsRate;
    final spentPct = income > 0 ? (expenses / income).clamp(0.0, 1.0) : 0.0;
    final spentPctLabel =
        income > 0 ? '${(expenses / income * 100).round()}%' : '—';

    return WebCard(
      title: 'Cash Flow',
      description: 'Income vs spending for ${monthLabel(p.currentMonth)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatGrid(items: [
            _MiniStat(
              label: 'Income',
              value: formatPeso(income),
              icon: Icons.south_rounded,
              valueColor: cs.tertiary,
            ),
            _MiniStat(
              label: 'Expenses',
              value: formatPeso(expenses),
              icon: Icons.north_rounded,
            ),
            _MiniStat(
              label: 'Net Flow',
              value: formatPeso(net),
              icon: Icons.swap_vert_rounded,
              valueColor: net >= 0 ? cs.tertiary : cs.error,
            ),
            _MiniStat(
              label: 'Savings Rate',
              value: rate == null ? '—' : '${(rate * 100).toStringAsFixed(1)}%',
              icon: Icons.percent_rounded,
            ),
          ]),
          const SizedBox(height: WebInsets.lg),
          Row(
            children: [
              Text('Spent $spentPctLabel of income',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
              const Spacer(),
              Text('${formatPeso(expenses)} / ${formatPeso(income)}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: WebInsets.sm),
          WebProgressBar(
            value: spentPct.toDouble(),
            color: spentPct >= 1.0 ? cs.error : cs.tertiary,
            height: 8,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Where Your Money Goes
// ===========================================================================

class _WhereMoneyGoesCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _WhereMoneyGoesCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final spend = presenter.categorySpendThisMonth;
    if (spend.isEmpty) {
      return WebCard(
        title: 'Where Your Money Goes',
        description: 'Top spending in ${monthLabel(presenter.currentMonth)}',
        child: const _CardEmpty(
          icon: Icons.donut_large_rounded,
          text: 'No expenses recorded this month',
        ),
      );
    }

    final total = spend.fold<double>(0, (s, e) => s + e.$2);
    final slices = <WebChartSlice>[
      for (var i = 0; i < spend.length; i++)
        WebChartSlice(
          label: spend[i].$1.name,
          value: spend[i].$2,
          color: resolveSliceColor(spend[i].$1.colorHex, i,
              brightness: Theme.of(context).brightness),
        ),
    ];

    return WebCard(
      title: 'Where Your Money Goes',
      description: 'Top spending in ${monthLabel(presenter.currentMonth)}',
      child: WebDonutChart(
        slices: slices,
        centerLabel: 'Spent',
        centerValue: formatPesoCompact(total),
        size: 168,
      ),
    );
  }
}

// ===========================================================================
// Savings Goals
// ===========================================================================

class _SavingsGoalsCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _SavingsGoalsCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Goal accounts (with targets) first, then savings accounts.
    final goals = [
      ...presenter.goalAccounts,
      ...presenter.savingsAccounts,
    ].where((a) => (a.goalTarget ?? 0) > 0).toList();

    if (goals.isEmpty) {
      return const WebCard(
        title: 'Savings Goals',
        description: 'Progress toward your targets',
        child: _CardEmpty(
          icon: Icons.flag_outlined,
          text: 'No savings goals with a target set',
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < goals.length; i++) {
      final a = goals[i];
      final target = a.goalTarget ?? 0;
      final progress = target > 0 ? (a.balance / target).clamp(0.0, 1.0) : 0.0;
      final pct = target > 0 ? (a.balance / target * 100).round() : 0;
      final color = resolveSliceColor(a.colorHex, i,
          brightness: Theme.of(context).brightness);
      if (i > 0) rows.add(const SizedBox(height: WebInsets.lg));
      rows.add(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text(formatPeso(a.balance),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: WebInsets.xs),
          Row(
            children: [
              Expanded(
                child: Text('of ${formatPeso(target)}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ),
              Text('$pct%',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: WebInsets.sm),
          WebProgressBar(value: progress.toDouble(), color: color, height: 6),
        ],
      ));
    }

    return WebCard(
      title: 'Savings Goals',
      description: 'Progress toward your targets',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

// ===========================================================================
// Shared page-private helpers
// ===========================================================================

/// A simple responsive grid that flows [children] into [columns] equal-width
/// cells with [spacing] between them. Each row stretches its cells to equal
/// height via IntrinsicHeight.
class _GridFlow extends StatelessWidget {
  final int columns;
  final double spacing;
  final List<Widget> children;
  const _GridFlow({
    required this.columns,
    required this.spacing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice =
          children.sublist(i, (i + columns).clamp(0, children.length).toInt());
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        if (c > 0) cells.add(SizedBox(width: spacing));
        cells.add(Expanded(
          child: c < slice.length ? slice[c] : const SizedBox.shrink(),
        ));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(IntrinsicHeight(
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// 2-column grid of [_MiniStat]s used inside the Cash Flow card.
class _StatGrid extends StatelessWidget {
  final List<_MiniStat> items;
  const _StatGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final a = items[i];
      final b = i + 1 < items.length ? items[i + 1] : null;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: WebInsets.lg));
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: WebInsets.lg),
          Expanded(child: b ?? const SizedBox.shrink()),
        ],
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: cs.onSurfaceVariant),
            const SizedBox(width: WebInsets.xs),
            Expanded(
              child: Text(label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  )),
            ),
          ],
        ),
        const SizedBox(height: WebInsets.xs),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor ?? cs.onSurface,
            )),
      ],
    );
  }
}

class _CardEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CardEmpty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: 140,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 28, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: WebInsets.sm),
            Text(text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WebInsets.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: WebInsets.lg),
            Text('No accounts yet',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: WebInsets.sm),
            Text(
              'Add an account to start tracking your financial position.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
