import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../web_keys.dart';
import '../../widgets/web_widgets.dart';
import 'web_month_detail_dialog_v2.dart';

/// Gap between cards — the canvas grid gap (20 px).
const double _gap = 20;

/// Under this content width the table and the two sparkline cards stack.
const double _threeColMin = 900;

/// Under this width the spending-by-category grid is one column. 720 keeps
/// each column ≥ 350 px, so a long category name, the vs-avg pill and the
/// amount share one line; beside the Nudgy rail (760 px) it is one column.
const double _twoColMin = 720;

/// Under this width the live card stacks its text above its three cells.
const double _liveCardSplitMin = 640;

/// How many closed months the range control shows. The presenter has no
/// notion of a range — it hands over every closed summary — so this is page
/// state that filters what was loaded. The live month is always shown.
enum _HistoryRange {
  threeMonths(3, '3 mo'),
  sixMonths(6, '6 mo'),
  twelveMonths(12, '12 mo'),
  all(null, 'All');

  final int? months;
  final String label;
  const _HistoryRange(this.months, this.label);
}

/// Web History, v2 (Plan 063 Phase 7) — the canvas layout in
/// `docs/design-reference/web-v2/History.dc.html`: header with a range
/// control, the live month full width on the Treasury gradient, one even
/// strip of five period stats, the cash-flow trend, then the monthly table
/// beside the two sparkline cards, and spending by category.
///
/// Every figure comes from the same [TreasuryHistoryPresenter] getters the
/// pre-v2 page read (`summaries`, `currentMonthSummary`, `categories`); this
/// file lays them out. Month detail opens from a table row and from the live
/// card; its "Open in Ledger" hands [onOpenLedgerMonth] the month key.
class WebHistoryPageV2 extends StatefulWidget {
  final TreasuryHistoryPresenter presenter;

  /// Month detail's "Open in Ledger" — the shell sets the ledger month and
  /// navigates. Null hides the button.
  final ValueChanged<String>? onOpenLedgerMonth;

  /// Slot after the header actions — the integrator passes the shell's
  /// `NudgyHeaderButton` here.
  final Widget? trailing;

  const WebHistoryPageV2({
    super.key,
    required this.presenter,
    this.onOpenLedgerMonth,
    this.trailing,
  });

  @override
  State<WebHistoryPageV2> createState() => _WebHistoryPageV2State();
}

class _WebHistoryPageV2State extends State<WebHistoryPageV2> {
  _HistoryRange _range = _HistoryRange.sixMonths;

  void _openDetail(BuildContext context, _MonthRow row) {
    showWebMonthDetailDialogV2(
      context,
      summary: row.summary,
      categories: widget.presenter.categories,
      isLive: row.isLive,
      onOpenLedger: widget.onOpenLedgerMonth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final presenter = widget.presenter;
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (presenter.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final view = _HistoryView(
          closedNewestFirst: presenter.summaries,
          current: presenter.currentMonthSummary,
          categories: presenter.categories,
          range: _range,
        );
        if (view.isEmpty) return const _EmptyState();

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebPageHeaderV2(
                title: 'History',
                subtitle: view.subtitle,
                actions: [
                  SizedBox(
                    width: 300,
                    child: WebSegmented<_HistoryRange>(
                      key: WebKeys.historyRange,
                      value: _range,
                      onChanged: (r) => setState(() => _range = r),
                      segments: [
                        for (final r in _HistoryRange.values)
                          WebSegment(r, r.label),
                      ],
                    ),
                  ),
                  if (widget.trailing != null) widget.trailing!,
                ],
              ),
              if (view.live != null) ...[
                _LiveCard(
                  row: view.live!,
                  onOpen: () => _openDetail(context, view.live!),
                ),
                const SizedBox(height: _gap),
              ],
              _PeriodStats(view: view),
              const SizedBox(height: _gap),
              _CashFlowTrendCard(view: view),
              const SizedBox(height: _gap),
              _TableAndSparklines(
                view: view,
                onOpenMonth: (row) => _openDetail(context, row),
              ),
              const SizedBox(height: _gap),
              _SpendingByCategoryCard(view: view),
            ],
          ),
        );
      },
    );
  }
}

// ===========================================================================
// View model — the presenter's summaries, filtered and aggregated once
// ===========================================================================

/// A computed view-row for one [MonthlySummary].
class _MonthRow {
  final MonthlySummary summary;
  final bool isLive;

  _MonthRow(this.summary, {this.isLive = false});

  String get month => summary.month;
  double get income => summary.totalInflow;
  double get expenses => summary.totalOutflow;
  double get net => summary.netSavings;
  double get rate => income > 0 ? net / income : 0;
  double get endingCash => summary.endingCash;

  /// Money actually moved into savings pockets this month (not the cash-flow
  /// surplus). Null on summaries closed before the field existed → 0.
  double get saved => summary.savingsContribution ?? 0;

  /// Short axis label, e.g. 'Jun'.
  String get axisLabel => monthShortLabel(month);
}

/// One category's average across the series, with the latest month beside it.
class _CategoryAgg {
  final String name;
  final Color color;
  final double avg;
  final double latest;
  const _CategoryAgg(this.name, this.color, this.avg, this.latest);

  /// Latest vs average, as a signed fraction (+0.09 → 9 % above).
  double get delta => avg > 0 ? (latest - avg) / avg : 0;
}

class _HistoryView {
  /// Chronological: the closed months in range, then the live month.
  final List<_MonthRow> rows;
  final List<_MonthRow> closed;
  final _MonthRow? live;
  final List<FinanceCategory> categories;
  final bool isEmpty;

  factory _HistoryView({
    required List<MonthlySummary> closedNewestFirst,
    required MonthlySummary? current,
    required List<FinanceCategory> categories,
    required _HistoryRange range,
  }) {
    final limit = range.months;
    final kept = limit == null
        ? closedNewestFirst
        : closedNewestFirst.take(limit).toList();
    final closed = [for (final s in kept.reversed) _MonthRow(s)];
    final live = current == null ? null : _MonthRow(current, isLive: true);
    final liveHasActivity = current != null &&
        (current.totalInflow != 0 ||
            current.totalOutflow != 0 ||
            current.billCount > 0);
    return _HistoryView._(
      rows: [...closed, if (live != null) live],
      closed: closed,
      live: live,
      categories: categories,
      isEmpty: closedNewestFirst.isEmpty && !liveHasActivity,
    );
  }

  const _HistoryView._({
    required this.rows,
    required this.closed,
    required this.live,
    required this.categories,
    required this.isEmpty,
  });

  String get spanLabel {
    if (rows.isEmpty) return '';
    if (rows.length == 1) return monthLabel(rows.first.month);
    return '${_shortMonthYear(rows.first.month)} – ${_shortMonthYear(rows.last.month)}';
  }

  String get subtitle {
    if (closed.isEmpty && live != null) {
      return 'Live month so far · ${monthLabel(live!.month)}';
    }
    final open =
        live == null ? '' : ' · ${monthShortLabel(live!.month)} still open';
    return 'Last ${rows.length} months · $spanLabel$open';
  }

  double _avg(double Function(_MonthRow r) f) =>
      rows.isEmpty ? 0 : rows.fold<double>(0, (s, r) => s + f(r)) / rows.length;

  double get avgNet => _avg((r) => r.net);
  double get avgRate => _avg((r) => r.rate);
  double get avgSaved => _avg((r) => r.saved);
  double get cashGrowth =>
      rows.length < 2 ? 0 : rows.last.endingCash - rows.first.endingCash;
  _MonthRow? get best =>
      rows.isEmpty ? null : rows.reduce((a, b) => b.net > a.net ? b : a);

  /// Running total of monthly net, one point per row.
  List<double> get cumulativeNet {
    var run = 0.0;
    return [for (final r in rows) run += r.net];
  }

  /// "Net up K of the last N months" over the last five month-to-month
  /// moves; null with fewer than two months.
  ({int up, int of})? get netTakeaway {
    if (rows.length < 2) return null;
    final of = math.min(5, rows.length - 1);
    var up = 0;
    for (var i = rows.length - of; i < rows.length; i++) {
      if (rows[i].net > rows[i - 1].net) up++;
    }
    return (up: up, of: of);
  }

  double get maxSaved => rows.fold<double>(0, (m, r) => math.max(m, r.saved));

  /// Per-category average across the series, highest first; empty when no
  /// month carries categorised spend.
  List<_CategoryAgg> categoryAverages(Brightness brightness) {
    if (rows.isEmpty) return const [];
    final catById = {for (final c in categories) c.id: c};
    final latest = rows.last.summary;
    final totals = <String, double>{};
    for (final r in rows) {
      r.summary.categorySpend.forEach((id, v) {
        totals[id] = (totals[id] ?? 0) + v;
      });
    }
    final ids = totals.keys.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    return [
      for (var i = 0; i < ids.length; i++)
        _CategoryAgg(
          catById[ids[i]]?.name ?? 'Uncategorised',
          resolveSliceColor(
            catById[ids[i]]?.colorHex ?? '',
            i,
            brightness: brightness,
          ),
          totals[ids[i]]! / rows.length,
          latest.categorySpend[ids[i]] ?? 0,
        ),
    ];
  }
}

// ===========================================================================
// Live month — full width on the Treasury gradient
// ===========================================================================

class _LiveCard extends StatelessWidget {
  final _MonthRow row;
  final VoidCallback onOpen;
  const _LiveCard({required this.row, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;
    // The Treasury hero blue the Dashboard's net-worth card wears, so the
    // live month reads as the same family of card rather than a gold one-off.
    final blue = appColors.fast;
    final share = row.income > 0 ? row.expenses / row.income : 0.0;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                monthLabel(row.month),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: WebInsets.sm),
            _LivePill(color: blue),
          ],
        ),
        const SizedBox(height: WebInsets.xs),
        Text(
          'Still open — these numbers are still moving',
          style:
              theme.textTheme.bodySmall?.copyWith(color: appColors.textMuted),
        ),
        const SizedBox(height: WebInsets.sm),
        TextButton(
          key: WebKeys.historyLiveCardOpen,
          onPressed: onOpen,
          style: TextButton.styleFrom(
            minimumSize: const Size(kWebHitTarget, kWebHitTarget),
            padding: const EdgeInsets.symmetric(horizontal: WebInsets.sm),
            foregroundColor: blue,
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: const Text('Open month ›'),
        ),
      ],
    );

    final cells = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _HeroCell(
            label: 'IN',
            value: formatPesoCompact(row.income),
            caption: 'Income so far',
            valueColor: appColors.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _HeroCell(
            label: 'OUT',
            value: formatPesoCompact(row.expenses),
            caption: row.income > 0
                ? '${formatPercent(share)} of income'
                : 'Spent so far',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _HeroCell(
            label: 'SAVED',
            value: row.income > 0 ? formatPercent(row.rate) : '—',
            caption: '${_signedCompact(row.net)} net',
            valueColor: row.net >= 0 ? appColors.success : cs.error,
          ),
        ),
      ],
    );

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: WebKeys.historyLiveCard,
        onTap: onOpen,
        borderRadius: BorderRadius.circular(22),
        child: WebHeroCard(
          accent: blue,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < _liveCardSplitMin) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [text, const SizedBox(height: WebInsets.lg), cells],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: text),
                  const SizedBox(width: WebInsets.xl),
                  SizedBox(width: 420, child: cells),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The "LIVE" pill on the live card and the live table row.
class _LivePill extends StatelessWidget {
  final Color color;
  const _LivePill({required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'LIVE',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 10.5,
          letterSpacing: 0.9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// One of the three wells on the live card (In / Out / Saved).
class _HeroCell extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color? valueColor;
  const _HeroCell({
    required this.label,
    required this.value,
    required this.caption,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        // A translucent well over the gradient: darker than the hero in dark
        // mode, lighter in light mode — the surface tint does both.
        color: cs.surface.withValues(alpha: isDark ? 0.38 : 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.appColors.treasury,
              fontSize: 10.5,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: webNumericStyle(
              theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
              color: valueColor ?? cs.onSurface,
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: context.appColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Period stats — one even row of five
// ===========================================================================

class _PeriodStats extends StatelessWidget {
  final _HistoryView view;
  const _PeriodStats({required this.view});

  @override
  Widget build(BuildContext context) {
    final v = view;
    final best = v.best;
    WebStatTone signed(double x) =>
        x >= 0 ? WebStatTone.success : WebStatTone.danger;
    return WebStatStrip(
      key: WebKeys.historyStatStrip,
      items: [
        WebStat(
          label: 'Ending cash change',
          value: _signedCompact(v.cashGrowth),
          caption: v.spanLabel.isEmpty ? 'Across the period' : v.spanLabel,
          tone: signed(v.cashGrowth),
        ),
        WebStat(
          label: 'Avg monthly net',
          value: formatPesoCompact(v.avgNet),
          caption: 'Income − expenses',
          tone: signed(v.avgNet),
        ),
        WebStat(
          label: 'Avg savings rate',
          value: formatPercent(v.avgRate),
          caption: 'Of income kept',
        ),
        WebStat(
          label: 'Avg saved / mo',
          value: formatPesoCompact(v.avgSaved),
          caption: 'Into savings & goals',
          tone: signed(v.avgSaved),
        ),
        WebStat(
          label: 'Best month',
          value: best == null ? '—' : monthLabel(best.month).split(' ').first,
          caption: best == null ? 'No data' : '${_signedCompact(best.net)} net',
        ),
      ],
    );
  }
}

// ===========================================================================
// Cash flow trend — three lines, legend and takeaway in the header
// ===========================================================================

class _CashFlowTrendCard extends StatelessWidget {
  final _HistoryView view;
  const _CashFlowTrendCard({required this.view});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = view.rows;
    final takeaway = view.netTakeaway;
    final income = cs.tertiary;
    final expenses = cs.error;
    final net = cs.primary;

    return WebCard(
      key: WebKeys.historyCashFlowTrend,
      title: 'Cash flow trend',
      description: 'Income, expenses and net each month · ${view.spanLabel}',
      // A direct child of the header Row, so Flexible is legal here: the
      // legend wraps under the pill when Nudgy narrows the page.
      trailing: Flexible(
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: WebInsets.lg,
          runSpacing: WebInsets.sm,
          children: [
            if (takeaway != null)
              _TakeawayPill(
                'Net up ${takeaway.up} of the last ${takeaway.of} '
                '${takeaway.of == 1 ? 'month' : 'months'}',
                good: takeaway.up * 2 >= takeaway.of,
              ),
            _LegendDot(color: income, label: 'Income'),
            _LegendDot(color: expenses, label: 'Expenses'),
            _LegendDot(color: net, label: 'Net'),
          ],
        ),
      ),
      child: WebMultiLineChart(
        showLegend: false,
        bottomLabels: [for (final r in rows) r.axisLabel],
        leftLabelFormat: formatPesoCompact,
        height: 248,
        series: [
          WebLineSeries(
            label: 'Income',
            color: income,
            values: [for (final r in rows) r.income],
          ),
          WebLineSeries(
            label: 'Expenses',
            color: expenses,
            values: [for (final r in rows) r.expenses],
          ),
          WebLineSeries(
            label: 'Net',
            color: net,
            values: [for (final r in rows) r.net],
          ),
        ],
      ),
    );
  }
}

/// "Net up 4 of the last 5 months" — success when at least half were up.
class _TakeawayPill extends StatelessWidget {
  final String text;
  final bool good;
  const _TakeawayPill(this.text, {required this.good});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = good ? context.appColors.success : context.appColors.bills;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: WebInsets.sm),
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ===========================================================================
// Monthly table (2/3) + the two sparkline cards (1/3)
// ===========================================================================

class _TableAndSparklines extends StatelessWidget {
  final _HistoryView view;
  final ValueChanged<_MonthRow> onOpenMonth;
  const _TableAndSparklines({required this.view, required this.onOpenMonth});

  @override
  Widget build(BuildContext context) {
    final table = _MonthlyTableCard(view: view, onOpenMonth: onOpenMonth);
    final savings = _CumulativeSavingsCard(view: view);
    final cash = _EndingCashCard(view: view);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _threeColMin) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              table,
              const SizedBox(height: _gap),
              savings,
              const SizedBox(height: _gap),
              cash,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: table),
            const SizedBox(width: _gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [savings, const SizedBox(height: _gap), cash],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MonthlyTableCard extends StatelessWidget {
  final _HistoryView view;
  final ValueChanged<_MonthRow> onOpenMonth;
  const _MonthlyTableCard({required this.view, required this.onOpenMonth});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;
    final maxSaved = view.maxSaved;
    // Newest first, like the phone's list.
    final rows = view.rows.reversed.toList();

    return WebCard(
      key: WebKeys.historyMonthlyTable,
      title: 'Monthly summary',
      description: 'The numbers behind the trend · click a month for detail',
      padding: const EdgeInsets.all(WebInsets.sm),
      child: WebDataTable<_MonthRow>(
        rows: rows,
        emptyLabel: 'No months recorded',
        onRowTap: onOpenMonth,
        columns: [
          WebColumn<_MonthRow>(
            label: 'Month',
            flex: 3,
            cell: (context, r) => Row(
              key: WebKeys.historyMonthRow(r.month),
              children: [
                Flexible(
                  child: Text(
                    monthLabel(r.month),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (r.isLive) ...[
                  const SizedBox(width: WebInsets.sm),
                  _LivePill(color: appColors.fast),
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
              style: TextStyle(
                  color: appColors.success, fontWeight: FontWeight.w600),
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
              _signedCompact(r.net),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: r.net < 0 ? cs.error : cs.onSurface,
              ),
            ),
          ),
          WebColumn<_MonthRow>(
            label: 'Rate',
            numeric: true,
            flex: 1,
            cell: (context, r) => Text(
              formatPercent(r.rate),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          WebColumn<_MonthRow>(
            label: 'Saved',
            numeric: true,
            flex: 2,
            cell: (context, r) => Tooltip(
              message: '${formatPeso(r.saved)} set aside',
              child: SizedBox(
                width: 72,
                child: WebProgressBar(
                  value: maxSaved > 0 ? r.saved / maxSaved : 0,
                  color: appColors.treasury,
                  height: 6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CumulativeSavingsCard extends StatelessWidget {
  final _HistoryView view;
  const _CumulativeSavingsCard({required this.view});

  @override
  Widget build(BuildContext context) {
    final cumulative = view.cumulativeNet;
    final total = cumulative.isEmpty ? 0.0 : cumulative.last;
    return _SparklineCard(
      key: WebKeys.historyCumulativeSavings,
      title: 'Cumulative savings',
      description: 'Running total of monthly net',
      delta: total,
      values: cumulative,
      labels: [for (final r in view.rows) r.axisLabel],
    );
  }
}

class _EndingCashCard extends StatelessWidget {
  final _HistoryView view;
  const _EndingCashCard({required this.view});

  @override
  Widget build(BuildContext context) {
    return _SparklineCard(
      key: WebKeys.historyEndingCash,
      title: 'Ending cash trend',
      description: 'Month-end liquid balance',
      delta: view.cashGrowth,
      values: [for (final r in view.rows) r.endingCash],
      labels: [for (final r in view.rows) r.axisLabel],
    );
  }
}

/// A small area chart with a signed badge in the header.
class _SparklineCard extends StatelessWidget {
  final String title;
  final String description;
  final double delta;
  final List<double> values;
  final List<String> labels;
  const _SparklineCard({
    super.key,
    required this.title,
    required this.description,
    required this.delta,
    required this.values,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final up = delta >= 0;
    return WebCard(
      title: title,
      description: description,
      trailing: WebBadge(
        _signedCompact(delta),
        tone: up ? WebBadgeTone.success : WebBadgeTone.danger,
        icon: up ? Icons.arrow_upward : Icons.arrow_downward,
      ),
      child: WebLineChart(
        values: values,
        bottomLabels: labels,
        leftLabelFormat: formatPesoCompact,
        area: true,
        height: 120,
      ),
    );
  }
}

// ===========================================================================
// Spending by category — two columns of average-vs-latest rows
// ===========================================================================

class _SpendingByCategoryCard extends StatelessWidget {
  final _HistoryView view;
  const _SpendingByCategoryCard({required this.view});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aggs = view.categoryAverages(theme.brightness);
    final maxAvg = aggs.isEmpty ? 0.0 : aggs.first.avg;

    return WebCard(
      key: WebKeys.historySpendingByCategory,
      title: 'Spending by category',
      description:
          'Average per month, with the latest month against the average',
      child: view.rows.isEmpty
          ? const _Placeholder('No spending recorded yet.')
          : aggs.isEmpty
              ? const _Placeholder('No categorised spending yet.')
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final cols = w >= _twoColMin ? 2 : 1;
                    // Floored: the card's hairline border leaves a fractional
                    // width, and an Expanded text in a half-pixel column
                    // overflows by that half pixel.
                    final itemWidth =
                        ((w - _gap * (cols - 1)) / cols).floorToDouble();
                    return Wrap(
                      spacing: _gap,
                      runSpacing: WebInsets.lg,
                      children: [
                        for (final a in aggs)
                          SizedBox(
                            width: itemWidth,
                            child: _CategoryRow(agg: a, maxAvg: maxAvg),
                          ),
                      ],
                    );
                  },
                ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final _CategoryAgg agg;
  final double maxAvg;
  const _CategoryRow({required this.agg, required this.maxAvg});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final delta = agg.delta;
    final up = delta > 0.05;
    final down = delta < -0.05;
    final pct = '${(delta.abs() * 100).round()}%';
    final badge = up
        ? WebBadge('↑ $pct vs avg', tone: WebBadgeTone.warning)
        : down
            ? WebBadge('↓ $pct vs avg', tone: WebBadgeTone.success)
            : const WebBadge('about average', tone: WebBadgeTone.neutral);
    final fraction = maxAvg > 0 ? (agg.avg / maxAvg).clamp(0.0, 1.0) : 0.0;

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
            Text(
              '${formatPesoCompact(agg.avg)} / mo',
              style: webNumericStyle(
                theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: WebInsets.sm),
        WebProgressBar(value: fraction, color: agg.color),
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

class _Placeholder extends StatelessWidget {
  final String message;
  const _Placeholder(this.message);

  @override
  Widget build(BuildContext context) {
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

// ===========================================================================
// Empty state
// ===========================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
                  size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              const SizedBox(height: WebInsets.lg),
              Text(
                'No history yet',
                style: theme.textTheme.titleLarge
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

// ── Pure helpers ─────────────────────────────────────────────────────────────

/// '+₱1.2k' / '−₱1.2k' — compact with an explicit sign.
String _signedCompact(double amount) =>
    '${amount >= 0 ? '+' : '−'}${formatPesoCompact(amount.abs())}';

/// 'Jun 2026' from a 'YYYY-MM' key.
String _shortMonthYear(String monthKey) =>
    '${monthShortLabel(monthKey)} ${monthKey.substring(0, 4)}';
