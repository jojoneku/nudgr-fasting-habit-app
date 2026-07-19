import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/utils/amount_input_formatter.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
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

  bool _isSubmitting = false;

  // Cached presenter data — updated only when presenter fires, not on keystrokes
  List<FinancialAccount> _accounts = [];
  List<FinanceCategory> _categories = [];

  @override
  void initState() {
    super.initState();
    _syncFromPresenter();
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

  @override
  void dispose() {
    widget.presenter.removeListener(_onPresenterChange);
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select an account')));
      return;
    }
    if (_type == TransactionType.transfer && _transferToAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a destination account')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
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
                  const SizedBox(height: 16),
                  _DescriptionField(controller: _descriptionController),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _AmountField(controller: _amountController),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _DatePickerRow(
                            date: _date, onTap: _pickDate, compact: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _AccountDropdown(
                    accounts: _accounts,
                    label: _type == TransactionType.transfer
                        ? 'From Account'
                        : 'Account',
                    value: _selectedAccountId,
                    onChanged: (v) => setState(() => _selectedAccountId = v),
                  ),
                  if (_type == TransactionType.transfer) ...[
                    const SizedBox(height: 12),
                    _AccountDropdown(
                      accounts: _accounts,
                      label: 'To Account',
                      value: _transferToAccountId,
                      onChanged: (v) =>
                          setState(() => _transferToAccountId = v),
                    ),
                    const SizedBox(height: 12),
                    _PaidForSomeoneHint(
                        onUsePreset: _applyPaidForSomeonePreset),
                  ],
                  if (_type != TransactionType.transfer) ...[
                    const SizedBox(height: 16),
                    if (_filteredCategories.isEmpty)
                      _NoCategoriesHint(type: _type)
                    else
                      _CategoryChips(
                        categories: _filteredCategories,
                        selected: _selectedCategoryId,
                        onSelected: (id) =>
                            setState(() => _selectedCategoryId = id),
                      ),
                  ],
                  if (_type == TransactionType.outflow) ...[
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
                  const SizedBox(height: 12),
                  _NoteField(controller: _noteController),
                  const SizedBox(height: 20),
                  AppPrimaryButton(
                    label: isEdit ? 'Save' : 'Log Transaction',
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
            label: 'Outflow',
            value: TransactionType.outflow,
            accent: cs.error),
        SheetSegment(
            label: 'Transfer',
            value: TransactionType.transfer,
            accent: cs.primary),
      ],
    );
  }
}

// ── Amount Field ──────────────────────────────────────────────────────────────

class _AmountField extends StatelessWidget {
  final TextEditingController controller;

  const _AmountField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: amountInputFormatters,
      decoration: sheetFieldDecoration(context,
          label: 'Amount', prefixText: '₱ ', emphasize: true),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Enter an amount';
        final parsed = double.tryParse(v);
        if (parsed == null || parsed <= 0) return 'Amount must be > 0';
        return null;
      },
    );
  }
}

// ── Account Dropdown ──────────────────────────────────────────────────────────

class _AccountDropdown extends StatelessWidget {
  final List<FinancialAccount> accounts;
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _AccountDropdown({
    required this.accounts,
    required this.label,
    required this.value,
    required this.onChanged,
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
            );
            if (choice != null) onChanged(choice.id);
          },
        ),
      ],
    );
  }
}

// ── Category Chips ────────────────────────────────────────────────────────────

class _CategoryChips extends StatelessWidget {
  final List<FinanceCategory> categories;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: categories.map((cat) {
            final isSelected = selected == cat.id;
            return ChoiceChip(
              label: Text(cat.name),
              selected: isSelected,
              onSelected: (_) => onSelected(cat.id),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Description Field ─────────────────────────────────────────────────────────

class _DescriptionField extends StatelessWidget {
  final TextEditingController controller;

  const _DescriptionField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLength: 60,
      decoration: sheetFieldDecoration(context, label: 'Description'),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Enter a description' : null,
    );
  }
}

// ── Date Picker Row ───────────────────────────────────────────────────────────

class _DatePickerRow extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;
  final bool compact;

  const _DatePickerRow(
      {required this.date, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                color: cs.onSurfaceVariant, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                compact
                    ? DateFormat('MMM d, yyyy').format(date)
                    : DateFormat('MMMM d, yyyy').format(date),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
              ),
            ),
          ],
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
    return TextFormField(
      controller: controller,
      maxLines: 2,
      decoration: sheetFieldDecoration(context, label: 'Note (optional)'),
    );
  }
}

// ── No Categories Hint ────────────────────────────────────────────────────────

class _NoCategoriesHint extends StatelessWidget {
  final TransactionType type;

  const _NoCategoriesHint({required this.type});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = type == TransactionType.inflow ? 'income' : 'expense';
    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.onSurfaceVariant, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No $label categories yet — add some in the Ledger first.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
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
              child: TextFormField(
                controller: owedByController,
                maxLength: 40,
                decoration: sheetFieldDecoration(context,
                    label: 'Who owes you? (optional)', counterText: ''),
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
