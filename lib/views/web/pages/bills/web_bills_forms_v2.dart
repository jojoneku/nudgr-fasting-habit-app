/// The Bills forms on the v2 kit (Plan 063, Phase 5): Add/Edit Bill,
/// Receivable, Set-aside and Installment, the "Recurring: which ones?" scope
/// dialog, the undo-settlement confirm, and the delete confirms.
///
/// Same presenter calls and the same validation as the pre-v2 dialogs in
/// `web_bills_page.dart`; only the shell changed — every form is a
/// [WebDialog] of [WebField]s with the optional fields under
/// [WebMoreOptions]. Views stay dumb: the presenters own the series math,
/// the statement cycle and the installment arithmetic.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/bills/undo_settlement_dialog.dart';
import 'package:intermittent_fasting/views/treasury/shared/recurring_scope_field.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../../web_keys.dart';
import '../../widgets/web_widgets.dart';

const _gap = SizedBox(height: 14);

/// "1st", "2nd", "16th" — due days read as dates, not counts.
String ordinalDay(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}

String recurrenceLabel(RecurrenceType r) => switch (r) {
      RecurrenceType.monthly => 'Monthly',
      RecurrenceType.weekly => 'Weekly',
      RecurrenceType.yearly => 'Yearly',
      RecurrenceType.custom => 'Custom',
    };

String billTypeFormLabel(BillType type) => switch (type) {
      BillType.installment => 'Installment',
      BillType.creditCard => 'Credit Card',
      BillType.subscription => 'Subscription',
      BillType.insurance => 'Insurance',
      BillType.govtContribution => 'Govt Contribution',
      BillType.utility => 'Utility',
      BillType.other => 'Other',
    };

String receivableTypeLabel(ReceivableType type) => switch (type) {
      ReceivableType.salary => 'Salary',
      ReceivableType.reimbursement => 'Reimbursement',
      ReceivableType.business => 'Business',
      ReceivableType.other => 'Other',
    };

String _newId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

/// Amount text for an edit form: "1600" for a whole figure, "786.5" otherwise.
String _amountText(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

double? _parseAmount(String text) =>
    double.tryParse(text.replaceAll(',', '').trim());

String? _validateAmount(String text) {
  final p = _parseAmount(text);
  if (p == null || p <= 0) return 'Must be > 0';
  return null;
}

/// Cancel / submit footer shared by the four forms.
Widget _cancelButton(BuildContext context, bool busy) => TextButton(
      key: WebKeys.billsDialogCancel,
      onPressed: busy ? null : () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    );

Widget _submitButton(
  BuildContext context, {
  required bool busy,
  required String label,
  required VoidCallback onPressed,
}) =>
    FilledButton(
      key: WebKeys.billsDialogSubmit,
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );

/// The "add an account in the app" hint shown when a form has neither
/// accounts nor categories to offer.
Widget _emptyPickersHint(BuildContext context, String text) => Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12.5,
          ),
    );

// ─── Bill ─────────────────────────────────────────────────────────────────────

/// Opens the Add (or, with [existing], Edit) Bill form.
Future<void> showWebBillDialog(
  BuildContext context, {
  required BillsReceivablesPresenter presenter,
  Bill? existing,
}) =>
    showWebDialog<void>(
      context,
      builder: (_) => _BillDialog(presenter: presenter, existing: existing),
    );

class _BillDialog extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final Bill? existing;

  const _BillDialog({required this.presenter, this.existing});

  @override
  State<_BillDialog> createState() => _BillDialogState();
}

class _BillDialogState extends State<_BillDialog> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _paymentNoteController = TextEditingController();

  String? _nameError;
  String? _amountError;

  late BillType _billType;
  int _dueDay = 1;
  String? _accountId;
  String? _categoryId;
  bool _isRecurring = false;
  RecurrenceType _recurrenceType = RecurrenceType.monthly;
  bool _reminderOn = false;
  int _reminderDays = 2;
  bool _isSubmitting = false;

  /// How far this save reaches across the months already generated ahead —
  /// mirrors the mobile sheet, defaulting to carrying forward.
  RecurringScope _scope = RecurringScope.thisAndFuture;

  /// Later months the scope switch would touch, resolved once (Rule 1).
  late final int _futureMonthCount;

  /// Lead times offered for the due-date reminder, matching the mobile sheet.
  static const _reminderDayOptions = [1, 2, 3, 5, 7];

  bool get _wasRecurring => widget.existing?.isRecurring ?? false;
  bool get _dropsFutureMonths => !_isRecurring && _wasRecurring;
  bool get _showScopeField =>
      (_isRecurring || _wasRecurring) && _futureMonthCount > 0;
  bool get _applyToFuture =>
      _showScopeField && _scope == RecurringScope.thisAndFuture;

  List<FinanceCategory> get _expenseCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.expense)
      .toList();

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _billType = b?.billType ?? BillType.other;
    if (b != null) {
      _nameController.text = b.name;
      _amountController.text = _amountText(b.amount);
      _dueDay = b.dueDay;
      _accountId = b.accountId;
      _categoryId = b.categoryId.isEmpty ? null : b.categoryId;
      // Hide the internal auto-statement marker — it is not a user-facing
      // note (mirrors the mobile sheet).
      _paymentNoteController.text =
          b.isAutoStatement ? '' : (b.paymentNote ?? '');
      _isRecurring = b.isRecurring;
      _recurrenceType = b.recurrenceType ?? RecurrenceType.monthly;
      _reminderOn = b.reminderDaysBefore != null;
      _reminderDays = b.reminderDaysBefore ?? 2;
    }
    _futureMonthCount = widget.presenter.futureBillReach(
      month: b?.month ?? widget.presenter.selectedMonth,
      existing: b,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _paymentNoteController.dispose();
    super.dispose();
  }

  /// Resolves the note to persist (mirrors the mobile sheet). A user-typed
  /// note wins; otherwise the auto-statement marker we hid from the field is
  /// re-applied, so editing an auto-generated statement doesn't strip its
  /// flag. On an edit, a cleared field persists as empty rather than null —
  /// `copyWith` reads null as "leave unchanged".
  String? _resolvePaymentNote() {
    final typed = _paymentNoteController.text.trim();
    if (typed.isNotEmpty) return typed;
    if (widget.existing?.isAutoStatement ?? false) {
      return Bill.autoStatementNote;
    }
    return widget.existing == null ? null : '';
  }

  bool _validate() {
    setState(() {
      _nameError = _nameController.text.trim().isEmpty ? 'Enter a name' : null;
      _amountError = _validateAmount(_amountController.text);
    });
    return _nameError == null && _amountError == null;
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = _parseAmount(_amountController.text)!;
      final existing = widget.existing;
      if (existing == null) {
        final bill = Bill(
          id: _newId(),
          name: _nameController.text.trim(),
          billType: _billType,
          amount: amount,
          dueDay: _dueDay,
          month: widget.presenter.selectedMonth,
          categoryId: _categoryId ?? '',
          accountId: _accountId,
          paymentNote: _resolvePaymentNote(),
          isRecurring: _isRecurring,
          recurrenceType: _isRecurring ? _recurrenceType : null,
          reminderDaysBefore: _reminderOn ? _reminderDays : null,
        );
        await widget.presenter.addBill(bill, applyToFuture: _applyToFuture);
      } else {
        // Edit in place — copyWith preserves fields the form doesn't expose
        // (paid state, linked transaction).
        await widget.presenter.updateBill(
          existing.copyWith(
            name: _nameController.text.trim(),
            billType: _billType,
            amount: amount,
            dueDay: _dueDay,
            categoryId: _categoryId ?? '',
            accountId: _accountId,
            paymentNote: _resolvePaymentNote(),
            isRecurring: _isRecurring,
            recurrenceType: _isRecurring ? _recurrenceType : null,
            // Passed explicitly on every save so the reminder can be switched
            // off here, not only on the phone.
            reminderDaysBefore: _reminderOn ? _reminderDays : null,
          ),
          applyToFuture: _applyToFuture,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save bill: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts =
        widget.presenter.accounts.where((a) => a.isActive).toList();
    final categories = _expenseCategories;
    final isEdit = widget.existing != null;
    final busy = _isSubmitting;

    return WebDialog(
      title: isEdit ? 'Edit bill' : 'Add bill',
      onSubmit: _submit,
      subtitle: 'Something you pay on a date.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WebField(
            label: 'Name',
            error: _nameError,
            child: WebInput(
              key: WebKeys.billsFormName,
              controller: _nameController,
              autofocus: true,
              hint: 'Electricity',
              enabled: !busy,
              error: _nameError != null,
              textInputAction: TextInputAction.next,
              onChanged: (_) =>
                  _nameError == null ? null : setState(() => _nameError = null),
            ),
          ),
          _gap,
          WebField(
            label: 'Type',
            child: WebDropdown<BillType>(
              key: WebKeys.billsFormType,
              value: _billType,
              items: [
                for (final t in BillType.values)
                  DropdownMenuItem(value: t, child: Text(billTypeFormLabel(t))),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() => _billType = v ?? _billType),
            ),
          ),
          _gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: WebField(
                  label: 'Amount',
                  error: _amountError,
                  child: WebInput.amount(
                    key: WebKeys.billsFormAmount,
                    controller: _amountController,
                    enabled: !busy,
                    error: _amountError != null,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _amountError == null
                        ? null
                        : setState(() => _amountError = null),
                  ),
                ),
              ),
              const SizedBox(width: WebInsets.md),
              Expanded(
                flex: 2,
                child: WebField(
                  label: 'Due day',
                  child: WebDropdown<int>(
                    key: WebKeys.billsFormDueDay,
                    value: _dueDay,
                    items: [
                      for (var d = 1; d <= 31; d++)
                        DropdownMenuItem(value: d, child: Text(ordinalDay(d))),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() => _dueDay = v ?? _dueDay),
                  ),
                ),
              ),
            ],
          ),
          if (accounts.isNotEmpty) ...[
            _gap,
            WebField(
              label: 'Pay from',
              optional: true,
              child: WebDropdown<String>(
                key: WebKeys.billsFormAccount,
                // A stored account that is no longer active would assert.
                value:
                    accounts.any((a) => a.id == _accountId) ? _accountId : null,
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('None')),
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: busy ? null : (v) => setState(() => _accountId = v),
              ),
            ),
          ],
          if (categories.isNotEmpty) ...[
            _gap,
            WebField(
              label: 'Category',
              optional: true,
              child: WebDropdown<String>(
                key: WebKeys.billsFormCategory,
                value: categories.any((c) => c.id == _categoryId)
                    ? _categoryId
                    : null,
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('None')),
                  for (final c in categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: busy ? null : (v) => setState(() => _categoryId = v),
              ),
            ),
          ],
          _gap,
          WebSwitchRow(
            key: WebKeys.billsFormRepeats,
            title: _isRecurring
                ? 'Repeats ${recurrenceLabel(_recurrenceType).toLowerCase()}'
                : 'Repeats',
            subtitle: "Next month's bill is created when this one is paid",
            value: _isRecurring,
            // Carrying an edit forward is the helpful default; carrying a
            // *deletion* forward is not, so switching recurrence off leaves
            // the scope opt-in (mirrors the mobile sheet).
            onChanged: busy
                ? null
                : (v) => setState(() {
                      _isRecurring = v;
                      _scope = v
                          ? RecurringScope.thisAndFuture
                          : RecurringScope.thisMonthOnly;
                    }),
          ),
          if (_showScopeField) ...[
            _gap,
            RecurringScopeField(
              key: WebKeys.billsFormScope,
              futureMonthCount: _futureMonthCount,
              month: widget.existing?.month ?? widget.presenter.selectedMonth,
              value: _scope,
              noun: 'amount',
              removesFutureMonths: _dropsFutureMonths,
              onChanged: (s) => setState(() => _scope = s),
            ),
          ],
          _gap,
          WebSwitchRow(
            key: WebKeys.billsFormReminder,
            title: 'Remind me before it is due',
            subtitle: _reminderOn
                ? '${_reminderDays == 1 ? '1 day' : '$_reminderDays days'} before'
                : 'A notification before the due date',
            value: _reminderOn,
            onChanged: busy ? null : (v) => setState(() => _reminderOn = v),
          ),
          if (_reminderOn) ...[
            const SizedBox(height: WebInsets.sm),
            WebChips<int>(
              key: WebKeys.billsFormReminderDays,
              options: [
                for (final d in _reminderDayOptions) WebChipOption(d, '$d d'),
              ],
              value: _reminderDays,
              onChanged: (d) => setState(() => _reminderDays = d),
            ),
          ],
          _gap,
          WebMoreOptions(
            key: WebKeys.billsDialogMoreOptions,
            hint: _isRecurring ? 'payment note, recurrence' : 'payment note',
            initiallyOpen: isEdit &&
                (_paymentNoteController.text.isNotEmpty ||
                    (_isRecurring &&
                        _recurrenceType != RecurrenceType.monthly)),
            children: [
              WebField(
                label: 'Payment note',
                optional: true,
                child: WebInput(
                  key: WebKeys.billsFormNote,
                  controller: _paymentNoteController,
                  hint: 'Account number, reference…',
                  enabled: !busy,
                  textInputAction: TextInputAction.done,
                ),
              ),
              if (_isRecurring)
                WebField(
                  label: 'Recurrence',
                  child: WebDropdown<RecurrenceType>(
                    key: WebKeys.billsFormRecurrence,
                    value: _recurrenceType,
                    items: [
                      for (final r in RecurrenceType.values)
                        DropdownMenuItem(
                            value: r, child: Text(recurrenceLabel(r))),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(
                            () => _recurrenceType = v ?? _recurrenceType),
                  ),
                ),
            ],
          ),
          if (accounts.isEmpty && categories.isEmpty) ...[
            _gap,
            _emptyPickersHint(context,
                'Add an account or category in the app for richer bills.'),
          ],
        ],
      ),
      secondary: _cancelButton(context, busy),
      primary: _submitButton(
        context,
        busy: busy,
        label: isEdit ? 'Save' : 'Add bill',
        onPressed: _submit,
      ),
    );
  }
}

// ─── Receivable ───────────────────────────────────────────────────────────────

/// Opens the Add (or, with [existing], Edit) Receivable form.
Future<void> showWebReceivableDialog(
  BuildContext context, {
  required BillsReceivablesPresenter presenter,
  Receivable? existing,
}) =>
    showWebDialog<void>(
      context,
      builder: (_) =>
          _ReceivableDialog(presenter: presenter, existing: existing),
    );

class _ReceivableDialog extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final Receivable? existing;

  const _ReceivableDialog({required this.presenter, this.existing});

  @override
  State<_ReceivableDialog> createState() => _ReceivableDialogState();
}

class _ReceivableDialogState extends State<_ReceivableDialog> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  String? _nameError;
  String? _amountError;

  late DateTime _expectedDate;
  late ReceivableType _type;
  String? _accountId;
  String? _categoryId;
  bool _isRecurring = false;
  RecurrenceType _recurrenceType = RecurrenceType.monthly;
  bool _isSubmitting = false;

  RecurringScope _scope = RecurringScope.thisAndFuture;
  late final int _futureMonthCount;

  bool get _wasRecurring => widget.existing?.isRecurring ?? false;
  bool get _dropsFutureMonths => !_isRecurring && _wasRecurring;
  bool get _showScopeField =>
      (_isRecurring || _wasRecurring) && _futureMonthCount > 0;
  bool get _applyToFuture =>
      _showScopeField && _scope == RecurringScope.thisAndFuture;

  List<FinanceCategory> get _incomeCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.income)
      .toList();

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _type = r?.receivableType ?? ReceivableType.salary;
    // A new receivable starts on today's date rather than in the month being
    // browsed, matching the mobile sheet.
    _expectedDate = r?.expectedDate ?? DateTime.now();
    if (r != null) {
      _nameController.text = r.name;
      _amountController.text = _amountText(r.amount);
      _accountId = r.accountId;
      _categoryId = r.categoryId.isEmpty ? null : r.categoryId;
      _isRecurring = r.isRecurring;
      _recurrenceType = r.recurrenceType ?? RecurrenceType.monthly;
    }
    _futureMonthCount = widget.presenter.futureReceivableReach(
      month: r?.month ?? widget.presenter.selectedMonth,
      existing: r,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _nameError = _nameController.text.trim().isEmpty ? 'Enter a name' : null;
      _amountError = _validateAmount(_amountController.text);
    });
    return _nameError == null && _amountError == null;
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = _parseAmount(_amountController.text)!;
      final existing = widget.existing;
      // Day only — a stored time of day is invisible on the card yet used to
      // order same-day entries, same as the mobile sheet.
      final expected = DateUtils.dateOnly(_expectedDate);
      if (existing == null) {
        await widget.presenter.addReceivable(
          Receivable(
            id: _newId(),
            name: _nameController.text.trim(),
            receivableType: _type,
            amount: amount,
            expectedDate: expected,
            month: widget.presenter.selectedMonth,
            categoryId: _categoryId ?? '',
            accountId: _accountId,
            isRecurring: _isRecurring,
            recurrenceType: _isRecurring ? _recurrenceType : null,
          ),
          applyToFuture: _applyToFuture,
        );
      } else {
        await widget.presenter.updateReceivable(
          existing.copyWith(
            name: _nameController.text.trim(),
            receivableType: _type,
            amount: amount,
            expectedDate: expected,
            categoryId: _categoryId ?? '',
            accountId: _accountId,
            isRecurring: _isRecurring,
            recurrenceType: _isRecurring ? _recurrenceType : null,
          ),
          applyToFuture: _applyToFuture,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save receivable: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same eligible set as the settle step, so a saved default can never be an
    // account mark-received would reject.
    final accounts = widget.presenter.depositAccountsFor(widget.existing);
    final categories = _incomeCategories;
    final isEdit = widget.existing != null;
    final busy = _isSubmitting;

    return WebDialog(
      title: isEdit ? 'Edit receivable' : 'Add receivable',
      onSubmit: _submit,
      subtitle: 'Money someone owes you.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WebField(
            label: 'Name',
            error: _nameError,
            child: WebInput(
              key: WebKeys.billsFormName,
              controller: _nameController,
              autofocus: true,
              hint: 'Who owes you, and for what',
              enabled: !busy,
              error: _nameError != null,
              textInputAction: TextInputAction.next,
              onChanged: (_) =>
                  _nameError == null ? null : setState(() => _nameError = null),
            ),
          ),
          _gap,
          WebField(
            label: 'Type',
            child: WebDropdown<ReceivableType>(
              key: WebKeys.billsFormType,
              value: _type,
              items: [
                for (final t in ReceivableType.values)
                  DropdownMenuItem(
                      value: t, child: Text(receivableTypeLabel(t))),
              ],
              onChanged:
                  busy ? null : (v) => setState(() => _type = v ?? _type),
            ),
          ),
          _gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: WebField(
                  label: 'Amount',
                  error: _amountError,
                  child: WebInput.amount(
                    key: WebKeys.billsFormAmount,
                    controller: _amountController,
                    enabled: !busy,
                    error: _amountError != null,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _amountError == null
                        ? null
                        : setState(() => _amountError = null),
                  ),
                ),
              ),
              const SizedBox(width: WebInsets.md),
              Expanded(
                flex: 2,
                child: WebField(
                  label: 'Expected on',
                  child: WebDateButton(
                    key: WebKeys.billsFormDate,
                    value: _expectedDate,
                    onChanged:
                        busy ? null : (d) => setState(() => _expectedDate = d),
                  ),
                ),
              ),
            ],
          ),
          if (accounts.isNotEmpty) ...[
            _gap,
            WebField(
              label: 'Deposit into',
              optional: true,
              child: WebDropdown<String>(
                key: WebKeys.billsFormAccount,
                value:
                    accounts.any((a) => a.id == _accountId) ? _accountId : null,
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('None')),
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: busy ? null : (v) => setState(() => _accountId = v),
              ),
            ),
          ],
          if (categories.isNotEmpty) ...[
            _gap,
            WebField(
              label: 'Category',
              optional: true,
              child: WebDropdown<String>(
                key: WebKeys.billsFormCategory,
                value: categories.any((c) => c.id == _categoryId)
                    ? _categoryId
                    : null,
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('None')),
                  for (final c in categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: busy ? null : (v) => setState(() => _categoryId = v),
              ),
            ),
          ],
          _gap,
          WebSwitchRow(
            key: WebKeys.billsFormRepeats,
            title: _isRecurring
                ? 'Repeats ${recurrenceLabel(_recurrenceType).toLowerCase()}'
                : 'Repeats',
            subtitle: 'The next one is created when this one is received',
            value: _isRecurring,
            onChanged: busy
                ? null
                : (v) => setState(() {
                      _isRecurring = v;
                      _scope = v
                          ? RecurringScope.thisAndFuture
                          : RecurringScope.thisMonthOnly;
                    }),
          ),
          if (_showScopeField) ...[
            _gap,
            RecurringScopeField(
              key: WebKeys.billsFormScope,
              futureMonthCount: _futureMonthCount,
              month: widget.existing?.month ?? widget.presenter.selectedMonth,
              value: _scope,
              noun: 'amount',
              removesFutureMonths: _dropsFutureMonths,
              onChanged: (s) => setState(() => _scope = s),
            ),
          ],
          if (_isRecurring) ...[
            _gap,
            WebMoreOptions(
              key: WebKeys.billsDialogMoreOptions,
              hint: 'recurrence',
              initiallyOpen:
                  isEdit && _recurrenceType != RecurrenceType.monthly,
              children: [
                WebField(
                  label: 'Recurrence',
                  child: WebDropdown<RecurrenceType>(
                    key: WebKeys.billsFormRecurrence,
                    value: _recurrenceType,
                    items: [
                      for (final r in RecurrenceType.values)
                        DropdownMenuItem(
                            value: r, child: Text(recurrenceLabel(r))),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(
                            () => _recurrenceType = v ?? _recurrenceType),
                  ),
                ),
              ],
            ),
          ],
          if (accounts.isEmpty && categories.isEmpty) ...[
            _gap,
            _emptyPickersHint(
                context,
                'Add an account or income category in the app for richer '
                'receivables.'),
          ],
        ],
      ),
      secondary: _cancelButton(context, busy),
      primary: _submitButton(
        context,
        busy: busy,
        label: isEdit ? 'Save' : 'Add receivable',
        onPressed: _submit,
      ),
    );
  }
}

// ─── Set-aside ────────────────────────────────────────────────────────────────

/// Opens the Add (or, with [existing], Edit) Set-aside form.
Future<void> showWebSetAsideDialog(
  BuildContext context, {
  required BillsReceivablesPresenter presenter,
  BudgetedExpense? existing,
}) =>
    showWebDialog<void>(
      context,
      builder: (_) => _SetAsideDialog(presenter: presenter, existing: existing),
    );

class _SetAsideDialog extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final BudgetedExpense? existing;

  const _SetAsideDialog({required this.presenter, this.existing});

  @override
  State<_SetAsideDialog> createState() => _SetAsideDialogState();
}

class _SetAsideDialogState extends State<_SetAsideDialog> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String? _nameError;
  String? _amountError;

  late SetAsideType _type;
  String? _categoryId;
  String? _accountId;
  String? _destinationId;
  bool _isRecurring = false;
  RecurrenceType _recurrenceType = RecurrenceType.monthly;
  bool _isSubmitting = false;

  RecurringScope _scope = RecurringScope.thisAndFuture;
  late final int _futureMonthCount;

  bool get _wasRecurring => widget.existing?.isRecurring ?? false;
  bool get _dropsFutureMonths => !_isRecurring && _wasRecurring;
  bool get _showScopeField =>
      (_isRecurring || _wasRecurring) && _futureMonthCount > 0;
  bool get _applyToFuture =>
      _showScopeField && _scope == RecurringScope.thisAndFuture;

  List<FinanceCategory> get _expenseCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.expense)
      .toList();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.budgetedType ?? SetAsideType.other;
    if (e != null) {
      _nameController.text = e.name;
      _amountController.text = _amountText(e.allocatedAmount);
      _noteController.text = e.note ?? '';
      _categoryId = e.categoryId.isEmpty ? null : e.categoryId;
      _accountId = e.accountId;
      _destinationId = e.destinationAccountId;
      _isRecurring = e.isRecurring;
      _recurrenceType = e.recurrenceType ?? RecurrenceType.monthly;
    }
    _futureMonthCount = widget.presenter.futureExpenseReach(
      month: e?.month ?? widget.presenter.selectedMonth,
      existing: e,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _nameError = _nameController.text.trim().isEmpty ? 'Enter a name' : null;
      _amountError = _validateAmount(_amountController.text);
    });
    return _nameError == null && _amountError == null;
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = _parseAmount(_amountController.text)!;
      final note = _noteController.text.trim();
      final existing = widget.existing;
      if (existing == null) {
        await widget.presenter.addBudgetedExpense(
          BudgetedExpense(
            id: _newId(),
            name: _nameController.text.trim(),
            budgetedType: _type,
            month: widget.presenter.selectedMonth,
            allocatedAmount: amount,
            categoryId: _categoryId ?? '',
            note: note.isEmpty ? null : note,
            accountId: _accountId,
            destinationAccountId: _destinationId,
            isRecurring: _isRecurring,
            recurrenceType: _isRecurring ? _recurrenceType : null,
          ),
          applyToFuture: _applyToFuture,
        );
      } else {
        await widget.presenter.updateBudgetedExpense(
          existing.copyWith(
            name: _nameController.text.trim(),
            budgetedType: _type,
            allocatedAmount: amount,
            categoryId: _categoryId ?? '',
            note: note.isEmpty ? null : note,
            accountId: _accountId,
            destinationAccountId: _destinationId,
            isRecurring: _isRecurring,
            recurrenceType: _isRecurring ? _recurrenceType : null,
          ),
          applyToFuture: _applyToFuture,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save set-aside: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _expenseCategories;
    // Set-asides are funded out of spendable cash, so only offer liquid
    // accounts — funding debits one of these (mirrors the mark-funded flow).
    final liquidAccounts = widget.presenter.setAsideFundingAccounts;
    final destinationAccounts = widget.presenter.setAsideDestinationAccounts
        .where((a) => a.id != _accountId)
        .toList();
    final isEdit = widget.existing != null;
    final busy = _isSubmitting;

    return WebDialog(
      title: isEdit ? 'Edit set-aside' : 'Add set-aside',
      onSubmit: _submit,
      subtitle: 'A planned amount to move into a fund this month.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WebField(
            label: 'Name',
            error: _nameError,
            child: WebInput(
              key: WebKeys.billsFormName,
              controller: _nameController,
              autofocus: true,
              hint: 'Travel Fund, Tanel Birthday…',
              enabled: !busy,
              error: _nameError != null,
              textInputAction: TextInputAction.next,
              onChanged: (_) =>
                  _nameError == null ? null : setState(() => _nameError = null),
            ),
          ),
          _gap,
          WebField(
            label: 'Type',
            child: WebDropdown<SetAsideType>(
              key: WebKeys.billsFormType,
              value: _type,
              items: [
                for (final t in SetAsideType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged:
                  busy ? null : (v) => setState(() => _type = v ?? _type),
            ),
          ),
          _gap,
          WebField(
            label: 'Amount',
            error: _amountError,
            child: WebInput.amount(
              key: WebKeys.billsFormAmount,
              controller: _amountController,
              enabled: !busy,
              error: _amountError != null,
              textInputAction: TextInputAction.done,
              onChanged: (_) => _amountError == null
                  ? null
                  : setState(() => _amountError = null),
            ),
          ),
          if (destinationAccounts.isNotEmpty) ...[
            _gap,
            WebField(
              label: 'Set aside into',
              // Naming it here decides "₱5,000 from BPI to Maya" once; leaving
              // it blank means the funding dialog asks.
              helper: _destinationId == null
                  ? 'Leave it blank and Fund will ask where it goes'
                  : null,
              child: WebDropdown<String>(
                key: ValueKey(
                    '${WebKeys.billsFormDestination.value}:$_accountId'),
                value: destinationAccounts.any((a) => a.id == _destinationId)
                    ? _destinationId
                    : null,
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('Decide when funding')),
                  for (final a in destinationAccounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged:
                    busy ? null : (v) => setState(() => _destinationId = v),
              ),
            ),
          ],
          if (liquidAccounts.isNotEmpty) ...[
            _gap,
            WebField(
              label: 'Fund from',
              optional: true,
              child: WebDropdown<String>(
                key: WebKeys.billsFormAccount,
                value: liquidAccounts.any((a) => a.id == _accountId)
                    ? _accountId
                    : null,
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('None')),
                  for (final a in liquidAccounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                          _accountId = v;
                          // The source can't also be the destination.
                          if (_destinationId == v) _destinationId = null;
                        }),
              ),
            ),
          ],
          if (categories.isNotEmpty) ...[
            _gap,
            WebField(
              label: 'Category',
              optional: true,
              child: WebDropdown<String>(
                key: WebKeys.billsFormCategory,
                value: categories.any((c) => c.id == _categoryId)
                    ? _categoryId
                    : null,
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('None')),
                  for (final c in categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: busy ? null : (v) => setState(() => _categoryId = v),
              ),
            ),
          ],
          _gap,
          WebSwitchRow(
            key: WebKeys.billsFormRepeats,
            title: _isRecurring
                ? 'Repeats ${recurrenceLabel(_recurrenceType).toLowerCase()}'
                : 'Repeats',
            subtitle: 'Shows in Budget as a Savings row',
            value: _isRecurring,
            onChanged: busy
                ? null
                : (v) => setState(() {
                      _isRecurring = v;
                      _scope = v
                          ? RecurringScope.thisAndFuture
                          : RecurringScope.thisMonthOnly;
                    }),
          ),
          if (_showScopeField) ...[
            _gap,
            RecurringScopeField(
              key: WebKeys.billsFormScope,
              futureMonthCount: _futureMonthCount,
              month: widget.existing?.month ?? widget.presenter.selectedMonth,
              value: _scope,
              noun: 'allocation',
              removesFutureMonths: _dropsFutureMonths,
              onChanged: (s) => setState(() => _scope = s),
            ),
          ],
          _gap,
          WebMoreOptions(
            key: WebKeys.billsDialogMoreOptions,
            hint: _isRecurring ? 'note, recurrence' : 'note',
            initiallyOpen: isEdit && _noteController.text.isNotEmpty,
            children: [
              WebField(
                label: 'Note',
                optional: true,
                child: WebInput(
                  key: WebKeys.billsFormNote,
                  controller: _noteController,
                  hint: 'Maya Savings',
                  enabled: !busy,
                  textInputAction: TextInputAction.done,
                ),
              ),
              if (_isRecurring)
                WebField(
                  label: 'Recurrence',
                  child: WebDropdown<RecurrenceType>(
                    key: WebKeys.billsFormRecurrence,
                    value: _recurrenceType,
                    items: [
                      for (final r in RecurrenceType.values)
                        DropdownMenuItem(
                            value: r, child: Text(recurrenceLabel(r))),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(
                            () => _recurrenceType = v ?? _recurrenceType),
                  ),
                ),
            ],
          ),
          _gap,
          _emptyPickersHint(
              context,
              'Funding a set-aside later debits a liquid account — the money '
              'leaves your spendable cash.'),
        ],
      ),
      secondary: _cancelButton(context, busy),
      primary: _submitButton(
        context,
        busy: busy,
        label: isEdit ? 'Save' : 'Add set-aside',
        onPressed: _submit,
      ),
    );
  }
}

// ─── Installment ──────────────────────────────────────────────────────────────

/// Opens the Add (or, with [existing], Edit) Installment form.
Future<void> showWebInstallmentDialog(
  BuildContext context, {
  required InstallmentPresenter presenter,
  Installment? existing,
}) =>
    showWebDialog<void>(
      context,
      builder: (_) =>
          _InstallmentDialog(presenter: presenter, existing: existing),
    );

class _InstallmentDialog extends StatefulWidget {
  final InstallmentPresenter presenter;
  final Installment? existing;

  const _InstallmentDialog({required this.presenter, this.existing});

  @override
  State<_InstallmentDialog> createState() => _InstallmentDialogState();
}

class _InstallmentDialogState extends State<_InstallmentDialog> {
  final _nameController = TextEditingController();
  final _totalController = TextEditingController();
  final _monthlyController = TextEditingController();
  final _noteController = TextEditingController();
  final _customMonthsController = TextEditingController();
  final _customRateController = TextEditingController();

  String? _nameError;
  String? _cardError;
  String? _totalError;
  String? _monthlyError;

  String? _accountId;
  int _totalMonths = 12;
  late String _startMonth;
  late DateTime _purchaseDate;
  int _deferralMonths = 0;
  double _interestRate = 0.0;
  bool _monthlyManuallyEdited = false;
  bool _customMonthsOpen = false;
  bool _customRateOpen = false;

  /// True once the start-month stepper was used in THIS session. Until then
  /// the start month follows account / purchase date / deferral — on edit
  /// too, so changing the deferral saves the month the hint shows.
  bool _startMonthTouched = false;
  bool _isSubmitting = false;

  static const _monthPresets = [3, 6, 12, 24, 36];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _startMonth = e?.startMonth ?? widget.presenter.selectedMonth;
    if (e != null) {
      _nameController.text = e.name;
      _totalController.text = _trim(e.totalAmount);
      _monthlyController.text = _trim(e.monthlyAmount);
      _noteController.text = e.note ?? '';
      _accountId = e.accountId;
      _totalMonths = e.totalMonths;
      _purchaseDate = e.purchaseDate ??
          DateTime.tryParse('${e.startMonth}-01') ??
          DateTime.now();
      _deferralMonths = e.deferralMonths;
      _interestRate = e.interestRate;
      _monthlyManuallyEdited = true;
      _customMonthsOpen = !_monthPresets.contains(e.totalMonths);
      _customRateOpen = !InstallmentPresenter.isPresetRate(e.interestRate);
      if (_customMonthsOpen) _customMonthsController.text = '${e.totalMonths}';
      if (_customRateOpen) {
        _customRateController.text =
            InstallmentPresenter.rateText(e.interestRate);
      }
    } else {
      _purchaseDate = DateTime.now();
      final accounts = widget.presenter.creditAccounts;
      if (accounts.isNotEmpty) _accountId = accounts.first.id;
      _recalculateStartMonth();
    }
    _totalController.addListener(_recomputeMonthly);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _totalController.dispose();
    _monthlyController.dispose();
    _noteController.dispose();
    _customMonthsController.dispose();
    _customRateController.dispose();
    super.dispose();
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

  void _recalculateStartMonth() {
    if (_startMonthTouched) return;
    _startMonth = widget.presenter.suggestedStartMonth(
      accountId: _accountId,
      purchaseDate: _purchaseDate,
      deferralMonths: _deferralMonths,
    );
  }

  void _recomputeMonthly() {
    // Rebuild either way: the summary line reads the total.
    setState(() {
      _totalError = null;
      if (_monthlyManuallyEdited) return;
      final total = _parseAmount(_totalController.text);
      if (total != null && _totalMonths > 0) {
        final monthly = Installment.computeMonthlyAmount(
          principal: total,
          months: _totalMonths,
          monthlyRate: _interestRate,
        );
        _monthlyController.text = _trim(monthly);
        _monthlyError = null;
      }
    });
  }

  void _onMonthsChanged(int months) {
    setState(() {
      _totalMonths = months;
      _monthlyManuallyEdited = false;
    });
    _recomputeMonthly();
  }

  void _onInterestRateChanged(double rate) {
    setState(() {
      _interestRate = rate;
      _monthlyManuallyEdited = false;
    });
    _recomputeMonthly();
  }

  void _adjustStartMonth(int delta) {
    final date = DateTime.parse('$_startMonth-01');
    setState(() {
      _startMonth = toMonthKey(DateTime(date.year, date.month + delta));
      _startMonthTouched = true;
    });
  }

  /// "Nov 2027" — the month of the last payment, from the start and the count.
  String get _endMonthLabel {
    final start = DateTime.parse('$_startMonth-01');
    final end = DateTime(start.year, start.month + _totalMonths - 1);
    return monthLabel(toMonthKey(end));
  }

  InstallmentInterestPreview? get _interestPreview =>
      widget.presenter.interestPreview(
        principal: _parseAmount(_totalController.text),
        months: _totalMonths,
        rate: _interestRate,
        monthlyAmount: _parseAmount(_monthlyController.text),
      );

  bool _validate() {
    setState(() {
      _nameError = _nameController.text.trim().isEmpty ? 'Enter a name' : null;
      _cardError = _accountId == null ? 'Select an account' : null;
      _totalError = _validateAmount(_totalController.text);
      _monthlyError = _validateAmount(_monthlyController.text);
    });
    return _nameError == null &&
        _cardError == null &&
        _totalError == null &&
        _monthlyError == null;
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final existing = widget.existing;
      // No category picker here: buildInstallment keeps the existing one.
      final installment = widget.presenter.buildInstallment(
        existing: existing,
        name: _nameController.text,
        accountId: _accountId!,
        totalAmount: _parseAmount(_totalController.text)!,
        monthlyAmount: _parseAmount(_monthlyController.text)!,
        totalMonths: _totalMonths,
        startMonth: _startMonth,
        purchaseDate: _purchaseDate,
        deferralMonths: _deferralMonths,
        interestRate: _interestRate,
        note: _noteController.text,
      );
      await widget.presenter
          .saveInstallment(installment, isEdit: existing != null);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save installment: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final creditAccounts = widget.presenter.creditAccounts;
    final accounts = [
      ...creditAccounts,
      if (_accountId != null && !creditAccounts.any((a) => a.id == _accountId))
        ...widget.presenter.accounts.where((a) => a.id == _accountId),
    ];
    final isEdit = widget.existing != null;
    final busy = _isSubmitting;
    final monthly = _parseAmount(_monthlyController.text);
    final preview = _interestPreview;
    final cycleHint = widget.presenter.cycleHint(
      accountId: _accountId,
      purchaseDate: _purchaseDate,
      deferralMonths: _deferralMonths,
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontSize: 12.5,
      height: 1.4,
    );

    return WebDialog(
      title: isEdit ? 'Edit installment' : 'Add installment',
      onSubmit: _submit,
      subtitle: 'A purchase paid over several card statements.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WebField(
            label: 'Name',
            error: _nameError,
            child: WebInput(
              key: WebKeys.billsFormName,
              controller: _nameController,
              autofocus: true,
              hint: 'MacBook Pro, Braces…',
              enabled: !busy,
              error: _nameError != null,
              textInputAction: TextInputAction.next,
              onChanged: (_) =>
                  _nameError == null ? null : setState(() => _nameError = null),
            ),
          ),
          _gap,
          WebField(
            label: 'Card',
            error: _cardError ??
                (accounts.isEmpty
                    ? 'Add a credit card, credit line, or BNPL account before '
                        'creating installments.'
                    : null),
            child: WebDropdown<String>(
              key: WebKeys.billsFormCard,
              value:
                  accounts.any((a) => a.id == _accountId) ? _accountId : null,
              hint: 'Credit card, credit line or BNPL',
              error: _cardError != null,
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: busy || accounts.isEmpty
                  ? null
                  : (v) => setState(() {
                        _accountId = v;
                        _cardError = null;
                        _recalculateStartMonth();
                      }),
            ),
          ),
          _gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: WebField(
                  label: 'Total amount',
                  error: _totalError,
                  child: WebInput.amount(
                    key: WebKeys.billsFormTotal,
                    controller: _totalController,
                    enabled: !busy,
                    error: _totalError != null,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ),
              const SizedBox(width: WebInsets.md),
              Expanded(
                flex: 2,
                child: WebField(
                  label: 'First statement',
                  child: _MonthStepperField(
                    key: WebKeys.billsFormStartMonth,
                    label: monthLabel(_startMonth),
                    onPrev: busy ? null : () => _adjustStartMonth(-1),
                    onNext: busy ? null : () => _adjustStartMonth(1),
                  ),
                ),
              ),
            ],
          ),
          _gap,
          WebField(
            label: 'Months',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                WebChips<int>(
                  key: WebKeys.billsFormMonths,
                  options: [
                    for (final m in _monthPresets) WebChipOption(m, '$m'),
                  ],
                  value: _totalMonths,
                  onChanged: (m) {
                    setState(() => _customMonthsOpen = false);
                    _onMonthsChanged(m);
                  },
                  allowCustom: true,
                  customLabel: 'Custom',
                  onCustom: () => setState(() => _customMonthsOpen = true),
                ),
                if (_customMonthsOpen) ...[
                  const SizedBox(height: WebInsets.sm),
                  SizedBox(
                    width: 120,
                    child: WebInput(
                      controller: _customMonthsController,
                      hint: 'Months',
                      autofocus: true,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final parsed = int.tryParse(v);
                        if (parsed != null && parsed > 0) {
                          _onMonthsChanged(parsed);
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          _gap,
          WebField(
            label: 'Interest / month',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                WebChips<double>(
                  key: WebKeys.billsFormInterest,
                  options: [
                    for (final r in InstallmentPresenter.ratePresets)
                      WebChipOption(r, InstallmentPresenter.ratePresetLabel(r)),
                  ],
                  value: _interestRate,
                  onChanged: (r) {
                    setState(() {
                      _customRateOpen = false;
                      _customRateController.clear();
                    });
                    _onInterestRateChanged(r);
                  },
                  allowCustom: true,
                  customLabel: 'Custom',
                  onCustom: () => setState(() => _customRateOpen = true),
                ),
                if (_customRateOpen) ...[
                  const SizedBox(height: WebInsets.sm),
                  SizedBox(
                    width: 120,
                    child: WebInput(
                      controller: _customRateController,
                      hint: '% / month',
                      autofocus: true,
                      enabled: !busy,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null && parsed >= 0) {
                          _onInterestRateChanged(parsed);
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (monthly != null && monthly > 0) ...[
            _gap,
            Text(
              '${formatPeso(monthly)} / month × $_totalMonths · ends '
              '$_endMonthLabel'
              '${preview != null ? '\n${preview.label}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ],
          _gap,
          WebField(
            label: 'Monthly payment',
            helper: _monthlyManuallyEdited
                ? 'Edited by hand'
                : 'Worked out from the total, months and interest · editable',
            error: _monthlyError,
            child: WebInput.amount(
              key: WebKeys.billsFormMonthly,
              controller: _monthlyController,
              enabled: !busy,
              error: _monthlyError != null,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {
                _monthlyManuallyEdited = true;
                _monthlyError = null;
              }),
            ),
          ),
          _gap,
          WebMoreOptions(
            key: WebKeys.billsDialogMoreOptions,
            hint: 'purchase date, deferral, note',
            initiallyOpen: isEdit &&
                (_deferralMonths > 0 || _noteController.text.isNotEmpty),
            children: [
              WebField(
                label: 'Purchase date',
                child: WebDateButton(
                  key: WebKeys.billsFormPurchaseDate,
                  value: _purchaseDate,
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  onChanged: busy
                      ? null
                      : (d) => setState(() {
                            _purchaseDate = d;
                            _recalculateStartMonth();
                          }),
                ),
              ),
              WebField(
                label: 'Deferred first payment',
                optional: true,
                child: WebChips<int>(
                  key: WebKeys.billsFormDeferral,
                  options: const [
                    WebChipOption(0, 'None'),
                    WebChipOption(1, '1 mo'),
                    WebChipOption(2, '2 mo'),
                    WebChipOption(3, '3 mo'),
                  ],
                  value: _deferralMonths,
                  onChanged: (d) => setState(() {
                    _deferralMonths = d;
                    _recalculateStartMonth();
                  }),
                ),
              ),
              if (cycleHint != null) Text(cycleHint, style: muted),
              WebField(
                label: 'Note',
                optional: true,
                child: WebInput(
                  key: WebKeys.billsFormNote,
                  controller: _noteController,
                  hint: '0% interest',
                  enabled: !busy,
                  textInputAction: TextInputAction.done,
                ),
              ),
            ],
          ),
        ],
      ),
      secondary: _cancelButton(context, busy),
      primary: _submitButton(
        context,
        busy: busy,
        label: isEdit ? 'Save' : 'Add installment',
        onPressed: _submit,
      ),
    );
  }
}

/// `‹ Dec 2026 ›` in the kit's input frame — the installment's first statement
/// month. Pure UI; the dialog owns the month.
class _MonthStepperField extends StatelessWidget {
  final String label;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _MonthStepperField({
    super.key,
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      height: kWebInputHeight,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WebInput.textStyle(context)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: onNext,
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }
}

// ─── Recurring: which ones? ───────────────────────────────────────────────────

/// The two-option scope question for deleting a recurring bill, receivable or
/// set-aside (Forms canvas, "Recurring: which ones?"): only this month, or
/// this and future months. Both outcomes are named and neither is the button
/// a thumb lands on by reflex — a delete cannot be reviewed afterwards.
/// Returns null when the user backs out.
Future<RecurringScope?> showWebRecurringScopeDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String month,
  required String noun,
  String confirmLabel = 'Delete',
  bool plural = false,
}) {
  return showWebDialog<RecurringScope>(
    context,
    builder: (_) => _RecurringScopeDialog(
      title: title,
      subtitle: subtitle,
      month: month,
      noun: noun,
      confirmLabel: confirmLabel,
      plural: plural,
    ),
  );
}

class _RecurringScopeDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String month;
  final String noun;
  final String confirmLabel;
  final bool plural;

  const _RecurringScopeDialog({
    required this.title,
    required this.subtitle,
    required this.month,
    required this.noun,
    required this.confirmLabel,
    required this.plural,
  });

  @override
  State<_RecurringScopeDialog> createState() => _RecurringScopeDialogState();
}

class _RecurringScopeDialogState extends State<_RecurringScopeDialog> {
  RecurringScope _scope = RecurringScope.thisMonthOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final thisMonth = monthLabel(widget.month);
    final next = monthLabel(nextMonth(widget.month));
    final them = widget.plural ? 'They stay' : 'It stays';
    final series = widget.plural ? 'their series' : 'the series';

    return WebDialog(
      title: widget.title,
      subtitle: widget.subtitle,
      primaryExpands: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ScopeOption(
            key: WebKeys.billsScopeOnlyThisMonth,
            title: 'Only this month',
            subtitle:
                '$thisMonth stays deleted; $next is created as usual. Earlier '
                'months are left as they are.',
            selected: _scope == RecurringScope.thisMonthOnly,
            onTap: () => setState(() => _scope = RecurringScope.thisMonthOnly),
          ),
          const SizedBox(height: WebInsets.sm),
          _ScopeOption(
            key: WebKeys.billsScopeThisAndFuture,
            title: 'This and future months',
            subtitle: 'Stops $series from $thisMonth on. $them in the months '
                'already behind you.',
            selected: _scope == RecurringScope.thisAndFuture,
            onTap: () => setState(() => _scope = RecurringScope.thisAndFuture),
          ),
        ],
      ),
      secondary: TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      primary: FilledButton(
        key: WebKeys.billsScopeConfirm,
        style: FilledButton.styleFrom(
          backgroundColor: cs.error,
          foregroundColor: cs.onError,
        ),
        onPressed: () => Navigator.of(context).pop(_scope),
        child: Text(widget.confirmLabel),
      ),
    );
  }
}

class _ScopeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ScopeOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? cs.primary.withValues(alpha: 0.08)
            : theme.scaffoldBackgroundColor.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? cs.primary : cs.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kWebHitTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      size: 18,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: WebInsets.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks how far a delete of one row reaches — the v2 twin of the mobile
/// `confirmRecurringDelete`. A one-off with nothing ahead gets the plain
/// confirm; a recurring item gets the two-option scope dialog, even when no
/// later month exists yet (the series would otherwise re-create it).
Future<RecurringScope?> confirmWebRecurringDelete(
  BuildContext context, {
  required String noun,
  required String name,
  required String month,
  required int futureMonthCount,
  required bool isRecurring,
}) async {
  if (futureMonthCount == 0 && !isRecurring) {
    final ok = await showWebConfirm(
      context,
      title: 'Delete $name?',
      message: 'This removes the $noun from ${monthLabel(month)}. '
          'This cannot be undone.',
    );
    return ok ? RecurringScope.thisMonthOnly : null;
  }
  if (!context.mounted) return null;
  final ahead = futureMonthCount == 0
      ? ''
      : ' It is also set up in ${_laterMonths(futureMonthCount)}.';
  return showWebRecurringScopeDialog(
    context,
    title: 'Delete $name',
    subtitle: 'This $noun repeats every month.$ahead',
    month: month,
    noun: noun,
  );
}

/// The same question for a batch delete — the v2 twin of the mobile
/// `confirmRecurringBatchDelete`. Delegates to [confirmWebRecurringDelete]
/// for a single selection so the copy can name the item.
Future<RecurringScope?> confirmWebRecurringBatchDelete(
  BuildContext context, {
  required String noun,
  required String month,
  required int selectedCount,
  required int recurringCount,
  required int extraMonthCount,
  required String plainBody,
  String? soleName,
}) async {
  final title = 'Delete $selectedCount ${_pluralNoun(selectedCount, noun)}?';
  if (recurringCount == 0) {
    final ok = await showWebConfirm(context, title: title, message: plainBody);
    return ok ? RecurringScope.thisMonthOnly : null;
  }
  if (selectedCount == 1 && soleName != null) {
    return confirmWebRecurringDelete(
      context,
      noun: noun,
      name: soleName,
      month: month,
      futureMonthCount: extraMonthCount,
      isRecurring: true,
    );
  }
  final repeats = recurringCount == selectedCount
      ? (selectedCount == 2 ? 'Both repeat' : 'All $selectedCount repeat')
      : (recurringCount == 1
          ? '1 of them repeats'
          : '$recurringCount of them repeat');
  final ahead = extraMonthCount == 0
      ? ', so they will keep coming back each month.'
      : ' — with ${_laterMonths(extraMonthCount)} already set up ahead.';
  if (!context.mounted) return null;
  return showWebRecurringScopeDialog(
    context,
    title: 'Delete $selectedCount ${_pluralNoun(selectedCount, noun)}',
    subtitle: '$repeats$ahead',
    month: month,
    noun: noun,
    plural: true,
  );
}

String _laterMonths(int count) =>
    count == 1 ? '1 later month' : '$count later months';

String _pluralNoun(int n, String noun) => n == 1 ? noun : '${noun}s';

// ─── Undo settlement ──────────────────────────────────────────────────────────

/// Confirms reversing a paid / received / funded entry — the v2 twin of the
/// mobile [showUndoSettlementDialog], returning the same
/// [UndoSettlementChoice]. When the settlement wrote to the ledger, a switch
/// decides whether the transaction goes with it (the default) or stays.
Future<UndoSettlementChoice?> showWebUndoSettlementDialog(
  BuildContext context, {
  required String title,
  required String name,
  required String entryLabel,
  required bool hasLedgerEntry,
  String? ledgerEffect,
}) {
  return showWebDialog<UndoSettlementChoice>(
    context,
    builder: (_) => _UndoSettlementDialog(
      title: title,
      name: name,
      entryLabel: entryLabel,
      hasLedgerEntry: hasLedgerEntry,
      ledgerEffect: ledgerEffect,
    ),
  );
}

class _UndoSettlementDialog extends StatefulWidget {
  final String title;
  final String name;
  final String entryLabel;
  final bool hasLedgerEntry;
  final String? ledgerEffect;

  const _UndoSettlementDialog({
    required this.title,
    required this.name,
    required this.entryLabel,
    required this.hasLedgerEntry,
    required this.ledgerEffect,
  });

  @override
  State<_UndoSettlementDialog> createState() => _UndoSettlementDialogState();
}

class _UndoSettlementDialogState extends State<_UndoSettlementDialog> {
  bool _removeTransaction = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontSize: 13.5,
      height: 1.45,
    );
    return WebDialog(
      title: widget.title,
      primaryExpands: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.name} goes back to being an open ${widget.entryLabel}.',
            style: body,
          ),
          const SizedBox(height: 14),
          if (widget.hasLedgerEntry)
            WebSwitchRow(
              key: WebKeys.billsUndoRemoveTransaction,
              title: 'Also remove the ledger transaction',
              subtitle: _removeTransaction
                  ? (widget.ledgerEffect ?? 'The account balance is restored.')
                  : 'The transaction stays in the ledger and balances are '
                      'unchanged.',
              value: _removeTransaction,
              onChanged: (v) => setState(() => _removeTransaction = v),
            )
          else
            Text(
              widget.ledgerEffect ??
                  'No ledger transaction is linked to it, so no balance '
                      'changes.',
              style: body?.copyWith(fontSize: 12.5),
            ),
        ],
      ),
      secondary: TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      primary: FilledButton(
        key: WebKeys.billsUndoConfirm,
        onPressed: () => Navigator.of(context).pop(
          UndoSettlementChoice(
            // Nothing to remove means the flag is all there is to reverse.
            removeTransaction: widget.hasLedgerEntry && _removeTransaction,
          ),
        ),
        child: const Text('Undo'),
      ),
    );
  }
}
