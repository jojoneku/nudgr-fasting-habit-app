import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class AddInstallmentSheet extends StatefulWidget {
  final InstallmentPresenter presenter;
  final Installment? existing;

  const AddInstallmentSheet(
      {super.key, required this.presenter, this.existing});

  @override
  State<AddInstallmentSheet> createState() => _AddInstallmentSheetState();
}

class _AddInstallmentSheetState extends State<AddInstallmentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _monthlyCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String? _accountId;
  int _totalMonths = 12;
  String _startMonth = toMonthKey(DateTime.now());
  bool _monthlyManuallyEdited = false;
  bool _saving = false;
  bool _accountError = false;

  FinancialAccount? get _selectedAccount {
    for (final a in widget.presenter.accounts) {
      if (a.id == _accountId) return a;
    }
    return null;
  }

  Future<void> _pickAccount() async {
    final choice = await showAccountPicker(
      context,
      accounts: widget.presenter.accounts,
      selectedId: _accountId,
    );
    if (choice != null) {
      setState(() {
        _accountId = choice.id;
        _accountError = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _totalCtrl.text = e.totalAmount.toStringAsFixed(2);
      _monthlyCtrl.text = e.monthlyAmount.toStringAsFixed(2);
      _noteCtrl.text = e.note ?? '';
      _accountId = e.accountId;
      _totalMonths = e.totalMonths;
      _startMonth = e.startMonth;
      _monthlyManuallyEdited = true;
    } else if (widget.presenter.accounts.isNotEmpty) {
      _accountId = widget.presenter.accounts.first.id;
    }
    _totalCtrl.addListener(_onTotalChanged);
  }

  void _onTotalChanged() {
    if (_monthlyManuallyEdited) return;
    final total = double.tryParse(_totalCtrl.text);
    if (total != null && _totalMonths > 0) {
      _monthlyCtrl.text = (total / _totalMonths).toStringAsFixed(2);
    }
  }

  void _onMonthsChanged(int months) {
    setState(() {
      _totalMonths = months;
      _monthlyManuallyEdited = false;
    });
    _onTotalChanged();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _totalCtrl.dispose();
    _monthlyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      setState(() => _accountError = true);
      return;
    }
    setState(() => _saving = true);

    final total = double.parse(_totalCtrl.text);
    final monthly = double.parse(_monthlyCtrl.text);
    final e = widget.existing;

    final installment = Installment(
      id: e?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
      name: _nameCtrl.text.trim(),
      accountId: _accountId!,
      totalAmount: total,
      monthlyAmount: monthly,
      totalMonths: _totalMonths,
      startMonth: _startMonth,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      isActive: e?.isActive ?? true,
    );

    if (e != null) {
      await widget.presenter.updateInstallment(installment);
    } else {
      await widget.presenter.addInstallment(installment);
    }
    if (mounted) Navigator.pop(context);
  }

  void _adjustStartMonth(int delta) {
    final date = DateTime.parse('$_startMonth-01');
    final next = DateTime(date.year, date.month + delta);
    setState(() => _startMonth = toMonthKey(next));
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name
          const _FieldLabel('Name'),
          TextFormField(
            controller: _nameCtrl,
            decoration:
                sheetFieldDecoration(context, hint: 'e.g. MacBook Pro, Braces'),
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),

          // Account
          const _FieldLabel('Account (Credit / BNPL)'),
          SheetAccountField(
            account: _selectedAccount,
            placeholder: 'Select account',
            onTap: _pickAccount,
          ),
          if (_accountError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text('Required',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ),
          const SizedBox(height: 16),

          // Total Amount
          const _FieldLabel('Total Amount'),
          TextFormField(
            controller: _totalCtrl,
            decoration: sheetFieldDecoration(context,
                hint: '0.00', prefixText: '₱ ', emphasize: true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: amountInputFormatters,
            textInputAction: TextInputAction.next,
            validator: (v) {
              final p = double.tryParse(v ?? '');
              if (p == null || p <= 0) return 'Must be > 0';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Number of months
          const _FieldLabel('Number of Months'),
          _MonthsSelector(
            selected: _totalMonths,
            onChanged: _onMonthsChanged,
          ),
          const SizedBox(height: 16),

          // Monthly Amount
          const _FieldLabel('Monthly Payment (auto-computed, editable)'),
          TextFormField(
            controller: _monthlyCtrl,
            decoration:
                sheetFieldDecoration(context, hint: '0.00', prefixText: '₱ '),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: amountInputFormatters,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _monthlyManuallyEdited = true),
            validator: (v) {
              final p = double.tryParse(v ?? '');
              if (p == null || p <= 0) return 'Must be > 0';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Start Month
          const _FieldLabel('Start Month'),
          _StartMonthSelector(
            selectedMonth: _startMonth,
            onAdjust: _adjustStartMonth,
          ),
          const SizedBox(height: 16),

          // Note
          const _FieldLabel('Note (optional)'),
          AppTextField(
            controller: _noteCtrl,
            hint: 'e.g. 0% interest, 12 months',
            maxLines: 2,
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                isEdit ? 'Edit Installment' : 'New Installment',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              _buildForm(context),
              const SizedBox(height: 28),
              AppPrimaryButton(
                label: isEdit ? 'Save Changes' : 'Add Installment',
                onPressed: _saving ? null : _save,
                isLoading: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin wrapper over the shared [SheetFieldLabel] so existing `_FieldLabel(...)`
/// call sites in this sheet pick up the reference uppercase-label styling.
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => SheetFieldLabel(text);
}

class _MonthsSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _MonthsSelector({required this.selected, required this.onChanged});

  static const _presets = [3, 6, 12, 24];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        ..._presets.map((m) => _MonthChip(
              label: '${m}mo',
              selected: selected == m,
              onTap: () => onChanged(m),
            )),
        _CustomMonthsField(
          selected: !_presets.contains(selected) ? selected : null,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _MonthChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MonthChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.15)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _CustomMonthsField extends StatefulWidget {
  final int? selected;
  final ValueChanged<int> onChanged;

  const _CustomMonthsField({this.selected, required this.onChanged});

  @override
  State<_CustomMonthsField> createState() => _CustomMonthsFieldState();
}

class _CustomMonthsFieldState extends State<_CustomMonthsField> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.selected != null) _ctrl.text = '${widget.selected}';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: AppTextField(
        controller: _ctrl,
        hint: 'Custom',
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        onChanged: (v) {
          final parsed = int.tryParse(v);
          if (parsed != null && parsed > 0) widget.onChanged(parsed);
        },
      ),
    );
  }
}

class _StartMonthSelector extends StatelessWidget {
  final String selectedMonth;
  final ValueChanged<int> onAdjust;

  const _StartMonthSelector(
      {required this.selectedMonth, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon:
                  Icon(Icons.chevron_left, color: colorScheme.onSurfaceVariant),
              onPressed: () => onAdjust(-1),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                monthLabel(selectedMonth),
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant),
              onPressed: () => onAdjust(1),
            ),
          ),
        ],
      ),
    );
  }
}
