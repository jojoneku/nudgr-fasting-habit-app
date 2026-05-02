import 'package:flutter/material.dart';
import '../../../../utils/app_radii.dart';

/// 44×44 rounded-square tonal icon container — module cards, list leadings, hub.
class AppIconBadge extends StatelessWidget {
  const AppIconBadge({
    super.key,
    required this.icon,
    this.color,
    this.size = 44,
    this.iconSize = 22,
    this.radius = AppRadii.md,
    this.filled = true,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;
  final double radius;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? c.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        border: filled ? null : Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, color: c, size: iconSize),
    );
  }
}
