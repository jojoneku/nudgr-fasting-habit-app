import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A segmented donut showing the proportion of protein / carbs / fat as three
/// arcs summing to the full circle — a parts-of-a-whole visual, deliberately
/// distinct from the goal-progress [AppRingProgress] rings. Renders an idle
/// track when nothing is logged.
class MacroSplitRing extends StatelessWidget {
  const MacroSplitRing({
    super.key,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.proteinColor,
    required this.carbsColor,
    required this.fatColor,
    required this.trackColor,
    this.size = 88,
    this.strokeWidth = 8,
    this.caption = 'Macros',
  });

  final double protein;
  final double carbs;
  final double fat;
  final Color proteinColor;
  final Color carbsColor;
  final Color fatColor;
  final Color trackColor;
  final double size;
  final double strokeWidth;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = protein + carbs + fat;
    final idle = total <= 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _MacroSplitPainter(
              protein: protein,
              carbs: carbs,
              fat: fat,
              proteinColor: proteinColor,
              carbsColor: carbsColor,
              fatColor: fatColor,
              trackColor: trackColor,
              strokeWidth: strokeWidth,
            ),
            child: Center(
              child: idle
                  ? Icon(
                      Icons.egg_alt_outlined,
                      size: 22,
                      color: carbsColor.withValues(alpha: 0.55),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _macroText(theme, 'P', protein, proteinColor),
                        _macroText(theme, 'C', carbs, carbsColor),
                        _macroText(theme, 'F', fat, fatColor),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// One compact, color-coded macro value (e.g. `P 128`) for the ring center.
  Widget _macroText(ThemeData theme, String label, double grams, Color color) {
    return Text(
      '$label ${grams.round()}',
      style: theme.textTheme.labelSmall?.copyWith(
        fontSize: 9,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}

class _MacroSplitPainter extends CustomPainter {
  _MacroSplitPainter({
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.proteinColor,
    required this.carbsColor,
    required this.fatColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double protein;
  final double carbs;
  final double fat;
  final Color proteinColor;
  final Color carbsColor;
  final Color fatColor;
  final Color trackColor;
  final double strokeWidth;

  /// Blank angle between adjacent segments (radians).
  static const double _gap = 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = strokeWidth / 2;
    final rect = Offset(offset, offset) &
        Size(size.width - strokeWidth, size.height - strokeWidth);

    // Base track — always drawn (also the idle state).
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    final total = protein + carbs + fat;
    if (total <= 0) return;

    final segments = <(double, Color)>[
      (protein / total, proteinColor),
      (carbs / total, carbsColor),
      (fat / total, fatColor),
    ];

    const start = -math.pi / 2; // 12 o'clock
    var angle = start;
    for (final (fraction, color) in segments) {
      if (fraction <= 0) continue;
      final full = 2 * math.pi * fraction;
      // Trim a gap off each segment so the divisions read clearly.
      final sweep = math.max(0.0, full - _gap);
      canvas.drawArc(
        rect,
        angle + _gap / 2,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
      angle += full;
    }
  }

  @override
  bool shouldRepaint(covariant _MacroSplitPainter o) =>
      o.protein != protein ||
      o.carbs != carbs ||
      o.fat != fat ||
      o.proteinColor != proteinColor ||
      o.carbsColor != carbsColor ||
      o.fatColor != fatColor ||
      o.trackColor != trackColor ||
      o.strokeWidth != strokeWidth;
}
