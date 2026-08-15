import 'package:flutter/material.dart';

import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';

/// Desktop drill-down for one month — the counterpart of the mobile
/// `MonthlySummaryDetailView`.
///
/// The web History page was a read-only table of rounded figures with no way
/// in, on the platform people actually reconcile from. Every number here is
/// exact, not compacted.
Future<void> showWebMonthDetailDialog(
  BuildContext context, {
  required MonthlySummary summary,
  required List<FinanceCategory> categories,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _WebMonthDetailDialog(summary: summary, categories: categories),
  );
}

class _WebMonthDetailDialog extends StatelessWidget {
  final MonthlySummary summary;
  final List<FinanceCategory> categories;

  const _WebMonthDetailDialog({
    required this.summary,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final spend = summary.categorySpend.entries
        .where((e) => e.value != 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final spendTotal = spend.fold<double>(0, (s, e) => s + e.value);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(monthLabel(summary.month))),
          WebBadge(
            summary.netSavings >= 0 ? 'Net positive' : 'Net negative',
            tone: summary.netSavings >= 0
                ? WebBadgeTone.success
                : WebBadgeTone.danger,
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Section(
                title: 'Cash flow',
                rows: [
                  ('Income', formatPeso(summary.totalInflow), cs.tertiary),
                  ('Expenses', formatPeso(summary.totalOutflow), cs.error),
                  (
                    'Net',
                    formatPeso(summary.netSavings),
                    summary.netSavings >= 0 ? cs.tertiary : cs.error
                  ),
                  (
                    'Savings rate',
                    summary.totalInflow > 0
                        ? '${(summary.netSavings / summary.totalInflow * 100).toStringAsFixed(1)}%'
                        : '—',
                    cs.onSurface
                  ),
                  ('Ending cash', formatPeso(summary.endingCash), cs.onSurface),
                  if (summary.savingsContribution != null)
                    (
                      'Set aside to savings',
                      formatPeso(summary.savingsContribution!),
                      cs.onSurface
                    ),
                  if (summary.netWorth != null)
                    ('Net worth', formatPeso(summary.netWorth!), cs.onSurface),
                ],
              ),
              const SizedBox(height: WebInsets.xl),
              _Section(
                title: 'Bills & receivables',
                rows: [
                  (
                    'Bills',
                    '${summary.billsPaidCount} of ${summary.billCount} paid',
                    cs.onSurface
                  ),
                  (
                    'Billed',
                    '${formatPeso(summary.totalBillsPaid)} of ${formatPeso(summary.totalBills)}',
                    cs.onSurface
                  ),
                  (
                    'Receivables',
                    '${formatPeso(summary.totalReceived)} of ${formatPeso(summary.totalReceivables)} received',
                    cs.onSurface
                  ),
                ],
              ),
              const SizedBox(height: WebInsets.xl),
              Text('Spending by category',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: WebInsets.md),
              if (spend.isEmpty)
                Text('No categorised spending this month.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant))
              else
                for (var i = 0; i < spend.length; i++) ...[
                  if (i > 0) const SizedBox(height: WebInsets.md),
                  _CategoryLine(
                    name: categories
                            .where((c) => c.id == spend[i].key)
                            .map((c) => c.name)
                            .firstOrNull ??
                        'Uncategorised',
                    amount: spend[i].value,
                    share: spendTotal > 0 ? spend[i].value / spendTotal : 0,
                    color: resolveSliceColor(
                      categories
                              .where((c) => c.id == spend[i].key)
                              .map((c) => c.colorHex)
                              .firstOrNull ??
                          '',
                      i,
                      brightness: theme.brightness,
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<(String, String, Color)> rows;

  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: WebInsets.md),
        for (final (label, value, color) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: WebInsets.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ),
                Text(value,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );
  }
}

class _CategoryLine extends StatelessWidget {
  final String name;
  final double amount;
  final double share;
  final Color color;

  const _CategoryLine({
    required this.name,
    required this.amount,
    required this.share,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium),
            ),
            Text(formatPeso(amount),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: WebInsets.sm),
            SizedBox(
              width: 44,
              child: Text('${(share * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ],
        ),
        const SizedBox(height: WebInsets.xs),
        WebProgressBar(value: share, color: color, height: 5),
      ],
    );
  }
}
