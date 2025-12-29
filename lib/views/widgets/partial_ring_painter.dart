import 'dart:math' as math;
import 'package:flutter/material.dart';

class PartialRingPainter extends CustomPainter {
  PartialRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
    required this.reverse,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;
  final bool reverse;

  static const double _gapFraction = 0.2; // 20% gap at bottom

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

    const gapAngle = 2 * math.pi * _gapFraction;
    final startAngle = math.pi / 2 + gapAngle / 2;
    final sweepAngle = 2 * math.pi - gapAngle;

    canvas.drawArc(rect, startAngle, sweepAngle, false, paintBase);

    final paintProgress = paintBase..color = progressColor;
    final double clampedProgress = math.max(0.0, math.min(1.0, progress));
    final sweep = sweepAngle * clampedProgress;
    if (reverse) {
      canvas.drawArc(
        rect,
        startAngle + sweepAngle,
        -sweep,
        false,
        paintProgress,
      );
    } else {
      canvas.drawArc(rect, startAngle, sweep, false, paintProgress);
    }
  }

  @override
  bool shouldRepaint(covariant PartialRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.reverse != reverse;
  }
}
