import 'package:flutter/material.dart';
import '../../../../utils/app_radii.dart';
import '../../../../utils/app_spacing.dart';
import 'app_pressable.dart';

enum AppCardVariant { elevated, filled, outlined, tonal }

/// M3 Card with optional header/footer slots and built-in tap support.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.header,
    required this.child,
    this.footer,
    this.variant = AppCardVariant.filled,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.color,
  });

  final Widget? header;
  final Widget child;
  final Widget? footer;
  final AppCardVariant variant;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = borderRadius ?? AppRadii.lgBorder;

    Color resolvedColor;
    BorderSide? border;
    double elevation = 0;

    switch (variant) {
      case AppCardVariant.elevated:
        resolvedColor = color ?? theme.colorScheme.surfaceContainerHigh;
        elevation = 1;
      case AppCardVariant.filled:
        resolvedColor = color ?? theme.colorScheme.surfaceContainerLow;
      case AppCardVariant.outlined:
        resolvedColor = color ?? theme.colorScheme.surface;
        border = BorderSide(color: theme.colorScheme.outlineVariant);
      case AppCardVariant.tonal:
        resolvedColor = color ??
            theme.colorScheme.secondaryContainer.withValues(alpha: 0.4);
    }

    Widget content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null) ...[
            header!,
            const SizedBox(height: AppSpacing.sm),
          ],
          child,
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.sm),
            footer!,
          ],
        ],
      ),
    );

    Widget card = Material(
      color: resolvedColor,
      elevation: elevation,
      borderRadius: border != null ? null : radius,
      shape: border != null
          ? RoundedRectangleBorder(borderRadius: radius, side: border)
          : null,
      child: content,
    );

    if (onTap != null || onLongPress != null) {
      card = AppPressable(
        onTap: onTap,
        onLongPress: onLongPress,
        child: card,
      );
    }

    return ClipRRect(borderRadius: radius, child: card);
  }
}
