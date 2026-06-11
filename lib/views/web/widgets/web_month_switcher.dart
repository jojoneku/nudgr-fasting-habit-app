import 'package:flutter/material.dart';
import '../../../utils/app_radii.dart';
import '../../../utils/finance_format.dart';
import '../design/web_breakpoints.dart';

/// A compact previous/next month control with the month label between the
/// chevrons. Shared by Budget, Bills, and History (Plan 050 polish).
class WebMonthSwitcher extends StatelessWidget {
  final String monthKey;
  final ValueChanged<String> onChanged;

  const WebMonthSwitcher({
    super.key,
    required this.monthKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: WebInsets.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left, size: 20),
            tooltip: 'Previous month',
            onPressed: () => onChanged(previousMonth(monthKey)),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 124),
            child: Text(
              monthLabel(monthKey),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right, size: 20),
            tooltip: 'Next month',
            onPressed: () => onChanged(nextMonth(monthKey)),
          ),
        ],
      ),
    );
  }
}
