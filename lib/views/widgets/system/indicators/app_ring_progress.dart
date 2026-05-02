import 'package:flutter/material.dart';
import '../../partial_ring_painter.dart';

/// Theme-aware wrapper around [PartialRingPainter].
/// Replaces ad-hoc CustomPaint + painter setups in timer_tab and activity_screen.
class AppRingProgress extends StatelessWidget {
  const AppRingProgress({
    super.key,
    required this.value,
    this.center,
    this.size = 220,
    this.strokeWidth = 14,
    this.glowOpacity = 0.12,
    this.primaryColor,
    this.trackColor,
    this.reversed = false,
  });

  final double value;
  final Widget? center;
  final double size;
  final double strokeWidth;
  final double glowOpacity;
  final Color? primaryColor;
  final Color? trackColor;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedPrimary = primaryColor ?? theme.colorScheme.primary;
    final resolvedTrack =
        trackColor ?? theme.colorScheme.surfaceContainerHighest;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: PartialRingPainter(
              progress: value.clamp(0.0, 1.0),
              progressColor: resolvedPrimary,
              trackColor: resolvedTrack,
              strokeWidth: strokeWidth,
              reverse: reversed,
            ),
          ),
          if (center != null) center!,
        ],
      ),
    );
  }
}
