import 'package:flutter/material.dart';

/// The bar that replaces the FAB while a Bills-tab section is in multi-select:
/// what is picked on top, what can be done to it underneath.
///
/// Dumb widget — the caller decides which actions apply to the current
/// selection and passes null for the ones that don't (a selection of unpaid
/// bills has nothing to undo, so Undo greys out rather than disappearing, and
/// the bar's shape stays put as the selection changes).
class BatchActionBar extends StatelessWidget {
  /// How many rows are picked, and how many the section holds.
  final int selectedCount;
  final int totalCount;

  /// The settle action's verb — "Pay", "Receive", "Fund".
  final String settleLabel;

  /// Settles every unsettled row in the selection. Null disables the button.
  final VoidCallback? onSettle;

  /// Reverses every settled row in the selection.
  final VoidCallback? onUndo;

  /// Deletes the whole selection.
  final VoidCallback? onDelete;

  /// Picks every row in the section, or clears the selection when they are all
  /// already picked.
  final VoidCallback onSelectAll;

  /// Leaves multi-select.
  final VoidCallback onClose;

  const BatchActionBar({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.settleLabel,
    required this.onSelectAll,
    required this.onClose,
    this.onSettle,
    this.onUndo,
    this.onDelete,
  });

  bool get _allSelected => selectedCount >= totalCount && totalCount > 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onClose,
                    tooltip: 'Done selecting',
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Text(
                      '$selectedCount of $totalCount selected',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onSelectAll,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      textStyle: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    child: Text(_allSelected ? 'Clear' : 'Select all'),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _BarButton(
                      label: settleLabel,
                      icon: Icons.check_rounded,
                      color: cs.primary,
                      filled: true,
                      onPressed: onSettle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BarButton(
                      label: 'Undo',
                      icon: Icons.undo_rounded,
                      color: cs.onSurfaceVariant,
                      onPressed: onUndo,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BarButton(
                      label: 'Delete',
                      icon: Icons.delete_outline_rounded,
                      color: cs.error,
                      onPressed: onDelete,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One action in the bar: filled for the primary settle action, outlined for the
/// rest. Both clear the 44px touch target.
class _BarButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback? onPressed;

  const _BarButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: cs.onPrimary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
        icon: Icon(icon, size: 16),
        label: child,
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: cs.outlineVariant),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
      icon: Icon(icon, size: 16),
      label: child,
    );
  }
}
