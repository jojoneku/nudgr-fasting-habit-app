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
  return showDialog<void>(
    context: context,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Dialog(
        backgroundColor: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(WebInsets.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEdit ? 'Edit transaction' : 'Log transaction',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: WebInsets.md),
                // AddTransactionSheet is a Flexible-wrapped Column already.
                Flexible(
                  child: AddTransactionSheet(
                    presenter: presenter,
                    existing: existing,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
