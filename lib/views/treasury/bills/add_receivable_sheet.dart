import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_chips.dart';
import 'package:intermittent_fasting/views/treasury/shared/recurring_scope_field.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class AddReceivableSheet extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final Receivable? existing;

  /// Embedded inside `NewEntrySheet` — render only the form + Save (see
  /// [AddBillSheet.embedded]).
  final bool embedded;

  const AddReceivableSheet({
    super.key,
    required this.presenter,
    this.existing,
    this.embedded = false,
  });

  @override
  State<AddReceivableSheet> createState() => _AddReceivableSheetState();
}

class _AddReceivableSheetState extends State<AddReceivableSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();

  ReceivableType _receivableType = ReceivableType.other;
  String? _selectedCategoryId;
  String? _selectedAccountId;
  DateTime _expectedDate = DateTime.now();
  bool _isRecurring = false;
  RecurrenceType _recurrenceType = RecurrenceType.monthly;
  bool _isSubmitting = false;

  /// How far this save reaches — see [AddBillSheet] for why it defaults to
  /// carrying forward.
  RecurringScope _scope = RecurringScope.thisAndFuture;

  /// Later months the scope switch would touch, snapshotted once (Rule 1).
  late final int _futureMonthCount;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    if (r != null) {
      _nameController.text = r.name;
      _amountController.text = r.amount.toStringAsFixed(2);
      _receivableType = r.receivableType;
      _selectedCategoryId = r.categoryId.isEmpty ? null : r.categoryId;
      _selectedAccountId = r.accountId;
      _expectedDate = r.expectedDate ?? DateTime.now();
      _isRecurring = r.isRecurring;
      _recurrenceType = r.recurrenceType ?? RecurrenceType.monthly;
    }
    _futureMonthCount = widget.presenter.futureReceivableReach(
      month: r?.month ?? widget.presenter.selectedMonth,
      existing: r,
    );
  }

  /// See [AddBillSheet]: turning recurrence off still needs the choice, because
  /// the months generated ahead exist only because it used to recur.
  bool get _wasRecurring => widget.existing?.isRecurring ?? false;

  bool get _dropsFutureMonths => !_isRecurring && _wasRecurring;

  bool get _showScopeField =>
      (_isRecurring || _wasRecurring) && _futureMonthCount > 0;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _incomeCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.income)
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
      // Same eligible set as the settle step, so a saved default can never be
      // an account mark-received would reject.
      accounts: widget.presenter.depositAccountsFor(widget.existing),
      selectedId: _selectedAccountId,
      allowNone: true,
      noneLabel: 'Ask me when received',
    );
    if (choice != null) setState(() => _selectedAccountId = choice.id);
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final e = widget.existing;
      final id = e?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      final receivable = Receivable(
        id: id,
        name: _nameController.text.trim(),
        receivableType: _receivableType,
        amount: amount,
        // Day only. A stored time of day is invisible on the card ("exp Aug 4")
        // yet used to be what ordered same-day entries, so the list looked
        // shuffled for no reason the user could see.
        expectedDate: DateUtils.dateOnly(_expectedDate),
        month: e?.month ?? widget.presenter.selectedMonth,
        categoryId: _selectedCategoryId ?? '',
        accountId: _selectedAccountId,
        isRecurring: _isRecurring,
        recurrenceType: _isRecurring ? _recurrenceType : null,
        // Preserve settled state, links, next-month override, and the hand-set
        // list rank when editing — this builds a fresh Receivable rather than
        // copyWith, so anything not restated here is dropped.
        isReceived: e?.isReceived ?? false,
        receivedDate: e?.receivedDate,
        receivedAmount: e?.receivedAmount,
        transactionId: e?.transactionId,
        reimbursementForTxnId: e?.reimbursementForTxnId,
        nextMonthAmount: e?.nextMonthAmount,
        sortIndex: e?.sortIndex,
        // Without this the fresh Receivable would drop the series link and the
        // save could no longer find the entry's other months.
        seriesId: e?.seriesId,
      );
      final applyToFuture =
          _showScopeField && _scope == RecurringScope.thisAndFuture;
      if (e != null) {
        await widget.presenter
            .updateReceivable(receivable, applyToFuture: applyToFuture);
      } else {
        await widget.presenter
            .addReceivable(receivable, applyToFuture: applyToFuture);
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
          SheetLabeledField(
            label: 'Source / Name',
            child: TextFormField(
              controller: _nameController,
              decoration: sheetFieldDecoration(context),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
          ),
          const SizedBox(height: 12),

          // Amount + Date
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SheetLabeledField(
                  label: 'Expected Amount',
                  child: TextFormField(
                    controller: _amountController,
                    decoration: sheetFieldDecoration(context,
                        prefixText: '₱ ', emphasize: true),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: amountInputFormatters,
                    textInputAction: TextInputAction.done,
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
                  label: 'Date',
                  child: SheetPickerBox(
                    onTap: _pickDate,
                    trailingIcon: Icons.calendar_today_outlined,
                    child: Text(
                      DateFormat('MMM d').format(_expectedDate),
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

          // Category — account-style picker (icon + name), optional.
          if (_incomeCategories.isNotEmpty) ...[
            const SizedBox(height: 16),
            SheetLabeledField(
              label: 'Category',
              child: CategoryPickerField(
                categories: _incomeCategories,
                selectedId: _selectedCategoryId,
                placeholder: 'None',
                onChanged: (id) => setState(() => _selectedCategoryId = id),
              ),
            ),
          ],

          // Destination account (optional) — pre-fills _MarkReceivedSheet.
          // Leave as "Ask me when received" to be asked at received-time.
          if (widget.presenter.accounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            const SheetFieldLabel('Destination account (optional)'),
            SheetAccountField(
              account: _selectedAccount,
              placeholder: 'Ask me when received',
              onTap: _pickAccount,
            ),
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
          ],

          // Recurring toggle
          const SizedBox(height: 16),
          SwitchListTile(
            value: _isRecurring,
            // Carrying an edit forward is the helpful default; carrying a
            // *deletion* forward is not, so switching recurrence off leaves the
            // scope opt-in rather than arming a destructive switch.
            onChanged: (v) => setState(() {
              _isRecurring = v;
              _scope = v
                  ? RecurringScope.thisAndFuture
                  : RecurringScope.thisMonthOnly;
            }),
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

          // How far this save reaches across the months already generated.
          if (_showScopeField) ...[
            const SizedBox(height: 12),
            RecurringScopeField(
              futureMonthCount: _futureMonthCount,
              month: widget.existing?.month ?? widget.presenter.selectedMonth,
              value: _scope,
              noun: 'amount',
              removesFutureMonths: _dropsFutureMonths,
              onChanged: (s) => setState(() => _scope = s),
            ),
          ],
        ],
      ),
    );
  }

  Widget _saveButton() => AppPrimaryButton(
        label: widget.existing != null ? 'Save' : 'Save receivable',
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
    final title =
        widget.existing != null ? 'Edit Receivable' : 'Add Receivable';

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
