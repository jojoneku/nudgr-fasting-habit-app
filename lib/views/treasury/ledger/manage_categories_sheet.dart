import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';

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

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addCategory() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final id = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      await widget.presenter.addCategory(FinanceCategory(
        id: id,
        name: _nameController.text.trim(),
        type: _type,
        icon: 'tag',
        colorHex: '#FFFFFF',
      ));
      _nameController.clear();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteCategory(String id) async {
    await widget.presenter.deleteCategory(id);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListenableBuilder(
        listenable: widget.presenter,
        builder: (context, _) {
          final expense = widget.presenter.categories
              .where((c) => c.type == CategoryType.expense)
              .toList();
          final income = widget.presenter.categories
              .where((c) => c.type == CategoryType.income)
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Categories',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Add form
                Form(
                  key: _formKey,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _nameController,
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Category name',
                            labelStyle: TextStyle(color: AppColors.textSecondary),
                            filled: true,
                            fillColor: AppColors.background,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: AppColors.textSecondary.withOpacity(0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: AppColors.accent),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _TypeToggle(
                        value: _type,
                        onChanged: (t) => setState(() => _type = t),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _addCategory,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.background,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: _isSubmitting
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppColors.background),
                                )
                              : const Icon(Icons.add, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                if (expense.isNotEmpty) ...[
                  _SectionLabel(label: 'EXPENSE', color: AppColors.danger),
                  const SizedBox(height: 8),
                  ...expense.map((c) => _CategoryRow(
                        category: c,
                        onDelete: () => _deleteCategory(c.id),
                      )),
                  const SizedBox(height: 16),
                ],

                if (income.isNotEmpty) ...[
                  _SectionLabel(label: 'INCOME', color: AppColors.success),
                  const SizedBox(height: 8),
                  ...income.map((c) => _CategoryRow(
                        category: c,
                        onDelete: () => _deleteCategory(c.id),
                      )),
                ],

                if (expense.isEmpty && income.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No categories yet — add one above.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  ),

                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TypeToggle extends StatelessWidget {
  final CategoryType value;
  final ValueChanged<CategoryType> onChanged;

  const _TypeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SmallTypeButton(
          label: 'Exp',
          selected: value == CategoryType.expense,
          color: AppColors.danger,
          onTap: () => onChanged(CategoryType.expense),
        ),
        const SizedBox(height: 4),
        _SmallTypeButton(
          label: 'Inc',
          selected: value == CategoryType.income,
          color: AppColors.success,
          onTap: () => onChanged(CategoryType.income),
        ),
      ],
    );
  }
}

class _SmallTypeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _SmallTypeButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 22,
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? color : AppColors.textSecondary.withOpacity(0.3),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final FinanceCategory category;
  final VoidCallback onDelete;

  const _CategoryRow({required this.category, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = category.type == CategoryType.expense
        ? AppColors.danger
        : AppColors.success;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              category.name,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.delete_outline,
                  color: AppColors.textSecondary, size: 18),
              onPressed: () => _confirmDelete(context),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete category?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Transactions using "${category.name}" will keep the category ID but won\'t display a name.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            child: Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}
