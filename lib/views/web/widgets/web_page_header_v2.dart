import 'package:flutter/material.dart';

import '../design/web_breakpoints.dart';

/// The v2 page header (Plan 063, Phase 2): a 28/800 title with a one-line
/// subtitle, and the page's controls right-aligned on the same baseline.
///
/// Every v2 page starts with one of these, and it is the *only* title on the
/// page — the shell no longer repeats it in a top bar. [actions] wrap onto a
/// second line when the page is narrow (Nudgy open on a small desktop) rather
/// than squeezing the title; the [monthStepper], when given, is always the
/// first control in that row so month-scoped pages read the same way.
class WebPageHeaderV2 extends StatelessWidget {
  final String title;

  /// Short scope line under the title ("3 due this week · ₱12,400 to pay").
  final String? subtitle;

  /// Page controls — Add buttons, filters, Ask Nudgy. Right-aligned, wrapping.
  final List<Widget> actions;

  /// A `WebMonthStepper` (or any month control) shown first among [actions].
  final Widget? monthStepper;

  const WebPageHeaderV2({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.monthStepper,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final controls = [
      if (monthStepper != null) monthStepper!,
      ...actions,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: WebInsets.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: cs.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    // −0.02em at 28 px.
                    letterSpacing: -0.56,
                    height: 1.1,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: WebInsets.xs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (controls.isNotEmpty) ...[
            const SizedBox(width: WebInsets.lg),
            Flexible(
              flex: 3,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: WebInsets.sm,
                runSpacing: WebInsets.sm,
                children: controls,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
