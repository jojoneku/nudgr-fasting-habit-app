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

  /// Plan 072: picks when [line]'s order was received — from the order day
  /// to about three months after it — and saves it. The statement follows.
  Future<void> _pickReceivedDate(
      BuildContext context, StatementLine line) async {
    final ordered = line.txn.date;
    final first = DateTime(ordered.year, ordered.month, ordered.day);
    final last = DateTime(first.year, first.month + 3, first.day);
    final today = DateTime.now();
    var initial = DateTime(today.year, today.month, today.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      helpText: 'Received on',
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    await presenter.ledger.setPostedDate(line.txn.id, picked);
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
              if (b.receivedDateNotice case final notice?)
                _ReceivedDateNotice(
                  text: notice,
                  onAllOnOrderDay: () =>
                      presenter.ledger.markReceivedOnOrderDay(
                    [for (final l in b.linesNeedingReceivedDate) l.txn.id],
                  ),
                ),
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
                  onSetReceivedDate: (line) => _pickReceivedDate(context, line),
                  onReceivedOnOrderDay: (line) =>
                      presenter.ledger.markReceivedOnOrderDay([line.txn.id]),
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
  final ValueChanged<StatementLine> onSetReceivedDate;
  final ValueChanged<StatementLine> onReceivedOnOrderDay;

  const _Section({
    required this.section,
    required this.onOpen,
    required this.onSetReceivedDate,
    required this.onReceivedOnOrderDay,
  });

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
                    onSetReceivedDate: () =>
                        onSetReceivedDate(section.lines[i]),
                    onReceivedOnOrderDay: () =>
                        onReceivedOnOrderDay(section.lines[i]),
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

  /// Plan 072: shown under a purchase that still needs a received date
  /// ([StatementLine.needsReceivedDate]). Null hides the actions (the
  /// dashboard card and the web dialog do not offer them yet).
  final VoidCallback? onSetReceivedDate;
  final VoidCallback? onReceivedOnOrderDay;

  const StatementLineRow({
    super.key,
    required this.line,
    required this.onTap,
    this.onSetReceivedDate,
    this.onReceivedOnOrderDay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = line.installmentLabel;
    final setReceived = onSetReceivedDate;
    final onOrderDay = onReceivedOnOrderDay;
    final row = InkWell(
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
    if (!line.needsReceivedDate || setReceived == null || onOrderDay == null) {
      return row;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 0, AppSpacing.sm, AppSpacing.sm),
          child: Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.local_shipping_outlined,
                  size: 16, color: context.appColors.bills),
              TextButton(
                key: ValueKey('statement.setReceived.${line.txn.id}'),
                onPressed: setReceived,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                child: const Text('Received on…'),
              ),
              TextButton(
                key: ValueKey('statement.orderDay.${line.txn.id}'),
                onPressed: onOrderDay,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                child: const Text('On order day'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Plan 072: "2 orders may post when received…" with one action to confirm
/// every flagged order was received on its order day.
class _ReceivedDateNotice extends StatelessWidget {
  final String text;
  final VoidCallback onAllOnOrderDay;

  const _ReceivedDateNotice(
      {required this.text, required this.onAllOnOrderDay});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tone = context.appColors.bills;
    return Container(
      key: const ValueKey('statement.receivedNotice'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.xs),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            tone.withValues(alpha: 0.10), cs.surfaceContainerHigh),
        borderRadius: AppRadii.mdBorder,
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child:
                    Icon(Icons.local_shipping_outlined, size: 18, color: tone),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(text, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('statement.allOrderDay'),
              onPressed: onAllOnOrderDay,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: const Text('All received on order day'),
            ),
          ),
        ],
      ),
    );
  }
}
