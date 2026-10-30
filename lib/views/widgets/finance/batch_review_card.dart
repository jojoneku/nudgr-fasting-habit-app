import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../presenters/finance_tool_executor.dart';
import '../../../presenters/ledger_presenter.dart';
import '../system/overlays/app_confirm_dialog.dart';
import 'entry_review_card.dart';

/// Every change Nudgy proposed in one step, reviewed as one list
/// (Plan 065 phase 4, decision 2).
///
/// One vertical list for any number of rows: no swipe cards (they hide rows
/// the user then approves unseen) and no table (five columns do not fit a
/// phone). Each row expands to edit in place with the same pickers the
/// ledger's review card uses, and each row has Remove. Approve all sits below
/// the list, outside its scroller, so it never scrolls away.
///
/// Rows are styled by tier. T1 is a plain row. T2 shows before → after (the
/// executor writes edits that way). T3 — a delete, a cascade, or a change the
/// user spread to later months — is red, lists what else changes, and makes
/// Approve all ask once more.
///
/// `logTransactions` rows are the ledger's own review rows, in the same list:
/// their gaps are pickers, and Approve all waits until none is left.
///
/// Nothing is written while this shows. The scope and "already in the ledger"
/// answers live here until Approve all hands them over.
class BatchReviewCard extends StatefulWidget {
  const BatchReviewCard({
    super.key,
    required this.host,
    required this.batch,
    required this.ledger,
    this.maxRowsHeight,
  });

  final FinanceProposalHost host;
  final PendingBatch batch;
  final LedgerPresenter ledger;

  /// Ceiling for the scrolling rows, measured by the chat shell. Null asks
  /// for a fraction of the screen.
  final double? maxRowsHeight;

  @override
  State<BatchReviewCard> createState() => _BatchReviewCardState();
}

class _BatchReviewCardState extends State<BatchReviewCard> {
  static final _money = NumberFormat('#,##0.##', 'en_US');

  final ScrollController _scroll = ScrollController();

  /// Per row, by tool call id. Recurrence scope starts narrow, always:
  /// widening it writes into months the user is not looking at.
  final Map<String, bool> _applyToFuture = {};
  final Map<String, bool> _alreadyLogged = {};
  final Set<String> _expanded = {};
  final Map<String, String> _errors = {};
  bool _busy = false;

  /// A new batch must not inherit the last one's answers: the executor swaps
  /// batches without a frame in between, so this State is reused.
  @override
  void didUpdateWidget(BatchReviewCard old) {
    super.didUpdateWidget(old);
    if (old.batch.id != widget.batch.id) {
      _applyToFuture.clear();
      _alreadyLogged.clear();
      _expanded.clear();
      _errors.clear();
      _busy = false;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    if (widget.batch.needsSecondConfirm(_applyToFuture)) {
      final ok = await AppConfirmDialog.confirm(
        context: context,
        title: 'Approve these changes?',
        body: 'Some of them delete data or change later months, and they '
            'cannot be undone from here.',
        confirmLabel: 'Approve',
        isDestructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    await widget.host.approveAll(
      applyToFuture: Map.of(_applyToFuture),
      alreadyLogged: Map.of(_alreadyLogged),
    );
    // Normally gone by now; a failed write leaves it, and a dead button is
    // no answer to "that didn't save".
    if (mounted) setState(() => _busy = false);
  }

  void _edit(String callId, Map<String, Object?> patch) {
    final error = widget.host.editAction(callId, patch);
    setState(() {
      if (error == null) {
        _errors.remove(callId);
      } else {
        _errors[callId] = error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final host = widget.host;
    final actions = widget.batch.actions;
    final entries =
        host.batchHasLedgerRows ? widget.ledger.chatState.entries : const [];
    final count = host.openRowCount;
    final rowsCap =
        widget.maxRowsHeight ?? MediaQuery.sizeOf(context).height * 0.32;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: rowsCap),
          child: Scrollbar(
            controller: _scroll,
            child: ListView(
              controller: _scroll,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                // Inside the scroller: the chat shell budgets this card as
                // rows + an 8px gap + the button row, like the ledger's
                // review card, so a header outside the cap overflowed.
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome_outlined,
                          size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        'NUDGY SUGGESTS',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                      ),
                    ],
                  ),
                ),
                for (final a in actions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ActionRow(
                      action: a,
                      ledger: widget.ledger,
                      expanded: _expanded.contains(a.call.id),
                      laterMonths: _applyToFuture[a.call.id] ?? false,
                      alreadyLogged: _alreadyLogged[a.call.id],
                      error: _errors[a.call.id],
                      busy: _busy,
                      onToggle: () => setState(() {
                        if (!_expanded.remove(a.call.id)) {
                          _expanded.add(a.call.id);
                        }
                      }),
                      onRemove: () => host.removeAction(a.call.id),
                      onScope: (v) =>
                          setState(() => _applyToFuture[a.call.id] = v),
                      onLedgerChoice: (v) =>
                          setState(() => _alreadyLogged[a.call.id] = v),
                      onEdit: (patch) => _edit(a.call.id, patch),
                    ),
                  ),
                for (var i = 0; i < entries.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: LedgerReviewRow(
                      ledger: widget.ledger,
                      entry: entries[i],
                      index: i,
                      money: _money,
                      showRemove: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : host.decline,
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              child: const Text('Not now'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed:
                  _busy || count == 0 || !host.canApproveAll ? null : _approve,
              style: widget.batch.needsSecondConfirm(_applyToFuture)
                  ? FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                      minimumSize: const Size(0, 44),
                    )
                  : FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.check, size: 18),
              label: Text(widget.batch.approveLabel(count)),
            ),
          ],
        ),
      ],
    );
  }
}

/// One proposed change: what will be saved, its tier, and — expanded — the
/// fields the user can change in place.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.action,
    required this.ledger,
    required this.expanded,
    required this.laterMonths,
    required this.alreadyLogged,
    required this.error,
    required this.busy,
    required this.onToggle,
    required this.onRemove,
    required this.onScope,
    required this.onLedgerChoice,
    required this.onEdit,
  });

  final PendingFinanceAction action;
  final LedgerPresenter ledger;
  final bool expanded;
  final bool laterMonths;
  final bool? alreadyLogged;
  final String? error;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  final ValueChanged<bool> onScope;
  final ValueChanged<bool> onLedgerChoice;
  final ValueChanged<Map<String, Object?>> onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tier = action.tierWith(laterMonths: laterMonths);
    final red = tier == ProposalTier.destructive;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      decoration: BoxDecoration(
        color: red ? cs.errorContainer : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: red ? cs.error : cs.outlineVariant,
          width: red ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  action.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: red ? cs.onErrorContainer : cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (action.editable.isNotEmpty)
                IconButton(
                  tooltip: expanded ? 'Done editing' : 'Edit',
                  onPressed: busy ? null : onToggle,
                  icon: Icon(expanded ? Icons.expand_less : Icons.edit_outlined,
                      size: 18),
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                ),
              IconButton(
                tooltip: 'Remove',
                onPressed: busy ? null : onRemove,
                icon: const Icon(Icons.close, size: 18),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ),
          for (final row in action.details)
            Padding(
              padding: const EdgeInsets.only(bottom: 3, right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      row.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: red ? cs.onErrorContainer : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: red ? cs.onErrorContainer : cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (red && laterMonths)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Text(
                action.laterMonthsNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (action.ledgerChoice case final choice?)
            LedgerChoiceTile(
              choice: choice,
              alreadyLogged: alreadyLogged ?? choice.alreadyLogged,
              onChanged: busy || !choice.canRecord ? null : onLedgerChoice,
            ),
          if (action.option case final option?)
            RowOptionTile(
              option: option,
              onChanged: busy ? null : (v) => onEdit({option.inputKey: v}),
            ),
          if (action.isRecurring) ...[
            const SizedBox(height: 4),
            ScopeChoice(
              applyToFuture: laterMonths,
              onChanged: busy ? null : onScope,
            ),
          ],
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  for (final e in action.editable.entries)
                    ReviewFieldChip(
                      icon: _icon(e.key),
                      label: _label(e.key),
                      needed: false,
                      onTap: busy
                          ? null
                          : () => _editField(context, e.key, e.value),
                    ),
                ],
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ),
        ],
      ),
    );
  }

  static IconData _icon(ProposalField f) => switch (f) {
        ProposalField.name => Icons.edit_note,
        ProposalField.amount => Icons.payments_outlined,
        ProposalField.account => Icons.account_balance_wallet_outlined,
        ProposalField.category => Icons.label_outline,
        ProposalField.date => Icons.event_outlined,
        ProposalField.day => Icons.calendar_today_outlined,
      };

  static String _label(ProposalField f) => switch (f) {
        ProposalField.name => 'Rename',
        ProposalField.amount => 'Change amount',
        ProposalField.account => 'Change account',
        ProposalField.category => 'Change category',
        ProposalField.date => 'Change date',
        ProposalField.day => 'Change day',
      };

  Future<void> _editField(
      BuildContext context, ProposalField field, String key) async {
    // Every use of [context] happens before the one await.
    final Future<Object?> asked = switch (field) {
      ProposalField.amount => showDialog<double>(
          context: context,
          builder: (_) => const ReviewAmountDialog(initial: null),
        ),
      ProposalField.account => _pick(context, 'Account', [
          for (final a in ledger.accounts)
            if (a.isActive)
              (
                id: a.name,
                label: a.name,
                icon: Icons.account_balance_wallet_outlined
              ),
        ]),
      ProposalField.category => _pick(context, 'Category', [
          for (final c in ledger.categories)
            (id: c.name, label: c.name, icon: Icons.label_outline),
        ]),
      ProposalField.date => _pickDate(context),
      ProposalField.name => showDialog<String>(
          context: context,
          builder: (_) => const _TextDialog(title: 'Name'),
        ),
      ProposalField.day => showDialog<String>(
          context: context,
          builder: (_) =>
              const _TextDialog(title: 'Day of month (1-31)', number: true),
        ).then((v) => v == null ? null : int.tryParse(v)),
    };
    final value = await asked;
    if (value == null) return;
    onEdit({key: value});
  }

  static Future<String?> _pick(BuildContext context, String title,
          List<ReviewPickerOption> options) =>
      showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (_) => ReviewPickerSheet(title: title, options: options),
      );

  static Future<String?> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    return chosen == null ? null : DateFormat('yyyy-MM-dd').format(chosen);
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, this.number = false});
  final String title;
  final bool number;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    Navigator.of(context).pop(text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType:
              widget.number ? TextInputType.number : TextInputType.text,
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

/// "Already in the ledger?" for a settlement. Checked means the bill or
/// receivable is only flagged; unchecked records the money as a new entry.
/// Locked on when there is no account to record it against.
class LedgerChoiceTile extends StatelessWidget {
  const LedgerChoiceTile({
    super.key,
    required this.choice,
    required this.alreadyLogged,
    required this.onChanged,
  });

  final LedgerEntryChoice choice;
  final bool alreadyLogged;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return CheckboxListTile(
      value: alreadyLogged,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        'Already added to ledger',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        choice.hint,
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// A row's optional extra ([RowOption]) as a checkbox, e.g. "Also add a
/// monthly set-aside in Bills" under a savings budget.
class RowOptionTile extends StatelessWidget {
  const RowOptionTile({
    super.key,
    required this.option,
    required this.onChanged,
  });

  final RowOption option;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return CheckboxListTile(
      value: option.value,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        option.label,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        option.hint,
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// The recurrence-scope control. Two explicit choices rather than a checkbox,
/// because the wider one writes into months the user is not looking at.
class ScopeChoice extends StatelessWidget {
  const ScopeChoice({
    super.key,
    required this.applyToFuture,
    required this.onChanged,
  });

  final bool applyToFuture;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Apply to',
          style:
              theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ScopeOption(
              label: 'This month',
              selected: !applyToFuture,
              onTap: onChanged == null ? null : () => onChanged!(false),
            ),
            _ScopeOption(
              label: 'Every month ahead',
              selected: applyToFuture,
              onTap: onChanged == null ? null : () => onChanged!(true),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          // 44px minimum touch target (CLAUDE.md #4).
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 1.2 : 0.5,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
