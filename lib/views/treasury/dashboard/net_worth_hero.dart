import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// The NET WORTH hero — the redesigned Treasury dashboard's lead card
/// (`Nutrition Focus Treasury.dc.html`, Frame 1). A blue-tinted gradient card
/// showing net worth, its month-over-month momentum pill, the "this month"
/// delta line, and a sparkline of the net-worth trend.
///
/// All figures come from [TreasuryDashboardPresenter]; the gradient and accents
/// are derived from theme tokens so the card reads correctly in dark and light.
class NetWorthHero extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const NetWorthHero({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final blue = context.appColors.fast;
    final surface = cs.surface;

    // Blend the domain blue into the card surface so the gradient tracks the
    // active theme instead of hardcoding per-mode hex.
    Color blend(double alpha) =>
        Color.alphaBlend(blue.withValues(alpha: alpha), surface);

    final trend = presenter.netWorthTrend();
    final delta = presenter.netWorthMonthDelta;
    final pct = presenter.netWorthMonthDeltaPct;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            blend(isDark ? 0.30 : 0.16),
            blend(isDark ? 0.16 : 0.08),
            surface,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: blue.withValues(alpha: isDark ? 0.35 : 0.22),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'NET WORTH',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: blue,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (pct != null) _TrendPill(pct: pct),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatPeso(presenter.netWorth),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          _ThisMonthLine(delta: delta),
          if (trend.length >= 2) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: CustomPaint(
                painter: _SparklinePainter(
                  values: trend.map((p) => p.value).toList(),
                  color: blue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Signed month-over-month percentage pill — success accent when up, error when
/// down.
class _TrendPill extends StatelessWidget {
  final double pct;
  const _TrendPill({required this.pct});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = pct >= 0;
    final color = up ? context.appColors.success : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            '${up ? '+' : ''}${(pct * 100).toStringAsFixed(1)}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// "±₱X this month" line, colored by direction. Falls back to a neutral prompt
/// when there is no prior month-end to compare against.
class _ThisMonthLine extends StatelessWidget {
  final double? delta;
  const _ThisMonthLine({required this.delta});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.appColors.textMuted;
    if (delta == null) {
      return Text(
        'Tracking this month',
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      );
    }
    final up = delta! >= 0;
    final color = up ? context.appColors.success : theme.colorScheme.error;
    return Row(
      children: [
        Text(
          '${up ? '+' : '−'}${formatPeso(delta!.abs())}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          'this month',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// Lightweight net-worth sparkline: a smoothed-enough polyline with a fading
/// area fill. Normalizes [values] to the paint box; a flat series is drawn as a
/// centered horizontal line rather than dividing by a zero range.
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({required this.values, required this.color});

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
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // End dot on the latest point.
    canvas.drawCircle(
      Offset(size.width, yFor(values.last)),
      3.0,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}
