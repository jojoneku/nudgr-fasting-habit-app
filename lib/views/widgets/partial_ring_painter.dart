import 'dart:math' as math;
import 'package:flutter/material.dart';

class PartialRingPainter extends CustomPainter {
  PartialRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
    required this.reverse,
    this.gapFraction = 0.2,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;
  final bool reverse;

  /// Fraction of the circle (0–1) left open at the bottom. Defaults to `0.2`
  /// (20% gap) to preserve the timer/activity look; pass `0` for a full circle.
  final double gapFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = strokeWidth / 2;
    final rect = Offset(offset, offset) &
        Size(size.width - strokeWidth, size.height - strokeWidth);

    final paintBase = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final gapAngle = 2 * math.pi * gapFraction;
    final startAngle = math.pi / 2 + gapAngle / 2;
    final sweepAngle = 2 * math.pi - gapAngle;

    canvas.drawArc(rect, startAngle, sweepAngle, false, paintBase);

    // Glow Paint
    final paintGlow = Paint()
      ..color = progressColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);

    final paintProgress = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final double clampedProgress = math.max(0.0, math.min(1.0, progress));
    final sweep = sweepAngle * clampedProgress;
    if (reverse) {
      // Draw Glow
      canvas.drawArc(
        rect,
        startAngle + sweepAngle,
        -sweep,
        false,
        paintGlow,
      );
      // Draw Progress
      canvas.drawArc(
        rect,
        startAngle + sweepAngle,
        -sweep,
        false,
        paintProgress,
      );
    } else {
      // Draw Glow
      canvas.drawArc(rect, startAngle, sweep, false, paintGlow);
      // Draw Progress
      canvas.drawArc(rect, startAngle, sweep, false, paintProgress);
    }
  }

  @override
  bool shouldRepaint(covariant PartialRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.reverse != reverse ||
        oldDelegate.gapFraction != gapFraction;
  }
}
