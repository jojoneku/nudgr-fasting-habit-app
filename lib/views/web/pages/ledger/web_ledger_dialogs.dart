import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/treasury/ledger/add_transaction_sheet.dart';
import '../../widgets/web_widgets.dart';

/// Opens the existing [AddTransactionSheet] as a centered web dialog — reuses
/// the mobile form verbatim (add when [existing] is null, edit + delete when
/// it's provided). The sheet pops itself via [Navigator.pop] on save/delete,
/// which dismisses the dialog (Plan 050-B).
Future<void> showLedgerTransactionDialog({
  required BuildContext context,
  required LedgerPresenter presenter,
  TransactionRecord? existing,
}) {
  final isEdit = existing != null;
  // AddTransactionSheet fills height and manages its own scroll, so the dialog
  // must NOT wrap it in a scroll view (scrollable: false).
  return showWebDialog<void>(
    context: context,
    title: isEdit ? 'Edit transaction' : 'Log transaction',
    maxWidth: 480,
    scrollable: false,
    child: AddTransactionSheet(presenter: presenter, existing: existing),
  );
}
