import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

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
          backgroundColor: Theme.of(context).colorScheme.error,
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

  bool get _isEdit =>
      _selectedCategoryId != null &&
      widget.presenter.budgetFor(_selectedCategoryId!) != null;

  @override
  Widget build(BuildContext context) {
    final allCategories = widget.presenter.allCategories;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Category selector or display
            if (widget.preselectedCategoryId == null) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedCategoryId,
                hint: Text(
                  'Select Category',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                decoration: const InputDecoration(labelText: 'Category'),
                items: allCategories
                    .map((c) =>
                        DropdownMenuItem(value: c.id, child: Text(c.name)))
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

            // Amount field
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ],
              decoration: const InputDecoration(
                labelText: 'Budget Amount',
                prefixText: '₱ ',
              ),
              validator: (v) {
                final p = double.tryParse(v ?? '');
                if (p == null || p <= 0) return 'Must be > 0';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Budget Group
            Text(
              'Budget Group',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            AppSegmentedControl<BudgetGroup>(
              segments: const [
                (
                  value: BudgetGroup.nonNegotiables,
                  label: 'Non-Neg.',
                  icon: null
                ),
                (value: BudgetGroup.livingExpense, label: 'Living', icon: null),
                (
                  value: BudgetGroup.variableOptional,
                  label: 'Variable',
                  icon: null
                ),
              ],
              selected: _group,
              onChanged: (g) => setState(() => _group = g),
            ),
            const SizedBox(height: 16),

            // Budget Type
            Text(
              'Budget Type',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            AppSegmentedControl<BudgetType>(
              segments: const [
                (value: BudgetType.monthly, label: 'Monthly', icon: null),
                (value: BudgetType.fixed, label: 'Fixed', icon: null),
                (value: BudgetType.goal, label: 'Goal', icon: null),
                (value: BudgetType.variable, label: 'Variable', icon: null),
              ],
              selected: _budgetType,
              onChanged: (t) => setState(() => _budgetType = t),
            ),
            const SizedBox(height: 20),

            // Save button
            AppPrimaryButton(
              label: _isEdit ? 'Save Budget' : 'Set Budget',
              onPressed: _isSubmitting ? null : _submit,
              isLoading: _isSubmitting,
            ),

            // Remove budget button (edit only)
            if (_isEdit) ...[
              const SizedBox(height: 8),
              AppDestructiveButton(
                label: 'Remove Budget',
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        await widget.presenter
                            .removeBudget(_selectedCategoryId!);
                        if (context.mounted) Navigator.pop(context);
                      },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CategoryDisplay extends StatelessWidget {
  final FinanceCategory? category;

  const _CategoryDisplay({required this.category});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      child: Row(
        children: [
          Text(
            'Category',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Text(
            category?.name ?? '—',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
