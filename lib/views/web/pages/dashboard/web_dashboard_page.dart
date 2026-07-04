import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
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
              _AccountBalancesRow(presenter: presenter),
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
      // Budget Allocated (this month's total planned spend) replaces the old
      // "Current Obligations" tile, which was a straight alias of the Month-End
      // Outlook's "Upcoming Bills" figure and so duplicated it.
      WebStatTile(
        label: 'Budget Allocated',
        value: formatPeso(p.totalBudgetAllocated),
        sub: 'Planned spend this month',
        icon: Icons.pie_chart_outline_rounded,
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
        value: formatPeso(p.budgetedExpensesRemaining),
        sub: 'Set-asides still to fund',
        icon: Icons.savings_outlined,
      ),
      WebStatTile(
        label: 'Proj. Month-End Cash',
        value: formatPeso(p.forecastedNetBalance),
        sub: 'After bills, budget & savings',
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
    // One priority-ordered list — the masonry packs each card into whichever
    // column is currently shortest, so a short card (Cash Flow, Budget Health)
    // no longer leaves the other column trailing off into whitespace. Order
    // roughly follows visual priority; balancing decides the final placement.
    // Accounts already moved up to the _AccountBalancesRow.
    final cards = <Widget>[
      _CashFlowCard(presenter: presenter),
      _IncomeExpensesCard(presenter: presenter),
      _BudgetHealthCard(presenter: presenter),
      _DailySpendingCard(presenter: presenter),
      if (presenter.creditAccounts.isNotEmpty)
        _CreditCard(presenter: presenter),
      _WhereMoneyGoesCard(presenter: presenter),
      _SavingsGoalsCard(presenter: presenter),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < minWidth ? 1 : 2;
        return _MasonryFlow(
          columns: columns,
          columnSpacing: WebInsets.xl,
          runSpacing: WebInsets.xl,
          children: cards,
        );
      },
    );
  }
}

// ===========================================================================
// Masonry — height-balanced multi-column flow
// ===========================================================================

/// Lays [children] out in [columns] equal-width columns, placing each child
/// into the currently-shortest column. Unlike a fixed two-list split, a short
/// card doesn't strand the other column in whitespace — the columns stay
/// balanced. Measures real child heights (charts, variable row counts), so no
/// height estimation is needed. With `columns == 1` it degrades to a plain
/// vertical stack.
class _MasonryFlow extends MultiChildRenderObjectWidget {
  final int columns;
  final double columnSpacing;
  final double runSpacing;

  const _MasonryFlow({
    required this.columns,
    required this.columnSpacing,
    required this.runSpacing,
    required super.children,
  });

  @override
  _RenderMasonry createRenderObject(BuildContext context) => _RenderMasonry(
        columns: columns,
        columnSpacing: columnSpacing,
        runSpacing: runSpacing,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderMasonry renderObject) {
    renderObject
      ..columns = columns
      ..columnSpacing = columnSpacing
      ..runSpacing = runSpacing;
  }
}

class _MasonryParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderMasonry extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MasonryParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MasonryParentData> {
  _RenderMasonry({
    required int columns,
    required double columnSpacing,
    required double runSpacing,
  })  : _columns = columns,
        _columnSpacing = columnSpacing,
        _runSpacing = runSpacing;

  int _columns;
  int get columns => _columns;
  set columns(int value) {
    if (_columns == value) return;
    _columns = value;
    markNeedsLayout();
  }

  double _columnSpacing;
  double get columnSpacing => _columnSpacing;
  set columnSpacing(double value) {
    if (_columnSpacing == value) return;
    _columnSpacing = value;
    markNeedsLayout();
  }

  double _runSpacing;
  double get runSpacing => _runSpacing;
  set runSpacing(double value) {
    if (_runSpacing == value) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MasonryParentData) {
      child.parentData = _MasonryParentData();
    }
  }

  double _columnWidth(double maxWidth) =>
      (maxWidth - _columnSpacing * (_columns - 1)) / _columns;

  int _shortestColumn(List<double> heights) {
    var shortest = 0;
    for (var c = 1; c < heights.length; c++) {
      if (heights[c] < heights[shortest]) shortest = c;
    }
    return shortest;
  }

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth;
    final columnWidth = _columnWidth(maxWidth);
    final childConstraints =
        BoxConstraints(minWidth: columnWidth, maxWidth: columnWidth);
    final heights = List<double>.filled(_columns, 0.0);

    var child = firstChild;
    while (child != null) {
      final pd = child.parentData! as _MasonryParentData;
      child.layout(childConstraints, parentUsesSize: true);
      final col = _shortestColumn(heights);
      final dx = col * (columnWidth + _columnSpacing);
      final dy = heights[col] == 0 ? 0.0 : heights[col] + _runSpacing;
      pd.offset = Offset(dx, dy);
      heights[col] = dy + child.size.height;
      child = pd.nextSibling;
    }

    final tallest =
        heights.isEmpty ? 0.0 : heights.reduce((a, b) => a > b ? a : b);
    size = constraints.constrain(Size(maxWidth, tallest));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
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
// Credit (cards / lines / BNPL)
// ===========================================================================

/// Surfaces the credit intelligence the presenter already computes — owed,
/// utilization, available/limit, and the next due date + minimum due — which the
/// web dashboard previously hid (it showed only an "available limit" figure in
/// the accounts card). Mirrors the mobile `_CreditSection`.
class _CreditCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _CreditCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final accounts = presenter.creditAccounts;
    final rows = <Widget>[];
    for (var i = 0; i < accounts.length; i++) {
      if (i > 0) rows.add(const SizedBox(height: WebInsets.lg));
      final a = accounts[i];
      rows.add(_CreditAccountRow(
        account: a,
        dueInfo: presenter.creditDueInfo(a),
        minimumDue: presenter.creditMinimumDue(a),
      ));
    }

    return WebCard(
      title: 'Credit',
      description:
          'Owe ${formatPeso(presenter.totalCreditOwed)} · ${formatPeso(presenter.totalCreditAvailable)} available',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _CreditAccountRow extends StatelessWidget {
  final FinancialAccount account;
  final ({String label, bool imminent})? dueInfo;
  final double? minimumDue;

  const _CreditAccountRow({
    required this.account,
    required this.dueInfo,
    required this.minimumDue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final utilization = account.utilization;
    final available = account.availableCredit;
    final due = dueInfo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.credit_card_outlined, color: cs.error, size: 18),
            const SizedBox(width: WebInsets.sm),
            Expanded(
              child: Text(
                account.name,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Owe',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                Text(
                  formatPeso(account.currentPayable),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (utilization != null) ...[
          const SizedBox(height: WebInsets.md),
          WebProgressBar(
            value: utilization.clamp(0.0, 1.0),
            color: utilization >= 0.9 ? cs.error : cs.primary,
          ),
          const SizedBox(height: WebInsets.xs),
          Text(
            '${formatPeso(available ?? 0)} of ${formatPeso(account.creditLimit ?? 0)} available',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (due != null) ...[
          const SizedBox(height: WebInsets.sm),
          Row(
            children: [
              Icon(Icons.event_outlined,
                  size: 14,
                  color: due.imminent ? cs.error : cs.onSurfaceVariant),
              const SizedBox(width: WebInsets.xs),
              Text(
                minimumDue != null
                    ? '${due.label} · min ${formatPeso(minimumDue!)}'
                    : due.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: due.imminent ? cs.error : cs.onSurfaceVariant,
                  fontWeight: due.imminent ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ===========================================================================
// Budget Health
// ===========================================================================

class _BudgetHealthCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _BudgetHealthCard({required this.presenter});

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

    final budgetGroups = presenter.budgetGroups;
    final active = budgetGroups
        .where((g) => (allocated[g.id] ?? 0) > 0 || (spent[g.id] ?? 0) > 0)
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
      final alloc = allocated[g.id] ?? 0;
      final spnt = spent[g.id] ?? 0;
      final ratio = alloc > 0 ? (spnt / alloc) : 0.0;
      final left = (alloc - spnt).clamp(0.0, double.infinity);
      final pct = alloc > 0 ? (spnt / alloc * 100).round() : 0;
      final dot = _groupColor(cs, i, ratio);
      if (i > 0) rows.add(const SizedBox(height: WebInsets.lg));
      rows.add(WebBudgetRow(
        dotColor: dot,
        name: g.name,
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

  Color _groupColor(ColorScheme cs, int index, double ratio) {
    if (ratio >= 1.0) return cs.error;
    if (ratio >= 0.85) return cs.secondary;
    return [cs.primary, cs.tertiary, cs.secondary, cs.primary][index % 4];
  }
}

// ===========================================================================
// Account balances — glanceable cards below the Month-End Outlook
// ===========================================================================

IconData _accountIcon(FinancialAccount a) => switch (a.category) {
      AccountCategory.bank => Icons.account_balance_outlined,
      AccountCategory.ewallet => Icons.phone_android_outlined,
      AccountCategory.cash => Icons.payments_outlined,
      AccountCategory.savings => Icons.savings_outlined,
      AccountCategory.goal => Icons.flag_outlined,
      AccountCategory.timeDeposit => Icons.lock_clock_outlined,
      AccountCategory.investment => Icons.trending_up_rounded,
      AccountCategory.custodian => Icons.people_outline_rounded,
      AccountCategory.creditCard => Icons.credit_card_outlined,
      AccountCategory.creditLine => Icons.credit_score_outlined,
      AccountCategory.bnpl => Icons.shopping_bag_outlined,
    };

String _accountCategoryLabel(FinancialAccount a) => switch (a.category) {
      AccountCategory.bank => 'Bank',
      AccountCategory.ewallet => 'E-wallet',
      AccountCategory.cash => 'Cash',
      AccountCategory.savings => 'Savings',
      AccountCategory.goal => 'Goal',
      AccountCategory.timeDeposit => 'Time deposit',
      AccountCategory.investment => 'Investment',
      AccountCategory.custodian => 'Custodian',
      AccountCategory.creditCard => 'Credit card',
      AccountCategory.creditLine => 'Credit line',
      AccountCategory.bnpl => 'BNPL',
    };

/// Renders every liquid + credit account as its own compact balance card in a
/// responsive grid, placed directly under the Month-End Outlook so the user can
/// see all balances at a glance without scrolling into the content columns.
class _AccountBalancesRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _AccountBalancesRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final held = presenter.heldAmountByAccountId;
    final accounts = [...presenter.liquidAccounts, ...presenter.creditAccounts];
    if (accounts.isEmpty) return const SizedBox.shrink();

    final tiles = [
      for (final a in accounts) _tile(context, a, held[a.id] ?? 0),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.only(bottom: WebInsets.md, left: WebInsets.xs),
          child: Row(
            children: [
              Text('Accounts',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${formatPeso(presenter.totalLiquidCash)} liquid cash',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
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

  Widget _tile(BuildContext context, FinancialAccount a, double held) {
    final cs = Theme.of(context).colorScheme;
    final isCredit = a.isLiability;
    // Credit shows what's still available to spend; liquid shows spendable cash
    // (balance minus any amount ring-fenced by linked custodians / holds).
    final value =
        isCredit ? (a.availableCredit ?? a.balance) : (a.balance - held);
    final sub = isCredit
        ? 'Available credit'
        : (held > 0
            ? '${_accountCategoryLabel(a)} · ${formatPeso(held)} held'
            : _accountCategoryLabel(a));
    return WebStatTile(
      label: a.name,
      value: formatPeso(value),
      sub: sub,
      icon: _accountIcon(a),
      valueColor: isCredit ? cs.primary : null,
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
