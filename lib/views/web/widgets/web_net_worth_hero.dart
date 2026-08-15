import 'package:flutter/material.dart';

import '../../../app_colors.dart';
import '../../../presenters/treasury_dashboard_presenter.dart';
import '../../../utils/finance_format.dart';
import '../../widgets/system/system.dart';
import '../design/web_breakpoints.dart';
import 'web_hero_card.dart';
import 'web_number.dart';

/// Desktop counterpart of the mobile `NetWorthHero` — the blue gradient card,
/// the signed momentum pill, the "±₱X this month" line, and the shared
/// [AppSparkline] of the net-worth trend.
///
/// Re-proportioned rather than re-styled: a desktop card is wide and short
/// where the phone's is narrow and tall, so the figure and the sparkline sit
/// side by side instead of stacked. Every colour is derived from theme tokens,
/// exactly as on mobile, so it tracks both modes.
///
/// Replaces the flat `WebStatTile(accent: true)` "Net Position" tile, which
/// showed the same number with none of the redesign's identity.
class WebNetWorthHero extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  /// Below this width the sparkline drops below the figure instead of beside
  /// it, so the number never gets squeezed.
  static const double _sideBySideMin = 560;

  const WebNetWorthHero({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final blue = context.appColors.fast;

    final trend = presenter.netWorthTrend();
    final values = [for (final p in trend) p.value];
    final delta = presenter.netWorthMonthDelta;
    final pct = presenter.netWorthMonthDeltaPct;

    // The gradient shell now lives in WebHeroCard — the same one the Bills
    // due-soon hero frames itself with, so "a Nudgr hero" is one definition
    // rather than a treatment each page re-derives.
    return WebHeroCard(
      accent: blue,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final figure = _Figure(
            netWorth: presenter.netWorth,
            delta: delta,
            pct: pct,
            blue: blue,
          );
          final spark = AppSparkline(
            values: values,
            color: blue,
            height: 72,
            strokeWidth: 3,
            endDotRadius: 3.5,
          );

          if (!spark.hasTrend) return figure;

          if (constraints.maxWidth < _sideBySideMin) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                figure,
                const SizedBox(height: WebInsets.lg),
                spark,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: figure),
              const SizedBox(width: WebInsets.xl),
              Expanded(flex: 4, child: spark),
            ],
          );
        },
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final double netWorth;
  final double? delta;
  final double? pct;
  final Color blue;

  const _Figure({
    required this.netWorth,
    required this.delta,
    required this.pct,
    required this.blue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
            const SizedBox(width: WebInsets.md),
            if (pct != null) _TrendPill(pct: pct!),
          ],
        ),
        const SizedBox(height: WebInsets.sm),
        WebNumber(
          formatPeso(netWorth),
          size: WebNumberSize.hero,
          weight: FontWeight.w800,
        ),
        const SizedBox(height: WebInsets.xs),
        _ThisMonthLine(delta: delta),
      ],
    );
  }
}

/// Signed month-over-month percentage pill — success accent when up, error when
/// down. Mirrors the mobile hero's pill.
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

/// "±₱X this month" line, coloured by direction; a neutral prompt when there is
/// no prior month-end to compare against.
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
          style: webNumericStyle(
            theme.textTheme.bodyMedium,
            color: color,
          )?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 5),
        Text(
          'this month',
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
      ],
    );
  }
}
