import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_chips.dart';
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
  String? _selectedDestinationId;
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
      _selectedDestinationId = e.destinationAccountId;
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
        destinationAccountId: _selectedDestinationId,
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

  // Only liquid accounts can fund a set-aside — funding it later debits one.
  List<FinancialAccount> get _liquidAccounts =>
      widget.presenter.setAsideFundingAccounts;

  /// Where the money lands when this is funded. Excludes the funding account —
  /// a transfer to itself isn't one.
  List<FinancialAccount> get _destinationAccounts =>
      widget.presenter.setAsideDestinationAccounts
          .where((a) => a.id != _selectedAccountId)
          .toList();

  FinancialAccount? get _selectedAccount {
    for (final a in _liquidAccounts) {
      if (a.id == _selectedAccountId) return a;
    }
    return null;
  }

  FinancialAccount? get _selectedDestination {
    for (final a in widget.presenter.setAsideDestinationAccounts) {
      if (a.id == _selectedDestinationId) return a;
    }
    return null;
  }

  Future<void> _pickAccount() async {
    final choice = await showAccountPicker(
      context,
      accounts: _liquidAccounts,
      selectedId: _selectedAccountId,
      allowNone: true,
      noneLabel: 'None',
    );
    if (choice != null) {
      setState(() {
        _selectedAccountId = choice.id;
        // The source can't also be the destination.
        if (_selectedDestinationId == _selectedAccountId) {
          _selectedDestinationId = null;
        }
      });
    }
  }

  Future<void> _pickDestination() async {
    final choice = await showAccountPicker(
      context,
      accounts: _destinationAccounts,
      selectedId: _selectedDestinationId,
      allowNone: true,
      noneLabel: 'Decide when funding',
    );
    if (choice != null) setState(() => _selectedDestinationId = choice.id);
  }

  Widget _buildForm(BuildContext context) {
    final expenseCategories = widget.presenter.categories
        .where((c) => c.type == CategoryType.expense)
        .toList();
    final liquidAccounts = _liquidAccounts;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetLabeledField(
            label: 'Name',
            child: TextFormField(
              controller: _nameController,
              decoration: sheetFieldDecoration(context),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
          ),
          const SizedBox(height: 12),
          SheetLabeledField(
            label: 'Allocated Amount',
            child: TextFormField(
              controller: _amountController,
              decoration: sheetFieldDecoration(context,
                  prefixText: '₱ ', emphasize: true),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              validator: (v) {
                final p = double.tryParse(v ?? '');
                if (p == null || p <= 0) return 'Must be > 0';
                return null;
              },
            ),
          ),
          const SizedBox(height: 12),
          SheetLabeledField(
            label: 'Type',
            child: DropdownButtonFormField<SetAsideType>(
              initialValue: _budgetedType,
              decoration: sheetFieldDecoration(context),
              items: SetAsideType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _budgetedType = v ?? _budgetedType),
            ),
          ),
          const SizedBox(height: 12),
          SheetLabeledField(
            label: 'Note (optional)',
            child: TextFormField(
              controller: _noteController,
              decoration: sheetFieldDecoration(context),
              textInputAction: TextInputAction.done,
            ),
          ),
          if (liquidAccounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            const SheetFieldLabel('Fund from account (optional)'),
            SheetAccountField(
              account: _selectedAccount,
              placeholder: 'None',
              onTap: _pickAccount,
            ),
          ],
          if (_destinationAccounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            const SheetFieldLabel('Set aside into (optional)'),
            SheetAccountField(
              account: _selectedDestination,
              // Naming it here means "₱5,000 from BPI to Maya" is decided once;
              // leaving it blank means the funding sheet asks at the time.
              placeholder: 'Decide when funding',
              onTap: _pickDestination,
            ),
          ],
          if (expenseCategories.isNotEmpty) ...[
            const SizedBox(height: 16),
            SheetLabeledField(
              label: 'Category',
              child: CategoryPickerField(
                categories: expenseCategories,
                selectedId: _selectedCategoryId,
                placeholder: 'None',
                onChanged: (id) => setState(() => _selectedCategoryId = id),
              ),
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
