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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
      },
    );
  }
}
