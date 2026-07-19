import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
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
