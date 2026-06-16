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

  /// Optional left accent stripe (e.g. red for bills due, green for income).
  final Color? accentColor;

  const WebCard({
    super.key,
    this.title,
    this.description,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(WebInsets.xl),
    this.onSurface = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasHeader = title != null || trailing != null;

    final content = Padding(
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

    return Container(
      decoration: BoxDecoration(
        color: onSurface ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      // Clip so the accent stripe follows the card's rounded corners.
      clipBehavior: accentColor != null ? Clip.antiAlias : Clip.none,
      child: accentColor == null
          ? content
          // IntrinsicHeight bounds the Row's height to the content so the
          // stretched stripe doesn't try to grow infinitely in the scroll view.
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: accentColor),
                  Expanded(child: content),
                ],
              ),
            ),
    );
  }
}
