import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/category_icon_catalog.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../../widgets/web_widgets.dart';
import 'web_manage_groups_dialog.dart';

/// Web Budget page (Plan 050-D) — tabular, editable budget setup + an
/// "Allocation by Group" donut. Mirrors the Claude design reference
/// (`docs/design/treasury-web-reference/budget.jsx` + `screens/budget2.png`)
/// using OUR theme tokens and the shared web design-system kit.
///
/// Data binds to [BudgetPresenter]:
/// - Rows: [BudgetPresenter.categoriesByGroup] (expense) +
///   [BudgetPresenter.savingsBudgets] (savings/goal).
/// - Mutations: [BudgetPresenter.setBudget] (allocation + group change) and
///   [BudgetPresenter.addCategory] (new category, then a follow-up setBudget).
///   Per the optimistic-UI pattern the presenter handles mutate→notify→persist;
///   this view only calls those methods.
class WebBudgetPage extends StatelessWidget {
  final BudgetPresenter presenter;
  const WebBudgetPage({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => _BudgetBody(presenter: presenter),
    );
  }
}

/// One flattened table row. [accountBacked] rows are savings/goal budgets whose
/// group cannot be changed inline (savings rows are keyed by account id, not
/// category id — reassigning would point at a non-existent account).
class _Row {
  final String id; // categoryId or accountId
  final String name;
  final String groupId;
  final double allocated;
  final double spent;
  final Color color;
  final bool accountBacked;

  /// Savings rows: money that left the target this month. Shown beside what
  /// went in rather than netted off it — see [BudgetPresenter.fundedInto].
  final double withdrawn;

  const _Row({
    required this.id,
    required this.name,
    required this.groupId,
    required this.allocated,
    required this.spent,
    required this.color,
    required this.accountBacked,
    this.withdrawn = 0.0,
  });

  double get used => allocated > 0 ? spent / allocated : 0;
  double get remaining => allocated - spent;
}

/// Status pill for one row. [isSavings] flips the meaning of a full bar:
/// spending past an expense budget is the problem the badge exists to flag,
/// while funding past a savings goal is the point of the goal — so a savings
/// row never turns red, matching what [BudgetPresenter.budgetRows] already says
/// by pinning `isOver: false` on those rows.
({WebBadgeTone tone, String label}) _statusFor(
  double used, {
  bool isSavings = false,
}) {
  if (isSavings) {
    return used >= 1
        ? (tone: WebBadgeTone.success, label: 'Funded')
        : (tone: WebBadgeTone.info, label: 'On track');
  }
  if (used >= 1) return (tone: WebBadgeTone.danger, label: 'Over');
  if (used >= 0.75) return (tone: WebBadgeTone.warning, label: 'Watch');
  return (tone: WebBadgeTone.success, label: 'On track');
}

Color _statusColor(BuildContext context, double used,
    {bool isSavings = false}) {
  final cs = Theme.of(context).colorScheme;
  if (isSavings) return cs.tertiary;
  if (used >= 1) return cs.error;
  if (used >= 0.75) return cs.secondary;
  return cs.tertiary;
}

class _BudgetBody extends StatelessWidget {
  final BudgetPresenter presenter;
  const _BudgetBody({required this.presenter});

  List<_Row> _buildRows(BuildContext context) {
    final rows = <_Row>[];
    final byGroup = presenter.categoriesByGroup;
    var colorIndex = 0;
    for (final group in presenter.expenseGroups) {
      for (final cat in byGroup[group.id] ?? const <FinanceCategory>[]) {
        rows.add(_Row(
          id: cat.id,
          name: cat.name,
          groupId: group.id,
          allocated: presenter.budgetFor(cat.id)?.allocatedAmount ?? 0,
          spent: presenter.spentFor(cat.id),
          color: resolveSliceColor(cat.colorHex, colorIndex++,
              brightness: Theme.of(context).brightness),
          accountBacked: false,
        ));
      }
    }
    for (final entry in presenter.savingsBudgets) {
      rows.add(_Row(
        id: entry.account.id,
        name: entry.account.name,
        groupId: entry.budget.group,
        allocated: entry.budget.allocatedAmount,
        spent: presenter.fundedInto(entry.account.id),
        withdrawn: presenter.withdrawnFrom(entry.account.id),
        color: Theme.of(context).colorScheme.tertiary,
        accountBacked: true,
      ));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows(context);
    final allocated = presenter.totalAllocated;
    final spent = presenter.totalSpent;
    final remaining = presenter.totalRemaining;
    final usedPct = allocated > 0 ? (spent / allocated * 100) : 0.0;
    final groupCount = {for (final r in rows) r.groupId}.length;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: double.infinity),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebPageHeader(
            title: 'Budget',
            subtitle: '${monthLabel(presenter.selectedMonth)} · '
                'set your allocations',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Groups could only be *assigned* on web, never created —
                // leaving the Allocation by Group card below impossible to
                // populate without reaching for the phone.
                OutlinedButton.icon(
                  onPressed: () =>
                      showWebManageGroupsDialog(context, presenter: presenter),
                  icon: const Icon(Icons.folder_outlined, size: 16),
                  label: const Text('Manage groups'),
                ),
                const SizedBox(width: WebInsets.sm),
                WebMonthStepper(
                  label: monthLabel(presenter.selectedMonth),
                  onPrev: () => presenter
                      .setMonth(previousMonth(presenter.selectedMonth)),
                  onNext: () =>
                      presenter.setMonth(nextMonth(presenter.selectedMonth)),
                ),
              ],
            ),
          ),
          // The question a budget screen exists to answer is "am I on track",
          // and only the ring hero answers it — the tiles below say how much.
          // Web opened straight on the tiles; the phone leads with the ring.
          if (rows.isNotEmpty) ...[
            _PaceRingHero(presenter: presenter),
            const SizedBox(height: WebInsets.xl),
          ],
          _StatStrip(
            allocated: allocated,
            spent: spent,
            remaining: remaining,
            usedPct: usedPct,
            categoryCount: rows.length,
            groupCount: groupCount,
          ),
          const SizedBox(height: WebInsets.xl),
          if (rows.isEmpty) ...[
            const _EmptyState(),
            const SizedBox(height: WebInsets.xl),
          ],
          // The setup card always renders so the trailing "Add a category…"
          // row is available even with no budget set yet.
          //
          // Keyed because the siblings around it come and go with `rows`: the
          // pace ring and the empty state swap on the first budget of a month,
          // which shifts this card's index and, unkeyed, hands the add-row a
          // fresh State — silently dropping the user out of Savings mode
          // between their first entry and their second.
          _SetupCard(
            key: const ValueKey('budget-setup-card'),
            presenter: presenter,
            rows: rows,
            allocated: allocated,
            remaining: remaining,
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: WebInsets.xl),
            _AllocationByGroup(presenter: presenter, rows: rows),
          ],
        ],
      ),
    );

    // No explicit background: let the page show the shell's (darker)
    // scaffoldBackgroundColor like the Dashboard/Setup pages, so the content
    // area is distinct from the sidebar (both the sidebar and `cs.surface`
    // share surfaceContainerLow, which made the page blend into the rail).
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WebInsets.xxl),
      child: Align(alignment: Alignment.topCenter, child: content),
    );
  }
}

// ─── Pace ring hero ────────────────────────────────────────────────────────

/// Desktop counterpart of the mobile Budget hero: the spent-percentage ring
/// beside the SPENT figure, "of {allocated}", the remaining line, and the
/// Ahead-of-pace / Over-pace / Over-budget pill.
///
/// Deliberately a plain [WebCard] and not a [WebHeroCard] — the phone's Budget
/// hero is an ordinary elevated card, and the gradient treatment is reserved
/// for net worth and what's due. Every figure is a presenter getter; the only
/// decision here is which colour the ring escalates to.
class _PaceRingHero extends StatelessWidget {
  final BudgetPresenter presenter;

  const _PaceRingHero({required this.presenter});

  /// Below this width the ring drops above the figure instead of beside it.
  static const double _sideBySideMin = 460;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;

    final allocated = presenter.totalAllocated;
    final spent = presenter.totalSpent;
    final remaining = presenter.totalRemaining;
    final pct = presenter.percentUsed;
    final over = spent > allocated && allocated > 0;
    // Keys off the raw sign, not `over` — spending against a zero allocation
    // still reads as overspent (matching the phone).
    final overspent = remaining < 0;

    final ring = AppRingProgress(
      value: pct.clamp(0.0, 1.0),
      size: 128,
      strokeWidth: 14,
      primaryColor: over ? cs.error : appColors.fast,
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(pct * 100).round()}%',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            'spent',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: appColors.textMuted),
          ),
        ],
      ),
    );

    final figure = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
        WebNumber(
          formatPeso(spent),
          size: WebNumberSize.tileLarge,
          weight: FontWeight.w800,
        ),
        Text(
          'of ${formatPeso(allocated)}',
          style:
              theme.textTheme.bodySmall?.copyWith(color: appColors.textMuted),
        ),
        const SizedBox(height: WebInsets.sm),
        Text(
          overspent
              ? '${formatPeso(remaining.abs())} over'
              : '${formatPeso(remaining)} left',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: overspent ? cs.error : appColors.success,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (presenter.isCurrentMonth) ...[
          const SizedBox(height: WebInsets.md),
          _PacePill(ahead: presenter.isAheadOfPace, over: over),
        ],
      ],
    );

    return WebCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _sideBySideMin) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ring,
                const SizedBox(height: WebInsets.lg),
                figure,
              ],
            );
          }
          return Row(
            children: [
              ring,
              const SizedBox(width: WebInsets.xxl),
              Expanded(child: figure),
            ],
          );
        },
      ),
    );
  }
}

/// Ahead of pace / Over pace / Over budget — the phone's pill, same wording and
/// same escalation.
class _PacePill extends StatelessWidget {
  final bool ahead;
  final bool over;

  const _PacePill({required this.ahead, required this.over});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final good = ahead && !over;
    final color = good ? context.appColors.success : theme.colorScheme.error;
    final label = over
        ? 'Over budget'
        : ahead
            ? 'Ahead of pace'
            : 'Over pace';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ─── Stat strip ────────────────────────────────────────────────────────────

class _StatStrip extends StatelessWidget {
  final double allocated;
  final double spent;
  final double remaining;
  final double usedPct;
  final int categoryCount;
  final int groupCount;

  const _StatStrip({
    required this.allocated,
    required this.spent,
    required this.remaining,
    required this.usedPct,
    required this.categoryCount,
    required this.groupCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tiles = <Widget>[
      WebStatTile(
        label: 'Allocated',
        value: formatPeso(allocated),
        sub: 'Planned this month',
        icon: Icons.pie_chart_outline,
      ),
      WebStatTile(
        label: 'Spent',
        value: formatPeso(spent),
        sub: '${usedPct.toStringAsFixed(1)}% used',
        icon: Icons.north_east,
      ),
      WebStatTile(
        label: 'Remaining',
        value: formatPeso(remaining),
        sub: 'Left to spend',
        icon: Icons.account_balance_wallet_outlined,
        valueColor: remaining < 0 ? cs.error : cs.tertiary,
      ),
      WebStatTile(
        label: 'Categories',
        value: '$categoryCount',
        sub: '$groupCount groups',
        icon: Icons.layers_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 900 ? 4 : 2;
        const gap = WebInsets.lg;
        final tileWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }
}

// ─── Setup table card ────────────────────────────────────────────────────────

class _SetupCard extends StatelessWidget {
  final BudgetPresenter presenter;
  final List<_Row> rows;
  final double allocated;
  final double remaining;

  const _SetupCard({
    super.key,
    required this.presenter,
    required this.rows,
    required this.allocated,
    required this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return WebCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WebInsets.lg,
              vertical: WebInsets.md,
            ),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadii.lg),
                topRight: Radius.circular(AppRadii.lg),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Budget Setup',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        'Click any allocated cell to edit · Enter on the last row to add',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: WebInsets.md),
                Text.rich(
                  TextSpan(
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    children: [
                      TextSpan(
                        text: formatPeso(allocated),
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(text: ' allocated   ·   '),
                      TextSpan(
                        text: '${formatPeso(remaining)} left',
                        style: TextStyle(
                          color: remaining < 0 ? cs.error : cs.tertiary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Horizontally-scrollable table. The table must be given a BOUNDED
          // width: a horizontal SingleChildScrollView hands its child unbounded
          // width, and the rows use Expanded (the flexible Category column),
          // which asserts under unbounded constraints (box.dart). So size the
          // table to fill the card, falling back to a 920px min that scrolls
          // horizontally only when the viewport is narrower than that.
          LayoutBuilder(
            builder: (context, constraints) {
              final tableWidth = max(920.0, constraints.maxWidth);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: _Table(presenter: presenter, rows: rows),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Fixed column widths matching the reference (Category is flexible).
class _Table extends StatelessWidget {
  final BudgetPresenter presenter;
  final List<_Row> rows;

  const _Table({required this.presenter, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HeaderRow(),
        for (final row in rows)
          _DataRow(key: ValueKey(row.id), presenter: presenter, row: row),
        _AddRow(presenter: presenter),
      ],
    );
  }
}

// Column layout shared by header + body.
const double _kGroupW = 168;
const double _kAllocW = 132;
const double _kSpentW = 108;
const double _kRemainW = 116;
const double _kUsedW = 168;
const double _kStatusW = 116;
const double _kActionW = 48;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
    );
    Widget cell(String label, double? w, {TextAlign align = TextAlign.left}) {
      final text = Text(label.toUpperCase(), style: style, textAlign: align);
      final child = align == TextAlign.right
          ? Align(alignment: Alignment.centerRight, child: text)
          : text;
      return w == null
          ? Expanded(child: child)
          : SizedBox(width: w, child: child);
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.lg,
        vertical: WebInsets.sm,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          cell('Category', null),
          cell('Group', _kGroupW),
          cell('Allocated', _kAllocW, align: TextAlign.right),
          cell('Spent', _kSpentW, align: TextAlign.right),
          cell('Remaining', _kRemainW, align: TextAlign.right),
          cell('Used', _kUsedW),
          cell('Status', _kStatusW),
          cell('', _kActionW),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final BudgetPresenter presenter;
  final _Row row;

  const _DataRow({super.key, required this.presenter, required this.row});

  Future<void> _commitAllocation(double amount) async {
    final existing = presenter.budgetFor(row.id);
    await presenter.setBudget(
      row.id,
      amount,
      group: existing?.group ?? row.groupId,
      budgetType: existing?.budgetType ?? BudgetType.variable,
    );
  }

  Future<void> _changeGroup(String groupId) async {
    final existing = presenter.budgetFor(row.id);
    await presenter.setBudget(
      row.id,
      existing?.allocatedAmount ?? row.allocated,
      group: groupId,
      budgetType: existing?.budgetType ?? BudgetType.variable,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = _statusFor(row.used, isSavings: row.accountBacked);
    final remaining = row.remaining;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.lg,
        vertical: 2,
      ),
      child: Row(
        children: [
          // Category name
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(color: row.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: WebInsets.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      // Money out of a fund no longer subtracts from its
                      // progress, so it has to be said out loud here — netted
                      // away it was invisible, and the row just looked unfunded.
                      if (row.withdrawn > 0)
                        Text(
                          '${formatPeso(row.spent)} in · '
                          '${formatPeso(row.withdrawn)} out',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Group dropdown (expense rows) or static label (savings rows)
          SizedBox(
            width: _kGroupW,
            child: row.accountBacked
                ? _GroupLabel(
                    groupId: row.groupId,
                    groupName: presenter.budgetGroupLabel(row.groupId),
                    color: row.color,
                  )
                : _GroupDropdown(
                    groupId: row.groupId,
                    expenseGroups: presenter.expenseGroups,
                    onChanged: _changeGroup,
                  ),
          ),
          // Allocated (editable)
          SizedBox(
            width: _kAllocW,
            child: _AmountField(
              value: row.allocated,
              onCommit: _commitAllocation,
            ),
          ),
          // Spent
          SizedBox(
            width: _kSpentW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WebInsets.sm),
              child: Text(
                formatPeso(row.spent),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          // Remaining
          SizedBox(
            width: _kRemainW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WebInsets.sm),
              child: Text(
                formatPeso(remaining),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: remaining < 0 ? cs.error : cs.onSurface,
                ),
              ),
            ),
          ),
          // Used (progress + %)
          SizedBox(
            width: _kUsedW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WebInsets.sm),
              child: Row(
                children: [
                  Expanded(
                    child: WebProgressBar(
                      value: row.used,
                      color: _statusColor(context, row.used,
                          isSavings: row.accountBacked),
                    ),
                  ),
                  const SizedBox(width: WebInsets.sm),
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${(row.used * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Status
          SizedBox(
            width: _kStatusW,
            child: Align(
              alignment: Alignment.centerLeft,
              child: WebBadge(status.label, tone: status.tone),
            ),
          ),
          // Remove from budget
          SizedBox(
            width: _kActionW,
            child: IconButton(
              tooltip: 'Remove from budget',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
              onPressed: () => _confirmRemove(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from budget?'),
        content: Text(
            'Remove "${row.name}" from this month\'s budget? The category and '
            'its transactions stay — only the allocation is cleared.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await presenter.removeBudget(row.id);
    if (!context.mounted) return;
    AppToast.show(context, 'Removed "${row.name}" from the budget.');
  }
}

/// Static group chip for savings rows (group cannot be reassigned inline).
class _GroupLabel extends StatelessWidget {
  final String groupId;
  final String groupName;
  final Color color;

  const _GroupLabel({
    required this.groupId,
    required this.groupName,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WebInsets.sm),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: WebInsets.sm),
          Flexible(
            child: Text(
              groupName,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupDropdown extends StatelessWidget {
  final String groupId;
  final List<BudgetGroupDef> expenseGroups;
  final ValueChanged<String> onChanged;

  const _GroupDropdown({
    required this.groupId,
    required this.expenseGroups,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.xs,
        vertical: WebInsets.sm,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: expenseGroups.any((g) => g.id == groupId) ? groupId : null,
          isDense: true,
          isExpanded: true,
          borderRadius: AppRadii.smBorder,
          icon: Icon(Icons.expand_more, size: 16, color: cs.onSurfaceVariant),
          style: theme.textTheme.bodyMedium,
          dropdownColor: cs.surfaceContainerHigh,
          items: [
            for (var i = 0; i < expenseGroups.length; i++)
              DropdownMenuItem(
                value: expenseGroups[i].id,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _groupColorByIndex(context, i),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: WebInsets.sm),
                    Text(expenseGroups[i].name),
                  ],
                ),
              ),
          ],
          selectedItemBuilder: (context) => [
            for (var i = 0; i < expenseGroups.length; i++)
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _groupColorByIndex(context, i),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: WebInsets.sm),
                  Text(expenseGroups[i].name),
                ],
              ),
          ],
          onChanged: (gId) {
            if (gId != null && gId != groupId) onChanged(gId);
          },
        ),
      ),
    );
  }
}

/// Cycles through theme accent colors by index.
Color _groupColorByIndex(BuildContext context, int index) {
  final cs = Theme.of(context).colorScheme;
  return [cs.primary, cs.secondary, cs.tertiary, cs.error][index % 4];
}

/// Editable, right-aligned amount field. Shows formatted thousands when
/// unfocused, raw digits when focused. Commits on submit / focus loss.
class _AmountField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onCommit;

  const _AmountField({required this.value, required this.onCommit});

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _display(widget.value));
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _AmountField old) {
    super.didUpdateWidget(old);
    // Keep in sync with presenter when not actively editing.
    if (!_focus.hasFocus && old.value != widget.value) {
      _controller.text = _display(widget.value);
    }
  }

  String _display(double v) {
    final whole = v.round();
    final s = whole.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      // Show raw value for editing.
      final v = widget.value;
      _controller.text =
          v == v.roundToDouble() ? v.round().toString() : v.toString();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _commit();
    }
  }

  void _commit() {
    final raw = _controller.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final parsed = double.tryParse(raw) ?? 0;
    _controller.text = _display(parsed);
    if (parsed != widget.value) widget.onCommit(parsed);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      onSubmitted: (_) {
        _commit();
        _focus.unfocus();
      },
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WebInsets.sm,
          vertical: WebInsets.sm,
        ),
        filled: true,
        fillColor: Colors.transparent,
        hoverColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadii.smBorder,
          borderSide: BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.smBorder,
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
      ),
    );
  }
}

// Sentinel value for the picker's "create a new category" entry.
const String _kCreateNewCategory = '__create_new__';

/// Final add-budget row. Pick an existing expense category (or create one), set
/// a group + allocation, then bind the budget to that category via the
/// presenter. Picking an existing category — rather than typing a free-text
/// name that always mints a new one — keeps the budget bound to the category
/// your transactions actually use, so spend tracking matches and no duplicate
/// categories leak into the ledger. Mirrors the mobile add-budget sheet.
class _AddRow extends StatefulWidget {
  final BudgetPresenter presenter;
  const _AddRow({required this.presenter});

  @override
  State<_AddRow> createState() => _AddRowState();
}

class _AddRowState extends State<_AddRow> {
  final _amountController = TextEditingController();
  String _groupId = BudgetGroupDef.idVariableOptional;
  String? _selectedCategoryId;
  bool _busy = false;

  /// Savings mode mirrors mobile's segment: the picker swaps to savings/goal
  /// *accounts* (account ids, not expense categories) and the budget is
  /// persisted under [BudgetGroupDef.idSavings].
  ///
  /// Derived from [_groupId] rather than held alongside it, exactly as the
  /// mobile add-budget sheet does. When the two were separate fields they could
  /// disagree — the toggle read Savings while the group had reset to Variable —
  /// and the row was then written with an account id under an expense group,
  /// where neither the savings list nor the category list could find it again.
  bool get _isSavings => widget.presenter.isSavingsGroup(_groupId);

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  /// Expense categories that don't already have a budget this month — those are
  /// shown as their own rows above, so offering them again here would just be a
  /// confusing re-edit.
  List<FinanceCategory> get _availableCategories {
    final budgeted = <String>{
      for (final list in widget.presenter.categoriesByGroup.values)
        for (final c in list) c.id,
    };
    return widget.presenter.expenseCategories
        .where((c) => !budgeted.contains(c.id))
        .toList();
  }

  /// Savings/goal accounts that don't already have a savings budget this month
  /// (those render as their own rows above).
  List<FinancialAccount> get _availableSavingsTargets {
    final budgeted = <String>{
      for (final entry in widget.presenter.savingsBudgets) entry.account.id,
    };
    return widget.presenter.savingsTargets
        .where((a) => !budgeted.contains(a.id))
        .toList();
  }

  /// Switch between expense ↔ savings mode. Crossing invalidates the picked id
  /// since categories and accounts share the same `categoryId` slot but draw
  /// from different lists (mirrors the mobile add-budget sheet).
  void _setSavingsMode(bool savings) {
    if (savings == _isSavings) return;
    setState(() {
      _selectedCategoryId = null;
      _groupId = savings
          ? BudgetGroupDef.idSavings
          : BudgetGroupDef.idVariableOptional;
    });
  }

  Future<void> _onPick(String value) async {
    if (value != _kCreateNewCategory) {
      setState(() => _selectedCategoryId = value);
      return;
    }
    final cat = await _showCreateCategoryDialog();
    if (cat == null || !mounted) return;
    // addCategory delegates to the ledger so other presenters pick it up.
    await widget.presenter.addCategory(cat);
    if (!mounted) return;
    setState(() => _selectedCategoryId = cat.id);
  }

  Future<FinanceCategory?> _showCreateCategoryDialog() async {
    final nameCtrl = TextEditingController();
    final colorHex = categoryColorAt(
      widget.presenter.expenseCategories.length,
      isExpense: true,
    );
    // Starts on "Auto" (the name-derived glyph), which is exactly what the
    // hard-coded key here used to produce — so the default is unchanged and
    // picking a specific icon is now possible rather than mobile-only.
    var iconKey = kAutoCategoryIconKey;

    FinanceCategory? build() {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) return null;
      return FinanceCategory(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
        name: name,
        type: CategoryType.expense,
        icon: iconKey,
        colorHex: colorHex,
      );
    }

    final cat = await showDialog<FinanceCategory>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('New Expense Category'),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              WebCategoryIconPreview(
                iconKey: iconKey,
                name: nameCtrl.text,
                type: CategoryType.expense,
                onTap: () async {
                  final picked =
                      await showWebCategoryIconPicker(ctx, current: iconKey);
                  if (picked != null) setLocalState(() => iconKey = picked);
                },
              ),
              const SizedBox(width: WebInsets.md),
              Expanded(
                child: TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Category name'),
                  // Rebuild so the auto-glyph preview tracks the typed name
                  // live, the way the mobile add-form does.
                  onChanged: (_) => setLocalState(() {}),
                  onSubmitted: (_) {
                    final c = build();
                    if (c != null) Navigator.pop(ctx, c);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final c = build();
                if (c != null) Navigator.pop(ctx, c);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    return cat;
  }

  Future<void> _add() async {
    final id = _selectedCategoryId;
    final raw = _amountController.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final amount = double.tryParse(raw) ?? 0;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await widget.presenter.setBudget(
        id,
        amount,
        group: _groupId,
        budgetType: BudgetType.variable,
      );
      // Guard the controller writes after the await — the row may have been
      // removed mid-save, in which case the controller is disposed. (C11)
      if (!mounted) return;
      _amountController.clear();
      setState(() {
        // The just-budgeted id drops out of the picker's entries, so leaving it
        // selected left the field showing its hint while a stale id was still
        // armed — pressing ✓ again would silently re-write that budget.
        _selectedCategoryId = null;
        // Stay in whichever mode the user is working in. Resetting the group
        // unconditionally is what used to strand the next savings entry under
        // an expense group while the toggle still read Savings.
        if (!_isSavings) _groupId = BudgetGroupDef.idVariableOptional;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<WebDropdownEntry<String>> _expenseEntries(ThemeData theme) {
    final available = _availableCategories;
    return [
      const WebDropdownEntry(
          value: _kCreateNewCategory, label: '＋ New category…'),
      for (var i = 0; i < available.length; i++)
        WebDropdownEntry(
          value: available[i].id,
          label: available[i].name,
          dotColor: resolveSliceColor(available[i].colorHex, i,
              brightness: theme.brightness),
        ),
    ];
  }

  List<WebDropdownEntry<String>> _savingsEntries(ThemeData theme) {
    final available = _availableSavingsTargets;
    return [
      for (final a in available)
        WebDropdownEntry(
          value: a.id,
          label: _savingsAccountLabel(a),
          dotColor: theme.colorScheme.tertiary,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entries =
        _isSavings ? _savingsEntries(theme) : _expenseEntries(theme);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppRadii.lg),
          bottomRight: Radius.circular(AppRadii.lg),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: WebInsets.lg,
        vertical: WebInsets.xs,
      ),
      child: Row(
        children: [
          _AddModeToggle(
            isSavings: _isSavings,
            onChanged: _setSavingsMode,
          ),
          const SizedBox(width: WebInsets.sm),
          Expanded(
            child: WebSearchableDropdown<String>(
              value: _selectedCategoryId,
              entries: entries,
              hintText:
                  _isSavings ? 'Choose an account…' : 'Choose a category…',
              isDense: true,
              onChanged: _onPick,
            ),
          ),
          SizedBox(
            width: _kGroupW,
            // Savings rows are keyed by account id and always belong to the
            // Savings group — the group is fixed, so show a static label
            // instead of the expense-group dropdown (matches the data rows).
            child: _isSavings
                ? _GroupLabel(
                    groupId: BudgetGroupDef.idSavings,
                    groupName: widget.presenter
                        .budgetGroupLabel(BudgetGroupDef.idSavings),
                    color: cs.tertiary,
                  )
                : _GroupDropdown(
                    groupId: _groupId,
                    expenseGroups: widget.presenter.expenseGroups,
                    onChanged: (g) => setState(() => _groupId = g),
                  ),
          ),
          SizedBox(
            width: _kAllocW,
            child: TextField(
              controller: _amountController,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
              ],
              onSubmitted: (_) => _add(),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '0',
                hintStyle: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: WebInsets.sm),
              ),
            ),
          ),
          const SizedBox(width: _kSpentW + _kRemainW + _kUsedW),
          SizedBox(
            width: _kStatusW,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      onPressed: _add,
                      tooltip: _isSavings ? 'Add savings goal' : 'Add category',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadii.smBorder,
                        ),
                      ),
                      icon: const Icon(Icons.check, size: 16),
                    ),
            ),
          ),
          const SizedBox(width: _kActionW),
        ],
      ),
    );
  }
}

/// Display label for a savings/goal account in the add-row picker — mirrors the
/// mobile add-budget sheet (appends the goal target when present).
String _savingsAccountLabel(FinancialAccount a) {
  if (a.category == AccountCategory.goal && a.goalTarget != null) {
    return '${a.name}  ·  goal ${formatPesoCompact(a.goalTarget!)}';
  }
  return a.name;
}

/// Compact Expense ↔ Savings switch that leads the add-row, swapping the picker
/// between expense categories and savings/goal accounts (web parity with the
/// mobile add-budget sheet's Savings/Goals segment).
class _AddModeToggle extends StatelessWidget {
  final bool isSavings;
  final ValueChanged<bool> onChanged;

  const _AddModeToggle({required this.isSavings, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget seg(String label, IconData icon, bool savings) {
      final selected = savings == isSavings;
      return InkWell(
        borderRadius: AppRadii.smBorder,
        onTap: selected ? null : () => onChanged(savings),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WebInsets.sm,
            vertical: WebInsets.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: WebInsets.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    Color bgFor(bool savings) =>
        savings == isSavings ? cs.primary : Colors.transparent;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadii.smBorder,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: bgFor(false),
              borderRadius: AppRadii.smBorder,
            ),
            child: seg('Expense', Icons.shopping_bag_outlined, false),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: bgFor(true),
              borderRadius: AppRadii.smBorder,
            ),
            child: seg('Savings', Icons.savings_outlined, true),
          ),
        ],
      ),
    );
  }
}

// ─── Allocation by group ──────────────────────────────────────────────────────

class _AllocationByGroup extends StatelessWidget {
  final BudgetPresenter presenter;
  final List<_Row> rows;

  const _AllocationByGroup({required this.presenter, required this.rows});

  @override
  Widget build(BuildContext context) {
    final totalAllocated = presenter.totalAllocated;

    // Aggregate rows by group, preserving the sorted group order from presenter.
    final allGroups = presenter.groups;
    final groups = <({BudgetGroupDef def, double alloc, double spent})>[];
    for (var i = 0; i < allGroups.length; i++) {
      final g = allGroups[i];
      final inGroup = rows.where((r) => r.groupId == g.id).toList();
      if (inGroup.isEmpty) continue;
      groups.add((
        def: g,
        alloc: inGroup.fold<double>(0, (s, r) => s + r.allocated),
        spent: inGroup.fold<double>(0, (s, r) => s + r.spent),
      ));
    }

    final slices = [
      for (var i = 0; i < groups.length; i++)
        WebChartSlice(
          label: groups[i].def.name,
          value: groups[i].alloc,
          color: _groupColorByIndex(context, i),
        ),
    ];

    return WebCard(
      title: 'Allocation by Group',
      description: 'Updates as you edit',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final donut = WebDonutChart(
            slices: slices,
            centerLabel: 'Allocated',
            centerValue: formatPesoCompact(totalAllocated),
            showLegend: false,
            size: 170,
          );
          final legend = _GroupLegendGrid(
            groups: groups,
            totalAllocated: totalAllocated,
            twoCol: wide,
            colorOf: (i) => _groupColorByIndex(context, i),
          );

          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: donut),
                const SizedBox(height: WebInsets.xl),
                legend,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              donut,
              const SizedBox(width: WebInsets.xxl),
              Expanded(child: legend),
            ],
          );
        },
      ),
    );
  }
}

class _GroupLegendGrid extends StatelessWidget {
  final List<({BudgetGroupDef def, double alloc, double spent})> groups;
  final double totalAllocated;
  final bool twoCol;
  final Color Function(int index) colorOf;

  const _GroupLegendGrid({
    required this.groups,
    required this.totalAllocated,
    required this.twoCol,
    required this.colorOf,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      for (var i = 0; i < groups.length; i++)
        _GroupLegendItem(
          color: colorOf(i),
          name: groups[i].def.name,
          alloc: groups[i].alloc,
          spent: groups[i].spent,
          totalAllocated: totalAllocated,
        ),
    ];

    if (!twoCol) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: WebInsets.lg),
            items[i],
          ],
        ],
      );
    }

    // An odd group count (three groups is the default set) left the last
    // legend item at half width with a hole beside it; centre it instead.
    return WebTileFlow(
      columns: 2,
      spacing: WebInsets.xxl,
      runSpacing: WebInsets.lg,
      lastRowFit: WebLastRowFit.capAndCentre,
      children: items,
    );
  }
}

class _GroupLegendItem extends StatelessWidget {
  final Color color;
  final String name;
  final double alloc;
  final double spent;
  final double totalAllocated;

  const _GroupLegendItem({
    required this.color,
    required this.name,
    required this.alloc,
    required this.spent,
    required this.totalAllocated,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final used = alloc > 0 ? (spent / alloc) : 0.0;
    final shareOfBudget =
        totalAllocated > 0 ? (alloc / totalAllocated * 100) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: WebInsets.sm),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: WebInsets.sm),
            Text(
              formatPeso(alloc),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: WebInsets.sm),
        WebProgressBar(value: used, color: color),
        const SizedBox(height: WebInsets.xs),
        Text(
          '${formatPeso(spent)} spent · ${shareOfBudget.round()}% of budget',
          style:
              theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return WebCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WebInsets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: WebInsets.md),
            Text('No budget set for this month',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: WebInsets.xs),
            Text(
              'Add a category below to start planning your allocations.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
