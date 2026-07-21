import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/credit_brand_presets.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/account_badge.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../../design/account_category_label.dart';
import '../../widgets/web_widgets.dart';

/// Account color swatch options. These are user-chosen account colors — the
/// same list the mobile `AccountSetupView` uses — so the literal hex values are
/// intentional (they are data, not theme tokens).
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

/// Validator for optional currency/number fields: blank is allowed (treated as
/// 0 / unset on submit), but a non-empty value must parse cleanly so malformed
/// input like "1.2.3" is rejected up front instead of silently coerced to 0.
/// (Plan 052 C6)
String? _optionalAmountValidator(String? v) {
  final raw = (v ?? '').replaceAll(',', '').trim();
  if (raw.isEmpty) return null;
  final parsed = double.tryParse(raw);
  if (parsed == null) return 'Enter a valid number';
  if (parsed < 0) return 'Must be 0 or more';
  return null;
}

/// Native desktop Add/Edit Account form for the Treasury web "Setup & Accounts"
/// page. Replaces the mobile [AccountSetupView]-in-a-bottom-sheet with a
/// centered, scrollable [Dialog] matching the other web modals.
///
/// Builds the SAME [FinancialAccount] as the mobile form (same fields, defaults
/// and id generation) and calls the SAME presenter CRUD methods
/// ([TreasuryDashboardPresenter.addAccount] / `updateAccount` / `deleteAccount`).
class WebAccountFormDialog extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;
  final FinancialAccount? existing;
  final String? parentAccountId;
  final AccountCategory? initialCategory;

  const WebAccountFormDialog({
    super.key,
    required this.presenter,
    this.existing,
    this.parentAccountId,
    this.initialCategory,
  });

  /// Opens the form centered in a [showDialog]. Add when [existing] is null,
  /// edit otherwise. The dialog pops itself on save/delete; callers need no
  /// result handling because the presenter notifies its listeners.
  static Future<void> show(
    BuildContext context,
    TreasuryDashboardPresenter presenter, {
    FinancialAccount? existing,
    String? parentAccountId,
    AccountCategory? initialCategory,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => WebAccountFormDialog(
        presenter: presenter,
        existing: existing,
        parentAccountId: parentAccountId,
        initialCategory: initialCategory,
      ),
    );
  }

  @override
  State<WebAccountFormDialog> createState() => _WebAccountFormDialogState();
}

class _WebAccountFormDialogState extends State<WebAccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  final _goalTargetController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _financeRateController = TextEditingController();

  AccountCategory _category = AccountCategory.bank;
  String _selectedColor = _colorOptions[0];

  /// Stored badge choice (catalog key / [kMonogramBadgeKey] / '' = default).
  String _iconKey = '';
  DateTime? _maturityDate;
  String? _linkedAccountId;
  int? _statementDay;
  int? _paymentDueDay;
  String? _creditBrand;
  bool _isSubmitting = false;

  /// The parent this account belongs to. On EDIT the setup page opens the
  /// dialog without `parentAccountId`, so we must fall back to the existing
  /// record's parent — otherwise saving a sub-account would orphan it
  /// (`parentAccountId: null` detaches the pocket from its parent). (Plan 052 C1)
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
      _iconKey = existing.icon;
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

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _goalTargetController.dispose();
    _creditLimitController.dispose();
    _financeRateController.dispose();
    super.dispose();
  }

  /// Opens the icon/monogram picker and stores the chosen badge key.
  Future<void> _pickIcon() async {
    final chosen = await showAccountBadgePicker(
      context,
      current: _iconKey,
      category: _category,
      name: _nameController.text.trim(),
      colorHex: _selectedColor,
    );
    if (chosen != null && mounted) setState(() => _iconKey = chosen);
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
        // The badge choice: a catalog key / monogram sentinel, or the category
        // name as the "default" marker when the user hasn't picked one.
        icon: _iconKey.isEmpty ? _category.name : _iconKey,
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

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // A save failure was previously invisible (try/finally with no catch) —
      // the spinner reset and the dialog just sat there. Surface it. (C7)
      if (!mounted) return;
      AppToast.error(context, 'Could not save account: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _confirmDelete() async {
    final cs = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Text(
          'This will permanently remove "${widget.existing!.name}". '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.presenter.deleteAccount(widget.existing!.id);
      if (mounted) Navigator.of(context).pop();
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
      AppToast.error(context, message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isEdit = widget.existing != null;

    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  WebInsets.xl, WebInsets.lg, WebInsets.md, WebInsets.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit Account' : 'Add Account',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(WebInsets.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        autofocus: !isEdit,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Account Name',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter account name'
                            : null,
                      ),
                      const SizedBox(height: WebInsets.lg),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<AccountCategory>(
                              initialValue: _category,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: _availableCategories
                                  .map((c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c.label),
                                      ))
                                  .toList(),
                              onChanged: (c) =>
                                  setState(() => _category = c ?? _category),
                            ),
                          ),
                          const SizedBox(width: WebInsets.lg),
                          Expanded(
                            child: TextFormField(
                              controller: _balanceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d.]'))
                              ],
                              decoration: InputDecoration(
                                labelText: _balanceLabel,
                                prefixText: '₱ ',
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) =>
                                  _submit(), // Enter submits (U6)
                              // Reject malformed numbers (e.g. "1.2.3") instead
                              // of silently coercing them to 0. (Plan 052 C6)
                              validator: _optionalAmountValidator,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: WebInsets.lg),
                      // Icon / monogram picker
                      Text(
                        'Icon',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: WebInsets.sm),
                      InkWell(
                        onTap: _pickIcon,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              AccountBadge(
                                category: _category,
                                name: _nameController.text,
                                iconKey: _iconKey,
                                colorHex: _selectedColor,
                                size: 40,
                              ),
                              const SizedBox(width: WebInsets.md),
                              Expanded(
                                child: Text(
                                  'Tap to choose an icon or monogram',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: WebInsets.lg),
                      // Color picker
                      Text(
                        'Color',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: WebInsets.sm),
                      _ColorSwatchPicker(
                        selected: _selectedColor,
                        onSelected: (hex) =>
                            setState(() => _selectedColor = hex),
                      ),

                      // Conditional fields
                      if (_isGoal) ...[
                        const SizedBox(height: WebInsets.lg),
                        TextFormField(
                          controller: _goalTargetController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Goal Target',
                            prefixText: '₱ ',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (!_isGoal) return null;
                            final p =
                                double.tryParse((v ?? '').replaceAll(',', ''));
                            if (p == null || p <= 0) {
                              return 'Enter a goal target';
                            }
                            return null;
                          },
                        ),
                      ],
                      if (_isTimeDeposit) ...[
                        const SizedBox(height: WebInsets.lg),
                        _MaturityDateField(
                          date: _maturityDate,
                          onTap: _pickMaturityDate,
                        ),
                      ],
                      if (_isCustodian) ...[
                        const SizedBox(height: WebInsets.lg),
                        Builder(builder: (context) {
                          // Guard against a dangling link: if the stored
                          // linked account was deleted/de-listed, its id is no
                          // longer among the items and DropdownButtonFormField
                          // asserts. Fall back to "not linked". (Plan 052 C10)
                          final liquidIds = widget.presenter.liquidAccounts
                              .map((a) => a.id)
                              .toSet();
                          final selected = liquidIds.contains(_linkedAccountId)
                              ? _linkedAccountId
                              : null;
                          return DropdownButtonFormField<String>(
                            initialValue: selected,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Stored in account (optional)',
                              helperText:
                                  'These funds physically live in this account',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem<String>(
                                value: null,
                                child: Text(
                                  '— Not linked —',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ),
                              ...widget.presenter.liquidAccounts.map(
                                (a) => DropdownMenuItem<String>(
                                  value: a.id,
                                  child: Text(a.name),
                                ),
                              ),
                            ],
                            onChanged: (id) =>
                                setState(() => _linkedAccountId = id),
                          );
                        }),
                      ],
                      if (_isCredit) ...[
                        const SizedBox(height: WebInsets.lg),
                        _CreditDetailsSection(
                          creditLimitController: _creditLimitController,
                          financeRateController: _financeRateController,
                          statementDay: _statementDay,
                          onStatementDayChanged: (d) =>
                              setState(() => _statementDay = d),
                          paymentDueDay: _paymentDueDay,
                          onPaymentDueDayChanged: (d) =>
                              setState(() => _paymentDueDay = d),
                          creditBrand: _creditBrand,
                          onBrandChanged: _applyBrand,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            // Footer
            Padding(
              padding: const EdgeInsets.all(WebInsets.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isEdit) ...[
                    TextButton.icon(
                      onPressed: _isSubmitting ? null : _confirmDelete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                    ),
                    const Spacer(),
                  ],
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: WebInsets.sm),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isEdit ? 'Save' : 'Add Account'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Color swatch picker ──────────────────────────────────────────────────────

class _ColorSwatchPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _ColorSwatchPicker({required this.selected, required this.onSelected});

  Color _parse(String hex, Color fallback) {
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return fallback; // theme-resolved, not a hardcoded Colors.blue (T4)
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: WebInsets.md,
      runSpacing: WebInsets.md,
      children: [
        for (final hex in _colorOptions)
          _Swatch(
            color: _parse(hex, fallback),
            selected: hex.toLowerCase() == selected.toLowerCase(),
            onTap: () => onSelected(hex),
            semanticLabel: 'Color $hex',
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String semanticLabel;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 44px hit target wrapping a 32px visible swatch (≥44px touch rule).
    return Semantics(
      label: semanticLabel,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: cs.onSurface, width: 2.5)
                    : null,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 6,
                        )
                      ]
                    : null,
              ),
              child: selected
                  // Contrast against the arbitrary user swatch (not cs.onPrimary,
                  // which is near-invisible on light swatches in light mode). (T3)
                  ? Icon(Icons.check,
                      color: color.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white,
                      size: 18)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Maturity date field (time deposit) ───────────────────────────────────────

class _MaturityDateField extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onTap;

  const _MaturityDateField({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Maturity Date',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Icon(Icons.event_outlined, color: cs.onSurfaceVariant, size: 18),
            const SizedBox(width: WebInsets.md),
            Text(
              date != null
                  ? '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
                  : 'Pick a date',
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

// ─── Credit details (creditCard / creditLine / bnpl) ──────────────────────────

class _CreditDetailsSection extends StatelessWidget {
  final TextEditingController creditLimitController;
  final TextEditingController financeRateController;
  final int? statementDay;
  final ValueChanged<int?> onStatementDayChanged;
  final int? paymentDueDay;
  final ValueChanged<int?> onPaymentDueDayChanged;
  final String? creditBrand;
  final ValueChanged<String?> onBrandChanged;

  const _CreditDetailsSection({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Credit details',
          style:
              theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: WebInsets.sm),
        // Brand preset — seeds the finance rate when picked.
        DropdownButtonFormField<String?>(
          initialValue: creditBrand,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Card type (optional)',
            helperText: 'Pick a card to prefill its finance rate',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('— Manual —',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            ...kCreditBrandPresets.map(
              (p) =>
                  DropdownMenuItem<String?>(value: p.key, child: Text(p.label)),
            ),
          ],
          onChanged: onBrandChanged,
        ),
        const SizedBox(height: WebInsets.lg),
        TextFormField(
          controller: creditLimitController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
          ],
          decoration: const InputDecoration(
            labelText: 'Credit Limit',
            prefixText: '₱ ',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          validator: _optionalAmountValidator,
        ),
        const SizedBox(height: WebInsets.lg),
        Row(
          children: [
            Expanded(
              child: _DayOfMonthDropdown(
                label: 'Statement day',
                value: statementDay,
                onChanged: onStatementDayChanged,
              ),
            ),
            const SizedBox(width: WebInsets.lg),
            Expanded(
              child: _DayOfMonthDropdown(
                label: 'Due day',
                value: paymentDueDay,
                onChanged: onPaymentDueDayChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: WebInsets.lg),
        TextFormField(
          controller: financeRateController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
          ],
          decoration: const InputDecoration(
            labelText: 'Monthly finance rate',
            suffixText: '% / mo',
            helperText: 'Interest on unpaid balance (BSP cap 3%)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          validator: _optionalAmountValidator,
        ),
      ],
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
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
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
