import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/history/monthly_summary_card.dart';
import 'package:intermittent_fasting/views/treasury/history/monthly_summary_detail_view.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class TreasuryHistoryView extends StatefulWidget {
  final TreasuryHistoryPresenter presenter;

  const TreasuryHistoryView({super.key, required this.presenter});

  @override
  State<TreasuryHistoryView> createState() => _TreasuryHistoryViewState();
}

class _TreasuryHistoryViewState extends State<TreasuryHistoryView> {
  @override
  void initState() {
    super.initState();
    widget.presenter.load();
  }

  void _openDetail(MonthlySummary summary) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MonthlySummaryDetailView(
          summary: summary,
          categories: widget.presenter.categories,
          accounts: widget.presenter.accounts,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        // The module hides its "TREASURY" app bar on this tab, so keep the top
        // safe-area inset and render an in-page "History" title (per the
        // reference), matching the Ledger / Budget tabs.
        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    'History',
                    style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                ),
                Expanded(child: _content(context)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context) {
    if (widget.presenter.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final summaries = widget.presenter.summaries;
    final current = widget.presenter.currentMonthSummary;

    if (summaries.isEmpty && current == null) {
      return const AppEmptyState(
        icon: Icons.history_outlined,
        title: 'No history yet',
        body: 'Monthly summaries appear here after the month closes',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (widget.presenter.closedMonthCount > 0) ...[
          _OverviewSection(presenter: widget.presenter),
          const SizedBox(height: 20),
        ],
        if (current != null) ...[
          AppSection(
            title: 'CURRENT MONTH',
            trailing: const AppBadge(
              text: 'LIVE',
              variant: AppBadgeVariant.tonal,
            ),
            child: MonthlySummaryCard(
              summary: current,
              isLive: true,
              onTap: () => _openDetail(current),
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (summaries.isNotEmpty)
          AppSection(
            title: 'CLOSED MONTHS',
            child: Column(
              children: summaries
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: MonthlySummaryCard(
                        key: ValueKey(s.month),
                        summary: s,
                        onTap: () => _openDetail(s),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}

/// A dashboard-style snapshot across all closed months: average income /
/// spending / net saved, plus a few actionable insights (average savings rate,
/// months tracked + cumulative net, and how last month compares to the norm).
class _OverviewSection extends StatelessWidget {
  final TreasuryHistoryPresenter presenter;

  const _OverviewSection({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final avgNet = presenter.averageNetSavings;
    final netPositive = avgNet >= 0;
    final rate = presenter.averageSavingsRate;
    final cumulative = presenter.cumulativeNetSavings;
    final months = presenter.closedMonthCount;
    final latest = presenter.latestClosedMonth;

    return AppSection(
      title: 'OVERVIEW',
      child: AppCard(
        variant: AppCardVariant.filled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AvgCol(
                    label: 'AVG IN',
                    value: formatPesoCompact(presenter.averageInflow),
                    color: cs.tertiary,
                  ),
                  _divider(cs),
                  _AvgCol(
                    label: 'AVG OUT',
                    value: formatPesoCompact(presenter.averageOutflow),
                    color: cs.error,
                  ),
                  _divider(cs),
                  _AvgCol(
                    label: 'AVG SAVED',
                    value:
                        '${netPositive ? '+' : '−'}${formatPesoCompact(avgNet.abs())}',
                    color: netPositive ? cs.primary : cs.error,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            _Insight(
              icon: Icons.percent_rounded,
              color: cs.primary,
              text: 'Keeps ${(rate * 100).round()}% of income on average',
            ),
            const SizedBox(height: 8),
            _Insight(
              icon: Icons.savings_outlined,
              color: cs.tertiary,
              text: '$months ${months == 1 ? 'month' : 'months'} tracked · '
                  '${cumulative >= 0 ? '+' : '−'}${formatPesoCompact(cumulative.abs())} net all-time',
            ),
            if (latest != null && months >= 2) ...[
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final diff = latest.netSavings - avgNet;
                final above = diff >= 0;
                return _Insight(
                  icon: above
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  color: above ? cs.tertiary : cs.error,
                  text: above
                      ? 'Last month beat your average by ${formatPesoCompact(diff.abs())}'
                      : 'Last month was ${formatPesoCompact(diff.abs())} below average',
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _divider(ColorScheme cs) => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: cs.outlineVariant,
      );
}

class _AvgCol extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AvgCol(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _Insight extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Insight({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
