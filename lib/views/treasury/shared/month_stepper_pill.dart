import 'package:flutter/material.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// `‹ September ›` — the mobile counterpart to `WebMonthStepper`.
///
/// Web has had chevrons for a while; mobile only had the pill, so moving one
/// month meant open picker → find the month → tap, for the step people take
/// most often by far. The chevrons make the common move one tap and leave the
/// picker for the uncommon one.
///
/// The label stays tappable rather than becoming inert like the web version's:
/// on mobile it is the only way to reach a month several steps away, and
/// removing it to gain the chevrons would trade one annoyance for another.
///
/// Uncapped in both directions, matching web. A future month is a legitimate
/// thing to look at — you plan a budget before you live it — and the surfaces
/// that must not accept input for a non-current month say so themselves.
class MonthStepperPill extends StatelessWidget {
  /// Month key, `YYYY-MM`.
  final String month;

  /// Tapping the label — opens the full picker.
  final VoidCallback onTap;

  /// Step one month back / forward.
  final ValueChanged<String> onMonthChanged;

  const MonthStepperPill({
    super.key,
    required this.month,
    required this.onTap,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Chevron(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Previous month',
            onPressed: () => onMonthChanged(previousMonth(month)),
          ),
          // The label carries its own tap target rather than sitting inside the
          // row's: a stray tap between the chevrons should open the picker, not
          // step a month the user didn't mean to step.
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 88),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                monthChipLabel(month),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          _Chevron(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next month',
            onPressed: () => onMonthChanged(nextMonth(month)),
          ),
        ],
      ),
    );
  }
}

/// A chevron sized to the 44px minimum without widening the pill: the icon is
/// small, the touch target is not.
class _Chevron extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _Chevron({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Icon(icon, size: 20, color: cs.onSurfaceVariant),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        splashRadius: 22,
      ),
    );
  }
}
