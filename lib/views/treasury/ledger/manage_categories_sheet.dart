import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';

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
    final index = widget.presenter.categories
        .where((c) => c.type == _type)
        .length;
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListenableBuilder(
        listenable: widget.presenter,
        builder: (context, _) {
          final expense = widget.presenter.categories
              .where((c) => c.type == CategoryType.expense)
              .toList();
          final income = widget.presenter.categories
              .where((c) => c.type == CategoryType.income)
              .toList();

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DragHandle(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SheetHeader(
                          onClose: () => Navigator.pop(context)),
                      const SizedBox(height: 20),
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
                        _EmptyState()
                      else ...[
                        if (expense.isNotEmpty) ...[
                          _SectionHeader(
                            label: 'EXPENSE',
                            count: expense.length,
                            color: AppColors.danger,
                            icon: Icons.arrow_upward_rounded,
                          ),
                          const SizedBox(height: 8),
                          ...expense.map((c) => _CategoryTile(
                                key: ValueKey(c.id),
                                category: c,
                                accentColor: AppColors.danger,
                                onDelete: () => _confirmDelete(context, c),
                              )),
                        ],
                        if (expense.isNotEmpty && income.isNotEmpty)
                          const SizedBox(height: 20),
                        if (income.isNotEmpty) ...[
                          _SectionHeader(
                            label: 'INCOME',
                            count: income.length,
                            color: AppColors.success,
                            icon: Icons.arrow_downward_rounded,
                          ),
                          const SizedBox(height: 8),
                          ...income.map((c) => _CategoryTile(
                                key: ValueKey(c.id),
                                category: c,
                                accentColor: AppColors.success,
                                onDelete: () => _confirmDelete(context, c),
                              )),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, FinanceCategory category) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete category?',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '"${category.name}" will be removed. Existing transactions will keep the ID but won\'t display a label.',
          style:
              TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.presenter.deleteCategory(category.id);
            },
            child:
                Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

// ─── Drag Handle ─────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.textSecondary.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

// ─── Sheet Header ─────────────────────────────────────────────────────────────

class _SheetHeader extends StatelessWidget {
  final VoidCallback onClose;

  const _SheetHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CATEGORIES',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Manage Labels',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Semantics(
          label: 'Close',
          child: SizedBox(
            width: 44,
            height: 44,
            child: InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(22),
              child: Icon(Icons.close_rounded,
                  color: AppColors.textSecondary, size: 20),
            ),
          ),
        ),
      ],
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
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textSecondary.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TypeOption(
            label: 'Expense',
            icon: Icons.arrow_upward_rounded,
            selected: value == CategoryType.expense,
            color: AppColors.danger,
            onTap: () => onChanged(CategoryType.expense),
            isLeft: true,
          ),
          _TypeOption(
            label: 'Income',
            icon: Icons.arrow_downward_rounded,
            selected: value == CategoryType.income,
            color: AppColors.success,
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
              color: selected ? color.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.horizontal(
                left: isLeft ? const Radius.circular(12) : Radius.zero,
                right: !isLeft ? const Radius.circular(12) : Radius.zero,
              ),
              border: selected
                  ? Border.all(color: color.withOpacity(0.4))
                  : Border.all(color: Colors.transparent),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 14,
                    color: selected ? color : AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? color : AppColors.textSecondary,
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
    final color =
        type == CategoryType.expense ? AppColors.danger : AppColors.success;

    return Form(
      key: formKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Category name',
                labelStyle: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: AppColors.textSecondary.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: color),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.danger),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.danger),
                ),
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
              child: ElevatedButton(
                onPressed: isSubmitting ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: AppColors.background,
                  disabledBackgroundColor: color.withOpacity(0.3),
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
                            strokeWidth: 2,
                            color: AppColors.background),
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

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
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
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {},
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.textSecondary.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                // Left accent bar
                Container(
                  width: 3,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Icon(Icons.label_outline_rounded,
                    color: accentColor.withOpacity(0.7), size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category.name,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
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
                      child: Icon(Icons.delete_outline_rounded,
                          color: AppColors.textSecondary.withOpacity(0.5),
                          size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.label_off_outlined,
              color: AppColors.textSecondary.withOpacity(0.3), size: 40),
          const SizedBox(height: 12),
          Text(
            'No categories yet',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add expense and income labels above\nto start tagging transactions.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary.withOpacity(0.6),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
