import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/category_icon_catalog.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../../web_keys.dart';
import '../../widgets/web_widgets.dart';

/// Next color after [hex] in the Nudgr palette of the category's type
/// (expense → [kExpensePalette], income → [kIncomePalette]); wraps, and
/// starts the palette over when [hex] is not in it. Replaces the Tailwind
/// `kCategoryPalette` the pre-v2 Setup page cycled through, so a swatch
/// clicked here lands on the same colors the charts use.
String nextCategoryColor(String hex, {required bool isExpense}) {
  final palette = isExpense ? kExpensePalette : kIncomePalette;
  final i = palette.indexWhere((p) => p.toLowerCase() == hex.toLowerCase());
  return palette[(i + 1) % palette.length];
}

/// The categories the table lists — expense first, then income. The ledger's
/// reserved transfer category is system-owned and never shown in a picker,
/// so it is not a row here either.
List<FinanceCategory> webListedCategories(LedgerPresenter ledger) => [
      ...ledger.categories.where((c) => c.type == CategoryType.expense),
      ...ledger.categories.where((c) => c.type == CategoryType.income),
    ];

/// The Categories tab of Setup v2: the labels used to tag ledger entries and
/// drive the budget. Inline rename, icon picker, Expense/Income switch, a
/// color swatch that cycles the palette, the exclude-from-totals switch and
/// delete, plus the add row pinned to the bottom. CRUD is all on
/// [LedgerPresenter] — the same calls the pre-v2 page made.
class WebCategoriesTableV2 extends StatefulWidget {
  final LedgerPresenter ledger;

  const WebCategoriesTableV2({super.key, required this.ledger});

  @override
  State<WebCategoriesTableV2> createState() => _WebCategoriesTableV2State();
}

class _WebCategoriesTableV2State extends State<WebCategoriesTableV2> {
  final _nameController = TextEditingController();
  CategoryType _type = CategoryType.expense;
  String _draftColor = kExpensePalette.first;
  // "Auto" — the name-derived glyph; the user can override it before adding.
  String _draftIcon = kAutoCategoryIconKey;
  bool _submitting = false;

  bool get _draftIsExpense => _type == CategoryType.expense;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final id =
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      await widget.ledger.addCategory(FinanceCategory(
        id: id,
        name: name,
        type: _type,
        icon: _draftIcon,
        colorHex: _draftColor,
      ));
      _nameController.clear();
      setState(() {
        // Advance the draft swatch so consecutive adds get distinct colors;
        // reset the icon to Auto for the next add, as the mobile sheet does.
        _draftColor =
            nextCategoryColor(_draftColor, isExpense: _draftIsExpense);
        _draftIcon = kAutoCategoryIconKey;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmDelete(FinanceCategory category) async {
    final confirmed = await showWebConfirm(
      context,
      title: 'Delete ${category.name}?',
      message: 'The category is removed from the picker and the budget. '
          'Only a category with no transactions linked to it can be deleted.',
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.ledger.deleteCategory(category.id);
    } on StateError catch (e) {
      if (!mounted) return;
      AppToast.error(
        context,
        e.message == 'has_transactions'
            ? 'This category has transactions linked to it. '
                'Delete or reassign those entries first.'
            : 'Could not delete category: ${e.message}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ledger,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final listed = webListedCategories(widget.ledger);
        final expense =
            listed.where((c) => c.type == CategoryType.expense).length;
        final income = listed.length - expense;

        final rows = <Widget>[const _CategoryTableHeader()];
        for (var i = 0; i < listed.length; i++) {
          final c = listed[i];
          rows.add(_CategoryTableRow(
            key: ValueKey(c.id),
            ledger: widget.ledger,
            category: c,
            // Palette position within the category's own type, so the
            // fallback color for a near-white hex matches the charts.
            paletteIndex: i < expense ? i : i - expense,
            onDelete: () => _confirmDelete(c),
          ));
        }
        rows.add(_buildAddRow(context));

        return WebCard(
          key: WebKeys.setupCategoriesTable,
          title: 'Categories',
          description:
              'Labels for tagging transactions and budgeting · $expense expense · $income income',
          padding: const EdgeInsets.fromLTRB(
              WebInsets.xl, WebInsets.lg, WebInsets.xl, WebInsets.sm),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Scroll sideways on a narrow viewport instead of overflowing
              // the fixed TYPE / COLOR / EXCLUDE / actions columns.
              final tableWidth = max(480.0, constraints.maxWidth);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        rows[i],
                        if (i < rows.length - 1)
                          Divider(height: 1, color: cs.outlineVariant),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// The "Add a category…" row pinned to the bottom of the table: color dot,
  /// icon preview (opens the picker), name field, type, draft swatch, ✓.
  Widget _buildAddRow(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: WebKeys.setupCategoryAddRow,
      color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(vertical: WebInsets.xs),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const SizedBox(width: WebInsets.sm),
                _ColorDot(hex: _draftColor, index: 0),
                const SizedBox(width: WebInsets.sm),
                WebCategoryIconPreview(
                  iconKey: _draftIcon,
                  name: _nameController.text,
                  type: _type,
                  size: 32,
                  onTap: () async {
                    final picked = await showWebCategoryIconPicker(context,
                        current: _draftIcon);
                    if (picked != null && mounted) {
                      setState(() => _draftIcon = picked);
                    }
                  },
                ),
                const SizedBox(width: WebInsets.sm),
                Expanded(
                  child: TextField(
                    key: WebKeys.setupCategoryName,
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => _add(),
                    // Keeps the auto-glyph preview tracking the typed name.
                    onChanged: (_) => setState(() {}),
                    style: theme.textTheme.bodyMedium,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Add a category…',
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _CatCols.type,
            child: _CategoryTypeDropdown(
              key: WebKeys.setupCategoryType,
              value: _type,
              onChanged: (t) => setState(() {
                _type = t;
                // A fresh draft follows its type's palette.
                _draftColor = t == CategoryType.expense
                    ? kExpensePalette.first
                    : kIncomePalette.first;
              }),
            ),
          ),
          SizedBox(
            width: _CatCols.color,
            child: Center(
              child: _ColorSwatch(
                key: WebKeys.setupCategoryColor,
                hex: _draftColor,
                index: 0,
                onTap: () => setState(() => _draftColor =
                    nextCategoryColor(_draftColor, isExpense: _draftIsExpense)),
              ),
            ),
          ),
          // New categories count toward totals by default — the exclude
          // switch lives on the saved rows. Reserve the column to stay aligned.
          const SizedBox(width: _CatCols.exclude),
          SizedBox(
            width: _CatCols.actions,
            child: Center(
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      key: WebKeys.setupCategoryAdd,
                      tooltip: 'Add category',
                      onPressed: _add,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      style: _iconButtonStyle(cs, color: cs.primary),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 44 px icon button in the row's muted tone.
ButtonStyle _iconButtonStyle(ColorScheme cs, {Color? color}) =>
    IconButton.styleFrom(
      foregroundColor: color ?? cs.onSurfaceVariant,
      hoverColor: cs.surfaceContainerHigh,
      minimumSize: const Size(kWebHitTarget, kWebHitTarget),
      maximumSize: const Size(kWebHitTarget, kWebHitTarget),
      padding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.smBorder),
    );

/// Column widths for the categories table (Category flexes; the rest fixed).
class _CatCols {
  static const double type = 130;
  static const double color = 70;
  static const double exclude = 90;
  static const double actions = 56;
}

/// Uppercase column header row for the categories table.
class _CategoryTableHeader extends StatelessWidget {
  const _CategoryTableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget h(String label, {TextAlign align = TextAlign.left}) => Text(
          label,
          textAlign: align,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          WebInsets.sm, WebInsets.xs, 0, WebInsets.sm),
      child: Row(
        children: [
          Expanded(child: h('CATEGORY')),
          SizedBox(width: _CatCols.type, child: h('TYPE')),
          SizedBox(
              width: _CatCols.color,
              child: h('COLOR', align: TextAlign.center)),
          SizedBox(
              width: _CatCols.exclude,
              child: h('EXCLUDE', align: TextAlign.center)),
          const SizedBox(width: _CatCols.actions),
        ],
      ),
    );
  }
}

/// One editable category row: color dot + icon + inline-rename name field ·
/// type · color swatch (cycles the palette) · exclude switch · delete. Each
/// edit persists through [LedgerPresenter.updateCategory].
class _CategoryTableRow extends StatefulWidget {
  final LedgerPresenter ledger;
  final FinanceCategory category;
  final int paletteIndex;
  final VoidCallback onDelete;

  const _CategoryTableRow({
    super.key,
    required this.ledger,
    required this.category,
    required this.paletteIndex,
    required this.onDelete,
  });

  @override
  State<_CategoryTableRow> createState() => _CategoryTableRowState();
}

class _CategoryTableRowState extends State<_CategoryTableRow> {
  late final TextEditingController _ctl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.category.name);
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _CategoryTableRow old) {
    super.didUpdateWidget(old);
    // Reflect external renames (e.g. sync) when this row isn't being edited.
    if (!_focus.hasFocus && widget.category.name != _ctl.text) {
      _ctl.text = widget.category.name;
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final name = _ctl.text.trim();
    if (name.isEmpty) {
      _ctl.text = widget.category.name; // revert empties
      return;
    }
    if (name == widget.category.name) return;
    widget.ledger.updateCategory(widget.category.copyWith(name: name));
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cat = widget.category;
    final isExpense = cat.type == CategoryType.expense;

    return Container(
      constraints: const BoxConstraints(minHeight: kWebHitTarget),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const SizedBox(width: WebInsets.sm),
                _ColorDot(hex: cat.colorHex, index: widget.paletteIndex),
                const SizedBox(width: WebInsets.sm),
                WebCategoryIconPreview(
                  key: WebKeys.setupCategoryIcon,
                  iconKey: cat.icon,
                  name: cat.name,
                  type: cat.type,
                  size: 32,
                  onTap: () async {
                    final picked = await showWebCategoryIconPicker(context,
                        current: cat.icon);
                    if (picked != null && picked != cat.icon && mounted) {
                      await widget.ledger
                          .updateCategory(cat.copyWith(icon: picked));
                    }
                  },
                ),
                const SizedBox(width: WebInsets.sm),
                Expanded(
                  child: TextField(
                    key: WebKeys.setupCategoryName,
                    controller: _ctl,
                    focusNode: _focus,
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) {
                      _commit();
                      _focus.unfocus();
                    },
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _CatCols.type,
            child: _CategoryTypeDropdown(
              key: WebKeys.setupCategoryType,
              value: cat.type,
              onChanged: (t) =>
                  widget.ledger.updateCategory(cat.copyWith(type: t)),
            ),
          ),
          SizedBox(
            width: _CatCols.color,
            child: Center(
              child: _ColorSwatch(
                key: WebKeys.setupCategoryColor,
                hex: cat.colorHex,
                index: widget.paletteIndex,
                onTap: () => widget.ledger.updateCategory(cat.copyWith(
                    colorHex:
                        nextCategoryColor(cat.colorHex, isExpense: isExpense))),
              ),
            ),
          ),
          SizedBox(
            width: _CatCols.exclude,
            child: Center(
              child: Tooltip(
                message: 'Exclude from income/expense totals',
                child: Switch(
                  key: WebKeys.setupCategoryExclude,
                  value: cat.excludeFromTotals,
                  onChanged: (v) => widget.ledger
                      .updateCategory(cat.copyWith(excludeFromTotals: v)),
                ),
              ),
            ),
          ),
          SizedBox(
            width: _CatCols.actions,
            child: Center(
              child: IconButton(
                key: WebKeys.setupCategoryDelete,
                tooltip: 'Delete category',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                style: _iconButtonStyle(cs),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline Expense/Income dropdown used in both the category rows and add row.
class _CategoryTypeDropdown extends StatelessWidget {
  final CategoryType value;
  final ValueChanged<CategoryType> onChanged;

  const _CategoryTypeDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DropdownButtonHideUnderline(
      child: DropdownButton<CategoryType>(
        value: value,
        isDense: true,
        isExpanded: true,
        borderRadius: AppRadii.smBorder,
        icon: Icon(Icons.unfold_more, size: 14, color: cs.onSurfaceVariant),
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        dropdownColor: cs.surfaceContainerHigh,
        items: const [
          DropdownMenuItem(value: CategoryType.expense, child: Text('Expense')),
          DropdownMenuItem(value: CategoryType.income, child: Text('Income')),
        ],
        onChanged: (t) {
          if (t != null && t != value) onChanged(t);
        },
      ),
    );
  }
}

/// Small color dot before a category name, in the resolved chart color.
class _ColorDot extends StatelessWidget {
  final String hex;
  final int index;

  const _ColorDot({required this.hex, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: resolveSliceColor(hex, index,
            brightness: Theme.of(context).brightness),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Clickable color swatch (24 px in a 44 px hit area) — cycles the palette.
class _ColorSwatch extends StatelessWidget {
  final String hex;
  final int index;
  final VoidCallback onTap;

  const _ColorSwatch({
    super.key,
    required this.hex,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: 'Click to change color',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.smBorder,
        child: SizedBox(
          width: kWebHitTarget,
          height: kWebHitTarget,
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color:
                    resolveSliceColor(hex, index, brightness: theme.brightness),
                borderRadius: AppRadii.smBorder,
                border:
                    Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
