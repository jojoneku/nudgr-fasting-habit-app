import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class AddReceivableSheet extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final Receivable? existing;

  const AddReceivableSheet({super.key, required this.presenter, this.existing});

  @override
  State<AddReceivableSheet> createState() => _AddReceivableSheetState();
}

class _AddReceivableSheetState extends State<AddReceivableSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();

  ReceivableType _receivableType = ReceivableType.other;
  String? _selectedCategoryId;
  DateTime _expectedDate = DateTime.now();
  bool _isRecurring = false;
  RecurrenceType _recurrenceType = RecurrenceType.monthly;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    if (r != null) {
      _nameController.text = r.name;
      _amountController.text = r.amount.toStringAsFixed(2);
      _receivableType = r.receivableType;
      _selectedCategoryId = r.categoryId.isEmpty ? null : r.categoryId;
      _expectedDate = r.expectedDate;
      _isRecurring = r.isRecurring;
      _recurrenceType = r.recurrenceType ?? RecurrenceType.monthly;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _incomeCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.income)
      .toList();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _expectedDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final id = widget.existing?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      final receivable = Receivable(
        id: id,
        name: _nameController.text.trim(),
        receivableType: _receivableType,
        amount: amount,
        expectedDate: _expectedDate,
        month: widget.presenter.selectedMonth,
        categoryId: _selectedCategoryId ?? '',
        isRecurring: _isRecurring,
        recurrenceType: _isRecurring ? _recurrenceType : null,
      );
      if (widget.existing != null) {
        await widget.presenter.updateReceivable(receivable);
      } else {
        await widget.presenter.addReceivable(receivable);
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
            decoration: const InputDecoration(labelText: 'Source / Name'),
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
          ),
          const SizedBox(height: 12),

          // Receivable type selector
          _ReceivableTypeSelector(
            value: _receivableType,
            onChanged: (v) => setState(() => _receivableType = v),
          ),
          const SizedBox(height: 12),

          // Amount + Date
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                      labelText: 'Expected Amount', prefixText: '₱ '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  validator: (v) {
                    final p = double.tryParse(v ?? '');
                    if (p == null || p <= 0) return 'Must be > 0';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            color: colorScheme.onSurfaceVariant, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            DateFormat('MMM d').format(_expectedDate),
                            style: TextStyle(
                                color: colorScheme.onSurface, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Category chips
          if (_incomeCategories.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Category',
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _incomeCategories.map((cat) {
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
    final title = widget.existing != null ? 'Edit Receivable' : 'Add Receivable';

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
              label: widget.existing != null ? 'Save' : 'Add Receivable',
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

class _ReceivableTypeSelector extends StatelessWidget {
  final ReceivableType value;
  final ValueChanged<ReceivableType> onChanged;

  const _ReceivableTypeSelector(
      {required this.value, required this.onChanged});

  static const _labels = {
    ReceivableType.salary: 'Salary',
    ReceivableType.reimbursement: 'Reimbursement',
    ReceivableType.business: 'Business',
    ReceivableType.other: 'Other',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Type',
            style: TextStyle(
                color: colorScheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ReceivableType.values.map((t) {
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
