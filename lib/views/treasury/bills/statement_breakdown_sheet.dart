import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/utils/credit_statement_breakdown.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/ledger/add_transaction_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// What is on a credit statement — the issuer's bill screen, in the app.
///
/// Unpaid amount up top, then Bill / Repaid / Unpaid, the cycle's period and
/// item count, and the card's records grouped as Purchases, Installments,
/// Refunds and Repaid. Tapping a record opens its transaction form.
///
/// Dumb view: everything comes from
/// [BillsReceivablesPresenter.statementBreakdown], which reads the ledger on
/// every call. The sheet listens to both presenters, so an edit made from here
/// (or anywhere) redraws it with the new figures.
class StatementBreakdownSheet extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final Bill bill;

  const StatementBreakdownSheet({
    super.key,
    required this.presenter,
    required this.bill,
  });

  /// Opens the sheet for statement [bill].
  static Future<void> show(
    BuildContext context, {
    required BillsReceivablesPresenter presenter,
    required Bill bill,
  }) {
    HapticFeedback.selectionClick();
    return AppBottomSheet.show<void>(
      context: context,
      title: bill.name,
      body: StatementBreakdownSheet(presenter: presenter, bill: bill),
    );
  }

  void _openTransaction(BuildContext context, StatementLine line) {
    HapticFeedback.selectionClick();
    AppBottomSheet.show<void>(
      context: context,
      title: 'Edit Transaction',
      body: AddTransactionSheet(
        presenter: presenter.ledger,
        existing: line.txn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([presenter, presenter.ledger]),
      builder: (context, _) {
        final b = presenter.statementBreakdown(bill);
        if (b == null) {
          return const AppEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No statement cycle',
            body: 'This bill is not tied to a card with a statement date.',
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SummaryCard(breakdown: b),
              const SizedBox(height: AppSpacing.md),
              _PeriodLine(breakdown: b),
              if (b.hasCarriedOver) _CarriedOverRow(label: b.carriedOverLabel),
              if (b.isEmpty)
                const AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No items in this cycle yet',
                  body: 'Charges and payments on this card dated inside the '
                      'statement period will show here.',
                ),
              for (final section in b.sections)
                _Section(
                  section: section,
                  onOpen: (line) => _openTransaction(context, line),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final StatementBreakdown breakdown;

  const _SummaryCard({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final note = breakdown.unreconciledNote;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        // A card on a sheet sits one step up the surface ladder.
        color: cs.surfaceContainerHigh,
        borderRadius: AppRadii.lgBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unpaid amount',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppNumberDisplay(
            value: formatPeso(breakdown.unpaid),
            size: AppNumberSize.headline,
            textAlign: TextAlign.start,
            color: cs.onSurface,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            breakdown.dueLabel,
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(
              label: 'Bill amount', value: formatPeso(breakdown.billAmount)),
          _SummaryRow(label: 'Repaid', value: breakdown.repaidLabel),
          _SummaryRow(
            label: 'Unpaid',
            value: formatPeso(breakdown.unpaid),
            emphasized: true,
          ),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              note,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final weight = emphasized ? FontWeight.w700 : FontWeight.w500;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: emphasized ? cs.onSurface : cs.onSurfaceVariant,
                fontWeight: weight,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: weight,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Transaction total: 9 items · 05 Sep – 04 Oct".
class _PeriodLine extends StatelessWidget {
  final StatementBreakdown breakdown;

  const _PeriodLine({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Transaction total: ${breakdown.itemCountLabel}',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            breakdown.periodLabel,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The balance brought forward from the previous statement — not a record of
/// its own, so it has nothing to open.
class _CarriedOverRow extends StatelessWidget {
  final String label;

  const _CarriedOverRow({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Carried over from last statement',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final StatementSection section;
  final ValueChanged<StatementLine> onOpen;

  const _Section({required this.section, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${section.title} · ${section.countLabel}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                section.totalLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: AppRadii.mdBorder,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < section.lines.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: AppSpacing.md,
                      endIndent: AppSpacing.md,
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  StatementLineRow(
                    line: section.lines[i],
                    onTap: () => onOpen(section.lines[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One record on the statement: "[1/3] Xiaomi Camera · 04 Oct ₱299.62".
/// The whole row opens the record's transaction form.
class StatementLineRow extends StatelessWidget {
  final StatementLine line;
  final VoidCallback onTap;

  const StatementLineRow({super.key, required this.line, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = line.installmentLabel;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              if (label != null) ...[
                AppBadge(text: label, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      line.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line.dateLabel,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                line.amountLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: line.isCredit ? context.appColors.success : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
