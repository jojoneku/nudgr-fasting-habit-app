import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';

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

/// Display labels + group → BudgetGroup mapping used by the row dropdown.
const Map<BudgetGroup, String> _kGroupLabel = {
  BudgetGroup.nonNegotiables: 'Non-Negotiable',
  BudgetGroup.livingExpense: 'Living',
  BudgetGroup.variableOptional: 'Variable',
  BudgetGroup.savings: 'Savings',
};

/// Groups offered in the inline dropdown. Savings is excluded because savings
/// rows are keyed by *account* id (not a category id) — reassigning an expense
/// row into Savings would point at a non-existent account. Savings rows render
/// their group as a non-editable label.
const List<BudgetGroup> _kExpenseGroups = [
  BudgetGroup.nonNegotiables,
  BudgetGroup.livingExpense,
  BudgetGroup.variableOptional,
];

/// One flattened table row. [accountBacked] rows are savings/goal budgets whose
/// group cannot be changed inline (see [_kExpenseGroups]).
class _Row {
  final String id; // categoryId or accountId
  final String name;
  final BudgetGroup group;
  final double allocated;
  final double spent;
  final Color color;
  final bool accountBacked;

  const _Row({
    required this.id,
    required this.name,
    required this.group,
    required this.allocated,
    required this.spent,
    required this.color,
    required this.accountBacked,
  });

  double get used => allocated > 0 ? spent / allocated : 0;
  double get remaining => allocated - spent;
}

({WebBadgeTone tone, String label}) _statusFor(double used) {
  if (used >= 1) return (tone: WebBadgeTone.danger, label: 'Over');
  if (used >= 0.75) return (tone: WebBadgeTone.warning, label: 'Watch');
  return (tone: WebBadgeTone.success, label: 'On track');
}

Color _statusColor(BuildContext context, double used) {
  final cs = Theme.of(context).colorScheme;
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
    for (final group in _kExpenseGroups) {
      for (final cat in byGroup[group] ?? const <FinanceCategory>[]) {
        rows.add(_Row(
          id: cat.id,
          name: cat.name,
          group: group,
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
        group: BudgetGroup.savings,
        allocated: entry.budget.allocatedAmount,
        spent: presenter.contributedTo(entry.account.id),
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
    final groupCount = {for (final r in rows) r.group}.length;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: double.infinity),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebSectionHeader(
            title: 'Budget',
            subtitle:
                '${monthLabel(presenter.selectedMonth)} · set your allocations · '
                '${usedPct.toStringAsFixed(1)}% of ${formatPeso(allocated)} used',
            trailing: WebMonthStepper(
              label: monthLabel(presenter.selectedMonth),
              onPrev: () =>
                  presenter.setMonth(previousMonth(presenter.selectedMonth)),
              onNext: () =>
                  presenter.setMonth(nextMonth(presenter.selectedMonth)),
            ),
          ),
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
          _SetupCard(
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
    // Preserve the existing budget's group/type when editing the allocation.
    final existing = presenter.budgetFor(row.id);
    await presenter.setBudget(
      row.id,
      amount,
      group: existing?.group ?? row.group,
      budgetType: existing?.budgetType ?? BudgetType.variable,
    );
  }

  Future<void> _changeGroup(BudgetGroup group) async {
    final existing = presenter.budgetFor(row.id);
    await presenter.setBudget(
      row.id,
      existing?.allocatedAmount ?? row.allocated,
      group: group,
      budgetType: existing?.budgetType ?? BudgetType.variable,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = _statusFor(row.used);
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
                  child: Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          // Group dropdown (expense rows) or static label (savings rows)
          SizedBox(
            width: _kGroupW,
            child: row.accountBacked
                ? _GroupLabel(group: row.group, color: row.color)
                : _GroupDropdown(
                    group: row.group,
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
                      color: _statusColor(context, row.used),
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
        ],
      ),
    );
  }
}

/// Static group chip for savings rows (group cannot be reassigned inline).
class _GroupLabel extends StatelessWidget {
  final BudgetGroup group;
  final Color color;

  const _GroupLabel({required this.group, required this.color});

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
              _kGroupLabel[group] ?? 'Savings',
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
  final BudgetGroup group;
  final ValueChanged<BudgetGroup> onChanged;

  const _GroupDropdown({required this.group, required this.onChanged});

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
        child: DropdownButton<BudgetGroup>(
          value: group,
          isDense: true,
          isExpanded: true,
          borderRadius: AppRadii.smBorder,
          icon: Icon(Icons.expand_more, size: 16, color: cs.onSurfaceVariant),
          style: theme.textTheme.bodyMedium,
          dropdownColor: cs.surfaceContainerHigh,
          items: [
            for (final g in _kExpenseGroups)
              DropdownMenuItem(
                value: g,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _groupColor(context, g),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: WebInsets.sm),
                    Text(_kGroupLabel[g] ?? g.name),
                  ],
                ),
              ),
          ],
          selectedItemBuilder: (context) => [
            for (final g in _kExpenseGroups)
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _groupColor(context, g),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: WebInsets.sm),
                  Text(_kGroupLabel[g] ?? g.name),
                ],
              ),
          ],
          onChanged: (g) {
            if (g != null && g != group) onChanged(g);
          },
        ),
      ),
    );
  }
}

/// Distinct theme-derived accent per group for the dot + donut.
Color _groupColor(BuildContext context, BudgetGroup group) {
  final cs = Theme.of(context).colorScheme;
  return switch (group) {
    BudgetGroup.nonNegotiables => cs.primary,
    BudgetGroup.livingExpense => cs.secondary,
    BudgetGroup.variableOptional => cs.tertiary,
    BudgetGroup.savings => cs.tertiary,
  };
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

/// Final "Add a category…" row. Captures a name, group + allocation, then
/// creates the category and sets its budget via the presenter.
class _AddRow extends StatefulWidget {
  final BudgetPresenter presenter;
  const _AddRow({required this.presenter});

  @override
  State<_AddRow> createState() => _AddRowState();
}

class _AddRowState extends State<_AddRow> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  BudgetGroup _group = BudgetGroup.variableOptional;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    final raw = _amountController.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final amount = double.tryParse(raw) ?? 0;
    // Require a name — otherwise a stray amount would create a junk
    // "New Category" that leaks into the ledger app-wide.
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final existing = widget.presenter.expenseCategories;
      final category = FinanceCategory(
        id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
        name: name,
        type: CategoryType.expense,
        icon: 'tag',
        colorHex: categoryColorAt(existing.length, isExpense: true),
      );
      // addCategory delegates to the ledger so other presenters pick it up.
      await widget.presenter.addCategory(category);
      await widget.presenter.setBudget(
        category.id,
        amount,
        group: _group,
        budgetType: BudgetType.variable,
      );
      // Guard the controller writes after the await — the row may have been
      // removed mid-save, in which case the controllers are disposed. (C11)
      if (!mounted) return;
      _nameController.clear();
      _amountController.clear();
      setState(() => _group = BudgetGroup.variableOptional);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
          Expanded(
            child: TextField(
              controller: _nameController,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              onSubmitted: (_) => _add(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Add a category…',
                hintStyle: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          SizedBox(
            width: _kGroupW,
            child: _GroupDropdown(
              group: _group,
              onChanged: (g) => setState(() => _group = g),
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
                      tooltip: 'Add category',
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

    // Aggregate rows by group, preserving the canonical group order.
    final order = [..._kExpenseGroups, BudgetGroup.savings];
    final groups = <({BudgetGroup group, double alloc, double spent})>[];
    for (final g in order) {
      final inGroup = rows.where((r) => r.group == g).toList();
      if (inGroup.isEmpty) continue;
      groups.add((
        group: g,
        alloc: inGroup.fold<double>(0, (s, r) => s + r.allocated),
        spent: inGroup.fold<double>(0, (s, r) => s + r.spent),
      ));
    }

    final slices = [
      for (final g in groups)
        WebChartSlice(
          label: _kGroupLabel[g.group] ?? g.group.name,
          value: g.alloc,
          color: _groupColor(context, g.group),
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
  final List<({BudgetGroup group, double alloc, double spent})> groups;
  final double totalAllocated;
  final bool twoCol;

  const _GroupLegendGrid({
    required this.groups,
    required this.totalAllocated,
    required this.twoCol,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final g in groups)
        _GroupLegendItem(
          color: _groupColor(context, g.group),
          name: _kGroupLabel[g.group] ?? g.group.name,
          alloc: g.alloc,
          spent: g.spent,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = WebInsets.xxl;
        final colWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: WebInsets.lg,
          children: [
            for (final item in items) SizedBox(width: colWidth, child: item),
          ],
        );
      },
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
