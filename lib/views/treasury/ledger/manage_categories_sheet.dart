import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/category_icon_catalog.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_badge_widget.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class ManageCategoriesSheet extends StatefulWidget {
  final LedgerPresenter presenter;

  const ManageCategoriesSheet({super.key, required this.presenter});

  @override
  State<ManageCategoriesSheet> createState() => _ManageCategoriesSheetState();
}

class _ManageCategoriesSheetState extends State<ManageCategoriesSheet> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  CategoryType _type = CategoryType.expense;
  bool _isSubmitting = false;
  // Icon chosen for the category being added. Defaults to the "Auto" sentinel
  // (name-derived glyph) until the user explicitly picks one.
  String _iconKey = kAutoCategoryIconKey;

  String _nextColor() {
    final index =
        widget.presenter.categories.where((c) => c.type == _type).length;
    return categoryColorAt(index, isExpense: _type == CategoryType.expense);
  }

  @override
  void initState() {
    super.initState();
    // Rebuild so the add-form icon/monogram preview tracks the typed name live.
    _nameController.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addCategory() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final id =
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      await widget.presenter.addCategory(FinanceCategory(
        id: id,
        name: _nameController.text.trim(),
        type: _type,
        icon: _iconKey,
        colorHex: _nextColor(),
      ));
      _nameController.clear();
      _iconKey = kAutoCategoryIconKey; // reset for the next add
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickAddIcon() async {
    final picked = await showCategoryIconPicker(context, current: _iconKey);
    if (picked != null && mounted) setState(() => _iconKey = picked);
  }

  Future<void> _changeCategoryIcon(FinanceCategory category) async {
    final picked =
        await showCategoryIconPicker(context, current: category.icon);
    if (picked != null && picked != category.icon) {
      await widget.presenter.updateCategory(category.copyWith(icon: picked));
    }
  }

  Future<void> _toggleExclude(FinanceCategory category, bool value) =>
      widget.presenter
          .updateCategory(category.copyWith(excludeFromTotals: value));

  Future<void> _confirmDelete(
      BuildContext context, FinanceCategory category) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await AppConfirmDialog.confirm(
      context: context,
      title: 'Delete category?',
      body: '"${category.name}" will be removed. '
          'You can only delete categories with no transactions linked to them.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.presenter.deleteCategory(category.id);
    } on StateError catch (e) {
      if (!mounted) return;
      final message = e.message == 'has_transactions'
          ? 'This category has transactions linked to it. '
              'Delete or reassign those entries first.'
          : 'Could not delete category: ${e.message}';
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        final expense = widget.presenter.categories
            .where((c) => c.type == CategoryType.expense)
            .toList();
        final income = widget.presenter.categories
            .where((c) => c.type == CategoryType.income)
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TypeToggle(
                value: _type,
                onChanged: (t) => setState(() => _type = t),
              ),
              const SizedBox(height: 12),
              _AddCategoryForm(
                formKey: _formKey,
                controller: _nameController,
                isSubmitting: _isSubmitting,
                onSubmit: _addCategory,
                type: _type,
                iconKey: _iconKey,
                onPickIcon: _pickAddIcon,
                previewColorHex: _nextColor(),
              ),
              const SizedBox(height: 28),
              if (expense.isEmpty && income.isEmpty)
                const AppEmptyState(
                  icon: Icons.label_off_outlined,
                  title: 'No categories yet',
                  body:
                      'Add expense and income labels above\nto start tagging transactions.',
                )
              else ...[
                if (expense.isNotEmpty)
                  AppSection(
                    title: 'Expense',
                    trailing: _CountBadge(
                        count: expense.length,
                        color: Theme.of(context).colorScheme.error),
                    child: Column(
                      children: expense
                          .map((c) => _CategoryTile(
                                key: ValueKey(c.id),
                                category: c,
                                accentColor:
                                    Theme.of(context).colorScheme.error,
                                onDelete: () => _confirmDelete(context, c),
                                onToggleExclude: (v) => _toggleExclude(c, v),
                                onChangeIcon: () => _changeCategoryIcon(c),
                              ))
                          .toList(),
                    ),
                  ),
                if (expense.isNotEmpty && income.isNotEmpty)
                  const SizedBox(height: 20),
                if (income.isNotEmpty)
                  AppSection(
                    title: 'Income',
                    trailing: _CountBadge(
                        count: income.length,
                        color: Theme.of(context).colorScheme.tertiary),
                    child: Column(
                      children: income
                          .map((c) => _CategoryTile(
                                key: ValueKey(c.id),
                                category: c,
                                accentColor:
                                    Theme.of(context).colorScheme.tertiary,
                                onDelete: () => _confirmDelete(context, c),
                                onToggleExclude: (v) => _toggleExclude(c, v),
                                onChangeIcon: () => _changeCategoryIcon(c),
                              ))
                          .toList(),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Count Badge ──────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;

  const _CountBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─── Type Toggle ──────────────────────────────────────────────────────────────

class _TypeToggle extends StatelessWidget {
  final CategoryType value;
  final ValueChanged<CategoryType> onChanged;

  const _TypeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TypeOption(
            label: 'Expense',
            icon: Icons.arrow_upward_rounded,
            selected: value == CategoryType.expense,
            color: cs.error,
            onTap: () => onChanged(CategoryType.expense),
            isLeft: true,
          ),
          _TypeOption(
            label: 'Income',
            icon: Icons.arrow_downward_rounded,
            selected: value == CategoryType.income,
            color: cs.tertiary,
            onTap: () => onChanged(CategoryType.income),
            isLeft: false,
          ),
        ],
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final bool isLeft;

  const _TypeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        label: label,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.horizontal(
            left: isLeft ? const Radius.circular(12) : Radius.zero,
            right: !isLeft ? const Radius.circular(12) : Radius.zero,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: double.infinity,
            decoration: BoxDecoration(
              color:
                  selected ? color.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.horizontal(
                left: isLeft ? const Radius.circular(12) : Radius.zero,
                right: !isLeft ? const Radius.circular(12) : Radius.zero,
              ),
              border: selected
                  ? Border.all(color: color.withValues(alpha: 0.4))
                  : Border.all(color: Colors.transparent),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 14, color: selected ? color : cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? color : cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
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

// ─── Add Category Form ────────────────────────────────────────────────────────

class _AddCategoryForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final CategoryType type;
  final String iconKey;
  final VoidCallback onPickIcon;

  /// Hex of the color the new category will be assigned — used to tint the icon
  /// preview so it matches how the category will look in the ledger row.
  final String previewColorHex;

  const _AddCategoryForm({
    required this.formKey,
    required this.controller,
    required this.isSubmitting,
    required this.onSubmit,
    required this.type,
    required this.iconKey,
    required this.onPickIcon,
    required this.previewColorHex,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = type == CategoryType.expense ? cs.error : cs.tertiary;
    Color previewColor;
    try {
      previewColor = Color(
          int.parse('FF${previewColorHex.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      previewColor = color;
    }

    return Form(
      key: formKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tappable icon preview — opens the catalog picker.
          Semantics(
            button: true,
            label: 'Choose category icon',
            child: SizedBox(
              width: 52,
              height: 52,
              child: InkWell(
                onTap: onPickIcon,
                borderRadius: BorderRadius.circular(12),
                child: CategoryBadge(
                  iconKey: iconKey,
                  name: controller.text,
                  type: type,
                  color: previewColor,
                  size: 52,
                  iconSize: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SheetLabeledField(
              label: 'Category name',
              child: TextFormField(
                controller: controller,
                textCapitalization: TextCapitalization.words,
                decoration: sheetFieldDecoration(context),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                onFieldSubmitted: (_) => onSubmit(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            height: 52,
            child: Semantics(
              label: 'Add category',
              child: FilledButton(
                onPressed: isSubmitting ? null : onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: cs.onSurface,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: isSubmitting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.onPrimary),
                      )
                    : const Icon(Icons.add_rounded, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Category Tile ────────────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  final FinanceCategory category;
  final Color accentColor;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleExclude;
  final VoidCallback onChangeIcon;

  const _CategoryTile({
    super.key,
    required this.category,
    required this.accentColor,
    required this.onDelete,
    required this.onToggleExclude,
    required this.onChangeIcon,
  });

  /// The category's own color — matches how the ledger row tints the badge, so
  /// the icon looks identical here and in the feed. Falls back to the type
  /// accent if the stored hex can't be parsed.
  Color get _badgeColor {
    try {
      return Color(
          int.parse('FF${category.colorHex.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      return accentColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AppListTile(
        // 44×44 hit area (touch-target rule) around the 40px badge.
        leading: Semantics(
          button: true,
          label: 'Change icon for ${category.name}',
          child: SizedBox(
            width: 44,
            height: 44,
            child: InkWell(
              onTap: onChangeIcon,
              borderRadius: BorderRadius.circular(12),
              child: Center(
                child: CategoryBadge(
                  iconKey: category.icon,
                  name: category.name,
                  type: category.type,
                  color: _badgeColor,
                  size: 40,
                  iconSize: 18,
                ),
              ),
            ),
          ),
        ),
        title: Text(category.name),
        subtitle: category.excludeFromTotals
            ? Text(
                'Not counted in income/expense totals',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: 'Exclude ${category.name} from totals',
              toggled: category.excludeFromTotals,
              child: Switch.adaptive(
                value: category.excludeFromTotals,
                onChanged: onToggleExclude,
                activeThumbColor: accentColor,
              ),
            ),
            Semantics(
              label: 'Delete ${category.name}',
              child: SizedBox(
                width: 44,
                height: 44,
                child: InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(22),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
        onTap: () {},
      ),
    );
  }
}

// ─── Icon Picker ──────────────────────────────────────────────────────────────

/// Opens the category-icon catalog picker. Returns the chosen catalog key, the
/// [kAutoCategoryIconKey] sentinel ("Auto" — name-derived glyph), or null if the
/// user dismissed without choosing.
Future<String?> showCategoryIconPicker(
  BuildContext context, {
  required String current,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _CategoryIconPickerSheet(current: current),
  );
}

class _CategoryIconPickerSheet extends StatelessWidget {
  final String current;
  const _CategoryIconPickerSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Choose an icon',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            // "Auto" — routes through the name heuristic.
            _IconChoice(
              icon: Icons.auto_awesome_rounded,
              label: 'Auto',
              selected: current == kAutoCategoryIconKey ||
                  !kCategoryIconCatalog.containsKey(current),
              onTap: () => Navigator.of(context).pop(kAutoCategoryIconKey),
            ),
            for (final group in kCategoryIconGroups) ...[
              const SizedBox(height: 14),
              Text(
                group.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final key in group.keys)
                    _IconChoice(
                      icon: kCategoryIconCatalog[key]!,
                      selected: key == current,
                      onTap: () => Navigator.of(context).pop(key),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  final IconData icon;
  final String? label;
  final bool selected;
  final VoidCallback onTap;

  const _IconChoice({
    required this.icon,
    this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = Container(
      height: 52,
      width: label == null ? 52 : null,
      padding: label == null
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? cs.primary.withValues(alpha: 0.15)
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: selected ? cs.primary : cs.onSurface),
          if (label != null) ...[
            const SizedBox(width: 8),
            Text(
              label!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? cs.primary : cs.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }
}
