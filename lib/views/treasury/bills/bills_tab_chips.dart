import 'package:flutter/material.dart';

/// The five lists on the mobile Bills tab (Plan 071 Phase 6). Same order and
/// names as the web v2 tabs.
enum BillsTab {
  upcoming('Upcoming'),
  setAsides('Set-asides'),
  receivables('Receivables'),
  installments('Installments'),
  paid('Paid');

  const BillsTab(this.label);

  final String label;
}

/// The presenter's `tabCounts` record keyed by tab, for [BillsTabChips].
Map<BillsTab, int> billsTabCountMap(
        ({
          int upcoming,
          int setAsides,
          int receivables,
          int installments,
          int paid
        }) c) =>
    {
      BillsTab.upcoming: c.upcoming,
      BillsTab.setAsides: c.setAsides,
      BillsTab.receivables: c.receivables,
      BillsTab.installments: c.installments,
      BillsTab.paid: c.paid,
    };

/// Keys for the tab chips, for tests.
abstract final class BillsTabKeys {
  static ValueKey<String> chip(BillsTab tab) =>
      ValueKey('bills-tab-${tab.name}');
}

/// A horizontally scrollable row of tab chips, each with its row count. Five
/// labels do not fit a segmented control at 360 dp, so the row scrolls.
///
/// Dumb: the counts come from the presenter, the selection from the view.
/// Each chip is at least 44 px tall.
class BillsTabChips extends StatelessWidget {
  final BillsTab selected;
  final Map<BillsTab, int> counts;
  final ValueChanged<BillsTab> onSelected;

  const BillsTabChips({
    super.key,
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in BillsTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _TabChip(
                key: BillsTabKeys.chip(tab),
                label: tab.label,
                count: counts[tab] ?? 0,
                selected: tab == selected,
                onTap: () => onSelected(tab),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimary : cs.onSurface;
    final countFg = selected ? cs.onPrimary : cs.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? cs.primary : cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    color: countFg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
