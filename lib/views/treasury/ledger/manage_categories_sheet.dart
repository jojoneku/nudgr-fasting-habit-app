import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
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

  String _nextColor() {
    final index =
        widget.presenter.categories.where((c) => c.type == _type).length;
    return categoryColorAt(index, isExpense: _type == CategoryType.expense);
  }

  @override
  void dispose() {
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
        icon: 'tag',
        colorHex: _nextColor(),
      ));
      _nameController.clear();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, FinanceCategory category) async {
    final confirmed = await AppConfirmDialog.confirm(
      context: context,
      title: 'Delete category?',
      body:
          '"${category.name}" will be removed. Existing transactions will keep the ID but won\'t display a label.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );
    if (confirmed) {
      widget.presenter.deleteCategory(category.id);
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
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
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
              color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
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
                    size: 14,
                    color: selected ? color : cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? color : cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.normal,
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

  const _AddCategoryForm({
    required this.formKey,
    required this.controller,
    required this.isSubmitting,
    required this.onSubmit,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = type == CategoryType.expense ? cs.error : cs.tertiary;

    return Form(
      key: formKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Category name',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              onFieldSubmitted: (_) => onSubmit(),
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

  const _CategoryTile({
    super.key,
    required this.category,
    required this.accentColor,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AppListTile(
        leading: AppIconBadge(
          icon: Icons.label_outline_rounded,
          color: accentColor,
          size: 40,
          iconSize: 18,
        ),
        title: Text(category.name),
        trailing: Semantics(
          label: 'Delete ${category.name}',
          child: SizedBox(
            width: 44,
            height: 44,
            child: InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(22),
              child: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                size: 18,
              ),
            ),
          ),
        ),
        onTap: () {},
      ),
    );
  }
}
