import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class AddBillSheet extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final Bill? existing;

  const AddBillSheet({super.key, required this.presenter, this.existing});

  @override
  State<AddBillSheet> createState() => _AddBillSheetState();
}

class _AddBillSheetState extends State<AddBillSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _dueDayController = TextEditingController();
  final _paymentNoteController = TextEditingController();

  BillType _billType = BillType.other;
  String? _selectedAccountId;
  String? _selectedCategoryId;
  bool _isRecurring = false;
  RecurrenceType _recurrenceType = RecurrenceType.monthly;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _nameController.text = b.name;
      _amountController.text = b.amount.toStringAsFixed(2);
      _dueDayController.text = b.dueDay.toString();
      _paymentNoteController.text = b.paymentNote ?? '';
      _billType = b.billType;
      _selectedAccountId = b.accountId;
      _selectedCategoryId = b.categoryId.isEmpty ? null : b.categoryId;
      _isRecurring = b.isRecurring;
      _recurrenceType = b.recurrenceType ?? RecurrenceType.monthly;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _dueDayController.dispose();
    _paymentNoteController.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _expenseCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.expense)
      .toList();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final dueDay = int.parse(_dueDayController.text);
      final id = widget.existing?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      final bill = Bill(
        id: id,
        name: _nameController.text.trim(),
        billType: _billType,
        amount: amount,
        dueDay: dueDay,
        month: widget.presenter.selectedMonth,
        categoryId: _selectedCategoryId ?? '',
        accountId: _selectedAccountId,
        paymentNote: _paymentNoteController.text.trim().isEmpty
            ? null
            : _paymentNoteController.text.trim(),
        isRecurring: _isRecurring,
        recurrenceType: _isRecurring ? _recurrenceType : null,
      );
      if (widget.existing != null) {
        await widget.presenter.updateBill(bill);
      } else {
        await widget.presenter.addBill(bill);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _recurrenceLabel(RecurrenceType r) => switch (r) {
        RecurrenceType.monthly => 'Monthly',
        RecurrenceType.weekly => 'Weekly',
        RecurrenceType.yearly => 'Yearly',
        RecurrenceType.custom => 'Custom',
      };

  Widget _buildForm(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Name
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
          ),
          const SizedBox(height: 12),

          // Bill type selector
          _BillTypeSelector(
            value: _billType,
            onChanged: (v) => setState(() => _billType = v),
          ),
          const SizedBox(height: 12),

          // Amount + Due Day
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                      labelText: 'Amount', prefixText: '₱ '),
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
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _dueDayController,
                  decoration:
                      const InputDecoration(labelText: 'Due Day (1–31)'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final d = int.tryParse(v ?? '');
                    if (d == null || d < 1 || d > 31) return '1–31';
                    return null;
                  },
                ),
              ),
            ],
          ),

          // Account dropdown
          if (widget.presenter.accounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedAccountId,
              hint: Text('Account (optional)',
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 14)),
              decoration: const InputDecoration(labelText: 'Payment Account'),
              items: widget.presenter.accounts
                  .map((a) =>
                      DropdownMenuItem(value: a.id, child: Text(a.name)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedAccountId = v),
            ),
          ],

          // Category chips
          if (_expenseCategories.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Category',
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _expenseCategories.map((cat) {
                final isSelected = _selectedCategoryId == cat.id;
                return ChoiceChip(
                  label: Text(cat.name),
                  selected: isSelected,
                  onSelected: (_) =>
                      setState(() => _selectedCategoryId = cat.id),
                );
              }).toList(),
            ),
          ],

          // Payment note
          const SizedBox(height: 12),
          AppTextField(
            controller: _paymentNoteController,
            label: 'Payment Note (optional)',
            textInputAction: TextInputAction.done,
          ),

          // Recurring toggle
          const SizedBox(height: 16),
          SwitchListTile(
            value: _isRecurring,
            onChanged: (v) => setState(() => _isRecurring = v),
            title: const Text('Recurring', style: TextStyle(fontSize: 14)),
            subtitle: Text('Auto-generate next month',
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 12)),
            contentPadding: EdgeInsets.zero,
          ),
          if (_isRecurring) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<RecurrenceType>(
              value: _recurrenceType,
              decoration: const InputDecoration(labelText: 'Recurrence'),
              items: RecurrenceType.values
                  .map((r) => DropdownMenuItem(
                      value: r, child: Text(_recurrenceLabel(r))))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _recurrenceType = v ?? _recurrenceType),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = widget.existing != null ? 'Edit Bill' : 'Add Bill';

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildForm(context),
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: widget.existing != null ? 'Save' : 'Add Bill',
              onPressed: _isSubmitting ? null : _submit,
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _BillTypeSelector extends StatelessWidget {
  final BillType value;
  final ValueChanged<BillType> onChanged;

  const _BillTypeSelector({required this.value, required this.onChanged});

  static const _labels = {
    BillType.installment: 'Installment',
    BillType.creditCard: 'Credit Card',
    BillType.subscription: 'Subscription',
    BillType.insurance: 'Insurance',
    BillType.govtContribution: 'Govt Contrib',
    BillType.utility: 'Utility',
    BillType.other: 'Other',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bill Type',
            style: TextStyle(
                color: colorScheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: BillType.values.map((t) {
            final isSelected = value == t;
            return ChoiceChip(
              label: Text(_labels[t]!),
              selected: isSelected,
              onSelected: (_) => onChanged(t),
            );
          }).toList(),
        ),
      ],
    );
  }
}
