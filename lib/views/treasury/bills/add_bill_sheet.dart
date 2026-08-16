import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_chips.dart';
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

  /// The month this bill belongs to (existing bill's month, or the month the
  /// user is currently viewing for a new one), as a real date anchor. The due
  /// date picker is constrained to this month so it stays a day-of-month choice
  /// (no accidental month change) while reading as a calendar, not a 1–31 list.
  DateTime get _dueMonthAnchor {
    final key = widget.existing?.month ?? widget.presenter.selectedMonth;
    return DateTime.tryParse('$key-01') ?? DateTime.now();
  }

  DateTime _resolveDueDate() {
    final a = _dueMonthAnchor;
    final lastDay = DateTime(a.year, a.month + 1, 0).day;
    return DateTime(a.year, a.month, _dueDay.clamp(1, lastDay));
  }

  Future<void> _pickDueDate() async {
    final a = _dueMonthAnchor;
    final lastDay = DateTime(a.year, a.month + 1, 0).day;
    final picked = await showDatePicker(
      context: context,
      initialDate: _resolveDueDate(),
      firstDate: DateTime(a.year, a.month, 1),
      lastDate: DateTime(a.year, a.month, lastDay),
    );
    if (picked != null) setState(() => _dueDay = picked.day);
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
        // Preserve paid state, links, and the next-month override when editing
        // — this builds a fresh Bill rather than copyWith, so anything not
        // restated here is dropped.
        isPaid: widget.existing?.isPaid ?? false,
        paidDate: widget.existing?.paidDate,
        paidAmount: widget.existing?.paidAmount,
        transactionId: widget.existing?.transactionId,
        nextMonthAmount: widget.existing?.nextMonthAmount,
      );
      if (widget.existing != null) {
        await widget.presenter.updateBill(bill);
      } else {
        await widget.presenter.addBill(bill);
      }
      if (mounted) await _offerToReplaceAutoStatement(bill);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// The bill is saved either way — this only decides the fate of a generated
  /// statement it appears to duplicate, and dismissing keeps both. Asked here,
  /// at the moment the collision is created, because the alternative (resolving
  /// it in the auto-generation pass) happens on app open where a removed row
  /// cannot be seen or undone.
  Future<void> _offerToReplaceAutoStatement(Bill bill) async {
    final auto = widget.presenter.redundantAutoStatementFor(bill);
    if (auto == null) return;
    final removeIt = await AppConfirmDialog.confirm(
      context: context,
      title: 'Replace the auto statement?',
      body: '${monthLabel(auto.month)} already has an auto-generated '
          '"${auto.name}" for ${formatPeso(auto.amount)}. Remove it and track '
          'this bill instead, or keep both?',
      confirmLabel: 'Remove it',
      cancelLabel: 'Keep both',
      isDestructive: true,
    );
    if (!removeIt || !mounted) return;
    await widget.presenter.deleteBill(auto.id);
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
                  label: 'Due Date',
                  child: SheetPickerBox(
                    onTap: _pickDueDate,
                    trailingIcon: Icons.calendar_today_outlined,
                    child: Text(
                      DateFormat('MMM d').format(_resolveDueDate()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: colorScheme.onSurface, fontSize: 14),
                    ),
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

          // Category — account-style picker (icon + name), optional.
          if (_expenseCategories.isNotEmpty) ...[
            const SizedBox(height: 16),
            SheetLabeledField(
              label: 'Category',
              child: CategoryPickerField(
                categories: _expenseCategories,
                selectedId: _selectedCategoryId,
                placeholder: 'None',
                onChanged: (id) => setState(() => _selectedCategoryId = id),
              ),
            ),
          ],

          // Payment note — outline field box like the rest of the form.
          const SizedBox(height: 12),
          SheetLabeledField(
            label: 'Payment Note (optional)',
            child: TextFormField(
              controller: _paymentNoteController,
              decoration: sheetFieldDecoration(context),
              textInputAction: TextInputAction.done,
            ),
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
            secondary:
                Icon(Icons.autorenew_rounded, color: colorScheme.primary),
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
