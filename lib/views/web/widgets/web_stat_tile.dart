import 'package:flutter/material.dart';
import '../../../utils/app_radii.dart';
import 'web_card.dart';
import '../design/web_breakpoints.dart';

/// A single KPI tile — an UPPERCASE label, a large value, and optional
/// sub-text / delta / icon. Drop several into a `Row`/`Wrap` for a dashboard
/// stat strip.
///
/// [emphasize] renders the hero metric slightly larger. [accent] fills the
/// card with [ColorScheme.primary] and flips text to `onPrimary` (the "NET
/// POSITION" hero card); the trailing [icon] then sits top-right.
class WebStatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData? icon;

  /// Optional tone for the value text (e.g. obligations in error color).
  /// Ignored when [accent] is true (hero uses `onPrimary`).
  final Color? valueColor;
  final bool emphasize;

  /// Filled hero variant: `primary` background, `onPrimary` text, trailing
  /// icon top-right.
  final bool accent;

  const WebStatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    this.valueColor,
    this.emphasize = false,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final fg = accent ? cs.onPrimary : cs.onSurface;
    final mutedFg =
        accent ? cs.onPrimary.withValues(alpha: 0.78) : cs.onSurfaceVariant;

    final valueStyle = (emphasize
            ? theme.textTheme.headlineMedium
            : theme.textTheme.headlineSmall)
        ?.copyWith(
      fontWeight: FontWeight.w700,
      color: accent ? fg : (valueColor ?? fg),
    );

    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: mutedFg,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.7,
    );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label.toUpperCase(),
                  style: labelStyle, overflow: TextOverflow.ellipsis),
            ),
            if (icon != null) ...[
              const SizedBox(width: WebInsets.sm),
              // Reference StatTile seats the icon in a 28px tinted rounded
              // square (`bg-hover-subtle`), not as a bare glyph.
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent
                      ? cs.onPrimary.withValues(alpha: 0.15)
                      : cs.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(icon, size: 16, color: mutedFg),
              ),
            ],
          ],
        ),
        const SizedBox(height: WebInsets.sm),
        Text(value,
            style: valueStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (sub != null) ...[
          const SizedBox(height: WebInsets.xs),
          Text(sub!,
              style: theme.textTheme.bodySmall?.copyWith(color: mutedFg)),
        ],
      ],
    );

    if (accent) {
      return Container(
        padding: const EdgeInsets.all(WebInsets.lg),
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: column,
      );
    }

    return WebCard(
      padding: const EdgeInsets.all(WebInsets.lg),
      child: column,
    );
  }
}
