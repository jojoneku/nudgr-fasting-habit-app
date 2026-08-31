import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/budget/add_budget_sheet.dart';
import 'package:intermittent_fasting/views/treasury/budget/budget_card.dart';
import 'package:intermittent_fasting/views/treasury/budget/manage_groups_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class BudgetView extends StatefulWidget {
  final BudgetPresenter presenter;

  const BudgetView({super.key, required this.presenter});

  @override
  State<BudgetView> createState() => _BudgetViewState();
}

class _BudgetViewState extends State<BudgetView> {
  @override
  void initState() {
    super.initState();
    widget.presenter.load();
  }

  void _showAddBudgetSheet([String? categoryId]) {
    AppBottomSheet.show(
      context: context,
      title:
          categoryId != null && widget.presenter.budgetFor(categoryId) != null
              ? 'Edit Budget'
              : 'Set Budget',
      body: AddBudgetSheet(
        presenter: widget.presenter,
        preselectedCategoryId: categoryId,
      ),
    );
  }

  void _showManageGroups() {
    AppBottomSheet.show(
      context: context,
      title: 'Manage Groups',
      body: ManageGroupsSheet(presenter: widget.presenter),
    );
  }

  Future<void> _pickMonth() async {
    final selected = widget.presenter.selectedMonth;
    final now = DateTime.now();
    // A window around today (12 back → 3 ahead) unioned with every month that
    // has budget data and the current selection, so no month is unreachable
    // (the old prev/next stepping had no bound). Newest first.
    final months = <String>{};
    for (var i = 3; i >= -12; i--) {
      months.add(toMonthKey(DateTime(now.year, now.month + i)));
    }
    months.addAll(widget.presenter.monthsWithBudgets);
    months.add(selected);
    final sorted = months.toList()..sort((a, b) => b.compareTo(a));
    final options = [
      for (final key in sorted)
        AppActionSheetItem<String>(
          label: monthLabel(key),
          value: key,
          isPrimary: key == selected,
        ),
    ];
    final picked = await AppActionSheet.show<String>(
      context: context,
      title: 'Jump to month',
      actions: options,
    );
    if (picked != null) widget.presenter.setMonth(picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        final sections = widget.presenter.budgetSections;
        final hasAny = sections.isNotEmpty;

        return Scaffold(
          // The module hides its "TREASURY" app bar on this tab, so keep the top
          // safe-area inset here to clear the status bar under the "Budget" title.
          body: SafeArea(
            child: Column(
              children: [
                _BudgetHeader(
                  presenter: widget.presenter,
                  onManageGroups: _showManageGroups,
                  onPickMonth: _pickMonth,
                ),
                Expanded(
                  child: hasAny
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          children: [
                            _BudgetRingHero(presenter: widget.presenter),
                            const SizedBox(height: 20),
                            _CarriedOverNotice(presenter: widget.presenter),
                            for (final section in sections) ...[
                              _SectionBlock(
                                section: section,
                                onEditRow: _showAddBudgetSheet,
                              ),
                              const SizedBox(height: 18),
                            ],
                          ],
                        )
                      : AppEmptyState(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'No budgets yet',
                          body: 'Tap + to set spending limits',
                          actionLabel: 'Set Budget',
                          onAction: () => _showAddBudgetSheet(),
                        ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddBudgetSheet(),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}

/// "Carried over from August" — shown the first time a month is populated by
/// carry-forward (Plan 059).
///
/// A month that silently fills with numbers is worse than one that says where
/// they came from: without this the user opens September, sees figures they
/// don't remember typing, and has no way to tell a carried budget from one they
/// set. It is also the only moment the feature explains itself.
///
/// Collapses to nothing when the month wasn't carried.
class _CarriedOverNotice extends StatelessWidget {
  final BudgetPresenter presenter;

  const _CarriedOverNotice({required this.presenter});

  /// "2026-08" → "August". Falls back to the raw key rather than throwing on
  /// anything unexpected — a malformed month must not take the page down.
  String _monthName(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return key;
    final month = int.tryParse(parts[1]);
    if (month == null || month < 1 || month > 12) return key;
    return const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ][month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final from = presenter.carriedFrom;
    if (from == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Carried over from ${_monthName(from)}. Edit any row and it '
                'applies from here on.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
              onPressed: presenter.clearCarriedNotice,
              tooltip: 'Dismiss',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header: big "Budget" title + month dropdown ────────────────────────────────

class _BudgetHeader extends StatelessWidget {
  final BudgetPresenter presenter;
  final VoidCallback onManageGroups;
  final VoidCallback onPickMonth;

  const _BudgetHeader({
    required this.presenter,
    required this.onManageGroups,
    required this.onPickMonth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Budget',
                style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Manage groups',
                onPressed: onManageGroups,
              ),
            ),
            const SizedBox(width: 2),
            _MonthSwitcher(
              month: presenter.selectedMonth,
              onTap: onPickMonth,
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  final String month;
  final VoidCallback onTap;

  const _MonthSwitcher({required this.month, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Text(
            monthChipLabel(month),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

// ─── Ring hero: spent vs budgeted ───────────────────────────────────────────────

class _BudgetRingHero extends StatelessWidget {
  final BudgetPresenter presenter;

  const _BudgetRingHero({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;
    final allocated = presenter.totalAllocated;
    final spent = presenter.totalSpent;
    final pct = presenter.percentUsed;
    final over = spent > allocated && allocated > 0;
    final ringColor = over ? cs.error : appColors.fast;
    // The remaining figure keys off the raw sign (not `over`, which needs an
    // allocation) so spend against a zero allocation still reads "over".
    final remaining = presenter.totalRemaining;
    final overspent = remaining < 0;

    return AppCard(
      variant: AppCardVariant.elevated,
      child: Row(
        children: [
          AppRingProgress(
            value: pct.clamp(0.0, 1.0),
            size: 104,
            strokeWidth: 12,
            primaryColor: ringColor,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(pct * 100).round()}%',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  'spent',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: appColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPENT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: appColors.textMuted,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatPeso(spent),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'of ${formatPeso(allocated)}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: appColors.textMuted),
                ),
                const SizedBox(height: 6),
                Text(
                  overspent
                      ? '${formatPeso(remaining.abs())} over'
                      : '${formatPeso(remaining)} left',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: overspent ? cs.error : appColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (presenter.isCurrentMonth) ...[
                  const SizedBox(height: 10),
                  _PacePill(ahead: presenter.isAheadOfPace, over: over),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PacePill extends StatelessWidget {
  final bool ahead;
  final bool over;

  const _PacePill({required this.ahead, required this.over});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final good = ahead && !over;
    final color = good ? context.appColors.success : cs.error;
    final label = over
        ? 'Over budget'
        : ahead
            ? 'Ahead of pace'
            : 'Over pace';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              good
                  ? Icons.check_circle_outline_rounded
                  : Icons.warning_amber_rounded,
              size: 13,
              color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ─── Section: group header + per-budget cards ──────────────────────────────────

class _SectionBlock extends StatelessWidget {
  final BudgetSection section;
  final ValueChanged<String> onEditRow;

  const _SectionBlock({required this.section, required this.onEditRow});

  @override
  Widget build(BuildContext context) {
    return AppSection(
      title: section.name.toUpperCase(),
      hint:
          '${formatPesoCompact(section.spent)} / ${formatPesoCompact(section.allocated)}',
      child: Column(
        children: [
          for (var i = 0; i < section.rows.length; i++) ...[
            BudgetCard(
              row: section.rows[i],
              onEdit: () => onEditRow(section.rows[i].targetId),
            ),
            if (i < section.rows.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
