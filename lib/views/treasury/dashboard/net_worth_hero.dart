import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

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
          const SizedBox(height: 12),
          // Compact figures so both cells fit side by side at 360 dp. Liquid
          // cash is not repeated: it already heads the Accounts section.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _HeroCell(
                  key: const ValueKey('dashboard.hero.netCashFlow'),
                  label: 'NET CASH FLOW',
                  value: presenter.monthNetCashFlowCompactLabel,
                  caption: 'Income less spending',
                  valueColor: presenter.monthNetCashFlowNegative
                      ? cs.error
                      : context.appColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroCell(
                  key: const ValueKey('dashboard.hero.totalAssets'),
                  label: 'TOTAL ASSETS',
                  value: presenter.totalAssetsCompactLabel,
                  caption: 'Cash, savings & goals',
                  valueColor: cs.onSurface,
                ),
              ),
            ],
          ),
          if (trend.length >= 2) ...[
            const SizedBox(height: 8),
            AppSparkline(
              values: trend.map((p) => p.value).toList(),
              color: blue,
            ),
          ],
        ],
      ),
    );
  }
}

/// One small well under the net worth figure (net cash flow, total assets).
class _HeroCell extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color valueColor;

  const _HeroCell({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        // A translucent well over the gradient; the surface tint reads darker
        // in dark mode and lighter in light mode.
        color: cs.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: appColors.fast,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AppNumberDisplay(
              value: value,
              size: AppNumberSize.body,
              color: valueColor,
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: appColors.textMuted,
            ),
          ),
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
