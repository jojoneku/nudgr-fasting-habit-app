import 'package:flutter/material.dart';

import '../design/web_breakpoints.dart';
import 'web_number.dart';

/// One tab of a [WebTabs] row: a label and an optional count pill.
class WebTab {
  final String label;
  final int? count;

  /// Stable key for parity tests (`WebKeys.billsTabUpcoming`, …).
  final Key? key;

  const WebTab(this.label, {this.count, this.key});
}

/// Underline tabs for the header of a list card (Bills: Upcoming · Set-asides
/// · Receivables · Installments · Paid; Setup: Accounts · Categories).
///
/// Labels never wrap — the row scrolls horizontally when the card is narrow,
/// so a five-tab strip at 600 px stays one line of readable labels rather
/// than a stack of broken words. Counts render in a small pill after the
/// label and use tabular figures so they do not jitter as lists change.
class WebTabs extends StatelessWidget {
  final List<WebTab> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  /// Horizontal padding inside the scroll row.
  final EdgeInsetsGeometry padding;

  const WebTabs({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: WebInsets.md),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              _WebTabButton(
                key: tabs[i].key,
                tab: tabs[i],
                selected: i == index,
                onTap: () => onChanged(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WebTabButton extends StatelessWidget {
  final WebTab tab;
  final bool selected;
  final VoidCallback onTap;

  const _WebTabButton({
    super.key,
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final count = tab.count;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(
            horizontal: WebInsets.md,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected ? cs.primary : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tab.label,
                softWrap: false,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? cs.onSurface : cs.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: ShapeDecoration(
                    color: cs.surfaceContainerHigh,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    '$count',
                    softWrap: false,
                    style: webNumericStyle(
                      theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
