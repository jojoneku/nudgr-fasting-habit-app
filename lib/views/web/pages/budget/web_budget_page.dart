import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/budget/add_budget_sheet.dart';

import '../../widgets/web_widgets.dart';
import 'budget_allocation_chart.dart';

/// Web Budget page (Plan 050-D).
///
/// Desktop allocation overview: a KPI strip, an allocated-vs-spent bar chart by
/// [BudgetGroup], and a per-category data table with inline progress + an
/// over-budget badge. Add/edit reuse the mobile [AddBudgetSheet] as a dialog.
class WebBudgetPage extends StatefulWidget {
  final BudgetPresenter presenter;

  const WebBudgetPage({super.key, required this.presenter});

  @override
  State<WebBudgetPage> createState() => _WebBudgetPageState();
}

class _WebBudgetPageState extends State<WebBudgetPage> {
  @override
  void initState() {
    super.initState();
    widget.presenter.load();
  }

  Future<void> _openSheet([String? targetId]) async {
    final isEdit =
        targetId != null && widget.presenter.budgetFor(targetId) != null;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Budget' : 'Set Budget'),
        content: SizedBox(
          width: 460,
          child: AddBudgetSheet(
            presenter: widget.presenter,
            preselectedCategoryId: targetId,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        final p = widget.presenter;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(WebInsets.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebSectionHeader(
                title: 'Budget',
                subtitle:
                    'Allocations vs. actual spend — ${monthLabel(p.selectedMonth)}.',
                trailing: _HeaderActions(
                  presenter: p,
                  onAdd: () => _openSheet(),
                ),
              ),
              _StatStrip(presenter: p),
              const SizedBox(height: WebInsets.xl),
              WebCard(
                title: 'Allocation by group',
                description: 'Allocated vs. spent across your budget sections.',
                child: BudgetAllocationChart(bars: p.groupBars),
              ),
              const SizedBox(height: WebInsets.xl),
              WebCard(
                title: 'Categories',
                description: 'Click a row to edit or remove its budget.',
                child: WebDataTable<WebBudgetRow>(
                  rows: p.budgetRows,
                  onRowTap: (row) => _openSheet(row.targetId),
                  emptyLabel: 'No budgets set for this month.',
                  columns: [
                    WebColumn<WebBudgetRow>(
                      label: 'Category',
                      flex: 3,
                      cell: (context, row) => _CategoryCell(row: row),
                    ),
                    WebColumn<WebBudgetRow>(
                      label: 'Allocated',
                      numeric: true,
                      flex: 2,
                      cell: (context, row) => Text(formatPeso(row.allocated)),
                    ),
                    WebColumn<WebBudgetRow>(
                      label: 'Spent',
                      numeric: true,
                      flex: 2,
                      cell: (context, row) => Text(formatPeso(row.spent)),
                    ),
                    WebColumn<WebBudgetRow>(
                      label: 'Remaining',
                      numeric: true,
                      flex: 2,
                      cell: (context, row) => _RemainingCell(row: row),
                    ),
                    WebColumn<WebBudgetRow>(
                      label: 'Progress',
                      flex: 3,
                      cell: (context, row) => _ProgressCell(row: row),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Header actions (month nav + add) ──────────────────────────────────────────

class _HeaderActions extends StatelessWidget {
  final BudgetPresenter presenter;
  final VoidCallback onAdd;

  const _HeaderActions({required this.presenter, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
          onPressed: () =>
              presenter.setMonth(previousMonth(presenter.selectedMonth)),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
          onPressed: () =>
              presenter.setMonth(nextMonth(presenter.selectedMonth)),
        ),
        const SizedBox(width: WebInsets.sm),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Set Budget'),
        ),
      ],
    );
  }
}

// ─── KPI strip ──────────────────────────────────────────────────────────────────

class _StatStrip extends StatelessWidget {
  final BudgetPresenter presenter;

  const _StatStrip({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final remaining = presenter.totalRemaining;
    final isOver = remaining < 0;
    final pctUsed = (presenter.percentUsed * 100).round();

    final tiles = <Widget>[
      WebStatTile(
        label: 'Total Allocated',
        value: formatPeso(presenter.totalAllocated),
        icon: Icons.account_balance_wallet_outlined,
      ),
      WebStatTile(
        label: 'Total Spent',
        value: formatPeso(presenter.totalSpent),
        icon: Icons.payments_outlined,
      ),
      WebStatTile(
        label: isOver ? 'Over Budget' : 'Remaining',
        value: formatPeso(remaining.abs()),
        valueColor: isOver ? cs.error : cs.tertiary,
        icon: Icons.savings_outlined,
      ),
      WebStatTile(
        label: '% Used',
        value: '$pctUsed%',
        valueColor: isOver ? cs.error : null,
        icon: Icons.donut_small_outlined,
      ),
    ];

    return WebStatGrid(tiles: tiles);
  }
}

// ─── Table cells ────────────────────────────────────────────────────────────────

class _CategoryCell extends StatelessWidget {
  final WebBudgetRow row;

  const _CategoryCell({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Flexible(
          child: Text(
            row.name,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (row.isOver) ...[
          const SizedBox(width: WebInsets.sm),
          const WebBadge('Over', tone: WebBadgeTone.danger),
        ] else if (row.group == BudgetGroup.savings) ...[
          const SizedBox(width: WebInsets.sm),
          Text(
            'savings',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _RemainingCell extends StatelessWidget {
  final WebBudgetRow row;

  const _RemainingCell({required this.row});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = row.remaining < 0 ? cs.error : cs.tertiary;
    return Text(
      formatPeso(row.remaining),
      style: DefaultTextStyle.of(context).style.copyWith(color: color),
    );
  }
}

class _ProgressCell extends StatelessWidget {
  final WebBudgetRow row;

  const _ProgressCell({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = row.isOver ? cs.error : cs.primary;
    final pct = row.allocated > 0
        ? '${(row.spent / row.allocated * 100).round()}%'
        : '—';
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: row.progress,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: WebInsets.sm),
        SizedBox(
          width: 40,
          child: Text(
            pct,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              color: row.isOver ? cs.error : cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
