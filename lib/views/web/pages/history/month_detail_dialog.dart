import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/views/treasury/history/monthly_summary_detail_view.dart';

/// Opens the existing [MonthlySummaryDetailView] as a centered desktop dialog
/// (Plan 050-E reuses the mobile detail rather than re-implementing it). The
/// detail view is a full `AppPageScaffold` with its own back button, so we host
/// it in a constrained, rounded card.
Future<void> showMonthDetailDialog(
  BuildContext context, {
  required MonthlySummary summary,
  required List<FinanceCategory> categories,
  required List<FinancialAccount> accounts,
}) {
  final cs = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              color: cs.surface,
              child: MonthlySummaryDetailView(
                summary: summary,
                categories: categories,
                accounts: accounts,
              ),
            ),
          ),
        ),
      );
    },
  );
}
