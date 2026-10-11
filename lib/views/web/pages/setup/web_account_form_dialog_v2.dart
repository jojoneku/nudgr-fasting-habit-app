import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/credit_brand_presets.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../../design/account_category_label.dart';
import '../../web_keys.dart';
import '../../widgets/web_widgets.dart';
import 'web_account_form_rules.dart';

/// What the delete confirm says before [TreasuryDashboardPresenter.deleteAccount]
/// runs. The presenter enforces the rule — it refuses with
/// `StateError('has_sub_accounts')` when pockets still sit under the account
/// and `StateError('has_transactions')` when any transaction or bill still
/// references it — so this text only explains that rule; nothing is deleted
/// around it.
String webAccountDeleteMessage(FinancialAccount account) =>
    'This removes "${account.name}" from every list and picker. An account '
    'with transactions or bills linked to it cannot be deleted — delete or '
    'reassign those first (a goal can be archived instead, which keeps its '
    'history). Pockets under it must be removed first too.';

/// The toast for a refused delete, by the presenter's reason.
String webAccountDeleteError(StateError e) => switch (e.message) {
      'has_sub_accounts' =>
        'Remove all sub-accounts first before deleting this account.',
      'has_transactions' =>
        'This account has transactions or bills linked to it. '
            'Delete or reassign them first.',
      _ => 'Could not delete account: ${e.message}',
    };

/// The v2 Add/Edit Account form (Plan 063, Phase 8) on the kit's [WebDialog]:
/// Name and Type side by side, the balance (with the credit limit or the goal
/// target beside it when the type calls for one), a "Look" row of color
/// swatches with the badge preview, and the type's extra fields — the
/// "Statement & payment" fold for credit, maturity date for a time deposit,
/// the stored-in link for custodian money. Delete sits at the footer's left
/// in edit mode.
///
/// Builds the SAME [FinancialAccount] as `web_account_form_dialog.dart` (same
/// fields, defaults and id generation) and calls the SAME presenter methods
/// ([TreasuryDashboardPresenter.addAccount] / `updateAccount` /
/// `deleteAccount`). Only the dialog language changed.
class WebAccountFormDialogV2 extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;
  final FinancialAccount? existing;
  final String? parentAccountId;
  final AccountCategory? initialCategory;

  const WebAccountFormDialogV2({
    super.key,
    required this.presenter,
    this.existing,
    this.parentAccountId,
    this.initialCategory,
  });

  /// Opens the form. Add when [existing] is null, edit otherwise; with
  /// [parentAccountId] the form creates a pocket (savings / goal / time
  /// deposit) under that account. The dialog pops itself on save/delete; the
  /// presenter notifies, so callers need no result.
  static Future<void> show(
    BuildContext context,
    TreasuryDashboardPresenter presenter, {
    FinancialAccount? existing,
    String? parentAccountId,
    AccountCategory? initialCategory,
  }) {
    return showWebDialog<void>(
      context,
      builder: (_) => WebAccountFormDialogV2(
        presenter: presenter,
        existing: existing,
        parentAccountId: parentAccountId,
        initialCategory: initialCategory,
      ),
    );
  }

  @override
  State<WebAccountFormDialogV2> createState() => _WebAccountFormDialogV2State();
}

class _WebAccountFormDialogV2State extends State<WebAccountFormDialogV2> {
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  final _goalTargetController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _financeRateController = TextEditingController();
  final _minimumFixedController = TextEditingController();

  /// Field errors shown under their [WebField]; cleared on each submit.
  final Map<String, String> _errors = {};

  AccountCategory _category = AccountCategory.bank;
  String _selectedColor = kWebAccountColorOptions[0];

  /// Stored badge choice (catalog key / monogram sentinel / '' = default).
  String _iconKey = '';
  DateTime? _maturityDate;
  String? _linkedAccountId;
  int? _statementDay;
  int? _paymentDueDay;

  /// Payment-due rule: false = a fixed day of month ([_paymentDueDay]), true =
  /// a number of days after the statement closes ([_dueDaysAfterStatement]).
  bool _dueAfterStatement = false;
  int? _dueDaysAfterStatement;

  /// The user's explicit minimum-payment pick. Null means "not chosen yet", so
  /// a new account keeps following its category default as the type changes.
  CreditMinimumRule? _minimumRuleChoice;
  String? _creditBrand;
  bool _isSubmitting = false;

  /// The parent this account belongs to. On EDIT the page opens the dialog
  /// without `parentAccountId`, so fall back to the record's parent — saving
  /// a pocket with `parentAccountId: null` would detach it.
  String? get _effectiveParentId =>
      widget.existing?.parentAccountId ?? widget.parentAccountId;

  bool get _isPocket => _effectiveParentId != null;
  bool get _isEdit => widget.existing != null;

  List<AccountCategory> get _availableCategories =>
      _isPocket ? kWebSubAccountCategories : kWebTopLevelAccountCategories;

  bool get _isGoal => _category == AccountCategory.goal;
  bool get _isTimeDeposit => _category == AccountCategory.timeDeposit;
  bool get _isCustodian => _category == AccountCategory.custodian;
  bool get _isCredit =>
      _category == AccountCategory.creditCard ||
      _category == AccountCategory.creditLine ||
      _category == AccountCategory.bnpl;

  CreditMinimumRule get _minimumRule =>
      _minimumRuleChoice ?? defaultMinimumRuleFor(_category);
  bool get _isFixedMinimum => _minimumRule == CreditMinimumRule.fixedAmount;

  FinancialAccount? get _parent {
    final id = _effectiveParentId;
    if (id == null) return null;
    return widget.presenter.accounts.where((a) => a.id == id).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    if (widget.parentAccountId != null) _category = AccountCategory.savings;
    if (widget.initialCategory != null) _category = widget.initialCategory!;

    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _balanceController.text = widget.presenter
          .accountBalanceFieldValue(existing)
          .toStringAsFixed(2);
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
      _dueDaysAfterStatement = existing.dueDaysAfterStatement;
      _dueAfterStatement = existing.dueDaysAfterStatement != null;
      _minimumRuleChoice =
          existing.isLiability ? existing.effectiveMinimumRule : null;
      if (existing.minimumFixedAmount != null) {
        _minimumFixedController.text =
            existing.minimumFixedAmount!.toStringAsFixed(2);
      }
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
    _minimumFixedController.dispose();
    super.dispose();
  }

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
      lastDate: kWebDateRange.end,
    );
    if (picked != null && mounted) setState(() => _maturityDate = picked);
  }

  bool _validate() {
    final errors = <String, String>{};
    if (_nameController.text.trim().isEmpty) {
      errors['name'] = 'Enter account name';
    }
    final balance = webOptionalAmountValidator(_balanceController.text) ??
        widget.presenter.accountBalanceError(_category, _balanceController.text,
            accountId: widget.existing?.id);
    if (balance != null) errors['balance'] = balance;
    if (_isGoal) {
      final target = webParseAmount(_goalTargetController.text);
      if (target == null || target <= 0) {
        errors['goalTarget'] = 'Enter a goal target';
      }
    }
    if (_isCredit) {
      final limit = webOptionalAmountValidator(_creditLimitController.text);
      if (limit != null) errors['creditLimit'] = limit;
      if (_isFixedMinimum) {
        final min = webPositiveAmountValidator(_minimumFixedController.text);
        if (min != null) errors['minimumFixed'] = min;
      }
      final rate = webOptionalAmountValidator(_financeRateController.text);
      if (rate != null) errors['financeRate'] = rate;
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    return errors.isEmpty;
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final id = widget.existing?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
      final balance = widget.presenter.balanceFromField(
        _category,
        webParseAmount(_balanceController.text) ?? 0,
        accountId: widget.existing?.id,
      );
      final goalTarget = _isGoal && _goalTargetController.text.isNotEmpty
          ? webParseAmount(_goalTargetController.text)
          : null;
      final creditLimit = _isCredit && _creditLimitController.text.isNotEmpty
          ? webParseAmount(_creditLimitController.text)
          : null;
      final financeRatePercent =
          _isCredit ? webParseAmount(_financeRateController.text) : null;
      final minimumFixedAmount = _isCredit && _isFixedMinimum
          ? webParseAmount(_minimumFixedController.text)
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
        linkedAccountId: _isCustodian ? _linkedAccountId : null,
        creditLimit: creditLimit,
        statementDay: _isCredit ? _statementDay : null,
        // Exactly one due rule is stored: a fixed day OR an offset from close.
        paymentDueDay: _isCredit && !_dueAfterStatement ? _paymentDueDay : null,
        dueDaysAfterStatement:
            _isCredit && _dueAfterStatement ? _dueDaysAfterStatement : null,
        // Always saved explicitly for credit, so a later change to the
        // category default never silently re-rules an existing account.
        minimumRule: _isCredit ? _minimumRule : null,
        minimumFixedAmount: minimumFixedAmount,
        // Stored as a fraction; entered as a percent.
        financeChargeRate:
            (financeRatePercent != null && financeRatePercent > 0)
                ? financeRatePercent / 100
                : null,
        creditBrand: _isCredit ? _creditBrand : null,
      );

      if (_isEdit) {
        await widget.presenter.updateAccount(account);
      } else {
        await widget.presenter.addAccount(account);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Could not save account: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _confirmDelete() async {
    final account = widget.existing!;
    final confirmed = await showWebConfirm(
      context,
      title: 'Delete ${account.name}?',
      message: webAccountDeleteMessage(account),
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.presenter.deleteAccount(account.id);
      if (mounted) Navigator.of(context).pop();
    } on StateError catch (e) {
      if (!mounted) return;
      AppToast.error(context, webAccountDeleteError(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parent = _parent;
    final String title;
    if (_isEdit) {
      title = 'Edit account';
    } else if (_isPocket) {
      title = 'Add pocket or goal';
    } else {
      title = 'Add account';
    }
    final subtitle = parent == null
        ? null
        : 'Inside ${parent.name} · its balance stays part of the parent';

    return WebDialog(
      title: title,
      subtitle: subtitle,
      width: kWebDialogWideWidth,
      destructive: _isEdit
          ? TextButton.icon(
              key: WebKeys.setupFormDelete,
              onPressed: _isSubmitting ? null : _confirmDelete,
              style: TextButton.styleFrom(foregroundColor: cs.error),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete'),
            )
          : null,
      secondary: TextButton(
        key: WebKeys.setupFormCancel,
        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      primary: FilledButton(
        key: WebKeys.setupFormSave,
        onPressed: _isSubmitting ? null : _submit,
        child: _isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                _isEdit ? 'Save' : (_isPocket ? 'Add pocket' : 'Add account')),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _TwoUp(
            left: WebField(
              label: 'Name',
              error: _errors['name'],
              child: WebInput(
                key: WebKeys.setupFormName,
                controller: _nameController,
                autofocus: !_isEdit,
                hint: _isPocket ? 'Travel Fund' : 'BPI Savings',
                textInputAction: TextInputAction.next,
                error: _errors['name'] != null,
                // Keeps the badge preview's monogram tracking the name.
                onChanged: (_) => setState(() {}),
              ),
            ),
            right: WebField(
              label: 'Type',
              child: _Dropdown<AccountCategory>(
                key: WebKeys.setupFormCategory,
                value: _category,
                items: [
                  for (final c in _availableCategories)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (c) => setState(() => _category = c ?? _category),
              ),
            ),
          ),
          const SizedBox(height: WebInsets.lg),
          _balanceRow(context),
          const SizedBox(height: WebInsets.lg),
          _lookField(context),
          if (_isTimeDeposit) ...[
            const SizedBox(height: WebInsets.lg),
            _maturityField(context),
          ],
          if (_isCustodian) ...[
            const SizedBox(height: WebInsets.lg),
            _custodianField(context),
          ],
          if (_isCredit) ...[
            const SizedBox(height: WebInsets.lg),
            _creditFold(context),
          ],
        ],
      ),
    );
  }

  /// The balance input, with the credit limit (credit) or the target (goal)
  /// beside it; alone otherwise.
  Widget _balanceRow(BuildContext context) {
    final balance = WebField(
      label: widget.presenter.accountBalanceLabel(_category),
      helper: widget.presenter
          .accountBalanceHint(_category, accountId: widget.existing?.id),
      error: _errors['balance'],
      child: _amountInput(
        key: WebKeys.setupFormBalance,
        controller: _balanceController,
        error: _errors['balance'] != null,
        onSubmitted: (_) => _submit(),
      ),
    );
    if (_isCredit) {
      return _TwoUp(
        left: balance,
        right: WebField(
          label: 'Credit limit',
          error: _errors['creditLimit'],
          child: _amountInput(
            key: _kFormCreditLimit,
            controller: _creditLimitController,
            error: _errors['creditLimit'] != null,
          ),
        ),
      );
    }
    if (_isGoal) {
      return _TwoUp(
        left: balance,
        right: WebField(
          label: 'Target',
          error: _errors['goalTarget'],
          child: _amountInput(
            key: WebKeys.setupFormGoalTarget,
            controller: _goalTargetController,
            error: _errors['goalTarget'] != null,
          ),
        ),
      );
    }
    return balance;
  }

  Widget _amountInput({
    required Key key,
    required TextEditingController controller,
    required bool error,
    ValueChanged<String>? onSubmitted,
  }) {
    return WebInput(
      key: key,
      controller: controller,
      prefixText: '₱',
      hint: '0.00',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      textInputAction:
          onSubmitted == null ? TextInputAction.next : TextInputAction.done,
      onSubmitted: onSubmitted,
      error: error,
    );
  }

  /// Color swatches with the badge preview at the right; the preview opens
  /// the icon / monogram picker.
  Widget _lookField(BuildContext context) {
    return WebField(
      label: 'Look',
      helper: 'Pick a color · click the tile to choose an icon or monogram',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              key: WebKeys.setupFormColor,
              spacing: WebInsets.xs,
              runSpacing: WebInsets.xs,
              children: [
                for (final hex in kWebAccountColorOptions)
                  _Swatch(
                    hex: hex,
                    selected: hex.toLowerCase() == _selectedColor.toLowerCase(),
                    onTap: () => setState(() => _selectedColor = hex),
                  ),
              ],
            ),
          ),
          const SizedBox(width: WebInsets.md),
          Tooltip(
            message: 'Choose an icon or monogram',
            child: InkWell(
              key: WebKeys.setupFormIcon,
              onTap: _pickIcon,
              borderRadius: AppRadii.mdBorder,
              child: SizedBox(
                width: kWebHitTarget,
                height: kWebHitTarget,
                child: Center(
                  child: AccountBadge(
                    category: _category,
                    name: _nameController.text,
                    iconKey: _iconKey,
                    colorHex: _selectedColor,
                    size: 36,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _maturityField(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = _maturityDate;
    final label = d == null
        ? 'Pick a date'
        : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return WebField(
      label: 'Maturity date',
      child: InkWell(
        key: WebKeys.setupFormMaturity,
        onTap: _pickMaturityDate,
        borderRadius: AppRadii.mdBorder,
        child: Theme(
          data:
              Theme.of(context).copyWith(visualDensity: VisualDensity.standard),
          child: InputDecorator(
            decoration: WebInput.decoration(
              context,
              suffixIcon: const Icon(Icons.event_outlined, size: 18),
            ),
            child: Text(
              label,
              style: WebInput.textStyle(context).copyWith(
                color: d == null ? cs.onSurfaceVariant : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _custodianField(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Guard against a dangling link: if the stored linked account was
    // deleted, its id is no longer among the items and the dropdown asserts.
    final liquid = widget.presenter.liquidAccounts;
    final selected =
        liquid.any((a) => a.id == _linkedAccountId) ? _linkedAccountId : null;
    return WebField(
      label: 'Stored in account',
      optional: true,
      helper: 'These funds physically live in this account',
      child: _Dropdown<String?>(
        key: WebKeys.setupFormCustodianLink,
        value: selected,
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text('— Not linked —',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          for (final a in liquid)
            DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
        ],
        onChanged: (id) => setState(() => _linkedAccountId = id),
      ),
    );
  }

  /// "Statement & payment" — the credit details (brand preset, statement and
  /// due days, minimum rule, finance rate) in one fold, open by default so a
  /// new card's billing cycle is not missed.
  Widget _creditFold(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return WebFold(
      key: WebKeys.setupFormCreditFold,
      title: 'Statement & payment',
      subtitle: 'So Bills can create the statement',
      initiallyOpen: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _TwoUp(
            left: WebField(
              label: 'Card preset',
              optional: true,
              helper: 'Prefills the finance rate',
              child: _Dropdown<String?>(
                key: _kFormCardPreset,
                value: _creditBrand,
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('— Manual —',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                  for (final p in kCreditBrandPresets)
                    DropdownMenuItem<String?>(
                        value: p.key, child: Text(p.label)),
                ],
                onChanged: _applyBrand,
              ),
            ),
            right: WebField(
              label: 'Statement day',
              child: _DayNumberDropdown(
                key: _kFormStatementDay,
                value: _statementDay,
                onChanged: (d) => setState(() => _statementDay = d),
              ),
            ),
          ),
          const SizedBox(height: WebInsets.lg),
          WebField(
            label: 'Payment due',
            helper: _dueAfterStatement
                ? 'Some issuers count days from the statement, e.g. due 15 days after.'
                : null,
            child: WebSegmented<bool>(
              segments: const [
                WebSegment(false, 'Day of month'),
                WebSegment(true, 'Days after statement'),
              ],
              value: _dueAfterStatement,
              onChanged: (v) => setState(() => _dueAfterStatement = v),
            ),
          ),
          const SizedBox(height: WebInsets.lg),
          // Keyed per mode: the two pickers hold different numbers, and a
          // shared field state would carry one into the other.
          if (_dueAfterStatement)
            WebField(
              label: 'Due after',
              child: _DayNumberDropdown(
                key: const ValueKey('web.setup.form.dueDaysAfter'),
                value: _dueDaysAfterStatement,
                max: kMaxDueDaysAfterStatement,
                itemLabel: (d) => d == 1 ? '1 day' : '$d days',
                onChanged: (d) => setState(() => _dueDaysAfterStatement = d),
              ),
            )
          else
            WebField(
              label: 'Due day',
              child: _DayNumberDropdown(
                key: const ValueKey('web.setup.form.dueDay'),
                value: _paymentDueDay,
                onChanged: (d) => setState(() => _paymentDueDay = d),
              ),
            ),
          const SizedBox(height: WebInsets.lg),
          WebField(
            label: 'Minimum payment',
            child: WebSegmented<CreditMinimumRule>(
              segments: const [
                WebSegment(CreditMinimumRule.percentOfBalance, '% of balance'),
                WebSegment(CreditMinimumRule.fixedAmount, 'Fixed amount'),
                WebSegment(CreditMinimumRule.payInFull, 'Pay in full'),
              ],
              value: _minimumRule,
              onChanged: (r) => setState(() => _minimumRuleChoice = r),
            ),
          ),
          if (_isFixedMinimum) ...[
            const SizedBox(height: WebInsets.lg),
            WebField(
              label: 'Minimum amount',
              helper: 'e.g. a monthly installment',
              error: _errors['minimumFixed'],
              child: _amountInput(
                key: _kFormMinimumFixed,
                controller: _minimumFixedController,
                error: _errors['minimumFixed'] != null,
              ),
            ),
          ],
          const SizedBox(height: WebInsets.lg),
          WebField(
            label: 'Finance rate / month',
            helper: 'Interest on the unpaid balance · BSP cap 3%',
            error: _errors['financeRate'],
            child: WebInput(
              key: _kFormFinanceRate,
              controller: _financeRateController,
              hint: '3.00',
              suffix: Text('% / mo',
                  style: WebInput.textStyle(context)
                      .copyWith(fontSize: 13, color: cs.onSurfaceVariant)),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ],
              error: _errors['financeRate'] != null,
            ),
          ),
        ],
      ),
    );
  }
}

// Local keys (not yet in WebKeys): the credit-only inputs.
const _kFormCreditLimit = ValueKey('web.setup.form.creditLimit');
const _kFormCardPreset = ValueKey('web.setup.form.cardPreset');
const _kFormStatementDay = ValueKey('web.setup.form.statementDay');
const _kFormMinimumFixed = ValueKey('web.setup.form.minimumFixed');
const _kFormFinanceRate = ValueKey('web.setup.form.financeRate');

/// Two fields side by side with the canvas' 14 px gutter.
class _TwoUp extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _TwoUp({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 14),
        Expanded(child: right),
      ],
    );
  }
}

/// A dropdown in the kit's input decoration.
class _Dropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _Dropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(visualDensity: VisualDensity.standard),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: WebInput.decoration(context),
        style: WebInput.textStyle(context),
        dropdownColor: theme.colorScheme.surfaceContainerHigh,
        borderRadius: AppRadii.mdBorder,
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

/// Dropdown for choosing a day number: a day of month (1–28 by default, to
/// stay valid in February) or, with [max], a count of days.
class _DayNumberDropdown extends StatelessWidget {
  final int? value;
  final int max;
  final String Function(int)? itemLabel;
  final ValueChanged<int?> onChanged;

  const _DayNumberDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.max = 28,
    this.itemLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Dropdown<int?>(
      value: value,
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text('—', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        for (int d = 1; d <= max; d++)
          DropdownMenuItem<int?>(
              value: d, child: Text(itemLabel?.call(d) ?? '$d')),
      ],
      onChanged: onChanged,
    );
  }
}

/// One account color swatch: a 28 px circle in a 44 px hit area, a check on
/// the selected one in whichever of black/white reads on that swatch.
class _Swatch extends StatelessWidget {
  final String hex;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color color;
    try {
      color = Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      color = cs.primary;
    }
    return Semantics(
      label: 'Color $hex',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: kWebHitTarget,
          height: kWebHitTarget,
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: cs.onSurface, width: 2.5)
                    : null,
              ),
              child: selected
                  ? Icon(Icons.check,
                      size: 16,
                      color: color.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
