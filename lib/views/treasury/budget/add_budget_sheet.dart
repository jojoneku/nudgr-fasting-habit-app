import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';

class AddBudgetSheet extends StatefulWidget {
  final BudgetPresenter presenter;
  final String? preselectedCategoryId;

  const AddBudgetSheet(
      {super.key, required this.presenter, this.preselectedCategoryId});

  @override
  State<AddBudgetSheet> createState() => _AddBudgetSheetState();
}

class _AddBudgetSheetState extends State<AddBudgetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();

  String? _selectedCategoryId;
  BudgetGroup _group = BudgetGroup.livingExpense;
  BudgetType _budgetType = BudgetType.variable;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.preselectedCategoryId;
    if (_selectedCategoryId != null) {
      final existing = widget.presenter.budgetFor(_selectedCategoryId!);
      if (existing != null) {
        _amountController.text = existing.allocatedAmount.toStringAsFixed(2);
        _group = existing.group;
        _budgetType = existing.budgetType;
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Select a category'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      await widget.presenter.setBudget(
        _selectedCategoryId!,
        amount,
        group: _group,
        budgetType: _budgetType,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allCategories = widget.presenter.allCategories;
    final isEdit = _selectedCategoryId != null &&
        widget.presenter.budgetFor(_selectedCategoryId!) != null;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEdit ? 'Edit Budget' : 'Set Budget',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (widget.preselectedCategoryId == null) ...[
                DropdownButtonFormField<String>(
                  value: _selectedCategoryId,
                  hint: Text('Select Category',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 14)),
                  dropdownColor: AppColors.surface,
                  style:
                      TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: _inputDec('Category'),
                  items: allCategories
                      .map((c) => DropdownMenuItem(
                          value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedCategoryId = v),
                  validator: (v) => v == null ? 'Select a category' : null,
                ),
                const SizedBox(height: 12),
              ] else ...[
                _CategoryDisplay(
                  category: allCategories.cast<FinanceCategory?>().firstWhere(
                    (c) => c?.id == _selectedCategoryId,
                    orElse: () => null,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                ],
                style: TextStyle(color: AppColors.textPrimary),
                decoration: _inputDec('Budget Amount', prefix: '₱ '),
                validator: (v) {
                  final p = double.tryParse(v ?? '');
                  if (p == null || p <= 0) return 'Must be > 0';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text('Budget Group',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              _GroupSelector(
                value: _group,
                onChanged: (g) => setState(() => _group = g),
              ),
              const SizedBox(height: 16),
              Text('Budget Type',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              _TypeSelector(
                value: _budgetType,
                onChanged: (t) => setState(() => _budgetType = t),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          isEdit ? 'Save Budget' : 'Set Budget',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                ),
              ),
              if (isEdit) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: () async {
                      await widget.presenter
                          .removeBudget(_selectedCategoryId!);
                      if (context.mounted) Navigator.pop(context);
                    },
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger),
                    child: const Text('Remove Budget'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, {String? prefix}) =>
      InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary),
        prefixText: prefix,
        prefixStyle: TextStyle(color: AppColors.accent),
        filled: true,
        fillColor: AppColors.background,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: AppColors.textSecondary.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.accent),
        ),
      );
}

class _CategoryDisplay extends StatelessWidget {
  final FinanceCategory? category;

  const _CategoryDisplay({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppColors.textSecondary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text('Category',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(width: 12),
          Text(
            category?.name ?? '—',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _GroupSelector extends StatelessWidget {
  final BudgetGroup value;
  final ValueChanged<BudgetGroup> onChanged;

  const _GroupSelector(
      {required this.value, required this.onChanged});

  static const _labels = {
    BudgetGroup.nonNegotiables: 'Non-Negotiables',
    BudgetGroup.livingExpense: 'Living Expense',
    BudgetGroup.variableOptional: 'Variable / Optional',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: BudgetGroup.values.map((g) {
        final isSelected = value == g;
        return ChoiceChip(
          label: Text(_labels[g]!),
          selected: isSelected,
          selectedColor: AppColors.accent.withOpacity(0.15),
          labelStyle: TextStyle(
            color: isSelected ? AppColors.accent : AppColors.textSecondary,
            fontSize: 12,
          ),
          backgroundColor: AppColors.surface,
          side: BorderSide(
              color: isSelected
                  ? AppColors.accent
                  : AppColors.textSecondary.withOpacity(0.3)),
          onSelected: (_) => onChanged(g),
        );
      }).toList(),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  final BudgetType value;
  final ValueChanged<BudgetType> onChanged;

  const _TypeSelector(
      {required this.value, required this.onChanged});

  static const _labels = {
    BudgetType.monthly: 'Monthly',
    BudgetType.fixed: 'Fixed',
    BudgetType.goal: 'Goal',
    BudgetType.variable: 'Variable',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: BudgetType.values.map((t) {
        final isSelected = value == t;
        return ChoiceChip(
          label: Text(_labels[t]!),
          selected: isSelected,
          selectedColor: AppColors.accent.withOpacity(0.15),
          labelStyle: TextStyle(
            color: isSelected ? AppColors.accent : AppColors.textSecondary,
            fontSize: 12,
          ),
          backgroundColor: AppColors.surface,
          side: BorderSide(
              color: isSelected
                  ? AppColors.accent
                  : AppColors.textSecondary.withOpacity(0.3)),
          onSelected: (_) => onChanged(t),
        );
      }).toList(),
    );
  }
}
