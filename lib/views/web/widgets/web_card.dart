import 'package:flutter/material.dart';
import '../../../utils/app_radii.dart';
import '../design/web_breakpoints.dart';

/// shadcn-inspired surface card: a flat filled container with a hairline
/// border and an optional header (title + description + trailing action). The
/// base building block for every web page section.
///
/// Theme-aware only — fills with [ColorScheme.surfaceContainerLow] (card on
/// background) by default; pass [onSurface] = a card/sheet to bump to
/// `surfaceContainerHigh` per the house elevation rule.
class WebCard extends StatelessWidget {
  final String? title;
  final String? description;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Set true when this card sits on top of another card/sheet (raises the
  /// fill from `surfaceContainerLow` to `surfaceContainerHigh`).
  final bool onSurface;

  const WebCard({
    super.key,
    this.title,
    this.description,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(WebInsets.xl),
    this.onSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasHeader = title != null || trailing != null;

    return Container(
      decoration: BoxDecoration(
        color: onSurface ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null)
                        Text(title!,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      if (description != null) ...[
                        const SizedBox(height: WebInsets.xs),
                        Text(description!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: WebInsets.lg),
          ],
          child,
        ],
      ),
    );
  }
}
