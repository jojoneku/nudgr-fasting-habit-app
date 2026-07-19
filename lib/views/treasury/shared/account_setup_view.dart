import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:intermittent_fasting/models/finance/credit_brand_presets.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/views/treasury/shared/forms/forms.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

String _accountCategoryLabel(AccountCategory cat) => switch (cat) {
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
  AccountCategory.savings,
  AccountCategory.goal,
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
  final AccountCategory? initialCategory;

  const AccountSetupView({
    super.key,
    required this.presenter,
    this.existing,
    this.parentAccountId,
    this.initialCategory,
  });

  @override
  State<AccountSetupView> createState() => _AccountSetupViewState();
}

class _AccountSetupViewState extends State<AccountSetupView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  final _goalTargetController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _financeRateController = TextEditingController();

  AccountCategory _category = AccountCategory.bank;
  String _selectedColor = _colorOptions[0];
  DateTime? _maturityDate;
  String? _linkedAccountId;
  int? _statementDay;
  int? _paymentDueDay;
  String? _creditBrand;
  bool _isSubmitting = false;

  /// The parent this account belongs to. When editing an existing sub-account
  /// the form is often opened without `parentAccountId` (e.g. from the
  /// dashboard Goals section), so fall back to the account's own stored parent.
  /// Writing `widget.parentAccountId` (null) on save would detach the pocket
  /// while the parent's balance still counts it — double-counting net worth.
  /// Mirrors the web form (Plan 052 C1).
  String? get _effectiveParentId =>
      widget.existing?.parentAccountId ?? widget.parentAccountId;

  List<AccountCategory> get _availableCategories =>
      _effectiveParentId == null ? _topLevelCategories : _subAccountCategories;

  bool get _isGoal => _category == AccountCategory.goal;
  bool get _isTimeDeposit => _category == AccountCategory.timeDeposit;
  bool get _isCustodian => _category == AccountCategory.custodian;
  // Liability categories carry credit details (limit, statement/due dates, rate).
  bool get _isCredit =>
      _category == AccountCategory.creditCard ||
      _category == AccountCategory.creditLine ||
      _category == AccountCategory.bnpl;

  /// The opening "balance" field means *amount owed* for credit accounts.
  String get _balanceLabel =>
      _isCredit ? 'Current Balance Owed' : 'Opening Balance';

  @override
  void initState() {
    super.initState();
    if (widget.parentAccountId != null) {
      _category = AccountCategory.savings;
    }
    if (widget.initialCategory != null) {
      _category = widget.initialCategory!;
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
      if (existing.creditLimit != null) {
        _creditLimitController.text = existing.creditLimit!.toStringAsFixed(2);
      }
      if (existing.financeChargeRate != null) {
        // Stored as a fraction (0.03); edited as a percent (3).
        _financeRateController.text =
            (existing.financeChargeRate! * 100).toStringAsFixed(2);
      }
      _statementDay = existing.statementDay;
      _paymentDueDay = existing.paymentDueDay;
      _creditBrand = existing.creditBrand;
    }
  }

  /// Applies a brand preset's defaults into the editable fields. The user can
  /// still override the finance rate afterwards.
  void _applyBrand(String? key) {
    setState(() {
      _creditBrand = key;
      final preset = creditBrandPresetByKey(key);
      if (preset != null) {
        _financeRateController.text =
            (preset.monthlyFinanceRate * 100).toStringAsFixed(2);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _goalTargetController.dispose();
    _creditLimitController.dispose();
    _financeRateController.dispose();
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

      final creditLimit = _isCredit && _creditLimitController.text.isNotEmpty
          ? double.tryParse(_creditLimitController.text.replaceAll(',', ''))
          : null;
      final financeRatePercent = _isCredit
          ? double.tryParse(_financeRateController.text.replaceAll(',', ''))
          : null;

      final account = FinancialAccount(
        id: id,
        name: _nameController.text.trim(),
        category: _category,
        parentAccountId: _effectiveParentId,
        balance: balance,
        colorHex: _selectedColor,
        // Preserve the existing icon unless the category itself changed —
        // blindly writing `_category.name` discarded a customised icon. Mirrors
        // the web form (C5).
        icon:
            (widget.existing != null && widget.existing!.category == _category)
                ? widget.existing!.icon
                : _category.name,
        goalTarget: goalTarget,
        maturityDate: _isTimeDeposit ? _maturityDate : null,
        linkedAccountId:
            _category == AccountCategory.custodian ? _linkedAccountId : null,
        creditLimit: creditLimit,
        statementDay: _isCredit ? _statementDay : null,
        paymentDueDay: _isCredit ? _paymentDueDay : null,
        // Stored as a fraction; entered as a percent.
        financeChargeRate:
            (financeRatePercent != null && financeRatePercent > 0)
                ? financeRatePercent / 100
                : null,
        creditBrand: _isCredit ? _creditBrand : null,
      );

      if (widget.existing != null) {
        await widget.presenter.updateAccount(account);
      } else {
        await widget.presenter.addAccount(account);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      // Surface persistence failures instead of swallowing them — otherwise a
      // failed save looks identical to a successful one. Mirrors the delete
      // handler and the web form's error feedback.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save account: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Only an editable, top-level liquid account (bank / e-wallet / cash) can
  /// hold nested pockets (savings, goals, time deposits). Sub-accounts and
  /// non-liquid roles don't nest further.
  bool get _canAddPocket =>
      widget.existing != null &&
      widget.parentAccountId == null &&
      widget.existing!.parentAccountId == null &&
      widget.existing!.isLiquid;

  /// Opens a fresh form bound to this account as the parent so the user can add
  /// a pocket/goal/time deposit under it. Stacks over the current edit sheet and
  /// pops back to it on save.
  void _showAddPocket() {
    AppBottomSheet.show(
      context: context,
      title: 'Add Pocket',
      body: AccountSetupView(
        presenter: widget.presenter,
        parentAccountId: widget.existing!.id,
      ),
    );
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
      if (!mounted) return;
      final message = switch (e.message) {
        'has_sub_accounts' =>
          'Remove all sub-accounts first before deleting this account.',
        'has_transactions' =>
          'This account has transactions or bills linked to it. '
              'Delete or reassign them first.',
        _ => 'Could not delete account: ${e.message}',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    // AppBottomSheet.show owns the chrome (handle, title, close) and keyboard
    // inset padding — render only the form body here.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: _AccountSetupForm(
            formKey: _formKey,
            nameController: _nameController,
            balanceController: _balanceController,
            balanceLabel: _balanceLabel,
            goalTargetController: _goalTargetController,
            creditLimitController: _creditLimitController,
            financeRateController: _financeRateController,
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
            statementDay: _statementDay,
            onStatementDayChanged: (d) => setState(() => _statementDay = d),
            paymentDueDay: _paymentDueDay,
            onPaymentDueDayChanged: (d) => setState(() => _paymentDueDay = d),
            creditBrand: _creditBrand,
            onBrandChanged: _applyBrand,
            isGoal: _isGoal,
            isTimeDeposit: _isTimeDeposit,
            isCustodian: _isCustodian,
            isCredit: _isCredit,
            isEdit: isEdit,
            isSubmitting: _isSubmitting,
            onSubmit: _submit,
            onDelete: isEdit ? _confirmDelete : null,
            onAddSubAccount: _canAddPocket ? _showAddPocket : null,
          ),
        ),
      ],
    );
  }
}

// ─── Form widget (separated so it can live inside AppBottomSheet.show body) ───

class _AccountSetupForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController balanceController;
  final String balanceLabel;
  final TextEditingController goalTargetController;
  final TextEditingController creditLimitController;
  final TextEditingController financeRateController;
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
  final int? statementDay;
  final ValueChanged<int?> onStatementDayChanged;
  final int? paymentDueDay;
  final ValueChanged<int?> onPaymentDueDayChanged;
  final String? creditBrand;
  final ValueChanged<String?> onBrandChanged;
  final bool isGoal;
  final bool isTimeDeposit;
  final bool isCustodian;
  final bool isCredit;
  final bool isEdit;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final VoidCallback? onDelete;

  /// Opens a nested sub-account (pocket/goal/time deposit) form. Null when the
  /// account can't hold pockets (not an editable liquid parent).
  final VoidCallback? onAddSubAccount;

  const _AccountSetupForm({
    required this.formKey,
    required this.nameController,
    required this.balanceController,
    required this.balanceLabel,
    required this.goalTargetController,
    required this.creditLimitController,
    required this.financeRateController,
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
    required this.statementDay,
    required this.onStatementDayChanged,
    required this.paymentDueDay,
    required this.onPaymentDueDayChanged,
    required this.creditBrand,
    required this.onBrandChanged,
    required this.isGoal,
    required this.isTimeDeposit,
    required this.isCustodian,
    required this.isCredit,
    required this.isEdit,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onDelete,
    required this.onAddSubAccount,
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
            // Type — chip row (reference: Bank / eWallet / Cash / Savings / …)
            AppFormField(
              label: 'Type',
              child: AppChipSelect<AccountCategory>(
                options: [
                  for (final c in availableCategories)
                    AppChipOption(c, _accountCategoryLabel(c)),
                ],
                selected: category,
                onChanged: onCategoryChanged,
              ),
            ),
            const SizedBox(height: 16),
            AppFormField(
              label: 'Name',
              child: TextFormField(
                controller: nameController,
                decoration:
                    const InputDecoration(hintText: 'e.g. BPI Personal'),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter account name'
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            AppFormField(
              label: balanceLabel,
              child: AppAmountField(
                controller: balanceController,
                hint: '0.00',
              ),
            ),
            const SizedBox(height: 16),
            AppFormField(
              label: 'Color',
              child: _ColorPicker(
                options: _colorOptions,
                selected: selectedColor,
                onSelected: onColorSelected,
              ),
            ),
            const SizedBox(height: 16),

            // Conditional fields
            if (isGoal) ...[
              AppFormField(
                label: 'Goal Target',
                child: AppAmountField(
                  controller: goalTargetController,
                  hint: '0.00',
                ),
              ),
              const SizedBox(height: 16),
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
            if (isCredit) ...[
              _CreditDetailsCard(
                creditLimitController: creditLimitController,
                financeRateController: financeRateController,
                statementDay: statementDay,
                onStatementDayChanged: onStatementDayChanged,
                paymentDueDay: paymentDueDay,
                onPaymentDueDayChanged: onPaymentDueDayChanged,
                creditBrand: creditBrand,
                onBrandChanged: onBrandChanged,
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

            // Add a nested pocket / goal under this liquid account (edit only).
            if (onAddSubAccount != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: isSubmitting ? null : onAddSubAccount,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Add savings pocket / goal'),
              ),
            ],

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
          // Contrast the ring/check against the swatch itself, not a fixed
          // white — otherwise a pale swatch in light mode shows an invisible
          // selection.
          final onSwatch =
              color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
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
                      ? Border.all(color: onSwatch, width: 2.5)
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
                    ? Icon(Icons.check, color: onSwatch, size: 18)
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
                      ? (_parse(selected).computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white)
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
                  ? Icon(
                      Icons.check,
                      color: _parse(selected).computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white,
                      size: 18,
                    )
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

/// Credit-only details: limit, statement/due day, finance rate, brand preset.
class _CreditDetailsCard extends StatelessWidget {
  final TextEditingController creditLimitController;
  final TextEditingController financeRateController;
  final int? statementDay;
  final ValueChanged<int?> onStatementDayChanged;
  final int? paymentDueDay;
  final ValueChanged<int?> onPaymentDueDayChanged;
  final String? creditBrand;
  final ValueChanged<String?> onBrandChanged;

  const _CreditDetailsCard({
    required this.creditLimitController,
    required this.financeRateController,
    required this.statementDay,
    required this.onStatementDayChanged,
    required this.paymentDueDay,
    required this.onPaymentDueDayChanged,
    required this.creditBrand,
    required this.onBrandChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      header: Text(
        'Credit details',
        style:
            theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand preset — seeds the finance rate when picked.
          DropdownButtonFormField<String?>(
            initialValue: creditBrand,
            decoration: const InputDecoration(
              labelText: 'Card type (optional)',
              helperText: 'Pick a card to prefill its finance rate',
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text('— Manual —',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
              ...kCreditBrandPresets.map(
                (p) => DropdownMenuItem<String?>(
                    value: p.key, child: Text(p.label)),
              ),
            ],
            onChanged: onBrandChanged,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: creditLimitController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: amountInputFormatters,
            decoration: const InputDecoration(
              labelText: 'Credit Limit',
              prefixText: '₱ ',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DayOfMonthDropdown(
                  label: 'Statement day',
                  value: statementDay,
                  onChanged: onStatementDayChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DayOfMonthDropdown(
                  label: 'Due day',
                  value: paymentDueDay,
                  onChanged: onPaymentDueDayChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: financeRateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: amountInputFormatters,
            decoration: const InputDecoration(
              labelText: 'Monthly finance rate',
              suffixText: '% / mo',
              helperText: 'Interest on unpaid balance (BSP cap 3%)',
            ),
          ),
        ],
      ),
    );
  }
}

/// Dropdown for choosing a day of month (1–28, to stay valid in February).
class _DayOfMonthDropdown extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _DayOfMonthDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text('—',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        for (int d = 1; d <= 28; d++)
          DropdownMenuItem<int?>(value: d, child: Text('$d')),
      ],
      onChanged: onChanged,
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
    // Guard against a dangling link: if the previously-stored account was since
    // deleted/deactivated it won't be in [accounts], and feeding a value with no
    // matching item trips DropdownButton's "exactly one item" assertion and
    // crashes the edit sheet. Fall back to "not linked". Mirrors the web form.
    final safeSelected =
        accounts.any((a) => a.id == selectedId) ? selectedId : null;
    return DropdownButtonFormField<String>(
      initialValue: safeSelected,
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
