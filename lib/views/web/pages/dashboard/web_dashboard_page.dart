import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';
import 'web_afford_checker.dart';
import 'web_dashboard_charts.dart';

/// Web Dashboard page (Plan 050-A). Desktop-grade financial overview: KPI
/// strips, fl_chart visuals, an accounts table, and the "Can I afford it?"
/// tool. All figures come from [TreasuryDashboardPresenter] getters — no math
/// in `build()`. Theme-aware throughout (works in dark and light).
class WebDashboardPage extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const WebDashboardPage({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (presenter.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(WebInsets.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebSectionHeader(
                title: 'Dashboard',
                subtitle:
                    'Your financial position — ${monthLabel(presenter.currentMonth)}.',
              ),
              _PositionStrip(presenter: presenter),
              const SizedBox(height: WebInsets.xl),
              _MonthStrip(presenter: presenter),
              const SizedBox(height: WebInsets.xl),
              _VisualsRow(presenter: presenter),
              const SizedBox(height: WebInsets.xl),
              _AccountsTable(presenter: presenter),
              const SizedBox(height: WebInsets.xl),
              WebAffordChecker(presenter: presenter),
            ],
          ),
        );
      },
    );
  }
}

/// A strip of KPI tiles laid out in balanced full rows (no card left hanging
/// alone on the last row) via [WebStatGrid].
class _StatStrip extends StatelessWidget {
  final List<Widget> tiles;
  const _StatStrip({required this.tiles});

  @override
  Widget build(BuildContext context) => WebStatGrid(tiles: tiles);
}

class _PositionStrip extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _PositionStrip({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _StatStrip(
      tiles: [
        WebStatTile(
          label: 'NET WORTH',
          value: formatPeso(presenter.netWorth),
          icon: Icons.account_balance_wallet_outlined,
          emphasize: true,
          valueColor: presenter.netWorth < 0 ? cs.error : null,
        ),
        WebStatTile(
          label: 'LIQUID CASH',
          value: formatPeso(presenter.totalLiquidCash),
          icon: Icons.payments_outlined,
        ),
        WebStatTile(
          label: 'TOTAL ASSETS',
          value: formatPeso(presenter.totalAssets),
          icon: Icons.savings_outlined,
        ),
        WebStatTile(
          label: 'CURRENT OBLIGATIONS',
          value: formatPeso(presenter.currentObligations),
          icon: Icons.receipt_long_outlined,
          valueColor: presenter.currentObligations > 0 ? cs.secondary : null,
        ),
      ],
    );
  }
}

class _MonthStrip extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _MonthStrip({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final savingsRate = presenter.savingsRate;
    final netFlow = presenter.monthNetCashFlow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WebSectionHeader(title: 'This month'),
        _StatStrip(
          tiles: [
            WebStatTile(
              label: 'INCOME',
              value: formatPeso(presenter.monthTotalInflow),
              icon: Icons.arrow_downward,
            ),
            WebStatTile(
              label: 'EXPENSES',
              value: formatPeso(presenter.monthTotalOutflow),
              icon: Icons.arrow_upward,
            ),
            WebStatTile(
              label: 'NET CASH FLOW',
              value: formatPeso(netFlow),
              icon: Icons.swap_vert,
              valueColor: netFlow < 0 ? cs.error : cs.tertiary,
            ),
            WebStatTile(
              label: 'SAVINGS RATE',
              value: savingsRate == null
                  ? '—'
                  : '${(savingsRate * 100).toStringAsFixed(0)}%',
              icon: Icons.percent,
            ),
            WebStatTile(
              label: 'PROJECTED SPARE',
              value: formatPeso(presenter.projectedSpareThisMonth),
              icon: Icons.account_balance_outlined,
              valueColor:
                  presenter.projectedSpareThisMonth < 0 ? cs.error : null,
            ),
            WebStatTile(
              label: 'OUTSTANDING BILLS',
              value: formatPeso(presenter.monthUnpaidBills),
              icon: Icons.event_note_outlined,
            ),
            WebStatTile(
              label: 'OUTSTANDING BUDGET',
              value: formatPeso(presenter.totalBudgetRemaining),
              icon: Icons.pie_chart_outline,
            ),
            WebStatTile(
              label: 'RECEIVABLES',
              value: formatPeso(presenter.pendingReceivables),
              icon: Icons.call_received,
            ),
          ],
        ),
      ],
    );
  }
}

class _VisualsRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _VisualsRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      WebCard(
        title: 'Expenses by category',
        description: 'Where this month went.',
        child: ExpenseByCategoryDonut(
          slices: presenter.categorySpendThisMonth,
        ),
      ),
      WebCard(
        title: 'Last 30 days',
        description: 'Daily spending.',
        child: Last30DaySpendChart(days: presenter.lastNDaysSpending(30)),
      ),
      WebCard(
        title: 'Budget by group',
        description: 'Allocated vs spent.',
        child: BudgetByGroupChart(
          allocated: presenter.budgetAllocatedByGroup,
          spent: presenter.budgetSpentByGroup,
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Three across on wide desktops, otherwise stack to full width.
        final wide = constraints.maxWidth >= 900;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: WebInsets.lg),
                cards[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: WebInsets.lg),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }
}

class _AccountsTable extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  const _AccountsTable({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return WebCard(
      title: 'Accounts',
      description: 'Balances, money held for others, and credit available.',
      child: WebDataTable<DashboardAccountRow>(
        rows: presenter.dashboardAccountRows,
        emptyLabel: 'No accounts yet.',
        columns: [
          WebColumn<DashboardAccountRow>(
            label: 'Account',
            flex: 3,
            cell: (context, row) => _AccountNameCell(row: row),
          ),
          WebColumn<DashboardAccountRow>(
            label: 'Balance',
            numeric: true,
            flex: 2,
            cell: (context, row) => Text(formatPeso(row.balance)),
          ),
          WebColumn<DashboardAccountRow>(
            label: 'Held',
            numeric: true,
            flex: 2,
            cell: (context, row) => _HeldCell(row: row),
          ),
          WebColumn<DashboardAccountRow>(
            label: 'Yours',
            numeric: true,
            flex: 2,
            cell: (context, row) => _YoursCell(row: row),
          ),
        ],
      ),
    );
  }
}

class _AccountNameCell extends StatelessWidget {
  final DashboardAccountRow row;
  const _AccountNameCell({required this.row});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(row.name, overflow: TextOverflow.ellipsis),
        ),
        if (row.isCredit) ...[
          const SizedBox(width: WebInsets.sm),
          const WebBadge('Credit', tone: WebBadgeTone.info),
        ],
      ],
    );
  }
}

class _HeldCell extends StatelessWidget {
  final DashboardAccountRow row;
  const _HeldCell({required this.row});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (row.isCredit || row.held <= 0) {
      return Text('—', style: TextStyle(color: cs.onSurfaceVariant));
    }
    return Text(formatPeso(row.held),
        style: TextStyle(color: cs.onSurfaceVariant));
  }
}

class _YoursCell extends StatelessWidget {
  final DashboardAccountRow row;
  const _YoursCell({required this.row});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label =
        row.isCredit ? '${formatPeso(row.yours)} avail' : formatPeso(row.yours);
    return Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: row.isCredit ? cs.tertiary : cs.onSurface,
      ),
    );
  }
}
