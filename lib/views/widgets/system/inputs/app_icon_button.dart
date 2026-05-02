import 'package:flutter/material.dart';

enum AppIconButtonVariant { standard, filled, tonal, outlined }

/// M3 IconButton with optional badge overlay.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.badge,
    this.variant = AppIconButtonVariant.standard,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Widget? badge;
  final AppIconButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    Widget button;
    switch (variant) {
      case AppIconButtonVariant.filled:
        button = IconButton.filled(
            onPressed: onPressed, icon: Icon(icon), tooltip: tooltip);
      case AppIconButtonVariant.tonal:
        button = IconButton.filledTonal(
            onPressed: onPressed, icon: Icon(icon), tooltip: tooltip);
      case AppIconButtonVariant.outlined:
        button = IconButton.outlined(
            onPressed: onPressed, icon: Icon(icon), tooltip: tooltip);
      case AppIconButtonVariant.standard:
        button = IconButton(
            onPressed: onPressed, icon: Icon(icon), tooltip: tooltip);
    }

    if (badge != null) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(top: 4, right: 4, child: badge!),
        ],
      );
    }

    return button;
  }
}
