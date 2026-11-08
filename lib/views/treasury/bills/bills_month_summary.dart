import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Keys for the "This month" card, for tests.
abstract final class BillsMonthSummaryKeys {
  static const fold = ValueKey('bills-month-summary');
  static const byAccount = ValueKey('bills-month-summary-by-account');
}

/// The collapsible "This month" card under the Bills hero (Plan 071 Phase 6):
/// pending, paid, to receive, set-asides and installments, then "By account"
/// from [BillsReceivablesPresenter.fundingBreakdown]. It replaces the old
/// three stat chips. Closed by default so the tabs stay near the top.
///
/// Dumb: every figure and line comes from the presenter.
class BillsMonthSummary extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;

  const BillsMonthSummary({
    super.key,
    required this.presenter,
    required this.installmentPresenter,
  });

  @override
  Widget build(BuildContext context) {
    final lines = presenter.monthSummaryLines(installmentPresenter);
    final rows = presenter.fundingBreakdown();
    return AppFold(
      key: BillsMonthSummaryKeys.fold,
      title: 'This month',
      subtitle: presenter.monthSummaryHeadline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in lines) _SummaryLine(line: line),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              key: BillsMonthSummaryKeys.byAccount,
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'By account',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Text(
              'How much to move into each account to cover what is due',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            for (final row in rows)
              _AccountLine(
                name: row.account?.name ?? 'Unassigned',
                detail: presenter.fundingRowDetail(row),
                total: formatPeso(row.total),
                assigned: row.account != null,
              ),
          ],
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final BillsSummaryLine line;

  const _SummaryLine({required this.line});

  Color _toneColor(BuildContext context) => switch (line.tone) {
        BillsSummaryTone.warning => context.appColors.bills,
        BillsSummaryTone.positive => context.appColors.success,
        BillsSummaryTone.neutral => Theme.of(context).colorScheme.onSurface,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _KeyValueRow(
      label: line.label,
      sub: line.sub,
      value: line.value,
      valueColor: _toneColor(context),
      labelStyle: theme.textTheme.bodyMedium,
    );
  }
}

class _AccountLine extends StatelessWidget {
  final String name;
  final String detail;
  final String total;
  final bool assigned;

  const _AccountLine({
    required this.name,
    required this.detail,
    required this.total,
    required this.assigned,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _KeyValueRow(
      label: name,
      sub: detail,
      value: total,
      valueColor: assigned ? cs.primary : cs.onSurface,
      labelStyle: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

/// A label with a muted line under it on the left, a figure on the right.
class _KeyValueRow extends StatelessWidget {
  final String label;
  final String sub;
  final String value;
  final Color valueColor;
  final TextStyle? labelStyle;

  const _KeyValueRow({
    required this.label,
    required this.sub,
    required this.value,
    required this.valueColor,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
