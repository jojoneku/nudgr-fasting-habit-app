import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Add / edit a budgeted set-aside. Extracted from the Bills view so the unified
/// `NewEntrySheet` can embed it. Standalone use keeps the sheet chrome.
class AddBudgetedExpenseSheet extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final BudgetedExpense? existing;

  /// Embedded inside `NewEntrySheet` — render only the form + Save (see
  /// [AddBillSheet.embedded]).
  final bool embedded;

  const AddBudgetedExpenseSheet({
    super.key,
    required this.presenter,
    this.existing,
    this.embedded = false,
  });

  @override
  State<AddBudgetedExpenseSheet> createState() =>
      _AddBudgetedExpenseSheetState();
}

class _AddBudgetedExpenseSheetState extends State<AddBudgetedExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  SetAsideType _budgetedType = SetAsideType.other;
  String? _selectedCategoryId;
  String? _selectedAccountId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameController.text = e.name;
      _amountController.text = e.allocatedAmount.toStringAsFixed(2);
      _noteController.text = e.note ?? '';
      _budgetedType = e.budgetedType;
      _selectedCategoryId = e.categoryId.isEmpty ? null : e.categoryId;
      _selectedAccountId = e.accountId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final e = widget.existing;
      final id = e?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      final expense = BudgetedExpense(
        id: id,
        name: _nameController.text.trim(),
        budgetedType: _budgetedType,
        month: e?.month ?? widget.presenter.selectedMonth,
        allocatedAmount: amount,
        categoryId: _selectedCategoryId ?? '',
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        accountId: _selectedAccountId,
        // Preserve funded state + link when editing.
        isPaid: e?.isPaid ?? false,
        spentAmount: e?.spentAmount ?? 0,
        transactionId: e?.transactionId,
      );
      if (e != null) {
        await widget.presenter.updateBudgetedExpense(expense);
      } else {
        await widget.presenter.addBudgetedExpense(expense);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildForm(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final expenseCategories = widget.presenter.categories
        .where((c) => c.type == CategoryType.expense)
        .toList();
    // Only liquid accounts can fund a set-aside — funding it later debits one.
    final liquidAccounts = widget.presenter.accounts
        .where((a) => a.isActive && a.isLiquid)
        .toList();

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: sheetFieldDecoration(context, label: 'Name'),
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountController,
            decoration: sheetFieldDecoration(context,
                label: 'Allocated Amount', prefixText: '₱ ', emphasize: true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            validator: (v) {
              final p = double.tryParse(v ?? '');
              if (p == null || p <= 0) return 'Must be > 0';
              return null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SetAsideType>(
            initialValue: _budgetedType,
            decoration: sheetFieldDecoration(context, label: 'Type'),
            items: SetAsideType.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                .toList(),
            onChanged: (v) => setState(() => _budgetedType = v ?? _budgetedType),
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _noteController,
            label: 'Note (optional)',
            textInputAction: TextInputAction.done,
          ),
          if (liquidAccounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue:
                  liquidAccounts.any((a) => a.id == _selectedAccountId)
                      ? _selectedAccountId
                      : null,
              decoration: const InputDecoration(
                  labelText: 'Fund from account (optional)'),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('None')),
                for (final a in liquidAccounts)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _selectedAccountId = v),
            ),
          ],
          if (expenseCategories.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Category',
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: expenseCategories.map((cat) {
                final isSelected = _selectedCategoryId == cat.id;
                return ChoiceChip(
                  label: Text(cat.name),
                  selected: isSelected,
                  onSelected: (_) => setState(() =>
                      _selectedCategoryId = isSelected ? null : cat.id),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _saveButton() => AppPrimaryButton(
        label: widget.existing != null ? 'Save' : 'Add Expense',
        onPressed: _isSubmitting ? null : _submit,
        isLoading: _isSubmitting,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildForm(context),
          const SizedBox(height: 20),
          _saveButton(),
          const SizedBox(height: 8),
        ],
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.existing != null
                  ? 'Edit Budgeted Expense'
                  : 'Add Budgeted Expense',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildForm(context),
            const SizedBox(height: 20),
            _saveButton(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
