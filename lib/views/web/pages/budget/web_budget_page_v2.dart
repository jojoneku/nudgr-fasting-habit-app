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
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../../web_keys.dart';
import '../../widgets/web_widgets.dart';
import 'web_budget_amount_field.dart';
import 'web_budget_shared.dart';
import 'web_manage_groups_dialog_v2.dart';
import 'web_new_category_dialog.dart';

/// The v2 Budget page (Plan 063, Phase 6; canvas `Budget.dc.html`).
///
/// Header with the month stepper and Manage groups; a hero pair — the pace
/// ring beside the allocation donut — then one grouped table: a subtotal row
/// per group, the category rows under it, and the draft row at the bottom.
/// The 4-tile stat strip of the pre-v2 page is gone (it repeated the hero);
/// its "N categories · M groups" moved into the table header.
///
/// Every figure is a [BudgetPresenter] getter and every mutation one of its
/// methods ([BudgetPresenter.setBudget], [BudgetPresenter.removeBudget],
/// [BudgetPresenter.addCategory], the group CRUD). Over-budget rows use the
/// warning tone with the words "Over by ₱X", never red alone, and the Watch
/// boundary is the shared [kBudgetWatchThreshold].
class WebBudgetPageV2 extends StatelessWidget {
  final BudgetPresenter presenter;

  /// Appended after the page's own header actions — the shell passes its
  /// Nudgy header button here.
  final Widget? trailing;

  const WebBudgetPageV2({super.key, required this.presenter, this.trailing});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) =>
          _BudgetBody(presenter: presenter, trailing: trailing),
    );
  }
}

// ─── Row model ───────────────────────────────────────────────────────────────

/// One table row. [accountBacked] rows are savings/goal budgets keyed by an
/// account id; their group is fixed and "spent" means funded in.
class _Row {
  final String id;
  final String name;
  final String groupId;
  final double allocated;
  final double spent;
  final double withdrawn;
  final Color color;
  final bool accountBacked;

  const _Row({
    required this.id,
    required this.name,
    required this.groupId,
    required this.allocated,
    required this.spent,
    required this.color,
    required this.accountBacked,
    this.withdrawn = 0,
  });

  double get used => allocated > 0 ? spent / allocated : 0;
  double get remaining => allocated - spent;
}

/// A group with its rows and subtotals, in presenter order. Only groups that
/// hold a row this month appear in the table and the donut.
class _Section {
  final BudgetGroupDef group;
  final Color color;
  final List<_Row> rows;

  const _Section(
      {required this.group, required this.color, required this.rows});

  double get allocated => rows.fold(0.0, (s, r) => s + r.allocated);
  double get spent => rows.fold(0.0, (s, r) => s + r.spent);
  double get remaining => allocated - spent;
  double get used => allocated > 0 ? spent / allocated : 0;
}

enum _Tone { ok, watch, over, funded }

/// Status of one row. Savings rows never read "Over": funding past a goal is
/// the goal working, so they go On track → Funded.
({_Tone tone, String label}) _statusFor(_Row row) {
  if (row.accountBacked) {
    return row.used >= 1
        ? (tone: _Tone.funded, label: 'Funded')
        : (tone: _Tone.ok, label: 'On track');
  }
  if (row.used >= 1 && row.allocated > 0 || row.spent > row.allocated) {
    return (
      tone: _Tone.over,
      label: 'Over by ${formatPesoWhole(row.spent - row.allocated)}',
    );
  }
  if (row.used >= kBudgetWatchThreshold) {
    return (tone: _Tone.watch, label: 'Watch · ${(row.used * 100).round()}%');
  }
  return (tone: _Tone.ok, label: 'On track');
}

Color _toneColor(BuildContext context, _Tone tone) {
  final cs = Theme.of(context).colorScheme;
  final a = context.appColors;
  return switch (tone) {
    _Tone.ok => cs.tertiary,
    _Tone.watch => a.bills,
    _Tone.over => a.bills,
    _Tone.funded => a.treasury,
  };
}

/// Days left in the current calendar month, including today.
int _daysToGo(DateTime now) {
  final lastDay = DateTime(now.year, now.month + 1, 0).day;
  return max(0, lastDay - now.day);
}

// ─── Body ────────────────────────────────────────────────────────────────────

class _BudgetBody extends StatelessWidget {
  final BudgetPresenter presenter;
  final Widget? trailing;

  const _BudgetBody({required this.presenter, this.trailing});

  List<_Section> _sections(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final byGroup = presenter.categoriesByGroup;
    final savings = presenter.savingsBudgets;
    final groups = presenter.groups;
    final sections = <_Section>[];
    var colorIndex = 0;
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      final color = webBudgetGroupColor(context, i);
      final rows = <_Row>[];
      if (g.isSavings) {
        for (final e in savings.where((e) => e.budget.group == g.id)) {
          rows.add(_Row(
            id: e.account.id,
            name: e.account.name,
            groupId: g.id,
            allocated: e.budget.allocatedAmount,
            spent: presenter.fundedInto(e.account.id),
            withdrawn: presenter.withdrawnFrom(e.account.id),
            color: color,
            accountBacked: true,
          ));
        }
      } else {
        for (final cat in byGroup[g.id] ?? const <FinanceCategory>[]) {
          rows.add(_Row(
            id: cat.id,
            name: cat.name,
            groupId: g.id,
            allocated: presenter.budgetFor(cat.id)?.allocatedAmount ?? 0,
            spent: presenter.spentFor(cat.id),
            color: resolveSliceColor(cat.colorHex, colorIndex++,
                brightness: brightness),
            accountBacked: false,
          ));
        }
      }
      if (rows.isNotEmpty) {
        sections.add(_Section(group: g, color: color, rows: rows));
      }
    }
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections(context);
    final rowCount = sections.fold(0, (n, s) => n + s.rows.length);
    final allocated = presenter.totalAllocated;
    final month = monthLabel(presenter.selectedMonth);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebPageHeaderV2(
          title: 'Budget',
          subtitle: rowCount == 0
              ? '$month · nothing allocated yet'
              : '$month · ${formatPeso(allocated)} allocated across '
                  '$rowCount ${rowCount == 1 ? 'category' : 'categories'} in '
                  '${sections.length} ${sections.length == 1 ? 'group' : 'groups'}',
          monthStepper: WebMonthStepper(
            key: WebKeys.budgetMonthStepper,
            label: month,
            onPrev: () =>
                presenter.setMonth(previousMonth(presenter.selectedMonth)),
            onNext: () =>
                presenter.setMonth(nextMonth(presenter.selectedMonth)),
          ),
          actions: [
            OutlinedButton.icon(
              key: WebKeys.budgetManageGroups,
              onPressed: () =>
                  showWebManageGroupsDialogV2(context, presenter: presenter),
              icon: const Icon(Icons.folder_outlined, size: 16),
              label: const Text('Manage groups'),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        if (rowCount == 0) ...[
          const _EmptyState(),
          const SizedBox(height: WebInsets.xl),
        ] else ...[
          _HeroPair(presenter: presenter, sections: sections),
          const SizedBox(height: WebInsets.xl),
        ],
        // Keyed because the hero and the empty state swap around it on the
        // first budget of a month; unkeyed, the draft row would get a fresh
        // State and drop out of Savings mode between two adds.
        _TableCard(
          key: const ValueKey('budget-table-card'),
          presenter: presenter,
          sections: sections,
          rowCount: rowCount,
        ),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(WebInsets.xxl),
      child: Align(alignment: Alignment.topCenter, child: content),
    );
  }
}

// ─── Hero: pace ring + donut ────────────────────────────────────────────────

class _HeroPair extends StatelessWidget {
  final BudgetPresenter presenter;
  final List<_Section> sections;

  const _HeroPair({required this.presenter, required this.sections});

  @override
  Widget build(BuildContext context) {
    final donut =
        _DonutCard(sections: sections, total: presenter.totalAllocated);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          // Below 460 the ring also drops above the figure.
          final pace = _PaceCard(
            presenter: presenter,
            stackRing: constraints.maxWidth < 460,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [pace, const SizedBox(height: WebInsets.xl), donut],
          );
        }
        // IntrinsicHeight keeps the two cards level; a stretch alone would
        // ask for infinite height inside the page scroll view.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _PaceCard(presenter: presenter)),
              const SizedBox(width: WebInsets.xl),
              Expanded(child: donut),
            ],
          ),
        );
      },
    );
  }
}

class _PaceCard extends StatelessWidget {
  final BudgetPresenter presenter;

  /// Ring above the figure (narrow column) instead of beside it.
  final bool stackRing;

  const _PaceCard({required this.presenter, this.stackRing = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = context.appColors;

    final allocated = presenter.totalAllocated;
    final spent = presenter.totalSpent;
    final remaining = presenter.totalRemaining;
    final pct = presenter.percentUsed;
    final over = spent > allocated;
    final overspent = remaining < 0;
    final current = presenter.isCurrentMonth;
    final elapsed = presenter.monthElapsedFraction;

    final ring = AppRingProgress(
      value: pct.clamp(0.0, 1.0),
      size: 132,
      strokeWidth: 12,
      gapFraction: 0,
      glowOpacity: 0,
      primaryColor: over ? a.bills : cs.primary,
      trackColor: cs.surfaceContainerHighest,
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(pct * 100).round()}%',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'SPENT',
            style: theme.textTheme.labelSmall?.copyWith(
              color: a.textMuted,
              fontSize: 10.5,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );

    final sentence = !current
        ? (elapsed >= 1
            ? 'Month closed · ${(pct * 100).round()}% spent'
            : 'Month not started yet')
        : '${(elapsed * 100).round()}% of the month gone · '
            '${(pct * 100).round()}% spent';
    final days = _daysToGo(DateTime.now());

    final figure = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'SPENT',
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.84,
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            text: formatPeso(spent),
            style: webNumericStyle(
              theme.textTheme.headlineMedium?.copyWith(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1,
                color: cs.onSurface,
              ),
            ),
            children: [
              TextSpan(
                text: ' of ${formatPeso(allocated)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
            children: [
              TextSpan(
                text: overspent
                    ? '${formatPeso(remaining.abs())} over'
                    : '${formatPeso(remaining)} left',
                style: TextStyle(
                  color: overspent ? a.bills : a.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (current)
                TextSpan(
                  text: ' · $days ${days == 1 ? 'day' : 'days'} to go',
                ),
            ],
          ),
        ),
        const SizedBox(height: WebInsets.md),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: WebInsets.sm,
          runSpacing: WebInsets.xs,
          children: [
            if (current)
              _PacePill(
                key: WebBudgetKeys.heroPacePill,
                ahead: presenter.isAheadOfPace,
                over: over,
              ),
            Text(
              sentence,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );

    return WebCard(
      key: WebKeys.budgetPaceRing,
      child: stackRing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [ring, const SizedBox(height: WebInsets.lg), figure],
            )
          : Row(
              children: [
                ring,
                const SizedBox(width: WebInsets.xl),
                Expanded(child: figure),
              ],
            ),
    );
  }
}

/// Ahead of pace / Over pace / Over budget — the phone's pill, same wording
/// and same escalation; the over states use the warning tone.
class _PacePill extends StatelessWidget {
  final bool ahead;
  final bool over;

  const _PacePill({super.key, required this.ahead, required this.over});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = context.appColors;
    final good = ahead && !over;
    final color = good ? a.success : a.bills;
    final label = over
        ? 'Over budget'
        : ahead
            ? 'Ahead of pace'
            : 'Over pace';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            good ? Icons.check_rounded : Icons.warning_amber_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            softWrap: false,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutCard extends StatelessWidget {
  final List<_Section> sections;
  final double total;

  const _DonutCard({required this.sections, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final slices = [
      for (final s in sections)
        WebChartSlice(label: s.group.name, value: s.allocated, color: s.color),
    ];

    return WebCard(
      key: WebKeys.budgetGroupDonut,
      title: 'Allocation by group',
      description: 'Updates as you edit the table',
      child: Wrap(
        spacing: 18,
        runSpacing: WebInsets.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          WebDonutChart(slices: slices, showLegend: false, size: 110),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 180, maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  if (i > 0) const SizedBox(height: WebInsets.sm),
                  Row(
                    key: WebBudgetKeys.legend(sections[i].group.id),
                    children: [
                      WebDot(color: sections[i].color),
                      const SizedBox(width: WebInsets.sm),
                      Expanded(
                        child: Text(
                          sections[i].group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: WebInsets.sm),
                      WebNumber(
                        formatPeso(sections[i].allocated),
                        size: WebNumberSize.body,
                        weight: FontWeight.w700,
                      ),
                      SizedBox(
                        width: 42,
                        child: Text(
                          total > 0
                              ? '${(sections[i].allocated / total * 100).round()}%'
                              : '—',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Table ───────────────────────────────────────────────────────────────────

// Column layout shared by the header, the group rows, the data rows and the
// draft row. Category is the flexible column.
const double _kGroupW = 150;
const double _kAllocW = 130;
const double _kSpentW = 128;
const double _kRemainW = 120;
const double _kUsedW = 170;
const double _kStatusW = 150;
const double _kActionW = 44;
const double _kCellPadX = 12;
const double _kTableMinWidth = 900;

class _TableCard extends StatelessWidget {
  final BudgetPresenter presenter;
  final List<_Section> sections;
  final int rowCount;

  const _TableCard({
    super.key,
    required this.presenter,
    required this.sections,
    required this.rowCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = context.appColors;
    final allocated = presenter.totalAllocated;
    final remaining = presenter.totalRemaining;

    return WebCard(
      key: WebKeys.budgetTable,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            key: WebBudgetKeys.tableHeader,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Budget setup',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Click an Allocated cell to edit · Enter on the last '
                        'row adds a category · $rowCount '
                        '${rowCount == 1 ? 'category' : 'categories'} · '
                        '${sections.length} '
                        '${sections.length == 1 ? 'group' : 'groups'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: WebInsets.md),
                Text.rich(
                  TextSpan(
                    style: webNumericStyle(
                      theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 12.5,
                      ),
                    ),
                    children: [
                      TextSpan(text: '${formatPeso(allocated)} allocated · '),
                      TextSpan(
                        text: remaining < 0
                            ? '${formatPeso(remaining.abs())} over'
                            : '${formatPeso(remaining)} left',
                        style: TextStyle(
                          color: remaining < 0 ? a.bills : a.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // The table needs a bounded width: a horizontal scroll view hands
          // its child unbounded width and the flexible Category column
          // asserts under it. Fill the card, scroll only below the minimum.
          LayoutBuilder(
            builder: (context, constraints) {
              final width = max(_kTableMinWidth, constraints.maxWidth);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _ColumnHeader(),
                      for (final s in sections) ...[
                        _GroupRow(section: s),
                        for (final r in s.rows)
                          _DataRow(
                            key: WebBudgetKeys.row(r.id),
                            presenter: presenter,
                            row: r,
                            groupColor: s.color,
                          ),
                      ],
                      _DraftRow(presenter: presenter),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.63,
    );
    Widget cell(String label, double? w, {bool right = false}) {
      final text = Text(
        label.toUpperCase(),
        style: style,
        softWrap: false,
        textAlign: right ? TextAlign.right : TextAlign.left,
      );
      final padded = Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kCellPadX),
        child: text,
      );
      return w == null
          ? Expanded(child: padded)
          : SizedBox(width: w, child: padded);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outline)),
      ),
      child: Row(
        children: [
          cell('Category', null),
          cell('Group', _kGroupW),
          cell('Allocated', _kAllocW, right: true),
          cell('Spent', _kSpentW, right: true),
          cell('Remaining', _kRemainW, right: true),
          cell('Used', _kUsedW),
          cell('Status', _kStatusW),
          cell('', _kActionW),
        ],
      ),
    );
  }
}

/// The subtotal row that opens a group: dot, "NAME · count", the three
/// totals, and "N% used" (or "funded" for a savings group).
class _GroupRow extends StatelessWidget {
  final _Section section;

  const _GroupRow({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = context.appColors;
    final s = section;
    final isSavings = s.group.isSavings;
    final label = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.66,
    );
    final figure = webNumericStyle(
      theme.textTheme.bodySmall?.copyWith(
        color: cs.onSurface,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    );
    final pct = (s.used * 100).round();
    final trailing =
        isSavings ? (s.used >= 1 ? 'funded' : '$pct% funded') : '$pct% used';

    Widget num(String text, double w, {Color? color}) => SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kCellPadX),
            child: Text(
              text,
              textAlign: TextAlign.right,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: figure?.copyWith(color: color),
            ),
          ),
        );

    return Container(
      key: WebBudgetKeys.group(s.group.id),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: _kGroupW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kCellPadX),
              child: Row(
                children: [
                  WebDot(color: s.color),
                  const SizedBox(width: WebInsets.sm),
                  Flexible(
                    child: Text(
                      '${s.group.name.toUpperCase()} · ${s.rows.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: label,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Expanded(child: SizedBox()),
          num(formatPeso(s.allocated), _kAllocW),
          num(
            isSavings ? '${formatPeso(s.spent)} in' : formatPeso(s.spent),
            _kSpentW,
          ),
          num(
            s.remaining < 0
                ? '${formatPesoWhole(s.remaining.abs())} over'
                : formatPeso(max(0.0, s.remaining)),
            _kRemainW,
            color: s.remaining < 0 ? a.bills : null,
          ),
          SizedBox(
            width: _kUsedW + _kStatusW + _kActionW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kCellPadX),
              child: Text(trailing, style: label),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final BudgetPresenter presenter;
  final _Row row;
  final Color groupColor;

  const _DataRow({
    super.key,
    required this.presenter,
    required this.row,
    required this.groupColor,
  });

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

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showWebConfirm(
      context,
      title: 'Remove from budget?',
      message: 'Remove "${row.name}" from this month\'s budget? The '
          '${row.accountBacked ? 'account' : 'category'} and its '
          'transactions stay — only the allocation is cleared.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    await presenter.removeBudget(row.id);
    if (!context.mounted) return;
    AppToast.show(context, 'Removed "${row.name}" from the budget.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = context.appColors;
    final status = _statusFor(row);
    final over = !row.accountBacked && row.spent > row.allocated;
    final warn = !row.accountBacked && row.used >= kBudgetWatchThreshold;
    final barColor = warn ? a.bills : groupColor;
    final figure = webNumericStyle(
      theme.textTheme.bodyMedium?.copyWith(fontSize: 13.5),
    );

    Widget cell(Widget child, double w) => SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kCellPadX),
            child: child,
          ),
        );

    return Container(
      constraints: const BoxConstraints(minHeight: kWebHitTarget),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          // Category
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kCellPadX),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: row.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: WebInsets.sm),
                  Expanded(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Group
          cell(
            row.accountBacked
                ? Text(
                    presenter.budgetGroupLabel(row.groupId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      color: cs.onSurfaceVariant,
                    ),
                  )
                : _GroupDropdown(
                    key: WebKeys.budgetRowGroup,
                    groupId: row.groupId,
                    expenseGroups: presenter.expenseGroups,
                    groups: presenter.groups,
                    onChanged: _changeGroup,
                  ),
            _kGroupW,
          ),
          // Allocated (editable)
          cell(
            WebBudgetAmountField(
              key: WebKeys.budgetRowAllocated,
              value: row.allocated,
              onCommit: _commitAllocation,
              dashed: true,
            ),
            _kAllocW,
          ),
          // Spent — savings rows say both directions.
          cell(
            Text(
              row.accountBacked
                  ? '${formatPesoWhole(row.spent)} in · '
                      '${formatPesoWhole(row.withdrawn)} out'
                  : formatPeso(row.spent),
              textAlign: TextAlign.right,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: figure?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: row.accountBacked ? 12 : 13.5,
              ),
            ),
            _kSpentW,
          ),
          // Remaining
          cell(
            Text(
              over
                  ? '${formatPesoWhole(row.spent - row.allocated)} over'
                  : formatPeso(max(0.0, row.remaining)),
              textAlign: TextAlign.right,
              softWrap: false,
              style: figure?.copyWith(
                fontWeight: FontWeight.w600,
                color: over ? a.bills : cs.onSurface,
              ),
            ),
            _kRemainW,
          ),
          // Used
          cell(
            Row(
              children: [
                Expanded(
                  child: WebProgressBar(value: row.used, color: barColor),
                ),
                const SizedBox(width: WebInsets.sm),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(row.used * 100).round()}%',
                    textAlign: TextAlign.right,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            _kUsedW,
          ),
          // Status — scaleDown rather than clip, so an unusually long
          // amount shrinks a little instead of losing its last digits.
          cell(
            Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _StatusPill(
                  key: WebBudgetKeys.status(row.id),
                  label: status.label,
                  tone: status.tone,
                ),
              ),
            ),
            _kStatusW,
          ),
          // Remove
          SizedBox(
            width: _kActionW,
            child: IconButton(
              key: WebKeys.budgetRowRemove,
              tooltip: 'Remove from budget',
              onPressed: () => _confirmRemove(context),
              style: IconButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                minimumSize: const Size(kWebHitTarget, kWebHitTarget),
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.close_rounded, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// The status pill. One line, always: `softWrap: false`, a column wide
/// enough for "Over by ₱12,345" at this size, and a `FittedBox` around it
/// in the table, so a long amount can never push the text onto a second
/// line and double the row height.
class _StatusPill extends StatelessWidget {
  final String label;
  final _Tone tone;

  const _StatusPill({super.key, required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _toneColor(context, tone);
    final over = tone == _Tone.over;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: over ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: over ? Border.all(color: color.withValues(alpha: 0.4)) : null,
      ),
      child: Text(
        label,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GroupDropdown extends StatelessWidget {
  final String groupId;
  final List<BudgetGroupDef> expenseGroups;
  final List<BudgetGroupDef> groups;
  final ValueChanged<String> onChanged;

  const _GroupDropdown({
    super.key,
    required this.groupId,
    required this.expenseGroups,
    required this.groups,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Colour by the group's position in the full list so the swatch matches
    // the group's table dot and donut slice.
    Color colorOf(BudgetGroupDef g) =>
        webBudgetGroupColor(context, groups.indexWhere((x) => x.id == g.id));
    Widget item(BudgetGroupDef g) => Row(
          children: [
            WebDot(color: colorOf(g)),
            const SizedBox(width: WebInsets.sm),
            Flexible(
              child: Text(
                g.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: expenseGroups.any((g) => g.id == groupId) ? groupId : null,
        isDense: true,
        isExpanded: true,
        borderRadius: AppRadii.smBorder,
        icon: Icon(Icons.expand_more_rounded,
            size: 16, color: cs.onSurfaceVariant),
        dropdownColor: cs.surfaceContainerHigh,
        items: [
          for (final g in expenseGroups)
            DropdownMenuItem(value: g.id, child: item(g)),
        ],
        onChanged: (id) {
          if (id != null && id != groupId) onChanged(id);
        },
      ),
    );
  }
}

// ─── Draft row ───────────────────────────────────────────────────────────────

const String _kCreateNewCategory = '__create_new__';

/// The last row: Expense/Savings segment, a searchable picker (categories
/// without a budget this month, or savings accounts; "＋ New category…" opens
/// the dialog), the group, the amount and ✓. Enter in the amount adds.
///
/// Savings mode is derived from the group, never held beside it — when they
/// were two fields they disagreed, and a row was written with an account id
/// under an expense group where nothing could render it.
class _DraftRow extends StatefulWidget {
  final BudgetPresenter presenter;

  const _DraftRow({required this.presenter});

  @override
  State<_DraftRow> createState() => _DraftRowState();
}

class _DraftRowState extends State<_DraftRow> {
  final _amountController = TextEditingController();
  String _groupId = BudgetGroupDef.idVariableOptional;
  String? _selectedId;
  bool _busy = false;

  BudgetPresenter get presenter => widget.presenter;

  bool get _isSavings => presenter.isSavingsGroup(_groupId);

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _availableCategories {
    final budgeted = <String>{
      for (final list in presenter.categoriesByGroup.values)
        for (final c in list) c.id,
    };
    return presenter.expenseCategories
        .where((c) => !budgeted.contains(c.id))
        .toList();
  }

  List<FinancialAccount> get _availableSavingsTargets {
    final budgeted = <String>{
      for (final e in presenter.savingsBudgets) e.account.id,
    };
    return presenter.savingsTargets
        .where((a) => !budgeted.contains(a.id))
        .toList();
  }

  void _setSavingsMode(bool savings) {
    if (savings == _isSavings) return;
    setState(() {
      _selectedId = null;
      _groupId = savings
          ? BudgetGroupDef.idSavings
          : BudgetGroupDef.idVariableOptional;
    });
  }

  Future<void> _onPick(String value) async {
    if (value != _kCreateNewCategory) {
      setState(() => _selectedId = value);
      return;
    }
    await _createCategory();
  }

  Future<void> _createCategory() async {
    final cat = await showWebNewCategoryDialog(
      context,
      existing: presenter.allCategories,
      initialType: CategoryType.expense,
      // Only an expense category can carry a budget row.
      allowTypeChange: false,
    );
    if (cat == null || !mounted) return;
    await presenter.addCategory(cat);
    if (!mounted) return;
    setState(() => _selectedId = cat.id);
  }

  Future<void> _add() async {
    final id = _selectedId;
    final raw = _amountController.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final amount = double.tryParse(raw) ?? 0;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await presenter.setBudget(
        id,
        amount,
        group: _groupId,
        budgetType: BudgetType.variable,
      );
      if (!mounted) return;
      _amountController.clear();
      setState(() {
        _selectedId = null;
        // Stay in the mode the user is working in; only the expense group
        // resets to its default.
        if (!_isSavings) _groupId = BudgetGroupDef.idVariableOptional;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<WebDropdownEntry<String>> _entries(ThemeData theme) {
    if (_isSavings) {
      return [
        for (final a in _availableSavingsTargets)
          WebDropdownEntry(
            value: a.id,
            label: _savingsAccountLabel(a),
            dotColor: theme.colorScheme.tertiary,
          ),
      ];
    }
    final available = _availableCategories;
    return [
      const WebDropdownEntry(
        value: _kCreateNewCategory,
        label: '＋ New category…',
      ),
      for (var i = 0; i < available.length; i++)
        WebDropdownEntry(
          value: available[i].id,
          label: available[i].name,
          dotColor: resolveSliceColor(available[i].colorHex, i,
              brightness: theme.brightness),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = context.appColors;

    Widget cell(Widget child, double w) => SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kCellPadX),
            child: child,
          ),
        );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: cs.outline),
    );

    return Container(
      key: WebBudgetKeys.draftRow,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kCellPadX),
              child: Row(
                children: [
                  SizedBox(
                    width: 176,
                    child: WebSegmented<bool>(
                      key: WebKeys.budgetAddRowMode,
                      value: _isSavings,
                      onChanged: _setSavingsMode,
                      segments: const [
                        WebSegment(false, 'Expense'),
                        WebSegment(true, 'Savings'),
                      ],
                    ),
                  ),
                  const SizedBox(width: WebInsets.sm),
                  Expanded(
                    child: WebSearchableDropdown<String>(
                      key: WebKeys.budgetAddRowPicker,
                      value: _selectedId,
                      entries: _entries(theme),
                      hintText: _isSavings
                          ? 'Choose an account…'
                          : 'Choose a category…',
                      isDense: true,
                      onChanged: _onPick,
                    ),
                  ),
                  if (!_isSavings)
                    IconButton(
                      key: WebKeys.budgetAddRowNewCategory,
                      tooltip: 'New category…',
                      onPressed: _createCategory,
                      style: IconButton.styleFrom(
                        foregroundColor: cs.onSurfaceVariant,
                        minimumSize: const Size(kWebHitTarget, kWebHitTarget),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                    ),
                ],
              ),
            ),
          ),
          cell(
            _isSavings
                ? Row(
                    children: [
                      WebDot(color: a.treasury),
                      const SizedBox(width: WebInsets.sm),
                      Flexible(
                        child: Text(
                          presenter.budgetGroupLabel(BudgetGroupDef.idSavings),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  )
                : _GroupDropdown(
                    key: WebKeys.budgetAddRowGroup,
                    groupId: _groupId,
                    expenseGroups: presenter.expenseGroups,
                    groups: presenter.groups,
                    onChanged: (g) => setState(() => _groupId = g),
                  ),
            _kGroupW,
          ),
          cell(
            SizedBox(
              height: 34,
              child: TextField(
                key: WebKeys.budgetAddRowAmount,
                controller: _amountController,
                textAlign: TextAlign.right,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '0',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: a.textMuted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: WebInsets.sm,
                    vertical: WebInsets.sm,
                  ),
                  enabledBorder: inputBorder,
                  focusedBorder: inputBorder.copyWith(
                    borderSide: BorderSide(color: cs.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            _kAllocW,
          ),
          SizedBox(
            width: _kSpentW + _kRemainW + _kUsedW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kCellPadX),
              child: Text(
                'Press Enter to add',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: a.textMuted,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          cell(
            Align(
              alignment: Alignment.centerLeft,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      key: WebKeys.budgetAddRowAdd,
                      tooltip: _isSavings ? 'Add savings goal' : 'Add category',
                      onPressed: _add,
                      style: IconButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        minimumSize: const Size(kWebHitTarget, 36),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 16),
                    ),
            ),
            _kStatusW,
          ),
          const SizedBox(width: _kActionW),
        ],
      ),
    );
  }
}

/// Picker label for a savings/goal account — appends the goal target when
/// there is one, as the mobile add-budget sheet does.
String _savingsAccountLabel(FinancialAccount a) {
  if (a.category == AccountCategory.goal && a.goalTarget != null) {
    return '${a.name}  ·  goal ${formatPesoCompact(a.goalTarget!)}';
  }
  return a.name;
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return WebCard(
      key: WebBudgetKeys.emptyState,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WebInsets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: WebInsets.md),
            Text(
              'No budget set for this month',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
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
