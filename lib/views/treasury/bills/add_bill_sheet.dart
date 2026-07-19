import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/views/treasury/shared/forms/forms.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class AddBillSheet extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final Bill? existing;

  /// When true, the sheet is hosted inside the combined [AddEntrySheet] which
  /// already provides the title/chrome, so the internal title is suppressed.
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
      // Hide the internal auto-statement marker from the editable note field —
      // it is not a user-facing note. _resolvePaymentNote re-applies it on save.
      _paymentNoteController.text =
          b.isAutoStatement ? '' : (b.paymentNote ?? '');
      _billType = b.billType;
      _selectedAccountId = b.accountId;
      _selectedCategoryId = b.categoryId.isEmpty ? null : b.categoryId;
      _isRecurring = b.isRecurring;
      _recurrenceType = b.recurrenceType ?? RecurrenceType.monthly;
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
    _dueDayController.dispose();
    _paymentNoteController.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _expenseCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.expense)
      .toList();

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
        paymentNote: _resolvePaymentNote(),
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

  String _billTypeLabel(BillType t) => switch (t) {
        BillType.installment => 'Installment',
        BillType.creditCard => 'Credit Card',
        BillType.subscription => 'Subscription',
        BillType.insurance => 'Insurance',
        BillType.govtContribution => 'Govt Contrib',
        BillType.utility => 'Utility',
        BillType.other => 'Other',
      };

  Future<void> _pickAccount() async {
    final accounts = widget.presenter.accounts;
    if (accounts.isEmpty) return;
    final picked = await AppActionSheet.show<String>(
      context: context,
      title: 'Pay from',
      actions: [
        for (final a in accounts)
          AppActionSheetItem(
            label: a.name,
            value: a.id,
            isPrimary: a.id == _selectedAccountId,
          ),
      ],
    );
    if (picked != null) setState(() => _selectedAccountId = picked);
  }

  Future<void> _pickRecurrence() async {
    final picked = await AppActionSheet.show<RecurrenceType>(
      context: context,
      title: 'Recurrence',
      actions: [
        for (final r in RecurrenceType.values)
          AppActionSheetItem(
            label: _recurrenceLabel(r),
            value: r,
            isPrimary: r == _recurrenceType,
          ),
      ],
    );
    if (picked != null) setState(() => _recurrenceType = picked);
  }

  Widget _buildForm(BuildContext context) {
    final accountName = widget.presenter.accounts
            .where((a) => a.id == _selectedAccountId)
            .map((a) => a.name)
            .firstOrNull ??
        '';
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppFormField(
            label: 'Name',
            child: TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(hintText: 'e.g. Meralco'),
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: AppFormField(
                  label: 'Amount',
                  child: AppAmountField(
                    controller: _amountController,
                    hint: '0.00',
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
                flex: 2,
                child: AppFormField(
                  label: 'Due day',
                  child: TextFormField(
                    controller: _dueDayController,
                    decoration: const InputDecoration(hintText: '1–31'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      final d = int.tryParse(v ?? '');
                      if (d == null || d < 1 || d > 31) return '1–31';
                      return null;
                    },
                  ),
                ),
              ),
            ],
          ),
          if (widget.presenter.accounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            AppFormField(
              label: 'Pay from',
              child: AppSelectField(
                value: accountName,
                placeholder: 'Optional',
                leadingIcon: Icons.account_balance_wallet_outlined,
                onTap: _pickAccount,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _MoreOptionsLabel(),
          const SizedBox(height: 12),
          AppFormField(
            label: 'Bill type',
            child: AppChipSelect<BillType>(
              options: [
                for (final t in BillType.values)
                  AppChipOption(t, _billTypeLabel(t)),
              ],
              selected: _billType,
              onChanged: (t) => setState(() => _billType = t),
            ),
          ),
          if (_expenseCategories.isNotEmpty) ...[
            const SizedBox(height: 16),
            AppFormField(
              label: 'Category',
              child: Wrap(
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
            ),
          ],
          const SizedBox(height: 16),
          AppFormField(
            label: 'Payment note (optional)',
            child: AppTextField(
              controller: _paymentNoteController,
              textInputAction: TextInputAction.done,
            ),
          ),
          const SizedBox(height: 8),
          AppFormToggle(
            icon: Icons.repeat_rounded,
            title: 'Recurring',
            subtitle: 'Auto-generate next month',
            value: _isRecurring,
            onChanged: (v) => setState(() => _isRecurring = v),
          ),
          if (_isRecurring) ...[
            const SizedBox(height: 12),
            AppFormField(
              label: 'Recurrence',
              child: AppSelectField(
                value: _recurrenceLabel(_recurrenceType),
                leadingIcon: Icons.event_repeat_outlined,
                onTap: _pickRecurrence,
              ),
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
        padding: EdgeInsets.fromLTRB(16, widget.embedded ? 4 : 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.embedded) ...[
              Text(title,
                  style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
            ],
            _buildForm(context),
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: widget.existing != null ? 'Save' : 'Save bill',
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

class _MoreOptionsLabel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Text(
          'MORE OPTIONS',
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: cs.outlineVariant)),
      ],
    );
  }
}
