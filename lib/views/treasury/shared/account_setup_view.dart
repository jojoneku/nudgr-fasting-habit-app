import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

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
  final _goalTargetController = TextEditingController();

  AccountCategory _category = AccountCategory.bank;
  String _selectedColor = _colorOptions[0];
  DateTime? _maturityDate;
  String? _linkedAccountId;
  bool _isSubmitting = false;

  List<AccountCategory> get _availableCategories =>
      widget.parentAccountId == null
          ? _topLevelCategories
          : _subAccountCategories;

  bool get _isGoal => _category == AccountCategory.goal;
  bool get _isTimeDeposit => _category == AccountCategory.timeDeposit;
  bool get _isCustodian => _category == AccountCategory.custodian;

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
      _category = existing.category;
      _selectedColor = existing.colorHex;
      _maturityDate = existing.maturityDate;
      _linkedAccountId = existing.linkedAccountId;
      if (existing.goalTarget != null) {
        _goalTargetController.text = existing.goalTarget!.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _goalTargetController.dispose();
    super.dispose();
  }

  Future<void> _pickMaturityDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _maturityDate ?? DateTime.now().add(const Duration(days: 180)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _maturityDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final id = widget.existing?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      final balance =
          double.tryParse(_balanceController.text.replaceAll(',', '')) ?? 0;
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
        icon: _category.name,
        goalTarget: goalTarget,
        maturityDate: _isTimeDeposit ? _maturityDate : null,
        linkedAccountId:
            _category == AccountCategory.custodian ? _linkedAccountId : null,
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

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Text(
          'This will permanently remove "${widget.existing!.name}". This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.presenter.deleteAccount(widget.existing!.id);
      if (mounted) Navigator.pop(context);
    } on StateError catch (e) {
      if (e.message == 'has_sub_accounts' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Remove all sub-accounts first before deleting this account.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
    final isSubAccount = widget.parentAccountId != null;

    final String title;
    if (isEdit) {
      title = 'Edit Account';
    } else if (isSubAccount) {
      title = 'Add Sub-Account';
    } else {
      title = 'Add Account';
    }

    // AccountSetupView is used as the builder body of showModalBottomSheet.
    // We render the sheet chrome here (handle + title + form).
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Form body
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _AccountSetupForm(
                formKey: _formKey,
                nameController: _nameController,
                balanceController: _balanceController,
                goalTargetController: _goalTargetController,
                availableCategories: _availableCategories,
                category: _category,
                onCategoryChanged: (c) => setState(() => _category = c!),
                selectedColor: _selectedColor,
                onColorSelected: (hex) => setState(() => _selectedColor = hex),
                maturityDate: _maturityDate,
                onPickMaturityDate: _pickMaturityDate,
                linkedAccountId: _linkedAccountId,
                onLinkedAccountChanged: (id) =>
                    setState(() => _linkedAccountId = id),
                liquidAccounts: widget.presenter.liquidAccounts,
                isGoal: _isGoal,
                isTimeDeposit: _isTimeDeposit,
                isCustodian: _isCustodian,
                isEdit: isEdit,
                isSubmitting: _isSubmitting,
                onSubmit: _submit,
                onDelete: isEdit ? _confirmDelete : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Form widget (separated so it can live inside AppBottomSheet.show body) ───

class _AccountSetupForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController balanceController;
  final TextEditingController goalTargetController;
  final List<AccountCategory> availableCategories;
  final AccountCategory category;
  final ValueChanged<AccountCategory?> onCategoryChanged;
  final String selectedColor;
  final ValueChanged<String> onColorSelected;
  final DateTime? maturityDate;
  final VoidCallback onPickMaturityDate;
  final String? linkedAccountId;
  final ValueChanged<String?> onLinkedAccountChanged;
  final List<FinancialAccount> liquidAccounts;
  final bool isGoal;
  final bool isTimeDeposit;
  final bool isCustodian;
  final bool isEdit;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final VoidCallback? onDelete;

  const _AccountSetupForm({
    required this.formKey,
    required this.nameController,
    required this.balanceController,
    required this.goalTargetController,
    required this.availableCategories,
    required this.category,
    required this.onCategoryChanged,
    required this.selectedColor,
    required this.onColorSelected,
    required this.maturityDate,
    required this.onPickMaturityDate,
    required this.linkedAccountId,
    required this.onLinkedAccountChanged,
    required this.liquidAccounts,
    required this.isGoal,
    required this.isTimeDeposit,
    required this.isCustodian,
    required this.isEdit,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Account details card
            AppCard(
              variant: AppCardVariant.outlined,
              child: Column(
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration:
                        const InputDecoration(labelText: 'Account Name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter account name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _CategoryDropdown(
                          categories: availableCategories,
                          value: category,
                          onChanged: onCategoryChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: balanceController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Opening Balance',
                            prefixText: '₱ ',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Color picker card
            AppCard(
              variant: AppCardVariant.outlined,
              header: Text(
                'Color',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              child: _ColorPicker(
                options: _colorOptions,
                selected: selectedColor,
                onSelected: onColorSelected,
              ),
            ),
            const SizedBox(height: 12),

            // Conditional fields
            if (isGoal) ...[
              TextFormField(
                controller: goalTargetController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                ],
                decoration: const InputDecoration(
                  labelText: 'Goal Target',
                  prefixText: '₱ ',
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (isTimeDeposit) ...[
              _MaturityDateRow(date: maturityDate, onTap: onPickMaturityDate),
              const SizedBox(height: 12),
            ],
            if (isCustodian) ...[
              _StoredInDropdown(
                accounts: liquidAccounts,
                selectedId: linkedAccountId,
                onChanged: onLinkedAccountChanged,
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 8),

            // Save button
            AppPrimaryButton(
              label: isEdit ? 'Save' : 'Add Account',
              onPressed: isSubmitting ? null : onSubmit,
              isLoading: isSubmitting,
            ),

            // Delete button (edit only)
            if (onDelete != null) ...[
              const SizedBox(height: 8),
              AppDestructiveButton(
                label: 'Delete Account',
                leading: Icons.delete_outline_rounded,
                onPressed: isSubmitting ? null : onDelete,
                isLoading: isSubmitting,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _CategoryDropdown extends StatelessWidget {
  final List<AccountCategory> categories;
  final AccountCategory value;
  final ValueChanged<AccountCategory?> onChanged;

  const _CategoryDropdown({
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  String _label(AccountCategory cat) => switch (cat) {
        AccountCategory.bank => 'Bank',
        AccountCategory.ewallet => 'eWallet',
        AccountCategory.cash => 'Cash',
        AccountCategory.savings => 'Savings',
        AccountCategory.goal => 'Goal',
        AccountCategory.timeDeposit => 'Time Deposit',
        AccountCategory.creditCard => 'Credit Card',
        AccountCategory.creditLine => 'Credit Line',
        AccountCategory.bnpl => 'BNPL',
        AccountCategory.investment => 'Investment',
        AccountCategory.custodian => 'External',
      };

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AccountCategory>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Category'),
      items: categories
          .map((c) => DropdownMenuItem(value: c, child: Text(_label(c))))
          .toList(),
      onChanged: onChanged,
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
      return Colors.blue;
    }
  }

  String _toHex(Color color) {
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  bool _isPreset(String hex) =>
      options.any((o) => o.toLowerCase() == hex.toLowerCase());

  void _openCustomPicker(BuildContext context) {
    Color pickerColor = _parse(selected);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom Color'),
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onSelected(_toHex(pickerColor));
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = !_isPreset(selected);

    return Wrap(
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
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 2.5)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 6)
                        ]
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
                  color: isCustom
                      ? Colors.white
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: isCustom ? 2.5 : 1.5,
                ),
                color: isCustom ? _parse(selected) : Colors.transparent,
                boxShadow: isCustom
                    ? [
                        BoxShadow(
                            color: _parse(selected).withValues(alpha: 0.5),
                            blurRadius: 6)
                      ]
                    : null,
              ),
              child: isCustom
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : Icon(
                      Icons.colorize_rounded,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.6),
                      size: 18,
                    ),
            ),
          ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AppCard(
        variant: AppCardVariant.outlined,
        child: Row(
          children: [
            Icon(Icons.event_outlined, color: cs.onSurfaceVariant, size: 18),
            const SizedBox(width: 12),
            Text(
              date != null
                  ? 'Matures: ${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
                  : 'Maturity Date',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: date != null ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoredInDropdown extends StatelessWidget {
  final List<FinancialAccount> accounts;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const _StoredInDropdown({
    required this.accounts,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      decoration: InputDecoration(
        labelText: 'Stored in account (optional)',
        helperText: 'These funds physically live in this account',
        helperStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.6)),
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(
            '— Not linked —',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        ...accounts.map(
            (a) => DropdownMenuItem<String>(value: a.id, child: Text(a.name))),
      ],
      onChanged: onChanged,
    );
  }
}
