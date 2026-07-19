import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/utils/app_motion.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// A single obligation row card — category icon, name, "amount · date", and a
/// right-aligned Pay / Receive action. Used by every Bills-tab section (bills,
/// receivables, budgeted, installments). Modeled on the reference's compact
/// Meralco card, minus the "due in N days" urgency line.
///
/// Dumb widget: the caller resolves the category [icon]/[iconColor] and passes
/// primitives + callbacks. Paid/received items render dimmed with a check in
/// place of the action button.
class ObligationCard extends StatelessWidget {
  final IconData icon;

  /// Category color for the leading badge (falls back to a type accent).
  final Color iconColor;
  final String name;
  final double amount;
  final String dateLabel;

  /// True for money coming in (receivables): amount shows a `+` in the success
  /// color and the action defaults to "Receive".
  final bool isInflow;

  /// Paid / received — dims the card and shows a check instead of the button.
  final bool done;

  /// Button label, e.g. "Pay" or "Receive".
  final String actionLabel;

  /// Fires the primary action (opens the existing mark-paid/received sheet).
  final VoidCallback? onAction;

  /// Tap (and long-press "Edit") — opens the existing edit sheet.
  final VoidCallback? onEdit;

  /// Long-press "Delete".
  final VoidCallback? onDelete;

  const ObligationCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.amount,
    required this.dateLabel,
    required this.actionLabel,
    this.isInflow = false,
    this.done = false,
    this.onAction,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amountColor = isInflow ? context.appColors.success : cs.onSurface;
    final amountText = '${isInflow ? '+' : ''}${formatPeso(amount)}';
    // Pay (outflow) = bills orange; Receive (inflow) = success green — a
    // consistent action language independent of the category color.
    final actionColor =
        isInflow ? context.appColors.success : context.appColors.bills;

    return AnimatedOpacity(
      opacity: done ? 0.55 : 1,
      duration: AppMotion.appear,
      child: AppCard(
        variant: AppCardVariant.outlined,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        onTap: onEdit,
        onLongPress: (onEdit != null || onDelete != null)
            ? () => _showMenu(context)
            : null,
        child: Row(
          children: [
            AppIconBadge(icon: icon, color: iconColor, size: 40, iconSize: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        amountText,
                        style: TextStyle(
                          color: amountColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '· $dateLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (done)
              Icon(Icons.check_circle,
                  color: context.appColors.success, size: 22)
            else if (onAction != null)
              _ActionButton(
                label: actionLabel,
                color: actionColor,
                onTap: onAction!,
              ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              ListTile(
                leading: Icon(Icons.edit_outlined, color: cs.primary),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  onEdit?.call();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('Delete', style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        minimumSize: const Size(0, 44),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
      child: Text(label),
    );
  }
}
