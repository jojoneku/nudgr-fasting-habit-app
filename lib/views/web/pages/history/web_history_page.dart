import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';
import 'history_trend_chart.dart';
import 'month_detail_dialog.dart';

/// Web History page (Plan 050-E): a KPI strip, a net-cash-flow trend chart, and
/// a sortable monthly-summary table. Row click opens the existing month detail
/// as a desktop dialog. All math lives in [TreasuryHistoryPresenter].
class WebHistoryPage extends StatelessWidget {
  final TreasuryHistoryPresenter presenter;
  const WebHistoryPage({super.key, required this.presenter});

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
              const WebSectionHeader(
                title: 'History',
                subtitle: 'Month-by-month cash flow, savings, and trends.',
              ),
              _KpiStrip(presenter: presenter),
              const SizedBox(height: WebInsets.xl),
              _TrendCard(presenter: presenter),
              const SizedBox(height: WebInsets.xl),
              _SummaryTableCard(presenter: presenter),
            ],
          ),
        );
      },
    );
  }
}

// ─── KPI strip ──────────────────────────────────────────────────────────────

class _KpiStrip extends StatelessWidget {
  final TreasuryHistoryPresenter presenter;
  const _KpiStrip({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cumulative = presenter.cumulativeNetSavings;
    final avgNet = presenter.averageNetSavings;
    final avgRate = presenter.averageSavingsRate;
    final monthCount = presenter.summaries.length;

    final tiles = <Widget>[
      WebStatTile(
        label: 'Cumulative net',
        value: _signedPeso(cumulative),
        valueColor: _toneColor(cs, cumulative),
        sub: '$monthCount closed ${monthCount == 1 ? 'month' : 'months'}',
        icon: Icons.savings_outlined,
        emphasize: true,
      ),
      WebStatTile(
        label: 'Avg net / month',
        value: _signedPeso(avgNet),
        valueColor: _toneColor(cs, avgNet),
        icon: Icons.trending_up,
      ),
      WebStatTile(
        label: 'Avg savings rate',
        value: _percent(avgRate),
        valueColor: _toneColor(cs, avgRate),
        icon: Icons.percent,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth < 720 ? 1 : tiles.length;
        const spacing = WebInsets.lg;
        final tileWidth =
            (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final t in tiles) SizedBox(width: tileWidth, child: t),
          ],
        );
      },
    );
  }
}

// ─── Trend chart ──────────────────────────────────────────────────────────────

class _TrendCard extends StatelessWidget {
  final TreasuryHistoryPresenter presenter;
  const _TrendCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final points = presenter.trendPoints;
    if (points.isEmpty) {
      return const WebCard(
        title: 'Cash flow trend',
        description: 'Income, expenses, and net savings across closed months.',
        child: _EmptyHint(
          text: 'Trends appear once you have at least one closed month.',
        ),
      );
    }
    return WebCard(
      title: 'Cash flow trend',
      description: 'Income, expenses, and net savings across closed months.',
      child: HistoryTrendChart(
        points: points,
        bound: presenter.trendMaxMagnitude,
      ),
    );
  }
}

// ─── Summary table ──────────────────────────────────────────────────────────────

class _SummaryTableCard extends StatelessWidget {
  final TreasuryHistoryPresenter presenter;
  const _SummaryTableCard({required this.presenter});

  @override
  Widget build(BuildContext context) {
    // summaries is already sorted most-recent first by the presenter.
    final rows = presenter.summaries;
    return WebCard(
      title: 'Monthly summaries',
      description: 'Most recent first. Click a month for the full breakdown.',
      child: WebDataTable<MonthlySummary>(
        rows: rows,
        emptyLabel: 'No closed months yet.',
        onRowTap: (row) => showMonthDetailDialog(
          context,
          summary: row,
          categories: presenter.categories,
          accounts: presenter.accounts,
        ),
        columns: [
          WebColumn<MonthlySummary>(
            label: 'Month',
            flex: 3,
            cell: (context, row) => Text(
              monthLabel(row.month),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          WebColumn<MonthlySummary>(
            label: 'Income',
            numeric: true,
            flex: 2,
            cell: (context, row) => _PesoText(
              value: row.totalInflow,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
          WebColumn<MonthlySummary>(
            label: 'Expenses',
            numeric: true,
            flex: 2,
            cell: (context, row) => _PesoText(
              value: row.totalOutflow,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          WebColumn<MonthlySummary>(
            label: 'Net',
            numeric: true,
            flex: 2,
            cell: (context, row) => _NetText(value: row.netSavings),
          ),
          WebColumn<MonthlySummary>(
            label: 'Savings rate',
            numeric: true,
            flex: 2,
            cell: (context, row) =>
                _RateBadge(rate: presenter.savingsRate(row)),
          ),
        ],
      ),
    );
  }
}

// ─── Leaf cells (presentational sign→color mapping only) ───────────────────────

class _PesoText extends StatelessWidget {
  final double value;
  final Color color;
  const _PesoText({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      formatPeso(value),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
    );
  }
}

class _NetText extends StatelessWidget {
  final double value;
  const _NetText({required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      _signedPeso(value),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _toneColor(cs, value),
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _RateBadge extends StatelessWidget {
  final double rate;
  const _RateBadge({required this.rate});

  @override
  Widget build(BuildContext context) {
    final tone = rate < 0
        ? WebBadgeTone.danger
        : (rate >= 0.2 ? WebBadgeTone.success : WebBadgeTone.neutral);
    return Align(
      alignment: Alignment.centerRight,
      child: WebBadge(_percent(rate), tone: tone),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebInsets.xxl),
      child: Center(
        child: Text(
          text,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ─── Pure formatting helpers ──────────────────────────────────────────────────

String _signedPeso(double v) {
  final prefix = v < 0 ? '−' : '+';
  return '$prefix${formatPeso(v.abs())}';
}

String _percent(double ratio) => '${(ratio * 100).toStringAsFixed(0)}%';

Color _toneColor(ColorScheme cs, double v) => v < 0 ? cs.error : cs.tertiary;
