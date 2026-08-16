import 'package:flutter/material.dart';

import '../design/web_breakpoints.dart';

/// The domain-accent gradient shell every Nudgr screen is framed by — the
/// mobile redesign's signature move, extracted so web pages stop re-deriving it.
///
/// Mobile hard-codes this treatment once per hero (`NetWorthHero`, `DueSoonHero`,
/// the Budget pace hero); on web it is one widget, so a new page frames itself by
/// picking an accent rather than by copying gradient stops. The blend is
/// deliberate: the gradient tints [ColorScheme.surface] with the accent instead
/// of baking a hex pair, so a hero tracks both themes for free, exactly as its
/// mobile counterpart does.
///
/// The accent is the domain hue for the screen — `context.appColors.fast` (blue)
/// for net worth, `.bills` (orange) for what's due, `colorScheme.error` when the
/// state has escalated to overdue/over-budget.
class WebHeroCard extends StatelessWidget {
  /// Domain hue the card is tinted and outlined with.
  final Color accent;

  final Widget child;
  final EdgeInsetsGeometry padding;

  const WebHeroCard({
    super.key,
    required this.accent,
    required this.child,
    this.padding = const EdgeInsets.all(WebInsets.xl),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;

    Color blend(double alpha) =>
        Color.alphaBlend(accent.withValues(alpha: alpha), surface);

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
          color: accent.withValues(alpha: isDark ? 0.35 : 0.22),
          width: 1,
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}
