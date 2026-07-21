import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// The "DUE SOON" hero for the Bills tab (`Nutrition Focus Treasury.dc.html`,
/// Frame 3): a bills-accent gradient card spotlighting the most imminent unpaid
/// bill with a Mark-paid action. Shown only when a bill is due soon or overdue.
///
/// Dumb widget — the view resolves the bill, its due label, and subtitle from
/// the presenter and passes primitives; colors derive from theme tokens so the
/// card reads correctly in dark and light.
class DueSoonHero extends StatelessWidget {
  final String billName;
  final double amount;
  final String dueLabel;
  final String subtitle;
  final bool overdue;
  final VoidCallback onMarkPaid;
  final VoidCallback onEdit;

  const DueSoonHero({
    super.key,
    required this.billName,
    required this.amount,
    required this.dueLabel,
    required this.subtitle,
    required this.overdue,
    required this.onMarkPaid,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    // Overdue escalates the accent to the danger color; otherwise the bills
    // (orange) accent, matching the reference's warm due-soon card.
    final accent = overdue ? cs.error : context.appColors.bills;
    final surface = cs.surface;

    Color blend(double alpha) =>
        Color.alphaBlend(accent.withValues(alpha: alpha), surface);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            blend(isDark ? 0.30 : 0.16),
            blend(isDark ? 0.15 : 0.08),
            surface,
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.35 : 0.22),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                overdue
                    ? Icons.error_outline_rounded
                    : Icons.warning_amber_rounded,
                size: 15,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                dueLabel.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      billName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: context.appColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatPeso(amount),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onMarkPaid,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: cs.surface,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Mark paid',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 46,
                height: 44,
                child: IconButton(
                  onPressed: onEdit,
                  tooltip: 'Edit bill',
                  style: IconButton.styleFrom(
                    backgroundColor: accent.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: Icon(Icons.edit_outlined, size: 18, color: accent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
