import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Which side of the unified "New entry" sheet is active.
enum EntryKind { bill, receivable }

/// Unified Bill / Receivable creation & edit sheet (reference "New entry").
/// Replaces the separate AddBillSheet / AddReceivableSheet — a segmented toggle
/// picks the kind; editing an existing entry locks the toggle to its kind.
class EntrySheet extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final EntryKind initialKind;
  final Bill? existingBill;
  final Receivable? existingReceivable;

  const EntrySheet({
    super.key,
    required this.presenter,
    this.initialKind = EntryKind.bill,
    this.existingBill,
    this.existingReceivable,
  });

  bool get isEdit => existingBill != null || existingReceivable != null;

  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<EntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _dueDayController = TextEditingController();
  final _paymentNoteController = TextEditingController();

  late EntryKind _kind;

  // Bill-specific
  BillType _billType = BillType.other;

  // Receivable-specific
  ReceivableType _receivableType = ReceivableType.other;
  DateTime _expectedDate = DateTime.now();

  // Shared
  String? _selectedAccountId;
  String? _selectedCategoryId;
  bool _isRecurring = false;
  RecurrenceType _recurrenceType = RecurrenceType.monthly;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final b = widget.existingBill;
    final r = widget.existingReceivable;
    _kind = b != null
        ? EntryKind.bill
        : (r != null ? EntryKind.receivable : widget.initialKind);

    if (b != null) {
      _nameController.text = b.name;
      _amountController.text = b.amount.toStringAsFixed(2);
      _dueDayController.text = b.dueDay.toString();
      // Hide the internal auto-statement marker from the editable note field —
      // _resolvePaymentNote re-applies it on save.
      _paymentNoteController.text =
          b.isAutoStatement ? '' : (b.paymentNote ?? '');
      _billType = b.billType;
      _selectedAccountId = b.accountId;
      _selectedCategoryId = b.categoryId.isEmpty ? null : b.categoryId;
      _isRecurring = b.isRecurring;
      _recurrenceType = b.recurrenceType ?? RecurrenceType.monthly;
    } else if (r != null) {
      _nameController.text = r.name;
      _amountController.text = r.amount.toStringAsFixed(2);
      _receivableType = r.receivableType;
      _selectedCategoryId = r.categoryId.isEmpty ? null : r.categoryId;
      _selectedAccountId = r.accountId;
      _expectedDate = r.expectedDate ?? DateTime.now();
      _isRecurring = r.isRecurring;
      _recurrenceType = r.recurrenceType ?? RecurrenceType.monthly;
    } else if (_kind == EntryKind.bill && widget.presenter.accounts.isNotEmpty) {
      // New bill: default the payment account to the first (one tap closer).
      _selectedAccountId = widget.presenter.accounts.first.id;
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

  bool get _isBill => _kind == EntryKind.bill;

  List<FinanceCategory> get _categories => widget.presenter.categories
      .where((c) =>
          c.type == (_isBill ? CategoryType.expense : CategoryType.income))
      .toList();

  FinancialAccount? get _selectedAccount {
    for (final a in widget.presenter.accounts) {
      if (a.id == _selectedAccountId) return a;
    }
    return null;
  }

  String _recurrenceLabel(RecurrenceType r) => switch (r) {
        RecurrenceType.monthly => 'Monthly',
        RecurrenceType.weekly => 'Weekly',
        RecurrenceType.yearly => 'Yearly',
        RecurrenceType.custom => 'Custom',
      };

  /// Resolves the bill note to persist. A user-typed note wins; otherwise
  /// re-apply the auto-statement marker we hid from the field.
  String? _resolvePaymentNote() {
    final typed = _paymentNoteController.text.trim();
    if (typed.isNotEmpty) return typed;
    final wasAuto = widget.existingBill?.isAutoStatement ?? false;
    return wasAuto ? Bill.autoStatementNote : null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _expectedDate = picked);
  }

  Future<void> _pickAccount() async {
    final choice = await showAccountPicker(
      context,
      accounts: widget.presenter.accounts,
      selectedId: _selectedAccountId,
      allowNone: true,
      noneLabel: _isBill ? 'None' : 'Ask me when received',
    );
    if (choice != null) setState(() => _selectedAccountId = choice.id);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final id = widget.existingBill?.id ??
          widget.existingReceivable?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

      if (_isBill) {
        final bill = Bill(
          id: id,
          name: _nameController.text.trim(),
          billType: _billType,
          amount: amount,
          dueDay: int.parse(_dueDayController.text),
          month: widget.presenter.selectedMonth,
          categoryId: _selectedCategoryId ?? '',
          accountId: _selectedAccountId,
          paymentNote: _resolvePaymentNote(),
          isRecurring: _isRecurring,
          recurrenceType: _isRecurring ? _recurrenceType : null,
        );
        if (widget.existingBill != null) {
          await widget.presenter.updateBill(bill);
        } else {
          await widget.presenter.addBill(bill);
        }
      } else {
        final receivable = Receivable(
          id: id,
          name: _nameController.text.trim(),
          receivableType: _receivableType,
          amount: amount,
          expectedDate: _expectedDate,
          month: widget.presenter.selectedMonth,
          categoryId: _selectedCategoryId ?? '',
          accountId: _selectedAccountId,
          isRecurring: _isRecurring,
          recurrenceType: _isRecurring ? _recurrenceType : null,
        );
        if (widget.existingReceivable != null) {
          await widget.presenter.updateReceivable(receivable);
        } else {
          await widget.presenter.addReceivable(receivable);
        }
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEdit
        ? (_isBill ? 'Edit bill' : 'Edit receivable')
        : 'New entry';
    final saveLabel = widget.isEdit
        ? 'Save'
        : (_isBill ? 'Add bill' : 'Add receivable');

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            SheetTitle(title),
            const SizedBox(height: 14),

            // Kind toggle — disabled while editing so a bill can't become a
            // receivable (and vice-versa).
            SheetSegmentedToggle<EntryKind>(
              value: _kind,
              onChanged: widget.isEdit
                  ? null
                  : (k) => setState(() {
                        _kind = k;
                        // Category list differs per kind; drop a now-invalid pick.
                        _selectedCategoryId = null;
                        if (k == EntryKind.bill &&
                            _selectedAccountId == null &&
                            widget.presenter.accounts.isNotEmpty) {
                          _selectedAccountId =
                              widget.presenter.accounts.first.id;
                        }
                      }),
              segments: [
                SheetSegment(
                  label: 'Bill to pay',
                  value: EntryKind.bill,
                  accent: context.appColors.bills,
                ),
                SheetSegment(
                  label: 'Money owed me',
                  value: EntryKind.receivable,
                  accent: context.appColors.move,
                ),
              ],
            ),
            const SizedBox(height: 16),

            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Name
                  SheetFieldLabel(_isBill ? 'Name' : 'Source / Name'),
                  TextFormField(
                    controller: _nameController,
                    decoration: sheetFieldDecoration(context),
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 14),

                  // Type (many-valued) — bill vs receivable set.
                  if (_isBill)
                    _ChipTypeField<BillType>(
                      label: 'Bill type',
                      values: BillType.values,
                      selected: _billType,
                      labelOf: (t) => _billTypeLabels[t]!,
                      onChanged: (t) => setState(() => _billType = t),
                    )
                  else
                    _ChipTypeField<ReceivableType>(
                      label: 'Type',
                      values: ReceivableType.values,
                      selected: _receivableType,
                      labelOf: (t) => _receivableTypeLabels[t]!,
                      onChanged: (t) => setState(() => _receivableType = t),
                    ),
                  const SizedBox(height: 14),

                  // Amount + (Due Day | Expected Date)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SheetFieldLabel(
                                _isBill ? 'Amount' : 'Expected amount'),
                            TextFormField(
                              controller: _amountController,
                              decoration: sheetFieldDecoration(context,
                                  prefixText: '₱ ', emphasize: true),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              inputFormatters: amountInputFormatters,
                              textInputAction: TextInputAction.next,
                              validator: (v) {
                                final p = double.tryParse(
                                    (v ?? '').replaceAll(',', ''));
                                if (p == null || p <= 0) return 'Must be > 0';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _isBill
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SheetFieldLabel('Due day (1–31)'),
                                  TextFormField(
                                    controller: _dueDayController,
                                    decoration: sheetFieldDecoration(context),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(2),
                                    ],
                                    textInputAction: TextInputAction.next,
                                    validator: (v) {
                                      final d = int.tryParse(v ?? '');
                                      if (d == null || d < 1 || d > 31) {
                                        return '1–31';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SheetFieldLabel('Expected date'),
                                  SheetPickerBox(
                                    onTap: _pickDate,
                                    trailingIcon: Icons.calendar_today_rounded,
                                    child: Text(
                                      DateFormat('MMM d').format(_expectedDate),
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Account
                  SheetFieldLabel(_isBill ? 'Pay from' : 'Destination account'),
                  SheetAccountField(
                    account: _selectedAccount,
                    onTap: _pickAccount,
                    placeholder:
                        _isBill ? 'None' : 'Ask me when received',
                  ),
                  if (!_isBill)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 2),
                      child: Text(
                        'Pre-fills when you mark this received',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),

                  // Category
                  if (_categories.isNotEmpty) ...[
                    const SheetFieldLabel('Category'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _categories.map((cat) {
                        final isSelected = _selectedCategoryId == cat.id;
                        return ChoiceChip(
                          label: Text(cat.name),
                          selected: isSelected,
                          onSelected: (_) => setState(() =>
                              _selectedCategoryId = isSelected ? null : cat.id),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Bill-only: payment note
                  if (_isBill) ...[
                    const SheetFieldLabel('Payment note (optional)'),
                    AppTextField(
                      controller: _paymentNoteController,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Recurring + recurrence
                  SwitchListTile(
                    value: _isRecurring,
                    onChanged: (v) => setState(() => _isRecurring = v),
                    title:
                        const Text('Recurring', style: TextStyle(fontSize: 14)),
                    subtitle: Text('Auto-generate next month',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12)),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_isRecurring) ...[
                    const SizedBox(height: 4),
                    const SheetFieldLabel('Recurrence'),
                    DropdownButtonFormField<RecurrenceType>(
                      initialValue: _recurrenceType,
                      decoration: sheetFieldDecoration(context),
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
            ),

            const SizedBox(height: 20),
            AppPrimaryButton(
              label: saveLabel,
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

const Map<BillType, String> _billTypeLabels = {
  BillType.installment: 'Installment',
  BillType.creditCard: 'Credit Card',
  BillType.subscription: 'Subscription',
  BillType.insurance: 'Insurance',
  BillType.govtContribution: 'Govt Contrib',
  BillType.utility: 'Utility',
  BillType.other: 'Other',
};

const Map<ReceivableType, String> _receivableTypeLabels = {
  ReceivableType.salary: 'Salary',
  ReceivableType.reimbursement: 'Reimbursement',
  ReceivableType.business: 'Business',
  ReceivableType.other: 'Other',
};

/// A labelled chip group for a many-valued enum (bill/receivable type),
/// restyled to sit under a [SheetFieldLabel].
class _ChipTypeField<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  const _ChipTypeField({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetFieldLabel(label),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((t) {
            return ChoiceChip(
              label: Text(labelOf(t)),
              selected: selected == t,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                onChanged(t);
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
