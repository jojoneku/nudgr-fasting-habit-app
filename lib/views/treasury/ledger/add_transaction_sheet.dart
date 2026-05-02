import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class AddTransactionSheet extends StatefulWidget {
  final LedgerPresenter presenter;
  final TransactionRecord? existing;

  const AddTransactionSheet(
      {super.key, required this.presenter, this.existing});

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _noteController = TextEditingController();

  TransactionType _type = TransactionType.outflow;
  String? _selectedAccountId;
  String? _transferToAccountId;
  String? _selectedCategoryId;
  DateTime _date = DateTime.now();

  bool _isSubmitting = false;

  // Cached presenter data — updated only when presenter fires, not on keystrokes
  List<FinancialAccount> _accounts = [];
  List<FinanceCategory> _categories = [];

  @override
  void initState() {
    super.initState();
    _syncFromPresenter();
    widget.presenter.addListener(_onPresenterChange);
    // LedgerPresenter may have stale accounts if they were added/edited via
    // TreasuryDashboardPresenter. Reload from storage; the listener will
    // call _syncFromPresenter once the load completes.
    widget.presenter.reloadAccounts();
    final existing = widget.existing;
    if (existing != null) {
      _type = existing.type;
      _amountController.text = existing.amount.toStringAsFixed(2);
      _descriptionController.text = existing.description;
      _noteController.text = existing.note ?? '';
      _selectedAccountId = existing.accountId;
      _transferToAccountId = existing.transferToAccountId;
      _selectedCategoryId = existing.categoryId;
      _date = existing.date;
    }
  }

  void _syncFromPresenter() {
    _accounts = widget.presenter.accounts
        .where((a) => a.isActive && !a.isSubAccount)
        .toList();
    _categories = widget.presenter.categories;
  }

  void _onPresenterChange() {
    if (!mounted) return;
    setState(_syncFromPresenter);
  }

  @override
  void dispose() {
    widget.presenter.removeListener(_onPresenterChange);
    _amountController.dispose();
    _descriptionController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _filteredCategories {
    if (_type == TransactionType.inflow) {
      return _categories.where((c) => c.type == CategoryType.income).toList();
    }
    if (_type == TransactionType.outflow) {
      return _categories.where((c) => c.type == CategoryType.expense).toList();
    }
    return _categories;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountId == null) return;
    if (_type == TransactionType.transfer && _transferToAccountId == null) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final description = _descriptionController.text.trim();
      final note = _noteController.text.trim();
      final month = toMonthKey(_date);
      final categoryId = _selectedCategoryId ?? '';

      if (_type == TransactionType.transfer) {
        await widget.presenter.addTransfer(
          fromAccountId: _selectedAccountId!,
          toAccountId: _transferToAccountId!,
          amount: amount,
          categoryId: categoryId,
          description: description,
          date: _date,
          note: note.isEmpty ? null : note,
        );
      } else {
        final id = widget.existing?.id ??
            '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
        final txn = TransactionRecord(
          id: id,
          date: _date,
          accountId: _selectedAccountId!,
          categoryId: categoryId,
          amount: amount,
          type: _type,
          description: description,
          note: note.isEmpty ? null : note,
          month: month,
        );
        if (widget.existing != null) {
          await widget.presenter.updateTransaction(txn.copyWith());
        } else {
          await widget.presenter.addTransaction(txn);
        }
      }

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TypeToggle(
                      selected: _type,
                      onChanged: (t) => setState(() {
                            _type = t;
                            _selectedCategoryId = null;
                          })),
                  const SizedBox(height: 16),
                  _DescriptionField(controller: _descriptionController),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _AmountField(controller: _amountController),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _DatePickerRow(
                            date: _date, onTap: _pickDate, compact: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _AccountDropdown(
                    accounts: _accounts,
                    label: _type == TransactionType.transfer
                        ? 'From Account'
                        : 'Account',
                    value: _selectedAccountId,
                    onChanged: (v) => setState(() => _selectedAccountId = v),
                  ),
                  if (_type == TransactionType.transfer) ...[
                    const SizedBox(height: 12),
                    _AccountDropdown(
                      accounts: _accounts,
                      label: 'To Account',
                      value: _transferToAccountId,
                      onChanged: (v) =>
                          setState(() => _transferToAccountId = v),
                    ),
                  ],
                  if (_type != TransactionType.transfer) ...[
                    const SizedBox(height: 16),
                    if (_filteredCategories.isEmpty)
                      _NoCategoriesHint(type: _type)
                    else
                      _CategoryChips(
                        categories: _filteredCategories,
                        selected: _selectedCategoryId,
                        onSelected: (id) =>
                            setState(() => _selectedCategoryId = id),
                      ),
                  ],
                  const SizedBox(height: 12),
                  _NoteField(controller: _noteController),
                  const SizedBox(height: 20),
                  AppPrimaryButton(
                    label: isEdit ? 'Save' : 'Log Transaction',
                    isLoading: _isSubmitting,
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
        const _KeyboardSpacer(),
      ],
    );
  }
}

// ── Type Toggle ───────────────────────────────────────────────────────────────

class _TypeToggle extends StatelessWidget {
  final TransactionType selected;
  final ValueChanged<TransactionType> onChanged;

  const _TypeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        _TypeButton(
          label: 'Inflow',
          type: TransactionType.inflow,
          selected: selected,
          color: cs.tertiary,
          onTap: () => onChanged(TransactionType.inflow),
        ),
        const SizedBox(width: 8),
        _TypeButton(
          label: 'Outflow',
          type: TransactionType.outflow,
          selected: selected,
          color: cs.error,
          onTap: () => onChanged(TransactionType.outflow),
        ),
        const SizedBox(width: 8),
        _TypeButton(
          label: 'Transfer',
          type: TransactionType.transfer,
          selected: selected,
          color: cs.primary,
          onTap: () => onChanged(TransactionType.transfer),
        ),
      ],
    );
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final TransactionType type;
  final TransactionType selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeButton({
    required this.label,
    required this.type,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == type;
    return Expanded(
      child: SizedBox(
        height: 44,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            backgroundColor:
                isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
            side: BorderSide(
                color: isSelected
                    ? color
                    : Theme.of(context)
                        .colorScheme
                        .outlineVariant),
            foregroundColor:
                isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
            padding: EdgeInsets.zero,
          ),
          child: Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// ── Amount Field ──────────────────────────────────────────────────────────────

class _AmountField extends StatelessWidget {
  final TextEditingController controller;

  const _AmountField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      decoration: const InputDecoration(
        labelText: 'Amount',
        prefixText: '₱ ',
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Enter an amount';
        final parsed = double.tryParse(v);
        if (parsed == null || parsed <= 0) return 'Amount must be > 0';
        return null;
      },
    );
  }
}

// ── Account Dropdown ──────────────────────────────────────────────────────────

class _AccountDropdown extends StatelessWidget {
  final List<FinancialAccount> accounts;
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _AccountDropdown({
    required this.accounts,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      hint: Text(label),
      decoration: InputDecoration(labelText: label),
      items: accounts
          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
          .toList(),
      onChanged: onChanged,
      validator: (v) => v == null ? 'Select an account' : null,
    );
  }
}

// ── Category Chips ────────────────────────────────────────────────────────────

class _CategoryChips extends StatelessWidget {
  final List<FinanceCategory> categories;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category',
            style: TextStyle(
                color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: categories.map((cat) {
            final isSelected = selected == cat.id;
            return ChoiceChip(
              label: Text(cat.name),
              selected: isSelected,
              onSelected: (_) => onSelected(cat.id),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Description Field ─────────────────────────────────────────────────────────

class _DescriptionField extends StatelessWidget {
  final TextEditingController controller;

  const _DescriptionField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLength: 60,
      decoration: const InputDecoration(
        labelText: 'Description',
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Enter a description' : null,
    );
  }
}

// ── Date Picker Row ───────────────────────────────────────────────────────────

class _DatePickerRow extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;
  final bool compact;

  const _DatePickerRow(
      {required this.date, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                color: cs.onSurfaceVariant, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                compact
                    ? DateFormat('MMM d, yyyy').format(date)
                    : DateFormat('MMMM d, yyyy').format(date),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Note Field ────────────────────────────────────────────────────────────────

class _NoteField extends StatelessWidget {
  final TextEditingController controller;

  const _NoteField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: 2,
      decoration: const InputDecoration(
        labelText: 'Note (optional)',
      ),
    );
  }
}

// ── No Categories Hint ────────────────────────────────────────────────────────

class _NoCategoriesHint extends StatelessWidget {
  final TransactionType type;

  const _NoCategoriesHint({required this.type});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = type == TransactionType.inflow ? 'income' : 'expense';
    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.onSurfaceVariant, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No $label categories yet — add some in the Ledger first.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Isolated widget so only this rebuilds on keyboard animation frames,
/// not the entire form above it.
class _KeyboardSpacer extends StatelessWidget {
  const _KeyboardSpacer();

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: MediaQuery.of(context).viewInsets.bottom);
  }
}
