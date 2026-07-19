import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/utils/app_motion.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// A single obligation row card — category icon, name (+ optional type badge),
/// "amount · date", an optional note line, and an optional compact progress
/// bar, with a right-aligned Pay / Receive action. Used by every Bills-tab
/// section (bills, receivables, budgeted, installments). Modeled on the
/// reference's compact card.
///
/// Dumb widget: the caller resolves everything and passes primitives +
/// callbacks. Paid/received items render dimmed (a disabled look) with a check
/// in place of the action button; the caller passes the settled detail via
/// [note].
class ObligationCard extends StatelessWidget {
  final IconData icon;

  /// Category color for the leading badge (falls back to a type accent).
  final Color iconColor;
  final String name;
  final double amount;
  final String dateLabel;

  /// Small badge shown just after the name (e.g. the bill type "UTIL"/"CC").
  final String? badgeLabel;
  final Color? badgeColor;

  /// Secondary muted line under the amount — a payment note, "Auto-generated
  /// statement", a set-aside's funding note, or the settled detail
  /// ("Paid ₱… · Jun 28") when [done].
  final String? note;

  /// 0–1 progress shown as a thin bar at the bottom (installments, set-asides).
  final double? progress;

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
    this.badgeLabel,
    this.badgeColor,
    this.note,
    this.progress,
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (badgeLabel != null) ...[
                        const SizedBox(width: 6),
                        AppBadge(
                          text: badgeLabel!,
                          color: badgeColor ?? iconColor,
                        ),
                      ],
                    ],
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
                  if (note != null && note!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (progress != null) ...[
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor:
                            cs.outlineVariant.withValues(alpha: 0.3),
                        color: iconColor,
                      ),
                    ),
                  ],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
      child: Text(label),
    );
  }
}
