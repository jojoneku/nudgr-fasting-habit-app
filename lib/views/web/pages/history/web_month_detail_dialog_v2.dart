import 'package:flutter/material.dart';

import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../web_keys.dart';
import '../../widgets/web_widgets.dart';

/// The v2 month drill-down (Plan 063, Phase 7) — the "Month detail" dialog
/// of `Forms.dc.html` on [WebDialog]: the month as the title with a
/// net-positive/negative pill, "Closed · N of M bills paid" as the subtitle,
/// a three-cell Income / Expenses / Net strip, the cash and bills figures as
/// key-value rows, then spending by category as share bars.
///
/// Read-only. "Open in Ledger" closes the dialog and hands [onOpenLedger] the
/// month key; the page decides where that goes. Every figure is exact, not
/// compacted — this is the surface people reconcile from.
Future<void> showWebMonthDetailDialogV2(
  BuildContext context, {
  required MonthlySummary summary,
  required List<FinanceCategory> categories,
  bool isLive = false,
  ValueChanged<String>? onOpenLedger,
}) {
  return showWebDialog<void>(
    context,
    builder: (_) => WebMonthDetailDialogV2(
      summary: summary,
      categories: categories,
      isLive: isLive,
      onOpenLedger: onOpenLedger,
    ),
  );
}

class WebMonthDetailDialogV2 extends StatelessWidget {
  final MonthlySummary summary;
  final List<FinanceCategory> categories;
  final bool isLive;
  final ValueChanged<String>? onOpenLedger;

  const WebMonthDetailDialogV2({
    super.key,
    required this.summary,
    required this.categories,
    this.isLive = false,
    this.onOpenLedger,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = summary;
    final positive = s.netSavings >= 0;
    final rate = s.totalInflow > 0 ? s.netSavings / s.totalInflow : 0.0;

    final spend = s.categorySpend.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final spendTotal = spend.fold<double>(0, (t, e) => t + e.value);
    final catById = {for (final c in categories) c.id: c};

    final open = onOpenLedger == null
        ? null
        : FilledButton(
            key: WebKeys.historyMonthDetailOpenLedger,
            onPressed: () {
              Navigator.of(context).pop();
              onOpenLedger!(s.month);
            },
            child: const Text('Open in Ledger'),
          );
    // "Close" is the ghost secondary beside "Open in Ledger"; with no ledger
    // to open it becomes the one (filled) action.
    final close = open == null
        ? FilledButton(
            key: WebKeys.historyMonthDetailClose,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          )
        : TextButton(
            key: WebKeys.historyMonthDetailClose,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          );

    return WebDialog(
      key: WebKeys.historyMonthDetail,
      title: monthLabel(s.month),
      subtitle:
          '${isLive ? 'Still open' : 'Closed'} · ${s.billsPaidCount} of ${s.billCount} bills paid',
      width: kWebDialogWideWidth,
      primaryExpands: false,
      primary: open ?? close,
      secondary: open == null ? null : close,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: WebBadge(
              positive ? 'Net positive' : 'Net negative',
              tone: positive ? WebBadgeTone.success : WebBadgeTone.danger,
            ),
          ),
          const SizedBox(height: WebInsets.lg),
          WebStatStrip(
            onCard: true,
            minItemWidth: 140,
            items: [
              WebStat(
                label: 'Income',
                value: formatPeso(s.totalInflow),
                tone: WebStatTone.success,
              ),
              WebStat(
                label: 'Expenses',
                value: formatPeso(s.totalOutflow),
                tone: WebStatTone.danger,
              ),
              WebStat(
                label: 'Net · ${formatPercent(rate)} saved',
                value: formatPesoSigned(s.netSavings),
                tone: positive ? WebStatTone.success : WebStatTone.danger,
              ),
            ],
          ),
          const SizedBox(height: WebInsets.xl),
          _KvRow('Ending cash', formatPeso(s.endingCash)),
          if (s.savingsContribution != null)
            _KvRow('Set aside to savings', formatPeso(s.savingsContribution!)),
          if (s.netWorth != null) _KvRow('Net worth', formatPeso(s.netWorth!)),
          _KvRow(
            'Bills paid',
            '${formatPeso(s.totalBillsPaid)} · ${s.billsPaidCount} of ${s.billCount}',
          ),
          _KvRow(
            'Receivables received',
            '${formatPeso(s.totalReceived)} · ${s.receivableCount}',
          ),
          const SizedBox(height: WebInsets.xl),
          Text(
            'Spending by category',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: WebInsets.md),
          if (spend.isEmpty)
            Text(
              'No categorised spending this month.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            for (var i = 0; i < spend.length; i++) ...[
              if (i > 0) const SizedBox(height: WebInsets.md),
              _CategoryLine(
                name: catById[spend[i].key]?.name ?? 'Uncategorised',
                amount: spend[i].value,
                share: spendTotal > 0 ? spend[i].value / spendTotal : 0,
                color: resolveSliceColor(
                  catById[spend[i].key]?.colorHex ?? '',
                  i,
                  brightness: theme.brightness,
                ),
              ),
            ],
        ],
      ),
    );
  }
}

/// One "label · value" line of the detail, value in tabular figures.
class _KvRow extends StatelessWidget {
  final String label;
  final String value;
  const _KvRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: WebInsets.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: context.appColors.textMuted),
            ),
          ),
          Text(
            value,
            style: webNumericStyle(
              theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              color: cs.onSurface,
            ),
          ),
        ],
      ),
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
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              formatPeso(amount),
              style: webNumericStyle(
                theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: WebInsets.sm),
            SizedBox(
              width: 44,
              child: Text(
                formatPercent(share),
                textAlign: TextAlign.right,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: WebInsets.xs),
        WebProgressBar(value: share, color: color, height: 5),
      ],
    );
  }
}
