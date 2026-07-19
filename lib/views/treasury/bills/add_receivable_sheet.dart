import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/views/treasury/shared/forms/forms.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class AddReceivableSheet extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final Receivable? existing;

  /// When true, hosted inside the combined [AddEntrySheet] which provides the
  /// title/chrome, so the internal title is suppressed.
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
        accountId: _selectedAccountId,
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

  String _typeLabel(ReceivableType t) => switch (t) {
        ReceivableType.salary => 'Salary',
        ReceivableType.reimbursement => 'Reimbursement',
        ReceivableType.business => 'Business',
        ReceivableType.other => 'Other',
      };

  Future<void> _pickAccount() async {
    const askLater = '__ask__';
    final picked = await AppActionSheet.show<String>(
      context: context,
      title: 'Destination account',
      actions: [
        AppActionSheetItem(
          label: 'Ask me when received',
          value: askLater,
          isPrimary: _selectedAccountId == null,
        ),
        for (final a in widget.presenter.accounts)
          AppActionSheetItem(
            label: a.name,
            value: a.id,
            isPrimary: a.id == _selectedAccountId,
          ),
      ],
    );
    if (picked != null) {
      setState(() =>
          _selectedAccountId = picked == askLater ? null : picked);
    }
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
    final accountName = _selectedAccountId == null
        ? ''
        : (widget.presenter.accounts
                .where((a) => a.id == _selectedAccountId)
                .map((a) => a.name)
                .firstOrNull ??
            '');
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppFormField(
            label: 'Source / Name',
            child: TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(hintText: 'e.g. Client, Payroll'),
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
                  label: 'Expected amount',
                  child: AppAmountField(
                    controller: _amountController,
                    hint: '0.00',
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
                  label: 'Expected',
                  child: AppSelectField(
                    value: DateFormat('MMM d').format(_expectedDate),
                    leadingIcon: Icons.calendar_today_outlined,
                    onTap: _pickDate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _MoreOptionsLabel(),
          const SizedBox(height: 12),
          AppFormField(
            label: 'Type',
            child: AppChipSelect<ReceivableType>(
              options: [
                for (final t in ReceivableType.values)
                  AppChipOption(t, _typeLabel(t)),
              ],
              selected: _receivableType,
              onChanged: (t) => setState(() => _receivableType = t),
            ),
          ),
          if (_incomeCategories.isNotEmpty) ...[
            const SizedBox(height: 16),
            AppFormField(
              label: 'Category',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _incomeCategories.map((cat) {
                  final isSelected = _selectedCategoryId == cat.id;
                  return ChoiceChip(
                    label: Text(cat.name),
                    selected: isSelected,
                    onSelected: (_) => setState(
                        () => _selectedCategoryId = isSelected ? null : cat.id),
                  );
                }).toList(),
              ),
            ),
          ],
          if (widget.presenter.accounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            AppFormField(
              label: 'Destination account (optional)',
              hint: 'Pre-fills when you mark this received',
              child: AppSelectField(
                value: accountName,
                placeholder: 'Ask me when received',
                leadingIcon: Icons.account_balance_wallet_outlined,
                onTap: _pickAccount,
              ),
            ),
          ],
          const SizedBox(height: 16),
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
    final title =
        widget.existing != null ? 'Edit Receivable' : 'Add Receivable';

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
              label: widget.existing != null ? 'Save' : 'Save entry',
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
