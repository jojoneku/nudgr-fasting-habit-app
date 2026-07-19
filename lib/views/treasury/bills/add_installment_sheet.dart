import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/forms/forms.dart';
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
    if (_accountId == null) return;
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

  Future<void> _pickAccount() async {
    final accounts = widget.presenter.accounts;
    if (accounts.isEmpty) return;
    final picked = await AppActionSheet.show<String>(
      context: context,
      title: 'Account (Credit / BNPL)',
      actions: [
        for (final a in accounts)
          AppActionSheetItem(
            label: a.name,
            value: a.id,
            isPrimary: a.id == _accountId,
          ),
      ],
    );
    if (picked != null) setState(() => _accountId = picked);
  }

  Widget _buildForm(BuildContext context) {
    final accountName = widget.presenter.accounts
            .where((a) => a.id == _accountId)
            .map((a) => a.name)
            .firstOrNull ??
        '';
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFormField(
            label: 'Name',
            child: TextFormField(
              controller: _nameCtrl,
              decoration:
                  const InputDecoration(hintText: 'e.g. MacBook Pro, Braces'),
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
          const SizedBox(height: 16),
          AppFormField(
            label: 'Account (Credit / BNPL)',
            child: AppSelectField(
              value: accountName,
              placeholder: 'Select account',
              leadingIcon: Icons.credit_card_outlined,
              onTap: _pickAccount,
            ),
          ),
          const SizedBox(height: 16),
          AppFormField(
            label: 'Total Amount',
            child: AppAmountField(
              controller: _totalCtrl,
              hint: '0.00',
              textInputAction: TextInputAction.next,
              validator: (v) {
                final p = double.tryParse(v ?? '');
                if (p == null || p <= 0) return 'Must be > 0';
                return null;
              },
            ),
          ),
          const SizedBox(height: 16),
          AppFormField(
            label: 'Number of Months',
            child: _MonthsSelector(
              selected: _totalMonths,
              onChanged: _onMonthsChanged,
            ),
          ),
          const SizedBox(height: 16),
          AppFormField(
            label: 'Monthly Payment (auto · editable)',
            child: AppAmountField(
              controller: _monthlyCtrl,
              hint: '0.00',
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() => _monthlyManuallyEdited = true),
              validator: (v) {
                final p = double.tryParse(v ?? '');
                if (p == null || p <= 0) return 'Must be > 0';
                return null;
              },
            ),
          ),
          const SizedBox(height: 16),
          AppFormField(
            label: 'Start Month',
            child: _StartMonthSelector(
              selectedMonth: _startMonth,
              onAdjust: _adjustStartMonth,
            ),
          ),
          const SizedBox(height: 16),
          AppFormField(
            label: 'Note (optional)',
            child: AppTextField(
              controller: _noteCtrl,
              hint: 'e.g. 0% interest, 12 months',
              maxLines: 2,
              textInputAction: TextInputAction.done,
            ),
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
