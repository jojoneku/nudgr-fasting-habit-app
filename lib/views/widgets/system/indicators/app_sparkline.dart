import 'package:flutter/material.dart';

/// Lightweight trend sparkline: a polyline with a fading area fill and a dot on
/// the latest point. Normalizes [values] to the paint box; a flat series draws
/// as a centered horizontal line rather than dividing by a zero range.
///
/// Shared by the mobile Treasury net-worth hero and its web counterpart so the
/// two render the same curve from the same data — it was previously private to
/// `net_worth_hero.dart`.
class AppSparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;

  /// Stroke width of the trend line. The wider web card carries a slightly
  /// heavier line so it reads at desktop viewing distance.
  final double strokeWidth;

  /// Radius of the end dot; pass 0 to omit it.
  final double endDotRadius;

  const AppSparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 52,
    this.strokeWidth = 2.5,
    this.endDotRadius = 3.0,
  });

  /// A sparkline needs at least two points to describe a trend.
  bool get hasTrend => values.length >= 2;

  @override
  Widget build(BuildContext context) {
    if (!hasTrend) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: SparklinePainter(
            values: values,
            color: color,
            strokeWidth: strokeWidth,
            endDotRadius: endDotRadius,
          ),
        ),
      ),
    );
  }
}

/// Painter behind [AppSparkline]. Public so surfaces that already own a
/// `CustomPaint` can reuse it directly.
class SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double strokeWidth;
  final double endDotRadius;

  SparklinePainter({
    required this.values,
    required this.color,
    this.strokeWidth = 2.5,
    this.endDotRadius = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = maxV - minV;
    final dx = size.width / (values.length - 1);

    double yFor(double v) {
      if (range == 0) return size.height / 2;
      // Leave a little top/bottom padding so the peaks aren't clipped.
      const pad = 6.0;
      final t = (v - minV) / range;
      return size.height - pad - t * (size.height - pad * 2);
    }

    final linePath = Path();
    for (var i = 0; i < values.length; i++) {
      final x = dx * i;
      final y = yFor(values[i]);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final fillPath = Path.from(linePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (endDotRadius > 0) {
      canvas.drawCircle(
        Offset(size.width, yFor(values.last)),
        endDotRadius,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(SparklinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.endDotRadius != endDotRadius;
}
