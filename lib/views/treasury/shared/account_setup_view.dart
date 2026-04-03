import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';

const _colorOptions = [
  '#7C3AED',
  '#2563EB',
  '#059669',
  '#D97706',
  '#DC2626',
  '#0891B2',
  '#9333EA',
  '#64748B',
];

const _topLevelCategories = [
  AccountCategory.bank,
  AccountCategory.ewallet,
  AccountCategory.cash,
  AccountCategory.creditCard,
  AccountCategory.creditLine,
  AccountCategory.bnpl,
  AccountCategory.investment,
  AccountCategory.custodian,
];

const _subAccountCategories = [
  AccountCategory.savings,
  AccountCategory.goal,
  AccountCategory.timeDeposit,
];

class AccountSetupView extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;
  final FinancialAccount? existing;
  final String? parentAccountId;

  const AccountSetupView({
    super.key,
    required this.presenter,
    this.existing,
    this.parentAccountId,
  });

  @override
  State<AccountSetupView> createState() => _AccountSetupViewState();
}

class _AccountSetupViewState extends State<AccountSetupView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  final _iconController = TextEditingController();
  final _goalTargetController = TextEditingController();

  AccountCategory _category = AccountCategory.bank;
  String _selectedColor = _colorOptions[0];
  DateTime? _maturityDate;
  bool _isSubmitting = false;

  List<AccountCategory> get _availableCategories =>
      widget.parentAccountId == null ? _topLevelCategories : _subAccountCategories;

  bool get _isGoal => _category == AccountCategory.goal;
  bool get _isTimeDeposit => _category == AccountCategory.timeDeposit;

  @override
  void initState() {
    super.initState();
    if (widget.parentAccountId != null) {
      _category = AccountCategory.savings;
    }

    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _balanceController.text = existing.balance.toStringAsFixed(2);
      _iconController.text = existing.icon;
      _category = existing.category;
      _selectedColor = existing.colorHex;
      _maturityDate = existing.maturityDate;
      if (existing.goalTarget != null) {
        _goalTargetController.text = existing.goalTarget!.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _iconController.dispose();
    _goalTargetController.dispose();
    super.dispose();
  }

  Future<void> _pickMaturityDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _maturityDate ?? DateTime.now().add(const Duration(days: 180)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2035),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(primary: AppColors.accent),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _maturityDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final id = widget.existing?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      final balance = double.tryParse(_balanceController.text.replaceAll(',', '')) ?? 0;
      final goalTarget = _isGoal && _goalTargetController.text.isNotEmpty
          ? double.tryParse(_goalTargetController.text.replaceAll(',', ''))
          : null;

      final account = FinancialAccount(
        id: id,
        name: _nameController.text.trim(),
        category: _category,
        parentAccountId: widget.parentAccountId,
        balance: balance,
        colorHex: _selectedColor,
        icon: _iconController.text.trim().isEmpty ? 'wallet' : _iconController.text.trim(),
        goalTarget: goalTarget,
        maturityDate: _isTimeDeposit ? _maturityDate : null,
      );

      if (widget.existing != null) {
        await widget.presenter.updateAccount(account);
      } else {
        await widget.presenter.addAccount(account);
      }

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final isSubAccount = widget.parentAccountId != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetTitle(isEdit: isEdit, isSubAccount: isSubAccount),
              const SizedBox(height: 16),
              _NameField(controller: _nameController),
              const SizedBox(height: 12),
              _CategoryDropdown(
                categories: _availableCategories,
                value: _category,
                onChanged: (c) => setState(() => _category = c!),
              ),
              const SizedBox(height: 12),
              _BalanceField(controller: _balanceController),
              const SizedBox(height: 16),
              _ColorPicker(
                options: _colorOptions,
                selected: _selectedColor,
                onSelected: (hex) => setState(() => _selectedColor = hex),
              ),
              const SizedBox(height: 12),
              _IconField(controller: _iconController),
              if (_isGoal) ...[
                const SizedBox(height: 12),
                _GoalTargetField(controller: _goalTargetController),
              ],
              if (_isTimeDeposit) ...[
                const SizedBox(height: 12),
                _MaturityDateRow(date: _maturityDate, onTap: _pickMaturityDate),
              ],
              const SizedBox(height: 20),
              _SubmitButton(isEdit: isEdit, isSubmitting: _isSubmitting, onPressed: _submit),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  final bool isEdit;
  final bool isSubAccount;

  const _SheetTitle({required this.isEdit, required this.isSubAccount});

  @override
  Widget build(BuildContext context) {
    String title;
    if (isEdit) {
      title = 'Edit Account';
    } else if (isSubAccount) {
      title = 'Add Sub-Account';
    } else {
      title = 'Add Account';
    }
    return Text(
      title,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
    );
  }
}

class _NameField extends StatelessWidget {
  final TextEditingController controller;

  const _NameField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: AppColors.textPrimary),
      decoration: _inputDecoration('Account Name'),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter account name' : null,
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final List<AccountCategory> categories;
  final AccountCategory value;
  final ValueChanged<AccountCategory?> onChanged;

  const _CategoryDropdown({
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  String _label(AccountCategory cat) {
    switch (cat) {
      case AccountCategory.bank:
        return 'Bank';
      case AccountCategory.ewallet:
        return 'eWallet';
      case AccountCategory.cash:
        return 'Cash';
      case AccountCategory.savings:
        return 'Savings';
      case AccountCategory.goal:
        return 'Goal';
      case AccountCategory.timeDeposit:
        return 'Time Deposit';
      case AccountCategory.creditCard:
        return 'Credit Card';
      case AccountCategory.creditLine:
        return 'Credit Line';
      case AccountCategory.bnpl:
        return 'BNPL';
      case AccountCategory.investment:
        return 'Investment';
      case AccountCategory.custodian:
        return 'External';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AccountCategory>(
      initialValue: value,
      dropdownColor: AppColors.surface,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: _inputDecoration('Category'),
      items: categories
          .map((c) => DropdownMenuItem(value: c, child: Text(_label(c))))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _BalanceField extends StatelessWidget {
  final TextEditingController controller;

  const _BalanceField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      style: TextStyle(color: AppColors.textPrimary),
      decoration: _inputDecoration('Opening Balance').copyWith(prefixText: '₱ ', prefixStyle: TextStyle(color: AppColors.accent)),
    );
  }
}

class _GoalTargetField extends StatelessWidget {
  final TextEditingController controller;

  const _GoalTargetField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      style: TextStyle(color: AppColors.textPrimary),
      decoration: _inputDecoration('Goal Target').copyWith(prefixText: '₱ ', prefixStyle: TextStyle(color: AppColors.accent)),
    );
  }
}

class _IconField extends StatelessWidget {
  final TextEditingController controller;

  const _IconField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: AppColors.textPrimary),
      decoration: _inputDecoration('Icon name').copyWith(hintText: 'e.g. bank, wallet', hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5))),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const _ColorPicker({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  Color _parse(String hex) {
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return AppColors.accent;
    }
  }

  String _toHex(Color color) =>
      '#${color.red.toRadixString(16).padLeft(2, '0')}'
      '${color.green.toRadixString(16).padLeft(2, '0')}'
      '${color.blue.toRadixString(16).padLeft(2, '0')}'.toUpperCase();

  bool _isPreset(String hex) => options.contains(hex.toUpperCase()) ||
      options.contains(hex.toLowerCase()) ||
      options.any((o) => o.toLowerCase() == hex.toLowerCase());

  void _openCustomPicker(BuildContext context) {
    Color pickerColor = _parse(selected);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Custom Color',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: HueRingPicker(
            pickerColor: pickerColor,
            onColorChanged: (c) => pickerColor = c,
            enableAlpha: false,
            displayThumbColor: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onSelected(_toHex(pickerColor));
            },
            child: Text('Apply', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = !_isPreset(selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Color', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ...options.map((hex) {
              final color = _parse(hex);
              final isSelected = hex.toLowerCase() == selected.toLowerCase();
              return Semantics(
                label: 'Color $hex',
                selected: isSelected,
                child: GestureDetector(
                  onTap: () => onSelected(hex),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected ? Border.all(color: Colors.white, width: 2.5) : null,
                      boxShadow: isSelected
                          ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6)]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                ),
              );
            }),
            // Custom color swatch
            Semantics(
              label: 'Pick custom color',
              child: GestureDetector(
                onTap: () => _openCustomPicker(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCustom ? Colors.white : AppColors.textSecondary.withOpacity(0.4),
                      width: isCustom ? 2.5 : 1.5,
                    ),
                    color: isCustom ? _parse(selected) : Colors.transparent,
                    boxShadow: isCustom
                        ? [BoxShadow(color: _parse(selected).withOpacity(0.5), blurRadius: 6)]
                        : null,
                  ),
                  child: isCustom
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : Icon(Icons.colorize_rounded,
                          color: AppColors.textSecondary.withOpacity(0.6), size: 18),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MaturityDateRow extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onTap;

  const _MaturityDateRow({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.textSecondary.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.event_outlined, color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 12),
            Text(
              date != null
                  ? 'Matures: ${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
                  : 'Maturity Date',
              style: TextStyle(
                color: date != null ? AppColors.textPrimary : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final bool isEdit;
  final bool isSubmitting;
  final VoidCallback onPressed;

  const _SubmitButton({required this.isEdit, required this.isSubmitting, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isSubmitting ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: isSubmitting
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
              )
            : Text(
                isEdit ? 'Save' : 'Add Account',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
      ),
    );
  }
}

InputDecoration _inputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: AppColors.textSecondary),
    filled: true,
    fillColor: const Color(0xFF0A0E14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppColors.textSecondary.withOpacity(0.3)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppColors.accent),
    ),
  );
}
