import 'package:flutter/material.dart';

import '../design/web_breakpoints.dart';

/// Compact `◀ June 2026 ▶` stepper for paging a month-scoped page back/forward.
/// Pure UI — the page wires [onPrev]/[onNext] to its presenter's month setter.
class WebMonthStepper extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const WebMonthStepper({
    super.key,
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Previous month',
          visualDensity: VisualDensity.compact,
        ),
        Text(label,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: 'Next month',
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: WebInsets.xs),
      ],
    );
  }
}
