import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/finance/extracted_entry.dart';
import '../../../models/finance/finance_parse_result.dart';
import '../../../models/finance/transaction_record.dart';
import '../../../presenters/ledger_presenter.dart';

/// The rows the extractor found, shown for review before anything commits.
///
/// Every gap the model admitted to is a picker on the row that has it, not a
/// question in the conversation: the old clarify loop spent a Bedrock call and
/// a user turn to learn which account "90 for personal shopping" belonged to,
/// on a three-turn budget that ended at a blank form. A dropdown answers it
/// instantly, and it is what makes this card a workable substitute for the
/// manual form rather than a preview of one.
///
/// Layout note: each entry is its own inset card rather than a
/// divider-separated block. Three surfaces render this widget on three
/// different parent fills
/// (the chat panel's `surfaceContainerHigh`, the Ledger drawer's
/// `surfaceContainerLow`, the advisor card's `surfaceContainerHighest`), so the
/// rows use `surfaceContainerLowest` plus a hairline border — a well reads as a
/// row on all three, where a raised fill would vanish on one of them.
class EntryReviewCard extends StatelessWidget {
  const EntryReviewCard({
    super.key,
    required this.ledger,
    required this.state,
  });

  final LedgerPresenter ledger;
  final LedgerChatState state;

  static final _money = NumberFormat('#,##0.##', 'en_US');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = state.entries;
    final ready = state.isReadyToCommit;
    final outstanding = state.unresolvedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _ReviewRow(
            ledger: ledger,
            entry: entries[i],
            index: i,
            money: _money,
            showRemove: entries.length > 1,
          ),
        ],
        const SizedBox(height: 8),
        // Count and the "still needs a chip" nudge share the action row's left
        // slot: on a drawer that sits above the keyboard, a status line of its
        // own costs a row of entry for nothing.
        Row(
          children: [
            Expanded(
              child: _StatusLine(
                count: entries.length,
                outstanding: outstanding,
              ),
            ),
            TextButton(
              onPressed: ledger.cancelChat,
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 44),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              // Disabled while any row has a gap: committing "the ready ones"
              // behind the user's back is the silent partial logging this
              // whole change exists to end.
              onPressed: ready ? ledger.confirmEntries : null,
              icon: const Icon(Icons.check, size: 17),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(0, 44),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: Text(
                entries.length > 1 ? 'Log all ${entries.length}' : 'Log it',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One line of state for the whole card: what is left to fill, or how many rows
/// are about to be written.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.count, required this.outstanding});

  final int count;
  final int outstanding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pending = outstanding > 0;
    final text = pending
        ? (outstanding == 1
            ? 'Tap the lit chip to finish 1 entry'
            : 'Tap the lit chips to finish $outstanding entries')
        : (count > 1 ? '$count entries ready' : 'Ready to log');

    return Row(
      children: [
        Icon(
          pending ? Icons.edit_outlined : Icons.check_circle_outline,
          size: 13,
          color: pending ? cs.primary : cs.onSurfaceVariant,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: pending ? cs.primary : cs.onSurfaceVariant,
              fontSize: 11.5,
              fontWeight: pending ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// One reviewable row: what it was for, how much, and a chip per field. A chip
/// for a field the model resolved is informational; one for a field in
/// [ExtractedEntry.missing] is tinted and opens its picker.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.ledger,
    required this.entry,
    required this.index,
    required this.money,
    required this.showRemove,
  });

  final LedgerPresenter ledger;
  final ExtractedEntry entry;
  final int index;
  final NumberFormat money;
  final bool showRemove;

  bool _needs(EntryField f) => entry.missing.contains(f);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txn = entry.txn;
    final type = txn.type ?? TransactionType.outflow;

    final amountColor = switch (type) {
      TransactionType.inflow => cs.tertiary,
      TransactionType.outflow => cs.error,
      TransactionType.transfer => cs.primary,
    };
    final typeIcon = switch (type) {
      TransactionType.inflow => Icons.south_west,
      TransactionType.outflow => Icons.north_east,
      TransactionType.transfer => Icons.swap_horiz,
    };
    final sign = type == TransactionType.inflow ? '+' : '';
    final amountText =
        txn.amount == null ? 'Amount' : '$sign₱${money.format(txn.amount)}';

    return Container(
      // Vertical padding stays thin because both rows inside already carry the
      // 44px tap-target minimum — doubling that up is where the old card lost
      // most of its height.
      padding: const EdgeInsets.fromLTRB(10, 2, 6, 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: amountColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(typeIcon, size: 13, color: amountColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  txn.description.isEmpty ? 'New entry' : txn.description,
                  // Two lines, not one: a truncated description can hide the
                  // very detail the user is reviewing this row to catch.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _TapTarget(
                onTap: () => _editAmount(context),
                child: Text(
                  amountText,
                  style: TextStyle(
                    color: _needs(EntryField.amount) ? cs.primary : amountColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    decoration: _needs(EntryField.amount)
                        ? TextDecoration.underline
                        : null,
                  ),
                ),
              ),
              if (showRemove)
                IconButton(
                  icon: Icon(Icons.close, size: 15, color: cs.onSurfaceVariant),
                  onPressed: () => ledger.removeEntry(index),
                  tooltip: 'Remove this entry',
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                )
              else
                const SizedBox(width: 4),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              _FieldChip(
                icon: Icons.account_balance_wallet_outlined,
                label: _accountName(txn.accountId) ?? 'Add account',
                needed: _needs(EntryField.account),
                onTap: () => _pickAccount(context, EntryField.account),
              ),
              if (type == TransactionType.transfer)
                _FieldChip(
                  icon: Icons.arrow_forward,
                  label: _accountName(txn.transferToAccountId) ??
                      'Add destination',
                  needed: _needs(EntryField.transferTo),
                  onTap: () => _pickAccount(context, EntryField.transferTo),
                )
              else
                _FieldChip(
                  icon: Icons.label_outline,
                  label: _categoryName(txn.categoryId) ?? 'Add category',
                  needed: _needs(EntryField.category),
                  onTap: () => _pickCategory(context),
                ),
              _FieldChip(
                icon: Icons.event_outlined,
                label: _dateLabel(txn.date),
                needed: false,
                onTap: () => _pickDate(context),
              ),
              if (entry.isLowConfidence)
                const _FieldChip(
                  icon: Icons.help_outline,
                  label: 'Check this',
                  needed: true,
                  onTap: null,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String? _accountName(String? id) {
    if (id == null) return null;
    for (final a in ledger.accounts) {
      if (a.id == id) return a.name;
    }
    return null;
  }

  String? _categoryName(String? id) {
    if (id == null) return null;
    for (final c in ledger.categories) {
      if (c.id == id) return c.name;
    }
    return null;
  }

  /// A named date is shown; an unnamed one reads "Today", which is what the
  /// commit path will stamp — so the chip never implies a date that isn't real.
  String _dateLabel(DateTime? date) {
    if (date == null) return 'Today';
    final now = DateTime.now();
    final d = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('MMM d').format(date);
  }

  Future<void> _pickAccount(BuildContext context, EntryField field) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _PickerSheet(
        title: field == EntryField.transferTo ? 'Transfer to' : 'Account',
        options: [
          for (final a in ledger.accounts)
            if (a.isActive && !a.isSubAccount && !a.isCustodian)
              (
                id: a.id,
                label: a.name,
                icon: Icons.account_balance_wallet_outlined
              ),
        ],
      ),
    );
    if (chosen == null) return;
    if (field == EntryField.transferTo) {
      ledger.setEntryTransferTo(index, chosen);
    } else {
      ledger.setEntryAccount(index, chosen);
    }
  }

  Future<void> _pickCategory(BuildContext context) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _PickerSheet(
        title: 'Category',
        options: [
          for (final c in ledger.categories)
            (id: c.id, label: c.name, icon: Icons.label_outline),
        ],
      ),
    );
    if (chosen != null) ledger.setEntryCategory(index, chosen);
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: entry.txn.date ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (chosen != null) ledger.setEntryDate(index, chosen);
  }

  Future<void> _editAmount(BuildContext context) async {
    final value = await showDialog<double>(
      context: context,
      builder: (_) => _AmountDialog(initial: entry.txn.amount),
    );
    if (value != null) ledger.setEntryAmount(index, value);
  }
}

/// A chip that either reports a resolved field or invites the user to fill it.
/// Painted tight (a 30px pill) inside a 44px tap target, so the row reads as a
/// dense strip of metadata while still clearing the touch minimum.
class _FieldChip extends StatelessWidget {
  const _FieldChip({
    required this.icon,
    required this.label,
    required this.needed,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool needed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = needed ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return _TapTarget(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: needed ? cs.primaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: needed ? cs.primary : cs.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: needed ? fg : cs.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                height: 1.1,
                fontWeight: needed ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps a small chip tappable at the 44px minimum without inflating its
/// painted size.
class _TapTarget extends StatelessWidget {
  const _TapTarget({required this.onTap, required this.child});
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(widthFactor: 1, child: child),
        ),
      );
}

typedef _PickerOption = ({String id, String label, IconData icon});

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.title, required this.options});

  final String title;
  final List<_PickerOption> options;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              title,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (_, i) {
                final o = options[i];
                return ListTile(
                  leading: Icon(o.icon, color: cs.onSurfaceVariant),
                  title: Text(o.label),
                  onTap: () => Navigator.of(context).pop(o.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.initial});
  final double? initial;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial == null ? '' : widget.initial!.toStringAsFixed(2),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text.replaceAll(',', '').trim());
    Navigator.of(context).pop(value != null && value > 0 ? value : null);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Amount'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '₱ '),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Set')),
        ],
      );
}
