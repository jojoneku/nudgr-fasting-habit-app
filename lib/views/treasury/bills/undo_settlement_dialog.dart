import 'package:flutter/material.dart';

/// What the user chose in [showUndoSettlementDialog].
class UndoSettlementChoice {
  /// Also delete the ledger transaction the settlement created, restoring the
  /// account balance. False keeps the transaction and only reopens the entry.
  final bool removeTransaction;

  const UndoSettlementChoice({required this.removeTransaction});
}

/// Confirms reversing a paid / received / funded entry, and — when the
/// settlement wrote to the ledger — lets the user say whether the transaction
/// should go with it.
///
/// The two cases are genuinely different and only the user knows which applies:
/// a mis-tap means the money never moved (remove the transaction, the default),
/// while a correctly-recorded payment filed against the wrong row means the
/// money did move (keep it, and only the flag is reversed).
///
/// Returns null when cancelled.
///
/// [entryLabel] names what is being reversed ("bill", "receivable",
/// "set-aside"); [ledgerEffect] describes what removing the transaction does to
/// the balance, e.g. "GCash will be credited back ₱3,200".
///
/// Pass `hasLedgerEntry: false` when there is no choice to offer — either
/// nothing is linked, or the transaction always goes (an installment payment,
/// which has no flag of its own). [ledgerEffect] is then shown as a plain note.
Future<UndoSettlementChoice?> showUndoSettlementDialog({
  required BuildContext context,
  required String title,
  required String name,
  required String entryLabel,
  required bool hasLedgerEntry,
  String? ledgerEffect,
}) {
  var removeTransaction = true;
  return showDialog<UndoSettlementChoice>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocalState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"$name" goes back to being an open $entryLabel.'),
            if (hasLedgerEntry) ...[
              const SizedBox(height: 4),
              CheckboxListTile(
                value: removeTransaction,
                onChanged: (v) =>
                    setLocalState(() => removeTransaction = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Also remove the ledger transaction'),
                subtitle: Text(
                  removeTransaction
                      ? (ledgerEffect ?? 'The account balance is restored.')
                      : 'The transaction stays in the ledger and balances are '
                          'unchanged.',
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                ledgerEffect ??
                    'No ledger transaction is linked to it, so no balance '
                        'changes.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              UndoSettlementChoice(
                // Nothing to remove means the flag is all there is to reverse.
                removeTransaction: hasLedgerEntry && removeTransaction,
              ),
            ),
            child: const Text('Undo'),
          ),
        ],
      ),
    ),
  );
}
