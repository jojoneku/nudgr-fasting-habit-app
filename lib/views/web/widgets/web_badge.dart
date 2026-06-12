import 'package:flutter/material.dart';
import '../../../utils/app_radii.dart';
import '../design/web_breakpoints.dart';

/// Tone of a [WebBadge] — maps to a theme color, never a hardcoded one.
enum WebBadgeTone { neutral, success, warning, danger, info }

/// Small status pill (paid / unpaid / over-budget / due-soon). shadcn "badge".
class WebBadge extends StatelessWidget {
  final String label;
  final WebBadgeTone tone;
  final IconData? icon;

  const WebBadge(this.label,
      {super.key, this.tone = WebBadgeTone.neutral, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (fg, bg) = switch (tone) {
      WebBadgeTone.neutral => (cs.onSurfaceVariant, cs.surfaceContainerHighest),
      WebBadgeTone.success => (
          cs.tertiary,
          cs.tertiary.withValues(alpha: 0.14)
        ),
      WebBadgeTone.warning => (
          cs.secondary,
          cs.secondary.withValues(alpha: 0.14)
        ),
      WebBadgeTone.danger => (cs.error, cs.error.withValues(alpha: 0.14)),
      WebBadgeTone.info => (cs.primary, cs.primary.withValues(alpha: 0.14)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: WebInsets.sm, vertical: WebInsets.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: WebInsets.xs),
          ],
          Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  )),
        ],
      ),
    );
  }
}
