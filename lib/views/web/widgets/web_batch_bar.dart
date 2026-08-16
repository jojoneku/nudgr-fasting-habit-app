import 'package:flutter/material.dart';

import '../design/web_breakpoints.dart';

/// How one row participates in a batch selection.
///
/// Rows take this instead of raw booleans so a row that isn't selectable (the
/// section isn't in select mode, or another section owns the selection) is a
/// single null check rather than three flags threaded through every widget.
class WebRowSelection {
  /// This row's section is in select mode, so the row shows a selection box in
  /// place of its settle checkbox and hides its per-row actions.
  final bool active;
  final bool selected;
  final VoidCallback onToggle;

  const WebRowSelection({
    required this.active,
    required this.selected,
    required this.onToggle,
  });
}

/// The per-card header control: "Select" when idle, and the count + select-all
/// + Cancel once a selection is running.
///
/// Desktop deliberately diverges from mobile here. Mobile enters selection with
/// a long-press, which has no discoverable desktop equivalent — a mouse has no
/// long-press, and hiding the entry point behind one would leave batch settling
/// undiscoverable on the platform where it matters most.
class WebBatchSelectControl extends StatelessWidget {
  /// True when *this* section owns the running selection.
  final bool active;

  /// True when another section owns it — this one can't start a second.
  final bool locked;
  final int selectedCount;
  final int totalCount;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onToggleAll;

  const WebBatchSelectControl({
    super.key,
    required this.active,
    required this.locked,
    required this.selectedCount,
    required this.totalCount,
    required this.onStart,
    required this.onCancel,
    required this.onToggleAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!active) {
      return TextButton.icon(
        // Locked rather than hidden: the control staying put explains why the
        // other sections went quiet instead of looking broken.
        onPressed: locked || totalCount == 0 ? null : onStart,
        icon: const Icon(Icons.checklist_rounded, size: 18),
        label: const Text('Select'),
      );
    }

    final allSelected = totalCount > 0 && selectedCount == totalCount;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$selectedCount selected',
          style: theme.textTheme.labelLarge?.copyWith(color: cs.primary),
        ),
        const SizedBox(width: WebInsets.sm),
        TextButton(
          onPressed: onToggleAll,
          child: Text(allSelected ? 'Clear all' : 'Select all'),
        ),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }
}

/// The action bar shown under a card while a selection is running: settle, undo,
/// delete, for however many of the picked rows each action can actually apply
/// to.
///
/// Counts are passed in already resolved (Rule 1 — the caller's presenter-backed
/// getters do the arithmetic). An action with nothing to act on is disabled and
/// says so, rather than being hidden and leaving the bar jumping around as the
/// selection changes.
class WebBatchBar extends StatelessWidget {
  /// Verb for the settle action — "Pay", "Receive", "Fund".
  final String settleVerb;
  final int selectedCount;
  final int settleableCount;
  final int undoableCount;
  final VoidCallback onSettle;
  final VoidCallback onUndo;
  final VoidCallback onDelete;

  /// False while a batch is in flight, so a double-click can't fire it twice.
  final bool enabled;

  const WebBatchBar({
    super.key,
    required this.settleVerb,
    required this.selectedCount,
    required this.settleableCount,
    required this.undoableCount,
    required this.onSettle,
    required this.onUndo,
    required this.onDelete,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: WebInsets.md),
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.lg,
        vertical: WebInsets.md,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
      ),
      child: Wrap(
        spacing: WebInsets.sm,
        runSpacing: WebInsets.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: WebInsets.sm),
            child: Text(
              '$selectedCount selected',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton.icon(
            onPressed: enabled && settleableCount > 0 ? onSettle : null,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text('$settleVerb $settleableCount'),
          ),
          OutlinedButton.icon(
            onPressed: enabled && undoableCount > 0 ? onUndo : null,
            icon: const Icon(Icons.undo_rounded, size: 18),
            label: Text('Undo $undoableCount'),
          ),
          OutlinedButton.icon(
            onPressed: enabled && selectedCount > 0 ? onDelete : null,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text('Delete $selectedCount'),
            style: OutlinedButton.styleFrom(foregroundColor: cs.error),
          ),
        ],
      ),
    );
  }
}

/// The selection box a row shows in place of its settle checkbox while a batch
/// selection is running. Sized to the 44px minimum touch target.
class WebRowSelectBox extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const WebRowSelectBox({
    super.key,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Checkbox(
        value: selected,
        onChanged: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
