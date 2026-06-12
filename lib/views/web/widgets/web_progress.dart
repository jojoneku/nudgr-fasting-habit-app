import 'package:flutter/material.dart';
import '../design/web_breakpoints.dart';
import 'web_badge.dart';

/// A thin rounded progress bar (track + fill) for budget / goal health.
///
/// Theme-aware: the track is [ColorScheme.surfaceContainerHighest] and the
/// fill defaults to [ColorScheme.primary]. The fill animates implicitly when
/// [value] changes (≤300ms), respecting reduced-motion via the framework.
class WebProgressBar extends StatelessWidget {
  /// Fraction filled, 0..1 (clamped).
  final double value;

  /// Fill color. Defaults to [ColorScheme.primary].
  final Color? color;

  /// Bar thickness in logical pixels.
  final double height;

  const WebProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = (color ?? cs.primary);
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final radius = BorderRadius.circular(height / 2);

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Container(color: cs.surfaceContainerHighest),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: clamped),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: constraints.maxWidth * v,
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: radius,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One budget-health row: a color dot + category name (+ optional status
/// [WebBadge]), a right-aligned `spent / target` figure, a [WebProgressBar]
/// underneath, and an optional sub line ("₱X left · Y%").
///
/// Purely presentational — caller supplies all formatted strings and the
/// already-computed [progress] (0..1).
class WebBudgetRow extends StatelessWidget {
  final Color dotColor;
  final String name;

  /// Formatted spent figure, e.g. "₱2,738".
  final String spent;

  /// Formatted target figure, e.g. "₱10,000".
  final String target;

  /// Fraction of target used, 0..1 (clamped by the bar).
  final double progress;

  /// Optional status pill (e.g. "On track" / "Watch" / "Over").
  final WebBadge? status;

  /// Optional sub line, e.g. "₱7,262 left · 27%".
  final String? sub;

  /// Override the bar fill (defaults to [dotColor]).
  final Color? barColor;

  const WebBudgetRow({
    super.key,
    required this.dotColor,
    required this.name,
    required this.spent,
    required this.target,
    required this.progress,
    this.status,
    this.sub,
    this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: WebInsets.sm),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (status != null) ...[
              const SizedBox(width: WebInsets.sm),
              status!,
            ],
            const Spacer(),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: spent,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' / $target',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: WebInsets.sm),
        WebProgressBar(value: progress, color: barColor ?? dotColor),
        if (sub != null) ...[
          const SizedBox(height: WebInsets.xs),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              sub!,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}
