import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intl/intl.dart';
import '../../widgets/web_widgets.dart';

typedef LedgerRow = ({TransactionRecord txn, double runningBalance});

final _dayFmt = DateFormat('MMM d');

/// The sheet's "Detailed Records" as a [WebDataTable]: Date · Account ·
/// Description · Category · Inflow · Outflow · running Balance · Notes, grouped
/// under a month band with inflow/outflow subtotals. Row tap opens the edit
/// dialog (Plan 050-B). All math is presenter-derived.
class LedgerDataTable extends StatelessWidget {
  final LedgerPresenter presenter;
  final void Function(TransactionRecord txn) onRowTap;
  const LedgerDataTable({
    super.key,
    required this.presenter,
    required this.onRowTap,
  });

  String _accountName(String id) =>
      presenter.accounts
          .where((a) => a.id == id)
          .map((a) => a.name)
          .firstOrNull ??
      '—';

  String _categoryName(String id) =>
      presenter.categories
          .where((c) => c.id == id)
          .map((c) => c.name)
          .firstOrNull ??
      '—';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = presenter.ledgerRowsForMonth;

    final section = WebTableSection<LedgerRow>(
      title: monthLabel(presenter.selectedMonth),
      trailing: _SubtotalTrailing(
        inflow: presenter.tableInflow,
        outflow: presenter.tableOutflow,
      ),
      rows: rows,
    );

    return WebDataTable<LedgerRow>(
      emptyLabel: 'No transactions match this filter',
      onRowTap: (r) => onRowTap(r.txn),
      sections: [section],
      columns: [
        WebColumn(
          label: 'Date',
          flex: 2,
          cell: (_, r) => Text(_dayFmt.format(r.txn.date)),
        ),
        WebColumn(
          label: 'Account',
          flex: 2,
          cell: (_, r) => Text(_accountName(r.txn.accountId),
              overflow: TextOverflow.ellipsis),
        ),
        WebColumn(
          label: 'Description',
          flex: 3,
          cell: (_, r) =>
              Text(r.txn.description, overflow: TextOverflow.ellipsis),
        ),
        WebColumn(
          label: 'Category',
          flex: 2,
          cell: (_, r) => Text(_categoryName(r.txn.categoryId),
              overflow: TextOverflow.ellipsis),
        ),
        WebColumn(
          label: 'Inflow',
          numeric: true,
          flex: 2,
          cell: (_, r) => r.txn.type == TransactionType.inflow
              ? Text(formatPeso(r.txn.amount),
                  style: TextStyle(
                      color: cs.tertiary, fontWeight: FontWeight.w600))
              : const Text('—'),
        ),
        WebColumn(
          label: 'Outflow',
          numeric: true,
          flex: 2,
          cell: (_, r) => r.txn.type == TransactionType.outflow
              ? Text(formatPeso(r.txn.amount),
                  style:
                      TextStyle(color: cs.error, fontWeight: FontWeight.w600))
              : const Text('—'),
        ),
        WebColumn(
          label: 'Balance',
          numeric: true,
          flex: 2,
          cell: (_, r) => Text(
            formatPeso(r.runningBalance),
            style: TextStyle(
              color: r.runningBalance < 0 ? cs.error : cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        WebColumn(
          label: 'Notes',
          flex: 3,
          cell: (_, r) => Text(
            r.txn.note ?? '',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _SubtotalTrailing extends StatelessWidget {
  final double inflow;
  final double outflow;
  const _SubtotalTrailing({required this.inflow, required this.outflow});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(fontWeight: FontWeight.w700);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('+${formatPeso(inflow)}',
            style: style?.copyWith(color: cs.tertiary)),
        const SizedBox(width: WebInsets.lg),
        Text('-${formatPeso(outflow)}',
            style: style?.copyWith(color: cs.error)),
      ],
    );
  }
}
