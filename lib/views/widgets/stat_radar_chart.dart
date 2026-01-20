import 'dart:math';
import 'package:flutter/material.dart';
import '../../app_colors.dart';

class StatRadarChart extends StatelessWidget {
  final Map<String, int> stats;
  final double size;

  const StatRadarChart({
    super.key,
    required this.stats,
    this.size = 200,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RadarChartPainter(stats),
      ),
    );
  }
}

class _RadarChartPainter extends CustomPainter {
  final Map<String, int> stats;

  _RadarChartPainter(this.stats);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 * 0.8; // 80% of available space

    final paintOutline = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final paintFill = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final paintBorder = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final keys = stats.keys.toList();
    final values = stats.values.toList();
    final maxValue = values.reduce(max) > 0 ? values.reduce(max).toDouble() : 10.0;
    // Ensure a minimum scale so the chart doesn't look tiny at level 1
    final scaleMax = max(maxValue, 20.0); 

    final angleStep = (2 * pi) / keys.length;

    // Draw Background Webs (3 levels)
    for (int i = 1; i <= 3; i++) {
      final levelRadius = radius * (i / 3);
      final path = Path();
      for (int j = 0; j < keys.length; j++) {
        final angle = -pi / 2 + (j * angleStep); // Start from top
        final x = center.dx + levelRadius * cos(angle);
        final y = center.dy + levelRadius * sin(angle);
        if (j == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, paintOutline);
    }

    // Draw Stat Polygon
    final pathStats = Path();
    final points = <Offset>[];

    for (int i = 0; i < keys.length; i++) {
      final value = values[i];
      final normalizedValue = value / scaleMax;
      final r = radius * normalizedValue;
      final angle = -pi / 2 + (i * angleStep);
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      points.add(Offset(x, y));
      if (i == 0) {
        pathStats.moveTo(x, y);
      } else {
        pathStats.lineTo(x, y);
      }
    }
    pathStats.close();

    canvas.drawPath(pathStats, paintFill);
    canvas.drawPath(pathStats, paintBorder);

    // Draw Labels
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (int i = 0; i < keys.length; i++) {
      final angle = -pi / 2 + (i * angleStep);
      final labelRadius = radius + 20; // Push label out a bit
      final x = center.dx + labelRadius * cos(angle);
      final y = center.dy + labelRadius * sin(angle);

      textPainter.text = TextSpan(
        text: keys[i],
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
