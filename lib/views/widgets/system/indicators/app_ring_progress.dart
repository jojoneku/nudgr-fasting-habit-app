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
    this.gapFraction = 0.2,
  });

  final double value;
  final Widget? center;
  final double size;
  final double strokeWidth;
  final double glowOpacity;
  final Color? primaryColor;
  final Color? trackColor;
  final bool reversed;

  /// Fraction of the circle left open at the bottom. Defaults to `0.2` (the
  /// timer/activity look); pass `0` for a full circle (Hub ring hero).
  final double gapFraction;

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
              gapFraction: gapFraction,
            ),
          ),
          if (center != null) center!,
        ],
      ),
    );
  }
}
