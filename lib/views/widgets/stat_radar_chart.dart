import 'dart:math';
import 'package:flutter/material.dart';
import '../../app_colors.dart';

class StatRadarChart extends StatelessWidget {
  const StatRadarChart({
    super.key,
    required this.stats,
    this.size = 200,
    this.fillColor,
    this.borderColor,
    this.gridColor,
    this.labelColor,
  });

  final Map<String, int> stats;
  final double size;
  final Color? fillColor;
  final Color? borderColor;
  final Color? gridColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RadarChartPainter(
          stats,
          fillColor: fillColor ?? theme.colorScheme.primary.withValues(alpha: 0.3),
          borderColor: borderColor ?? theme.colorScheme.primary,
          gridColor: gridColor ??
              theme.colorScheme.onSurface.withValues(alpha: 0.2),
          labelColor: labelColor ?? AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _RadarChartPainter extends CustomPainter {
  _RadarChartPainter(
    this.stats, {
    required this.fillColor,
    required this.borderColor,
    required this.gridColor,
    required this.labelColor,
  });

  final Map<String, int> stats;
  final Color fillColor;
  final Color borderColor;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 * 0.8;

    final paintOutline = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final paintFill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final paintBorder = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final keys = stats.keys.toList();
    final values = stats.values.toList();
    final maxValue =
        values.reduce(max) > 0 ? values.reduce(max).toDouble() : 10.0;
    final scaleMax = max(maxValue, 20.0);

    final angleStep = (2 * pi) / keys.length;

    for (int i = 1; i <= 3; i++) {
      final levelRadius = radius * (i / 3);
      final path = Path();
      for (int j = 0; j < keys.length; j++) {
        final angle = -pi / 2 + (j * angleStep);
        final x = center.dx + levelRadius * cos(angle);
        final y = center.dy + levelRadius * sin(angle);
        j == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      path.close();
      canvas.drawPath(path, paintOutline);
    }

    final pathStats = Path();
    for (int i = 0; i < keys.length; i++) {
      final r = radius * (values[i] / scaleMax);
      final angle = -pi / 2 + (i * angleStep);
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      i == 0 ? pathStats.moveTo(x, y) : pathStats.lineTo(x, y);
    }
    pathStats.close();
    canvas.drawPath(pathStats, paintFill);
    canvas.drawPath(pathStats, paintBorder);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < keys.length; i++) {
      final angle = -pi / 2 + (i * angleStep);
      final labelRadius = radius + 20;
      final x = center.dx + labelRadius * cos(angle);
      final y = center.dy + labelRadius * sin(angle);
      textPainter.text = TextSpan(
        text: keys[i],
        style: TextStyle(
            color: labelColor, fontSize: 10, fontWeight: FontWeight.bold),
      );
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(x - textPainter.width / 2, y - textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter old) =>
      old.fillColor != fillColor ||
      old.borderColor != borderColor ||
      old.gridColor != gridColor ||
      old.labelColor != labelColor;
}
