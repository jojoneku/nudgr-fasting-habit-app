import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/credit_cycle.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_chips.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class AddTransactionSheet extends StatefulWidget {
  final LedgerPresenter presenter;
  final TransactionRecord? existing;

  /// Optional draft from chat-logging fallback — fills the form with what
  /// the AI managed to extract so the user can finish entry by hand.
  final ParsedTransaction? prefill;

  /// Pre-selects the transaction date for a NEW entry — used when the ledger has
  /// a past day filtered, so logging a forgotten transaction lands on that day
  /// without first clearing the filter. Ignored when editing an existing record.
  final DateTime? initialDate;

  const AddTransactionSheet({
    super.key,
    required this.presenter,
    this.existing,
    this.prefill,
    this.initialDate,
  });

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _amountFocus = FocusNode();
  final _descriptionController = TextEditingController();
  final _noteController = TextEditingController();
  final _owedByController = TextEditingController();

  TransactionType _type = TransactionType.outflow;
  String? _selectedAccountId;
  String? _transferToAccountId;
  String? _selectedCategoryId;
  DateTime _date = DateTime.now();

  // Reimbursable-expense state (outflow only): money spent now, recovered later.
  bool _reimbursable = false;
  DateTime? _expectedReimbursementDate;

  // Installment purchase state (outflow on liability account only):
  bool _splitInstallments = false;
  int _installmentMonths = 3;
  double _interestRate = 0.0;

  FinancialAccount? get _selectedAccount {
    final id = _selectedAccountId;
    if (id == null) return null;
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  bool _isSubmitting = false;

  // Cached presenter data — updated only when presenter fires, not on keystrokes
  List<FinancialAccount> _accounts = [];
  List<FinanceCategory> _categories = [];

  @override
  void initState() {
    super.initState();
    _syncFromPresenter();
    _amountFocus.addListener(_onAmountFocusChange);
    widget.presenter.addListener(_onPresenterChange);
    // LedgerPresenter may have stale accounts if they were added/edited via
    // TreasuryDashboardPresenter. Reload from storage; the listener will
    // call _syncFromPresenter once the load completes.
    widget.presenter.reloadAccounts();
    final existing = widget.existing;
    if (existing != null) {
      _amountController.text = existing.amount.toStringAsFixed(2);
      _descriptionController.text = existing.description;
      _noteController.text = existing.note ?? '';
      _selectedCategoryId = existing.categoryId;
      _date = existing.date;
      if (existing.isInstallment) {
        _splitInstallments = true;
        final inst =
            widget.presenter.findInstallmentById(existing.installmentId);
        if (inst != null) {
          _installmentMonths = inst.totalMonths;
          _interestRate = inst.interestRate;
        }
      }
      if (existing.transferGroupId != null) {
        // A transfer is stored as two legs (outflow on the source, inflow on
        // the destination) that share a groupId — NEITHER leg's `type` is
        // `transfer`. Deriving the toggle from the leg's type therefore always
        // reverted a transfer to Outflow on open. Detect the group instead and
        // rebuild From/To from the two legs.
        _type = TransactionType.transfer;
        String? fromId;
        String? toId;
        for (final t in widget.presenter.allTransactions) {
          if (t.transferGroupId != existing.transferGroupId) continue;
          if (t.type == TransactionType.outflow) fromId = t.accountId;
          if (t.type == TransactionType.inflow) toId = t.accountId;
        }
        _selectedAccountId = fromId ?? existing.accountId;
        _transferToAccountId = toId ?? existing.transferToAccountId;
      } else {
        _type = existing.type;
        _selectedAccountId = existing.accountId;
        _transferToAccountId = existing.transferToAccountId;
        _reimbursable = existing.reimbursable;
        _owedByController.text = existing.owedBy ?? '';
        // The expected payback date lives on the linked receivable, not on the
        // transaction — load it so editing a scheduled reimbursable doesn't
        // silently show (and re-save) "ASAP". Null stays "ASAP".
        final receivableId = existing.reimbursementReceivableId;
        if (existing.reimbursable && receivableId != null) {
          _expectedReimbursementDate = widget.presenter
              .reimbursementReceivableExpectedDate(receivableId);
        }
      }
    } else {
      if (widget.initialDate != null) _date = widget.initialDate!;
      final prefill = widget.prefill;
      if (prefill != null) {
        if (prefill.type != null) _type = prefill.type!;
        if (prefill.amount != null) {
          _amountController.text = prefill.amount!.toStringAsFixed(2);
        }
        if (prefill.description.isNotEmpty) {
          _descriptionController.text = prefill.description;
        }
        _selectedAccountId = prefill.accountId;
        _transferToAccountId = prefill.transferToAccountId;
        _selectedCategoryId = prefill.categoryId;
        if (prefill.reimbursable) {
          // No payback date by default — "ASAP", surfaces in the current month.
          // The user can set a fixed date below if they know when they'll be paid.
          _reimbursable = true;
        }
      }
    }
  }

  void _syncFromPresenter() {
    _accounts = widget.presenter.accounts
        .where((a) => a.isActive && !a.isSubAccount)
        .toList();
    _categories = widget.presenter.categories;
  }

  void _onPresenterChange() {
    if (!mounted) return;
    setState(_syncFromPresenter);
  }

  // Drives the operator strip (visible only while the amount field is focused)
  // and folds any typed expression down to its result on blur.
  void _onAmountFocusChange() {
    if (!mounted) return;
    if (!_amountFocus.hasFocus) {
      final text = _amountController.text;
      final value = text.isEmpty ? null : evalAmountExpression(text);
      if (value != null) {
        final formatted = formatEvaluatedAmount(value);
        if (formatted != text) _amountController.text = formatted;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.presenter.removeListener(_onPresenterChange);
    _amountFocus.removeListener(_onAmountFocusChange);
    _amountFocus.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _noteController.dispose();
    _owedByController.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _filteredCategories {
    if (_type == TransactionType.inflow) {
      return _categories.where((c) => c.type == CategoryType.income).toList();
    }
    if (_type == TransactionType.outflow) {
      return _categories.where((c) => c.type == CategoryType.expense).toList();
    }
    return _categories;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Account fields are pickers (not form fields), so validate them here and
    // surface feedback the old dropdown validator used to show.
    if (_selectedAccountId == null) {
      AppToast.error(context, 'Select an account');
      return;
    }
    if (_type == TransactionType.transfer && _transferToAccountId == null) {
      AppToast.error(context, 'Select a destination account');
      return;
    }
    // The amount is a borderless calculator field (no inline error): evaluate
    // any `+ - × ÷` expression to a value and validate here.
    final amount = evalAmountExpression(_amountController.text);
    if (amount == null || amount <= 0) {
      AppToast.error(context, 'Enter an amount greater than 0');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final description = _descriptionController.text.trim();
      final note = _noteController.text.trim();
      final month = toMonthKey(_date);
      final categoryId = _selectedCategoryId ?? '';

      final existing = widget.existing;
      if (_type == TransactionType.transfer) {
        // Editing a transfer: drop the existing leg(s) first so we replace the
        // pair in place. addTransfer always creates a fresh outflow+inflow
        // pair, so without this an edit would duplicate the transfer and
        // double-apply the balances.
        if (existing != null) {
          await widget.presenter.deleteTransactionOrGroup(existing.id);
        }
        await widget.presenter.addTransfer(
          fromAccountId: _selectedAccountId!,
          toAccountId: _transferToAccountId!,
          amount: amount,
          description: description,
          date: _date,
          note: note.isEmpty ? null : note,
        );
      } else if (_type == TransactionType.outflow &&
          _splitInstallments &&
          (existing == null ||
              existing.isInstallment ||
              existing.installmentId == null) &&
          _selectedAccount?.isLiability == true) {
        final startMonth = calculateInstallmentStartMonth(
          _selectedAccount,
          _date,
          deferralMonths: 0,
        );
        final monthlyAmount = Installment.computeMonthlyAmount(
          principal: amount,
          months: _installmentMonths,
          monthlyRate: _interestRate,
        );
        final instId = existing?.installmentId ?? _generateId();
        final inst = Installment(
          id: instId,
          name: description.isEmpty ? 'Installment purchase' : description,
          accountId: _selectedAccountId!,
          totalAmount: amount,
          monthlyAmount: double.parse(monthlyAmount.toStringAsFixed(2)),
          totalMonths: _installmentMonths,
          startMonth: startMonth,
          purchaseDate: _date,
          deferralMonths: 0,
          interestRate: _interestRate,
          note: note.isEmpty ? null : note,
          categoryId: categoryId.isEmpty ? null : categoryId,
          isActive: true,
        );
        if (existing != null) {
          final oldReceivableId = existing.reimbursementReceivableId;
          if (oldReceivableId != null) {
            await widget.presenter
                .deleteReimbursementReceivable(oldReceivableId);
          }
          if (existing.transferGroupId != null) {
            await widget.presenter.deleteTransactionOrGroup(existing.id);
          } else {
            await widget.presenter.deleteTransaction(existing.id);
          }
        }
        await widget.presenter.addInstallmentPurchase(
          inst,
          transaction: TransactionRecord(
            id: existing?.id ?? _generateId(),
            date: _date,
            accountId: _selectedAccountId!,
            categoryId: categoryId.isEmpty ? '' : categoryId,
            amount: amount,
            type: TransactionType.outflow,
            description:
                description.isEmpty ? 'Installment purchase' : description,
            note: note.isEmpty ? null : note,
            month: toMonthKey(_date),
            installmentId: inst.id,
            isInstallment: true,
          ),
        );
      } else {
        final id = existing?.id ?? _generateId();
        // Reimbursable only applies to outflows. Reuse the existing linked
        // receivable id when editing so the link survives; mint one otherwise.
        final isReimbursable =
            _type == TransactionType.outflow && _reimbursable;
        final receivableId = isReimbursable
            ? (existing?.reimbursementReceivableId ?? _generateId())
            : null;
        final owedBy = _owedByController.text.trim();
        final txn = TransactionRecord(
          id: id,
          date: _date,
          accountId: _selectedAccountId!,
          categoryId: categoryId,
          amount: amount,
          type: _type,
          description: description,
          note: note.isEmpty ? null : note,
          month: month,
          reimbursable: isReimbursable,
          reimbursementReceivableId: receivableId,
          owedBy: isReimbursable && owedBy.isNotEmpty ? owedBy : null,
        );
        // Null = "ASAP / no set date" — surfaces in the current month.
        final expectedDate = _expectedReimbursementDate;
        if (existing != null) {
          // Drop a stale linked receivable when the expense is no longer
          // reimbursable (toggled off, or type changed away from outflow).
          final oldReceivableId = existing.reimbursementReceivableId;
          if (oldReceivableId != null && !isReimbursable) {
            await widget.presenter
                .deleteReimbursementReceivable(oldReceivableId);
          }
          if (existing.transferGroupId != null) {
            // Converting a transfer into a normal income/expense: remove the
            // whole transfer group, then add the single replacement record.
            await widget.presenter.deleteTransactionOrGroup(existing.id);
            await widget.presenter.addTransaction(txn);
          } else {
            await widget.presenter.updateTransaction(txn);
          }
          // Newly reimbursable → spawn; still reimbursable on an existing
          // receivable → re-sync its amount/name/owedBy so it never drifts.
          if (isReimbursable && oldReceivableId == null) {
            await widget.presenter
                .spawnReimbursementReceivable(txn, expectedDate);
          } else if (isReimbursable) {
            // Propagate the (possibly changed or cleared) payback date so the
            // edit actually updates the receivable's schedule, not just its
            // amount/name.
            await widget.presenter.syncReimbursementReceivable(
              txn,
              updateExpectedDate: true,
              expectedDate: expectedDate,
            );
          }
        } else if (isReimbursable) {
          await widget.presenter.addReimbursableExpense(
            txn,
            expectedReimbursementDate: expectedDate,
          );
        } else {
          await widget.presenter.addTransaction(txn);
        }
      }

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  /// Default "expected back by" horizon for a reimbursable expense: 30 days
  /// after the transaction date.
  DateTime get _defaultExpectedReimbursementDate =>
      _date.add(const Duration(days: 30));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickExpectedReimbursementDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _expectedReimbursementDate ?? _defaultExpectedReimbursementDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _expectedReimbursementDate = picked);
    }
  }

  /// Pre-fills the transfer for the "paid on my card for someone, they paid me
  /// back in cash" case: From = a credit card (liability), To = a cash account.
  /// Picks the first of each as a starting point; the user can change either.
  void _applyPaidForSomeonePreset() {
    final cards = _accounts.where((a) => a.isLiability).toList();
    final cash =
        _accounts.where((a) => a.category == AccountCategory.cash).toList();
    setState(() {
      if (cards.isNotEmpty) _selectedAccountId = cards.first.id;
      if (cash.isNotEmpty) _transferToAccountId = cash.first.id;
    });
  }

  Future<void> _quickAddAccount([ValueChanged<String?>? onCreated]) async {
    final nameCtrl = TextEditingController();
    var category = AccountCategory.bank;
    final created = await showDialog<FinancialAccount>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Account Name',
                  hintText: 'e.g. BDO Savings, Cash, Maya',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AccountCategory>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(
                      value: AccountCategory.bank, child: Text('Bank')),
                  DropdownMenuItem(
                      value: AccountCategory.ewallet, child: Text('E-Wallet')),
                  DropdownMenuItem(
                      value: AccountCategory.cash, child: Text('Cash')),
                  DropdownMenuItem(
                      value: AccountCategory.creditCard,
                      child: Text('Credit Card')),
                  DropdownMenuItem(
                      value: AccountCategory.savings, child: Text('Savings')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => category = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final acc = await widget.presenter.createQuickAccount(
                  name: name,
                  category: category,
                );
                if (ctx.mounted) Navigator.pop(ctx, acc);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (created != null && mounted) {
      setState(() {
        _syncFromPresenter();
        if (onCreated != null) {
          onCreated(created.id);
        } else {
          _selectedAccountId = created.id;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TypeToggle(
                      selected: _type,
                      onChanged: (t) => setState(() {
                            _type = t;
                            _selectedCategoryId = null;
                          })),
                  const SizedBox(height: 20),
                  // The amount is the hero: a big centered number (reference
                  // "Log transaction" sheet), with description + date below it.
                  _BigAmountField(
                      controller: _amountController, focusNode: _amountFocus),
                  const SizedBox(height: 18),
                  _DescriptionField(controller: _descriptionController),
                  const SizedBox(height: 12),
                  if (_type == TransactionType.transfer) ...[
                    _DatePickerRow(date: _date, onTap: _pickDate),
                    const SizedBox(height: 12),
                    _AccountDropdown(
                      accounts: _accounts,
                      label: 'From Account',
                      value: _selectedAccountId,
                      onChanged: (v) => setState(() => _selectedAccountId = v),
                      onAddAccount: () => _quickAddAccount(
                          (id) => setState(() => _selectedAccountId = id)),
                    ),
                    const SizedBox(height: 12),
                    _AccountDropdown(
                      accounts: _accounts,
                      label: 'To Account',
                      value: _transferToAccountId,
                      onChanged: (v) =>
                          setState(() => _transferToAccountId = v),
                      onAddAccount: () => _quickAddAccount(
                          (id) => setState(() => _transferToAccountId = id)),
                    ),
                    const SizedBox(height: 12),
                    _PaidForSomeoneHint(
                        onUsePreset: _applyPaidForSomeonePreset),
                  ] else ...[
                    // Category + Account side by side (both are picker boxes;
                    // Category opens a sheet of colored pills). Reference layout.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SheetLabeledField(
                            label: 'Category',
                            child: CategoryPickerField(
                              categories: _filteredCategories,
                              selectedId: _selectedCategoryId,
                              onChanged: (id) =>
                                  setState(() => _selectedCategoryId = id),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _AccountDropdown(
                            accounts: _accounts,
                            label: 'Account',
                            value: _selectedAccountId,
                            onChanged: (v) =>
                                setState(() => _selectedAccountId = v),
                            onAddAccount: () => _quickAddAccount((id) =>
                                setState(() => _selectedAccountId = id)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _DatePickerRow(date: _date, onTap: _pickDate),
                  ],
                  if (_type == TransactionType.outflow) ...[
                    if ((!isEdit ||
                            widget.existing?.isInstallment == true ||
                            widget.existing?.installmentId == null) &&
                        _selectedAccount?.isLiability == true) ...[
                      const SizedBox(height: 12),
                      _InstallmentField(
                        value: _splitInstallments,
                        months: _installmentMonths,
                        interestRate: _interestRate,
                        isEdit: isEdit,
                        amount:
                            evalAmountExpression(_amountController.text) ?? 0.0,
                        onChanged: (v) {
                          setState(() {
                            _splitInstallments = v;
                            if (v) _reimbursable = false;
                          });
                        },
                        onMonthsChanged: (m) =>
                            setState(() => _installmentMonths = m),
                        onInterestRateChanged: (r) =>
                            setState(() => _interestRate = r),
                      ),
                    ],
                    if (!_splitInstallments) ...[
                      const SizedBox(height: 12),
                      _ReimbursableField(
                        value: _reimbursable,
                        expectedDate: _expectedReimbursementDate,
                        owedByController: _owedByController,
                        onChanged: (v) => setState(() => _reimbursable = v),
                        onPickDate: _pickExpectedReimbursementDate,
                        onClearDate: () =>
                            setState(() => _expectedReimbursementDate = null),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  _NoteField(controller: _noteController),
                  const SizedBox(height: 20),
                  AppPrimaryButton(
                    label: isEdit
                        ? (_splitInstallments
                            ? 'Convert to Installments'
                            : 'Save')
                        : (_splitInstallments
                            ? 'Log Installment'
                            : 'Log Transaction'),
                    isLoading: _isSubmitting,
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                  if (isEdit) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final nav = Navigator.of(context);
                          final confirmed = await AppConfirmDialog.confirm(
                            context: context,
                            title: 'Delete Transaction',
                            body: 'Delete "${widget.existing!.description}"?',
                            confirmLabel: 'Delete',
                            isDestructive: true,
                          );
                          if (confirmed && mounted) {
                            await widget.presenter
                                .deleteTransaction(widget.existing!.id);
                            nav.pop();
                          }
                        },
                        icon: Icon(Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error),
                        label: Text('Delete',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .error
                                  .withValues(alpha: 0.5)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
        // Calculator operator strip: a keyboard accessory shown only while the
        // amount field is focused (the OS numeric keypad has no +−×÷ keys), so
        // "calculator via keyboard" works without changing the form layout.
        if (_amountFocus.hasFocus)
          _OperatorBar(controller: _amountController, focusNode: _amountFocus),
      ],
    );
  }
}

// ── Type Toggle ───────────────────────────────────────────────────────────────

class _TypeToggle extends StatelessWidget {
  final TransactionType selected;
  final ValueChanged<TransactionType> onChanged;

  const _TypeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SheetSegmentedToggle<TransactionType>(
      value: selected,
      onChanged: onChanged,
      segments: [
        SheetSegment(
            label: 'Inflow',
            value: TransactionType.inflow,
            accent: cs.tertiary),
        SheetSegment(
            label: 'Outflow', value: TransactionType.outflow, accent: cs.error),
        SheetSegment(
            label: 'Transfer',
            value: TransactionType.transfer,
            accent: cs.primary),
      ],
    );
  }
}

// ── Amount Field ──────────────────────────────────────────────────────────────

/// The hero amount input (reference "Log transaction"): an uppercase AMOUNT
/// label over a big, centered `₱ 285` number. Doubles as a calculator — you can
/// type an expression like `285+15` (operators come from the [_OperatorBar]
/// keyboard strip) and it evaluates on blur/save, collapsing to the result so
/// no formula lingers. Borderless, so validation happens in `_submit`.
class _BigAmountField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _BigAmountField({required this.controller, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'AMOUNT',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '₱',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 5),
            IntrinsicWidth(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                inputFormatters: calcAmountInputFormatters,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  letterSpacing: -0.5,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: '0',
                  hintStyle: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A slim keyboard accessory strip of calculator operators for the amount field.
/// The OS numeric keypad has no `+ − × ÷`, so these keys insert the operators
/// at the cursor; `=` folds the expression to its result. Keys are plain
/// [GestureDetector]s (not focusable) so tapping them never steals focus from
/// the field — the keyboard stays up and the strip stays visible.
class _OperatorBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _OperatorBar({required this.controller, required this.focusNode});

  void _insert(String s) {
    final v = controller.value;
    final text = v.text;
    var start = v.selection.start;
    var end = v.selection.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    final newText = text.replaceRange(start, end, s);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + s.length),
    );
    focusNode.requestFocus();
  }

  void _backspace() {
    final v = controller.value;
    final text = v.text;
    if (text.isEmpty) return;
    var start = v.selection.start;
    var end = v.selection.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    if (start == end) {
      if (start == 0) return;
      controller.value = TextEditingValue(
        text: text.replaceRange(start - 1, start, ''),
        selection: TextSelection.collapsed(offset: start - 1),
      );
    } else {
      controller.value = TextEditingValue(
        text: text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }
    focusNode.requestFocus();
  }

  void _evaluate() {
    final value = evalAmountExpression(controller.text);
    if (value == null) return;
    final f = formatEvaluatedAmount(value);
    controller.value = TextEditingValue(
      text: f,
      selection: TextSelection.collapsed(offset: f.length),
    );
    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _OpKey(label: '÷', onTap: () => _insert('÷')),
            _OpKey(label: '×', onTap: () => _insert('×')),
            _OpKey(label: '−', onTap: () => _insert('-')),
            _OpKey(label: '+', onTap: () => _insert('+')),
            _OpKey(icon: Icons.backspace_outlined, onTap: _backspace),
            _OpKey(label: '=', onTap: _evaluate, accent: true),
          ],
        ),
      ),
    );
  }
}

class _OpKey extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool accent;

  const _OpKey({
    this.label,
    this.icon,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = accent ? Colors.white : cs.onSurface;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent ? cs.primary : cs.surface,
            borderRadius: AppRadii.smBorder,
            border: accent
                ? null
                : Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: icon != null
              ? Icon(icon, size: 18, color: fg)
              : Text(
                  label!,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Account Dropdown ──────────────────────────────────────────────────────────

class _AccountDropdown extends StatelessWidget {
  final List<FinancialAccount> accounts;
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onAddAccount;

  const _AccountDropdown({
    required this.accounts,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onAddAccount,
  });

  @override
  Widget build(BuildContext context) {
    FinancialAccount? selected;
    for (final a in accounts) {
      if (a.id == value) {
        selected = a;
        break;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetFieldLabel(label),
        SheetAccountField(
          account: selected,
          placeholder: 'Select account',
          onTap: () async {
            final choice = await showAccountPicker(
              context,
              accounts: accounts,
              selectedId: value,
              onAddAccount: onAddAccount,
            );
            if (choice != null) onChanged(choice.id);
          },
        ),
      ],
    );
  }
}

// ── Category Chips ────────────────────────────────────────────────────────────

// ── Description Field ─────────────────────────────────────────────────────────

class _DescriptionField extends StatelessWidget {
  final TextEditingController controller;

  const _DescriptionField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SheetLabeledField(
      label: 'Description',
      child: TextFormField(
        controller: controller,
        maxLength: 60,
        // Cap the length but hide the "0/60" counter (counterText: '').
        decoration: sheetFieldDecoration(context, counterText: ''),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Enter a description' : null,
      ),
    );
  }
}

// ── Date Picker Row ───────────────────────────────────────────────────────────

class _DatePickerRow extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;

  const _DatePickerRow({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SheetLabeledField(
      label: 'Date',
      child: SheetPickerBox(
        onTap: onTap,
        trailingIcon: Icons.calendar_today_outlined,
        child: Text(
          DateFormat('MMMM d, yyyy').format(date),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cs.onSurface, fontSize: 14),
        ),
      ),
    );
  }
}

// ── Note Field ────────────────────────────────────────────────────────────────

class _NoteField extends StatelessWidget {
  final TextEditingController controller;

  const _NoteField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SheetLabeledField(
      label: 'Note (optional)',
      child: TextFormField(
        controller: controller,
        maxLines: 2,
        decoration: sheetFieldDecoration(context),
      ),
    );
  }
}

// ── Installment Field ─────────────────────────────────────────────────────────

class _InstallmentField extends StatelessWidget {
  final bool value;
  final int months;
  final double interestRate;
  final double amount;
  final bool isEdit;
  final ValueChanged<bool> onChanged;
  final ValueChanged<int> onMonthsChanged;
  final ValueChanged<double> onInterestRateChanged;

  const _InstallmentField({
    required this.value,
    required this.months,
    this.interestRate = 0.0,
    required this.amount,
    this.isEdit = false,
    required this.onChanged,
    required this.onMonthsChanged,
    required this.onInterestRateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final monthly = months > 0 && amount > 0
        ? Installment.computeMonthlyAmount(
            principal: amount,
            months: months,
            monthlyRate: interestRate,
          )
        : 0.0;
    final totalPayable = monthly * months;
    final totalInterest = (totalPayable - amount).clamp(0.0, double.infinity);

    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEdit
                          ? 'Convert to installments'
                          : 'Split into installments',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEdit
                          ? 'Converts this entry into an installment plan: removes immediate lump-sum spending and bills it cycle-by-cycle.'
                          : 'Holds credit limit now, but monthly dues are billed per cycle under this category.',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
          if (value) ...[
            Divider(height: 16, color: cs.outlineVariant),
            Row(
              children: [
                Text(
                  'Duration',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  children: [3, 6, 12, 24].map((m) {
                    final selected = months == m;
                    return InkWell(
                      onTap: () => onMonthsChanged(m),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? cs.primary.withValues(alpha: 0.15)
                              : cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected ? cs.primary : cs.outlineVariant,
                          ),
                        ),
                        child: Text(
                          '${m}mo',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Interest / mo',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  children: [0.0, 1.0, 1.5, 2.0, 3.0].map((r) {
                    final selected = (interestRate == r);
                    final label = r == 0
                        ? '0%'
                        : '${r == r.roundToDouble() ? r.round() : r}%';
                    return InkWell(
                      onTap: () => onInterestRateChanged(r),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? cs.primary.withValues(alpha: 0.15)
                              : cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected ? cs.primary : cs.outlineVariant,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            if (amount > 0) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '≈ ${formatPeso(monthly)} / month for $months months',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                    if (interestRate > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Total interest: ${formatPeso(totalInterest)} · Total payable: ${formatPeso(totalPayable)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Reimbursable Field ──────────────────────────────────────────────────────

class _ReimbursableField extends StatelessWidget {
  final bool value;

  /// Null = "ASAP / no set date": the entry surfaces in the current month.
  /// A date buckets it into that month instead (e.g. a fixed reimbursement run).
  final DateTime? expectedDate;
  final TextEditingController owedByController;
  final ValueChanged<bool> onChanged;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;

  const _ReimbursableField({
    required this.value,
    required this.expectedDate,
    required this.owedByController,
    required this.onChanged,
    required this.onPickDate,
    required this.onClearDate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "I'll get this back",
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'A reimbursable expense or money you lent out. Leaves '
                      "your cash but isn't counted as spending — we'll track "
                      "it as money you're owed.",
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
          if (value) ...[
            Divider(height: 1, color: cs.outlineVariant),
            InkWell(
              onTap: onPickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined,
                        color: cs.onSurfaceVariant, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Expected back by',
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                    if (expectedDate == null)
                      // No date: "ASAP" — surfaces in the current month. Tapping
                      // the row still opens the picker to set a scheduled date.
                      Text(
                        'ASAP',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else ...[
                      Text(
                        DateFormat('MMM d, yyyy').format(expectedDate!),
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: onClearDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(Icons.close,
                              color: cs.onSurfaceVariant, size: 16),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SheetLabeledField(
                label: 'Who owes you? (optional)',
                child: TextFormField(
                  controller: owedByController,
                  maxLength: 40,
                  decoration: sheetFieldDecoration(context, counterText: ''),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Paid-For-Someone Hint ───────────────────────────────────────────────────

class _PaidForSomeoneHint extends StatelessWidget {
  final VoidCallback onUsePreset;

  const _PaidForSomeoneHint({required this.onUsePreset});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: cs.onSurfaceVariant, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Paid on your card for someone and got cash back? Pick your '
                  "credit card as From and Cash as To — it won't count as "
                  'spending or income.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onUsePreset,
              child: const Text('Set card → cash'),
            ),
          ),
        ],
      ),
    );
  }
}
