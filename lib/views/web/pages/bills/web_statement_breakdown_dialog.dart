import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/credit_statement_breakdown.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/bills/statement_breakdown_sheet.dart';
import 'package:intermittent_fasting/views/web/pages/ledger/web_ledger_page.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

import '../../widgets/web_widgets.dart';

/// Opens the item list of credit statement [bill] — the web twin of the
/// mobile [StatementBreakdownSheet].
Future<void> showWebStatementBreakdownDialog(
  BuildContext context, {
  required BillsReceivablesPresenter presenter,
  required Bill bill,
}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => WebStatementBreakdownDialog(
        presenter: presenter,
        bill: bill,
      ),
    );

/// Unpaid amount, Bill / Repaid / Unpaid, the cycle's period and item count,
/// then the card's records grouped as Purchases, Installments, Refunds and
/// Repaid. Clicking a record opens the ledger's edit dialog for it; the
/// dialog listens to both presenters, so the figures follow the edit.
class WebStatementBreakdownDialog extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final Bill bill;

  const WebStatementBreakdownDialog({
    super.key,
    required this.presenter,
    required this.bill,
  });

  void _open(BuildContext context, StatementLine line) {
    showWebEditTransactionDialog(
      context,
      presenter: presenter.ledger,
      txn: line.txn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([presenter, presenter.ledger]),
          builder: (context, _) {
            final b = presenter.statementBreakdown(bill);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Header(title: bill.name, subtitle: b?.dueLabel),
                Divider(
                    height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(WebInsets.xl),
                    child: b == null
                        ? const AppEmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'No statement cycle',
                            body: 'This bill is not tied to a card with a '
                                'statement date.',
                          )
                        : _Body(
                            breakdown: b,
                            onOpen: (line) => _open(context, line),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _Header({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebInsets.xl,
        WebInsets.lg,
        WebInsets.md,
        WebInsets.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final StatementBreakdown breakdown;
  final ValueChanged<StatementLine> onOpen;

  const _Body({required this.breakdown, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = breakdown;
    final note = b.unreconciledNote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Outlined(
          padding: const EdgeInsets.all(WebInsets.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unpaid amount',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: WebInsets.xs),
              AppNumberDisplay(
                value: formatPeso(b.unpaid),
                size: AppNumberSize.headline,
                textAlign: TextAlign.start,
                color: cs.onSurface,
              ),
              const SizedBox(height: WebInsets.md),
              _AmountRow(label: 'Bill amount', value: formatPeso(b.billAmount)),
              _AmountRow(label: 'Repaid', value: b.repaidLabel),
              _AmountRow(
                label: 'Unpaid',
                value: formatPeso(b.unpaid),
                emphasized: true,
              ),
              if (note != null) ...[
                const SizedBox(height: WebInsets.sm),
                Text(
                  note,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: WebInsets.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                'Transaction total: ${b.itemCountLabel}',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              b.periodLabel,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        if (b.hasCarriedOver)
          Padding(
            padding: const EdgeInsets.only(top: WebInsets.sm),
            child: _AmountRow(
              label: 'Carried over from last statement',
              value: b.carriedOverLabel,
            ),
          ),
        if (b.isEmpty)
          const AppEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No items in this cycle yet',
            body: 'Charges and payments on this card dated inside the '
                'statement period will show here.',
          ),
        for (final section in b.sections) ...[
          const SizedBox(height: WebInsets.lg),
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
          const SizedBox(height: WebInsets.xs),
          _Outlined(
            child: Column(
              children: [
                for (var i = 0; i < section.lines.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
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
      ],
    );
  }
}

/// A bordered block inside the dialog — outlined rather than filled, so it
/// reads as a group without stacking a third surface tone on the dialog.
class _Outlined extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _Outlined({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _AmountRow({
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
      padding: const EdgeInsets.symmetric(vertical: WebInsets.xs),
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
              fontWeight: weight,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
