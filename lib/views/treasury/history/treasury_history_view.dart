import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/views/treasury/history/monthly_summary_card.dart';
import 'package:intermittent_fasting/views/treasury/history/monthly_summary_detail_view.dart';

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
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }

        final summaries = widget.presenter.summaries;
        final current = widget.presenter.currentMonthSummary;

        if (summaries.isEmpty && current == null) {
          return _EmptyState();
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (current != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'CURRENT MONTH',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              MonthlySummaryCard(
                summary: current,
                isLive: true,
                onTap: () => _openDetail(current),
              ),
              const SizedBox(height: 8),
            ],
            if (summaries.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'CLOSED MONTHS',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              ...summaries.map(
                (s) => MonthlySummaryCard(
                  key: ValueKey(s.month),
                  summary: s,
                  onTap: () => _openDetail(s),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_outlined,
              color: AppColors.textSecondary, size: 48),
          const SizedBox(height: 12),
          Text(
            'No history yet',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Monthly summaries appear here after the month closes',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
