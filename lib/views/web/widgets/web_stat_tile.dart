import 'package:flutter/material.dart';
import 'web_card.dart';
import '../design/web_breakpoints.dart';

/// A single KPI tile — a label, a large value, and optional sub-text / delta /
/// icon. Drop several into a `Row`/`Wrap` for a dashboard stat strip.
///
/// [emphasize] renders the hero metric (Net Worth) slightly larger.
class WebStatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData? icon;

  /// Optional tone for the value text (e.g. negative net flow in error color).
  final Color? valueColor;
  final bool emphasize;

  const WebStatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    this.valueColor,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final valueStyle = (emphasize
            ? theme.textTheme.headlineMedium
            : theme.textTheme.headlineSmall)
        ?.copyWith(
      fontWeight: FontWeight.w700,
      color: valueColor ?? cs.onSurface,
      // Tabular figures so values keep an even rhythm and align with the grid.
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return WebCard(
      padding: const EdgeInsets.all(WebInsets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: WebInsets.sm),
              ],
              Expanded(
                // Normalize label presentation here (one source of truth) so
                // every KPI strip reads uniformly regardless of caller casing.
                child: Text(label.toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: WebInsets.sm),
          Text(value,
              style: valueStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (sub != null) ...[
            const SizedBox(height: WebInsets.xs),
            Text(sub!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
