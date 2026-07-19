import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class AddBillSheet extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final Bill? existing;

  /// When true the sheet renders only its form + Save (no drag handle, title, or
  /// scroll) so it can be embedded inside the unified `NewEntrySheet`, which
  /// provides those. Standalone use keeps the full sheet chrome.
  final bool embedded;

  const AddBillSheet({
    super.key,
    required this.presenter,
    this.existing,
    this.embedded = false,
  });

  @override
  State<AddBillSheet> createState() => _AddBillSheetState();
}

class _AddBillSheetState extends State<AddBillSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _paymentNoteController = TextEditingController();

  int _dueDay = 1;
  BillType _billType = BillType.other;
  String? _selectedAccountId;
  String? _selectedCategoryId;
  bool _isRecurring = false;
  RecurrenceType _recurrenceType = RecurrenceType.monthly;
  bool _reminderOn = false;
  int _reminderDays = 2;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _nameController.text = b.name;
      _amountController.text = b.amount.toStringAsFixed(2);
      _dueDay = b.dueDay.clamp(1, 31);
      // Hide the internal auto-statement marker from the editable note field —
      // it is not a user-facing note. _resolvePaymentNote re-applies it on save.
      _paymentNoteController.text =
          b.isAutoStatement ? '' : (b.paymentNote ?? '');
      _billType = b.billType;
      _selectedAccountId = b.accountId;
      _selectedCategoryId = b.categoryId.isEmpty ? null : b.categoryId;
      _isRecurring = b.isRecurring;
      _recurrenceType = b.recurrenceType ?? RecurrenceType.monthly;
      _reminderOn = b.reminderDaysBefore != null;
      _reminderDays = b.reminderDaysBefore ?? 2;
    } else {
      // Default the payment account to the first one so a new bill is one tap
      // closer to done; the user can still change or clear it.
      _selectedAccountId = widget.presenter.accounts.isNotEmpty
          ? widget.presenter.accounts.first.id
          : null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _paymentNoteController.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _expenseCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.expense)
      .toList();

  FinancialAccount? get _selectedAccount {
    for (final a in widget.presenter.accounts) {
      if (a.id == _selectedAccountId) return a;
    }
    return null;
  }

  Future<void> _pickAccount() async {
    final choice = await showAccountPicker(
      context,
      accounts: widget.presenter.accounts,
      selectedId: _selectedAccountId,
      allowNone: true,
      noneLabel: 'None',
    );
    if (choice != null) setState(() => _selectedAccountId = choice.id);
  }

  /// Resolves the note to persist. A user-typed note wins; otherwise we
  /// re-apply the auto-statement marker we hid from the field, so editing an
  /// auto-generated statement's other fields doesn't strip its flag.
  String? _resolvePaymentNote() {
    final typed = _paymentNoteController.text.trim();
    if (typed.isNotEmpty) return typed;
    final wasAuto = widget.existing?.isAutoStatement ?? false;
    return wasAuto ? Bill.autoStatementNote : null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final id = widget.existing?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      final bill = Bill(
        id: id,
        name: _nameController.text.trim(),
        billType: _billType,
        amount: amount,
        dueDay: _dueDay,
        month: widget.existing?.month ?? widget.presenter.selectedMonth,
        categoryId: _selectedCategoryId ?? '',
        accountId: _selectedAccountId,
        paymentNote: _resolvePaymentNote(),
        isRecurring: _isRecurring,
        recurrenceType: _isRecurring ? _recurrenceType : null,
        reminderDaysBefore: _reminderOn ? _reminderDays : null,
        // Preserve paid state / links when editing.
        isPaid: widget.existing?.isPaid ?? false,
        paidDate: widget.existing?.paidDate,
        paidAmount: widget.existing?.paidAmount,
        transactionId: widget.existing?.transactionId,
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

  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    return switch (day % 10) {
      1 => '${day}st',
      2 => '${day}nd',
      3 => '${day}rd',
      _ => '${day}th',
    };
  }

  Widget _buildForm(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Name
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

          // Bill type selector
          _BillTypeSelector(
            value: _billType,
            onChanged: (v) => setState(() => _billType = v),
          ),
          const SizedBox(height: 12),

          // Amount + Due Day
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SheetLabeledField(
                  label: 'Amount',
                  child: TextFormField(
                    controller: _amountController,
                    decoration: sheetFieldDecoration(context,
                        prefixText: '₱ ', emphasize: true),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: amountInputFormatters,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      final p = double.tryParse(v ?? '');
                      if (p == null || p <= 0) return 'Must be > 0';
                      return null;
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SheetLabeledField(
                  label: 'Due Day',
                  child: DropdownButtonFormField<int>(
                    initialValue: _dueDay,
                    isExpanded: true,
                    decoration: sheetFieldDecoration(context),
                    items: [
                      for (int d = 1; d <= 31; d++)
                        DropdownMenuItem(value: d, child: Text(_ordinal(d))),
                    ],
                    onChanged: (v) => setState(() => _dueDay = v ?? _dueDay),
                  ),
                ),
              ),
            ],
          ),

          // Account — reference badge + name + caret picker (optional).
          if (widget.presenter.accounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            const SheetFieldLabel('Pay from'),
            SheetAccountField(
              account: _selectedAccount,
              placeholder: 'None',
              onTap: _pickAccount,
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
                  // Tap again to clear — a bill needn't carry a category.
                  onSelected: (_) => setState(
                      () => _selectedCategoryId = isSelected ? null : cat.id),
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
          const SizedBox(height: 8),
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
            SheetLabeledField(
              label: 'Recurrence',
              child: DropdownButtonFormField<RecurrenceType>(
                initialValue: _recurrenceType,
                decoration: sheetFieldDecoration(context),
                items: RecurrenceType.values
                    .map((r) => DropdownMenuItem(
                        value: r, child: Text(_recurrenceLabel(r))))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _recurrenceType = v ?? _recurrenceType),
              ),
            ),
          ],

          // Reminder toggle (per-bill lead-time)
          SwitchListTile(
            value: _reminderOn,
            onChanged: (v) => setState(() => _reminderOn = v),
            title: const Text('Remind me before due',
                style: TextStyle(fontSize: 14)),
            secondary: Icon(Icons.notifications_none_rounded,
                color: colorScheme.primary),
            contentPadding: EdgeInsets.zero,
          ),
          if (_reminderOn) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [1, 2, 3, 5, 7].map((d) {
                return ChoiceChip(
                  label: Text(d == 1 ? '1 day' : '$d days'),
                  selected: _reminderDays == d,
                  onSelected: (_) => setState(() => _reminderDays = d),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _saveButton() => AppPrimaryButton(
        label: widget.existing != null ? 'Save' : 'Save bill',
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
            _saveButton(),
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
            style:
                TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
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
