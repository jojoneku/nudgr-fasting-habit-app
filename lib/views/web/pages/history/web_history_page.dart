import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';

/// Web History page (Plan 050-E).
///
/// A month-by-month view of closed months: aggregate stat tiles, a tri-series
/// cash-flow trend (income / expenses / net), an ending-cash trend, the monthly
/// summary table, and a 6-month category average breakdown.
///
/// Backed entirely by [TreasuryHistoryPresenter] — closed [MonthlySummary]
/// records (`summaries`) plus the live `currentMonthSummary`, joined to
/// `categories` for the per-category breakdown. The presenter has no net-worth
/// series, so the trend uses each month's `endingCash` (liquid balance) and is
/// labelled honestly as "Ending Cash".
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

        // Closed months, oldest → newest (presenter.summaries is newest-first).
        final months = presenter.summaries.reversed.toList();
        final current = presenter.currentMonthSummary;

        if (months.isEmpty && current == null) {
          return const _HistoryEmptyState();
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: double.infinity),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(WebInsets.xxl),
              child: _HistoryBody(
                months: months,
                current: current,
                categories: presenter.categories,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(WebInsets.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_outlined,
                  size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: WebInsets.lg),
              Text(
                'No history yet',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: WebInsets.sm),
              Text(
                'Monthly summaries appear here after each month closes.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A computed view-row for a single month (one [MonthlySummary]).
class _MonthRow {
  final String month;
  final double income;
  final double expenses;
  final double net;
  final double rate; // net / income, 0 when no income
  final double endingCash;
  final bool isLive;

  _MonthRow(this.month, MonthlySummary s, {this.isLive = false})
      : income = s.totalInflow,
        expenses = s.totalOutflow,
        net = s.netSavings,
        rate = s.totalInflow > 0 ? s.netSavings / s.totalInflow : 0,
        endingCash = s.endingCash;

  String get label => _shortMonth(month);
}

class _HistoryBody extends StatelessWidget {
  final List<MonthlySummary> months; // oldest → newest
  final MonthlySummary? current;
  final List<FinanceCategory> categories;

  const _HistoryBody({
    required this.months,
    required this.current,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 1000;

    // Build the full chronological series: closed months + the live month.
    final rows = <_MonthRow>[
      for (final s in months) _MonthRow(s.month, s),
      if (current != null) _MonthRow(current!.month, current!, isLive: true),
    ];

    final closedCount = months.length;
    final spanLabel = rows.isEmpty
        ? ''
        : rows.length == 1
            ? monthLabel(rows.first.month)
            : '${_shortMonth(rows.first.month)} – ${_shortMonth(rows.last.month)}';

    // Aggregates (over the series shown).
    final avgNet = rows.isEmpty
        ? 0.0
        : rows.fold<double>(0, (s, r) => s + r.net) / rows.length;
    final avgRate = rows.isEmpty
        ? 0.0
        : rows.fold<double>(0, (s, r) => s + r.rate) / rows.length;
    final cashGrowth =
        rows.length < 2 ? 0.0 : rows.last.endingCash - rows.first.endingCash;
    final best =
        rows.isEmpty ? null : rows.reduce((a, b) => b.net > a.net ? b : a);

    final upTone = cs.tertiary;
    final danger = cs.error;
    final neutralValue = cs.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebSectionHeader(
          title: 'History',
          subtitle: closedCount == 0
              ? 'Live month so far · $spanLabel'
              : 'Last ${rows.length} months · $spanLabel',
        ),

        // ── Stat strip ─────────────────────────────────────────────────────
        _StatStrip(
          tiles: [
            WebStatTile(
              label: 'Ending Cash Change',
              value: '${cashGrowth >= 0 ? '+' : '−'}'
                  '${formatPesoCompact(cashGrowth.abs())}',
              sub: 'Across the period',
              icon: Icons.savings_outlined,
              valueColor: cashGrowth >= 0 ? upTone : danger,
            ),
            WebStatTile(
              label: 'Avg Monthly Net',
              value: formatPesoCompact(avgNet),
              sub: 'Income − expenses',
              icon: Icons.swap_horiz,
              valueColor: avgNet >= 0 ? upTone : danger,
            ),
            WebStatTile(
              label: 'Avg Savings Rate',
              value: _pct(avgRate),
              sub: 'Of income kept',
              icon: Icons.percent,
            ),
            WebStatTile(
              label: 'Best Month',
              value:
                  best == null ? '—' : monthLabel(best.month).split(' ').first,
              sub: best == null
                  ? 'No data'
                  : '+${formatPesoCompact(best.net)} net',
              icon: Icons.trending_up,
            ),
          ],
        ),
        const SizedBox(height: WebInsets.xl),

        // ── Tri-series cash-flow trend ─────────────────────────────────────
        WebCard(
          title: 'Income vs Expenses vs Net',
          description: 'Monthly cash flow · $spanLabel',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebBarPairChart(
                groups: [
                  for (final r in rows)
                    (label: r.label, a: r.income, b: r.expenses),
                ],
                aColor: cs.tertiary,
                bColor: cs.error,
                aLabel: 'Income',
                bLabel: 'Expenses',
                leftLabelFormat: formatPesoCompact,
                height: 240,
              ),
            ],
          ),
        ),
        const SizedBox(height: WebInsets.xl),

        // ── Ending-cash trend (full-width, own row) ─────────────────────────
        _cashTrendCard(context, rows, cashGrowth),
        const SizedBox(height: WebInsets.xl),

        // ── Monthly summary + spending by category (side by side) ───────────
        if (isWide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _monthlyTableCard(
                        context, rows, neutralValue, upTone, danger)),
                const SizedBox(width: WebInsets.xl),
                Expanded(child: _categoryCard()),
              ],
            ),
          )
        else ...[
          _monthlyTableCard(context, rows, neutralValue, upTone, danger),
          const SizedBox(height: WebInsets.xl),
          _categoryCard(),
        ],
      ],
    );
  }

  Widget _categoryCard() => WebCard(
        title: 'Spending by Category',
        description: 'Average per month, with the latest month vs. average',
        child: _CategoryAverages(
          months: months,
          current: current,
          categories: categories,
        ),
      );

  Widget _cashTrendCard(
      BuildContext context, List<_MonthRow> rows, double growth) {
    return WebCard(
      title: 'Ending Cash Trend',
      description: 'Month-end liquid balance',
      trailing: WebBadge(
        '${growth >= 0 ? '+' : '−'}${formatPesoCompact(growth.abs())}',
        tone: growth >= 0 ? WebBadgeTone.success : WebBadgeTone.danger,
        icon: growth >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
      ),
      child: WebLineChart(
        values: [for (final r in rows) r.endingCash],
        bottomLabels: [for (final r in rows) r.label],
        leftLabelFormat: formatPesoCompact,
        area: true,
        height: 236,
      ),
    );
  }

  Widget _monthlyTableCard(
    BuildContext context,
    List<_MonthRow> rows,
    Color neutral,
    Color up,
    Color danger,
  ) {
    // Table reads newest-first.
    final tableRows = rows.reversed.toList();
    return WebCard(
      title: 'Monthly Summary',
      description: 'The numbers behind the trend',
      padding: const EdgeInsets.all(WebInsets.sm),
      child: WebDataTable<_MonthRow>(
        rows: tableRows,
        emptyLabel: 'No months recorded',
        columns: [
          WebColumn<_MonthRow>(
            label: 'Month',
            flex: 3,
            cell: (context, r) => Row(
              children: [
                Flexible(
                  child: Text(
                    r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (r.isLive) ...[
                  const SizedBox(width: WebInsets.sm),
                  const WebBadge('Live', tone: WebBadgeTone.info),
                ],
              ],
            ),
          ),
          WebColumn<_MonthRow>(
            label: 'Income',
            numeric: true,
            flex: 2,
            cell: (context, r) => Text(
              formatPesoCompact(r.income),
              style: TextStyle(color: up, fontWeight: FontWeight.w600),
            ),
          ),
          WebColumn<_MonthRow>(
            label: 'Expenses',
            numeric: true,
            flex: 2,
            cell: (context, r) => Text(formatPesoCompact(r.expenses)),
          ),
          WebColumn<_MonthRow>(
            label: 'Net',
            numeric: true,
            flex: 2,
            cell: (context, r) => Text(
              formatPesoCompact(r.net),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: r.net < 0 ? danger : neutral,
              ),
            ),
          ),
          WebColumn<_MonthRow>(
            label: 'Rate',
            numeric: true,
            flex: 2,
            cell: (context, r) => Text(
              _pct(r.rate),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Responsive stat strip: 4-up on wide, 2-up on medium, 1-up on narrow.
class _StatStrip extends StatelessWidget {
  final List<Widget> tiles;
  const _StatStrip({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 880 ? 4 : (w >= 520 ? 2 : 1);
        const gap = WebInsets.lg;
        final tileWidth = (w - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles) SizedBox(width: tileWidth, child: t),
          ],
        );
      },
    );
  }
}

/// A computed per-category average across closed months, with the latest
/// month's value for a "vs. average" comparison.
class _CatAgg {
  final String name;
  final Color color;
  final double avg;
  final double latest;

  _CatAgg(this.name, this.color, this.avg, this.latest);

  double get ratio => avg > 0 ? latest / avg : 0;
}

class _CategoryAverages extends StatelessWidget {
  final List<MonthlySummary> months; // oldest → newest closed
  final MonthlySummary? current;
  final List<FinanceCategory> categories;

  const _CategoryAverages({
    required this.months,
    required this.current,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final series = <MonthlySummary>[...months, if (current != null) current!];
    if (series.isEmpty) {
      return _placeholder(context, 'No spending recorded yet.');
    }

    final catById = {for (final c in categories) c.id: c};
    final latest = series.last;

    // Aggregate spend per category across the series.
    final totals = <String, double>{};
    for (final m in series) {
      m.categorySpend.forEach((id, v) {
        totals[id] = (totals[id] ?? 0) + v;
      });
    }
    if (totals.isEmpty) {
      return _placeholder(context, 'No categorised spending yet.');
    }

    final aggs = <_CatAgg>[];
    totals.forEach((id, total) {
      final cat = catById[id];
      aggs.add(_CatAgg(
        cat?.name ?? 'Uncategorised',
        _parseHex(cat?.colorHex) ?? cs.primary,
        total / series.length,
        latest.categorySpend[id] ?? 0,
      ));
    });
    aggs.sort((a, b) => b.avg.compareTo(a.avg));

    final maxAvg = aggs.first.avg;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < aggs.length; i++) ...[
          if (i > 0) const SizedBox(height: WebInsets.lg),
          _CategoryRow(agg: aggs[i], maxAvg: maxAvg),
        ],
      ],
    );
  }

  Widget _placeholder(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebInsets.xl),
      child: Center(
        child: Text(
          message,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final _CatAgg agg;
  final double maxAvg;

  const _CategoryRow({required this.agg, required this.maxAvg});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final up = agg.latest > agg.avg * 1.05;
    final down = agg.latest < agg.avg * 0.95;
    final barColor = up ? cs.error : (down ? cs.tertiary : agg.color);
    final fraction = maxAvg > 0 ? (agg.avg / maxAvg).clamp(0.0, 1.0) : 0.0;

    final WebBadge badge = up
        ? WebBadge(_pct(agg.ratio),
            tone: WebBadgeTone.warning, icon: Icons.arrow_upward)
        : down
            ? WebBadge(_pct(agg.ratio),
                tone: WebBadgeTone.success, icon: Icons.arrow_downward)
            : WebBadge(_pct(agg.ratio), tone: WebBadgeTone.neutral);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: agg.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: WebInsets.sm),
            Expanded(
              child: Text(
                agg.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: WebInsets.sm),
            badge,
            const SizedBox(width: WebInsets.md),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: formatPesoCompact(agg.avg),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: '  / mo avg',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: WebInsets.sm),
        WebProgressBar(value: fraction, color: barColor),
        const SizedBox(height: WebInsets.xs),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Latest: ${formatPesoCompact(agg.latest)}',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

// ── Pure helpers ─────────────────────────────────────────────────────────────

String _pct(double fraction) => '${(fraction * 100).toStringAsFixed(0)}%';

/// Short month label from a 'YYYY-MM' key, e.g. '2026-06' → 'Jun 2026'.
String _shortMonth(String monthKey) {
  final full = monthLabel(monthKey); // 'June 2026'
  final parts = full.split(' ');
  if (parts.length != 2) return full;
  final name = parts[0];
  final abbr = name.length > 3 ? name.substring(0, 3) : name;
  return '$abbr ${parts[1]}';
}

Color? _parseHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final value = int.tryParse(h, radix: 16);
  return value == null ? null : Color(value);
}
