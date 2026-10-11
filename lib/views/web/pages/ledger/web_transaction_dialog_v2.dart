import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';

import '../../design/web_breakpoints.dart';
import '../../design/web_constants.dart';
import '../../widgets/web_dialog.dart';
import '../../widgets/web_searchable_dropdown.dart';

/// Opens the v2 Add / Edit transaction dialog (Plan 063, Phase 4 — the
/// "Ledger" section of `Forms.dc.html`).
///
/// One of [existing] (edit), [duplicateOf] (prefill from a row, dated today)
/// or [prefill] (an assistant / receipt leftover) seeds the form; with none
/// the form is blank. [splitInstallments] and [reimbursable] open with the
/// matching fold or switch already on — the row ⋯ menu's "Split into
/// installments" and "Mark I'll get this back" entry points. [onDelete] adds
/// a destructive Delete to an edit of a transfer; the page supplies it so the
/// undo toast is raised with the page's context after the dialog closes.
///
/// Same `LedgerPresenter` calls as the pre-v2 dialog, including installments
/// and reimbursables; only the chrome changed.
Future<void> showWebTransactionDialogV2(
  BuildContext context, {
  required LedgerPresenter presenter,
  ParsedTransaction? prefill,
  TransactionRecord? existing,
  TransactionRecord? duplicateOf,
  bool splitInstallments = false,
  bool reimbursable = false,
  Future<void> Function(TransactionRecord record)? onDelete,
}) async {
  await presenter.reloadAccounts();
  if (!context.mounted) return;
  await showWebDialog<void>(
    context,
    builder: (_) => WebTransactionDialogV2(
      presenter: presenter,
      prefill: prefill,
      existing: existing,
      duplicateOf: duplicateOf,
      initialSplit: splitInstallments,
      initialReimbursable: reimbursable,
      onDelete: onDelete,
    ),
  );
}

class WebTransactionDialogV2 extends StatefulWidget {
  final LedgerPresenter presenter;
  final ParsedTransaction? prefill;

  /// When set, the dialog edits this transaction instead of adding a new one.
  /// For a transfer, pass either leg — both are rebuilt from the shared group.
  final TransactionRecord? existing;

  /// When set (and [existing] is null), the form is prefilled from this row
  /// with today's date, so the commit adds a new record.
  final TransactionRecord? duplicateOf;
  final bool initialSplit;
  final bool initialReimbursable;
  final Future<void> Function(TransactionRecord record)? onDelete;

  const WebTransactionDialogV2({
    super.key,
    required this.presenter,
    this.prefill,
    this.existing,
    this.duplicateOf,
    this.initialSplit = false,
    this.initialReimbursable = false,
    this.onDelete,
  });

  @override
  State<WebTransactionDialogV2> createState() => _WebTransactionDialogV2State();
}

class _WebTransactionDialogV2State extends State<WebTransactionDialogV2> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _noteController = TextEditingController();
  final _owedByController = TextEditingController();

  TransactionType _type = TransactionType.outflow;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  DateTime _date = DateTime.now();

  // Reimbursable / loan state (outflow only): money out now, owed back later.
  // [_expectedReimbursementDate] null = "ASAP" (surfaces in the current month);
  // a date buckets the spawned receivable into that month instead.
  bool _reimbursable = false;
  DateTime? _expectedReimbursementDate;

  // Installment purchase state (outflow on liability account only):
  bool _splitInstallments = false;
  int _installmentMonths = 3;
  double _interestRate = 0.0;

  bool _moreOpen = false;
  bool _isSubmitting = false;
  bool _showFieldErrors = false;

  LedgerPresenter get _p => widget.presenter;

  List<FinancialAccount> get _accounts =>
      _p.accounts.where((a) => a.isActive && !a.isSubAccount).toList();

  FinancialAccount? get _selectedAccount =>
      _accounts.where((a) => a.id == _accountId).firstOrNull;

  List<FinanceCategory> get _filteredCategories {
    if (_type == TransactionType.inflow) {
      return _p.categories.where((c) => c.type == CategoryType.income).toList();
    }
    return _p.categories.where((c) => c.type == CategoryType.expense).toList();
  }

  bool get _isEdit => widget.existing != null;
  bool get _isTransfer => _type == TransactionType.transfer;
  bool get _isOutflow => _type == TransactionType.outflow;

  /// The installment fold is offered for an expense on a credit account when
  /// the presenter allows the record to become (or stay) a purchase.
  bool get _canShowInstallments =>
      _isOutflow &&
      _p.canSplitIntoInstallments(widget.existing) &&
      _selectedAccount?.isLiability == true;

  bool get _splitActive => _canShowInstallments && _splitInstallments;

  @override
  void initState() {
    super.initState();
    final editing = widget.existing;
    final duplicate = widget.duplicateOf;
    if (editing != null) {
      _initFromExisting(editing);
    } else if (duplicate != null) {
      _initFromDuplicate(duplicate);
    } else {
      _initFromPrefill(widget.prefill);
    }
    if (widget.initialSplit) {
      _splitInstallments = true;
      _reimbursable = false;
    }
    if (widget.initialReimbursable &&
        _type == TransactionType.outflow &&
        !_splitInstallments) {
      _reimbursable = true;
    }
    _moreOpen = widget.initialReimbursable ||
        _reimbursable ||
        _noteController.text.isNotEmpty;
    // The installment preview reads the amount live.
    _amountController.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    if (_canShowInstallments && mounted) setState(() {});
  }

  void _initFromPrefill(ParsedTransaction? pre) {
    final liquid = _accounts;
    if (pre?.type != null) _type = pre!.type!;
    _accountId =
        (pre?.accountId != null && liquid.any((a) => a.id == pre!.accountId))
            ? pre!.accountId
            : liquid.firstOrNull?.id;
    _toAccountId = (pre?.transferToAccountId != null &&
            liquid.any((a) => a.id == pre!.transferToAccountId))
        ? pre!.transferToAccountId
        : (liquid.length > 1 ? liquid[1].id : null);
    if (pre?.categoryId != null &&
        _filteredCategories.any((c) => c.id == pre!.categoryId)) {
      _categoryId = pre!.categoryId;
    }
    if (pre?.amount != null && pre!.amount! > 0) {
      _amountController.text = pre.amount!.toStringAsFixed(2);
    }
    if (pre != null && pre.description.isNotEmpty) {
      _descriptionController.text = pre.description;
    }
    if (pre?.reimbursable == true) _reimbursable = true;
  }

  /// Hydrates the form from an existing record. A transfer is two legs sharing a
  /// `transferGroupId` (neither leg's `type` is `transfer`), so rebuild From/To
  /// from the pair rather than the single leg's fields.
  void _initFromExisting(TransactionRecord t) {
    _amountController.text = t.amount.toStringAsFixed(2);
    _descriptionController.text = t.description;
    _noteController.text = t.note ?? '';
    _date = t.date;
    if (t.transferGroupId != null) {
      _type = TransactionType.transfer;
      final (fromId, toId) = _transferLegs(t);
      _accountId = fromId ?? t.accountId;
      _toAccountId = toId ?? t.transferToAccountId;
    } else {
      _type = t.type;
      _accountId = t.accountId;
      _categoryId = t.categoryId;
      _reimbursable = t.reimbursable;
      _owedByController.text = t.owedBy ?? '';
      // The expected payback date lives on the linked receivable, not the txn —
      // load it so editing a scheduled reimbursable doesn't show (and re-save)
      // "ASAP". Null stays "ASAP".
      final receivableId = t.reimbursementReceivableId;
      if (t.reimbursable && receivableId != null) {
        _expectedReimbursementDate =
            _p.reimbursementReceivableExpectedDate(receivableId);
      }
      if (t.isInstallment) {
        _splitInstallments = true;
        if (t.installmentId != null) {
          final inst = _p.findInstallmentById(t.installmentId!);
          if (inst != null) {
            _installmentMonths = inst.totalMonths;
            _interestRate = inst.interestRate;
          }
        }
      }
    }
  }

  /// Prefills from a row the user chose to duplicate: everything but the
  /// date, which is today, and the links (bill, receivable, installment) that
  /// belong to the original.
  void _initFromDuplicate(TransactionRecord t) {
    _amountController.text = t.amount.toStringAsFixed(2);
    _descriptionController.text = t.description;
    _noteController.text = t.note ?? '';
    final liquid = _accounts;
    if (t.transferGroupId != null) {
      _type = TransactionType.transfer;
      final (fromId, toId) = _transferLegs(t);
      _accountId = fromId ?? t.accountId;
      _toAccountId = toId ?? t.transferToAccountId;
    } else {
      _type = t.type;
      _accountId = liquid.any((a) => a.id == t.accountId)
          ? t.accountId
          : liquid.firstOrNull?.id;
      _categoryId = t.categoryId.isEmpty ? null : t.categoryId;
      _reimbursable = t.reimbursable;
      _owedByController.text = t.owedBy ?? '';
    }
  }

  (String?, String?) _transferLegs(TransactionRecord t) {
    String? fromId;
    String? toId;
    for (final leg in _p.allTransactions) {
      if (leg.transferGroupId != t.transferGroupId) continue;
      if (leg.type == TransactionType.outflow) fromId = leg.accountId;
      if (leg.type == TransactionType.inflow) toId = leg.accountId;
    }
    return (fromId, toId);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _descriptionController.dispose();
    _noteController.dispose();
    _owedByController.dispose();
    super.dispose();
  }

  void _setType(TransactionType t) {
    setState(() {
      _type = t;
      _categoryId = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: kWebDateRange.start,
      lastDate: kWebDateRange.end,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickReimbursementDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _expectedReimbursementDate ?? _date.add(const Duration(days: 30)),
      firstDate: kWebDateRange.start,
      lastDate: kWebDateRange.end,
    );
    if (picked != null) setState(() => _expectedReimbursementDate = picked);
  }

  String _genId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  // ── Validation ─────────────────────────────────────────────────────────────

  double? get _parsedAmount =>
      double.tryParse(_amountController.text.replaceAll(',', ''));

  String? get _amountError {
    if (!_showFieldErrors) return null;
    if (_amountController.text.trim().isEmpty) return 'Enter an amount';
    final v = _parsedAmount;
    if (v == null || v <= 0) return 'Must be > 0';
    return null;
  }

  String? get _accountError =>
      _showFieldErrors && _accountId == null ? 'Select an account' : null;

  String? get _toAccountError =>
      _showFieldErrors && _isTransfer && _toAccountId == null
          ? 'Select an account'
          : null;

  String? get _categoryError => _showFieldErrors &&
          !_isTransfer &&
          _filteredCategories.isNotEmpty &&
          _categoryId == null
      ? 'Select a category'
      : null;

  String? get _descriptionError => _showFieldErrors &&
          !_isTransfer &&
          _descriptionController.text.trim().isEmpty
      ? 'Enter a description'
      : null;

  bool get _hasErrors {
    final amount = _parsedAmount;
    final amountBad =
        _amountController.text.trim().isEmpty || amount == null || amount <= 0;
    final accountMissing = _accountId == null;
    final toAccountMissing = _isTransfer && _toAccountId == null;
    final categoryMissing =
        !_isTransfer && _filteredCategories.isNotEmpty && _categoryId == null;
    final descriptionMissing =
        !_isTransfer && _descriptionController.text.trim().isEmpty;
    return amountBad ||
        accountMissing ||
        toAccountMissing ||
        categoryMissing ||
        descriptionMissing;
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_hasErrors) {
      setState(() => _showFieldErrors = true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final amount = _parsedAmount!;
      final description = _descriptionController.text.trim();
      final note = _noteController.text.trim();
      final month = toMonthKey(_date);
      final existing = widget.existing;

      if (_type == TransactionType.transfer) {
        // Editing a transfer: drop the old pair first, since addTransfer always
        // mints a fresh outflow+inflow — otherwise the edit would duplicate the
        // transfer and double-apply both account balances.
        if (existing != null) {
          await _p.deleteTransactionOrGroup(existing.id);
        }
        await _p.addTransfer(
          fromAccountId: _accountId!,
          toAccountId: _toAccountId!,
          amount: amount,
          description: description.isEmpty ? 'Transfer' : description,
          date: _date,
          note: note.isEmpty ? null : note,
        );
      } else if (_type == TransactionType.outflow &&
          _splitInstallments &&
          _p.canSplitIntoInstallments(existing) &&
          _selectedAccount?.isLiability == true) {
        // New purchase, in-place edit of an existing one, or conversion of a
        // regular record: the presenter owns all three.
        await _p.saveInstallmentPurchase(
          existing: existing,
          accountId: _accountId!,
          amount: amount,
          months: _installmentMonths,
          interestRate: _interestRate,
          date: _date,
          description: description,
          note: note,
          categoryId: _categoryId,
        );
      } else {
        // Reimbursable only applies to outflows. Reuse the existing linked
        // receivable id when editing so the link survives; mint one otherwise.
        final isReimbursable =
            _type == TransactionType.outflow && _reimbursable;
        final receivableId = isReimbursable
            ? (existing?.reimbursementReceivableId ?? _genId())
            : null;
        final owedBy = _owedByController.text.trim();
        // Null = "ASAP / no set date" — surfaces in the current month.
        final expectedDate = _expectedReimbursementDate;
        // Reuse the existing id when editing a normal record so the row updates
        // in place; mint a new one when adding (or converting a transfer).
        final id = (existing != null && existing.transferGroupId == null)
            ? existing.id
            : _genId();
        final txn = TransactionRecord(
          id: id,
          date: _date,
          accountId: _accountId!,
          categoryId: _categoryId ?? '',
          amount: amount,
          type: _type,
          description: description,
          note: note.isEmpty ? null : note,
          month: month,
          reimbursable: isReimbursable,
          reimbursementReceivableId: receivableId,
          owedBy: isReimbursable && owedBy.isNotEmpty ? owedBy : null,
        );
        if (existing != null) {
          // A stale linked receivable (no longer reimbursable) is retired by
          // updateTransaction itself.
          final oldReceivableId = existing.reimbursementReceivableId;
          if (existing.transferGroupId != null) {
            // Converting a transfer into a normal income/expense: remove the
            // whole transfer group, then add the single replacement record.
            await _p.deleteTransactionOrGroup(existing.id);
            await _p.addTransaction(txn);
          } else if (existing.isInstallment) {
            // Split turned off, or moved off a credit account: the plan goes
            // and the record takes its full balance effect, exactly once.
            await _p.convertInstallmentPurchaseToRegular(txn);
          } else {
            await _p.updateTransaction(txn);
          }
          // Newly reimbursable → spawn the linked receivable; still reimbursable
          // → re-sync its amount/name/owedBy so it never drifts.
          if (isReimbursable && oldReceivableId == null) {
            await _p.spawnReimbursementReceivable(txn, expectedDate);
          } else if (isReimbursable) {
            // Propagate the (possibly changed or cleared) payback date so the
            // edit actually updates the receivable's schedule, not just its
            // amount/name.
            await _p.syncReimbursementReceivable(
              txn,
              updateExpectedDate: true,
              expectedDate: expectedDate,
            );
          }
        } else if (isReimbursable) {
          await _p.addReimbursableExpense(
            txn,
            expectedReimbursementDate: expectedDate,
          );
        } else {
          await _p.addTransaction(txn);
        }
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  String get _title {
    if (!_isEdit) return 'Add transaction';
    return widget.existing!.transferGroupId != null && _isTransfer
        ? 'Edit transfer'
        : 'Edit transaction';
  }

  String get _subtitle => _isEdit && _isTransfer
      ? 'Both sides of the transfer change together.'
      : 'Saved to the ledger and synced to your phone.';

  String get _submitLabel {
    final existing = widget.existing;
    if (_isEdit) {
      if (_splitActive && existing?.isInstallment != true) {
        return 'Convert to installments';
      }
      return 'Save changes';
    }
    return _splitActive ? 'Add installment plan' : 'Add transaction';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final existing = widget.existing;
    final showDelete =
        _isEdit && existing!.transferGroupId != null && widget.onDelete != null;

    return WebDialog(
      title: _title,
      subtitle: _subtitle,
      onSubmit: _isSubmitting ? null : _submit,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WebSegmented<TransactionType>(
            key: WebKeys.ledgerDialogType,
            segments: const [
              WebSegment(TransactionType.outflow, 'Expense',
                  tone: WebSegmentTone.warning),
              WebSegment(TransactionType.inflow, 'Income',
                  tone: WebSegmentTone.success),
              WebSegment(TransactionType.transfer, 'Transfer'),
            ],
            value: _type,
            onChanged: _setType,
          ),
          const SizedBox(height: WebInsets.lg),
          WebField(
            label: 'Amount',
            error: _amountError,
            child: WebInput.amount(
              key: WebKeys.ledgerDialogAmount,
              controller: _amountController,
              autofocus: true,
              error: _amountError != null,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: WebField(
                  label: _isTransfer ? 'From account' : 'Account',
                  error: _accountError,
                  child: _accountPicker(
                    key: WebKeys.ledgerDialogAccount,
                    value: _accountId,
                    error: _accountError != null,
                    onChanged: (v) => setState(() => _accountId = v),
                  ),
                ),
              ),
              const SizedBox(width: WebInsets.md),
              Expanded(
                child: _isTransfer
                    ? WebField(
                        label: 'To account',
                        error: _toAccountError,
                        child: _accountPicker(
                          key: WebKeys.ledgerDialogToAccount,
                          value: _toAccountId,
                          error: _toAccountError != null,
                          onChanged: (v) => setState(() => _toAccountId = v),
                        ),
                      )
                    : WebField(
                        label: 'Category',
                        error: _categoryError,
                        child: _categoryPicker(),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: WebField(
                  label: 'Description',
                  optional: _isTransfer,
                  error: _descriptionError,
                  child: WebInput(
                    key: WebKeys.ledgerDialogDescription,
                    controller: _descriptionController,
                    hint: _isTransfer
                        ? 'e.g. To Emergency Fund'
                        : 'e.g. Groceries · SM',
                    maxLength: 60,
                    error: _descriptionError != null,
                    onChanged: (_) {
                      if (_showFieldErrors) setState(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(width: WebInsets.md),
              Expanded(
                child: WebField(
                  label: 'Date',
                  child: _dateButton(
                    key: WebKeys.ledgerDialogDate,
                    label: _dateLabel(_date),
                    onTap: _pickDate,
                  ),
                ),
              ),
            ],
          ),
          if (_isTransfer) ...[
            const SizedBox(height: 14),
            const _HelpNote(
              'Transfers carry no category and never count as spending or '
              'income.',
            ),
          ],
          if (_canShowInstallments) ...[
            const SizedBox(height: 14),
            _installmentFold(theme),
          ],
          const SizedBox(height: 14),
          WebMoreOptions(
            key: WebKeys.ledgerDialogMoreOptions,
            hint: _isOutflow && !_splitActive
                ? 'notes, "I\'ll get this back"'
                : 'notes',
            initiallyOpen: _moreOpen,
            children: [
              WebField(
                label: 'Notes',
                optional: true,
                child: WebInput.multiline(
                  key: WebKeys.ledgerDialogNotes,
                  controller: _noteController,
                  hint: 'Add a note…',
                  minLines: 2,
                  maxLines: 4,
                ),
              ),
              if (_isOutflow && !_splitActive)
                WebSwitchRow(
                  key: WebKeys.ledgerDialogReimbursable,
                  title: "I'll get this back",
                  subtitle: 'Tracks as money owed to you, not spending',
                  value: _reimbursable,
                  onChanged: (v) => setState(() => _reimbursable = v),
                ),
              if (_isOutflow && !_splitActive && _reimbursable)
                _reimbursableDetails(theme, cs),
            ],
          ),
        ],
      ),
      destructive: showDelete
          ? TextButton(
              key: WebKeys.ledgerDialogDelete,
              style: TextButton.styleFrom(foregroundColor: cs.error),
              onPressed: _isSubmitting
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      widget.onDelete!(existing);
                    },
              child: const Text('Delete'),
            )
          : null,
      secondary: TextButton(
        key: WebKeys.ledgerDialogCancel,
        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      primary: FilledButton(
        key: WebKeys.ledgerDialogSubmit,
        onPressed: _isSubmitting ? null : _submit,
        child: _isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(_submitLabel),
      ),
    );
  }

  static final _kLongDate = DateFormat('MMM d, yyyy');
  static final _kShortDate = DateFormat('MMM d');

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final today =
        d.year == now.year && d.month == now.month && d.day == now.day;
    return today ? 'Today, ${_kShortDate.format(d)}' : _kLongDate.format(d);
  }

  /// A 46 px box in the input style hosting a searchable dropdown.
  Widget _pickerBox({required Widget child, bool error = false}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: kWebInputHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppRadii.mdBorder,
        border: Border.all(
          color: error ? cs.error : cs.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: child,
    );
  }

  Widget _accountPicker({
    required Key key,
    required String? value,
    required bool error,
    required ValueChanged<String> onChanged,
  }) {
    final accounts = _accounts;
    final brightness = Theme.of(context).brightness;
    final entries = [
      for (var i = 0; i < accounts.length; i++)
        WebDropdownEntry<String>(
          value: accounts[i].id,
          label: accounts[i].name,
          dotColor: resolveSliceColor(
            accounts[i].colorHex,
            i,
            brightness: brightness,
          ),
        ),
    ];
    return _pickerBox(
      error: error,
      child: WebSearchableDropdown<String>(
        key: key,
        value: accounts.any((a) => a.id == value) ? value : null,
        hintText: accounts.isEmpty ? 'No accounts' : 'Select…',
        entries: entries,
        isDense: true,
        onChanged: onChanged,
      ),
    );
  }

  Widget _categoryPicker() {
    final cats = _filteredCategories;
    final brightness = Theme.of(context).brightness;
    final entries = [
      for (var i = 0; i < cats.length; i++)
        WebDropdownEntry<String>(
          value: cats[i].id,
          label: cats[i].name,
          dotColor: resolveSliceColor(
            cats[i].colorHex,
            i,
            brightness: brightness,
          ),
        ),
    ];
    return _pickerBox(
      error: _categoryError != null,
      child: WebSearchableDropdown<String>(
        key: WebKeys.ledgerDialogCategory,
        value: cats.any((c) => c.id == _categoryId) ? _categoryId : null,
        hintText: cats.isEmpty ? 'No categories' : 'Select…',
        entries: entries,
        isDense: true,
        onChanged: (v) => setState(() => _categoryId = v),
      ),
    );
  }

  Widget _dateButton({
    required Key key,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(visualDensity: VisualDensity.standard),
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: AppRadii.mdBorder,
        child: InputDecorator(
          decoration: WebInput.decoration(
            context,
            suffixIcon:
                trailing ?? const Icon(Icons.calendar_today_outlined, size: 16),
          ).copyWith(
            suffixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WebInput.textStyle(context),
          ),
        ),
      ),
    );
  }

  /// "Split into installments" — logs a purchase on a credit / BNPL liability
  /// account as an installment plan. Holds credit limit now without inflating
  /// the current month's cash expenses.
  Widget _installmentFold(ThemeData theme) {
    final cs = theme.colorScheme;
    final muted = context.appColors.textMuted;
    final existing = widget.existing;
    final isPurchase = existing?.isInstallment == true;
    final amount = _parsedAmount ?? 0.0;
    final monthly = _installmentMonths > 0 && amount > 0
        ? Installment.computeMonthlyAmount(
            principal: amount,
            months: _installmentMonths,
            monthlyRate: _interestRate,
          )
        : 0.0;
    final totalPayable = monthly * _installmentMonths;
    final totalInterest = (totalPayable - amount).clamp(0.0, double.infinity);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: muted,
      fontSize: 11.5,
    );

    return WebFold(
      key: WebKeys.ledgerDialogInstallments,
      title: isPurchase
          ? 'Installment plan'
          : _isEdit
              ? 'Convert to installments'
              : 'Split into installments',
      subtitle: isPurchase
          ? 'Turn off to make this a regular expense again'
          : _isEdit
              ? 'Removes the lump sum and bills it cycle by cycle'
              : 'Credit accounts only · holds the limit now, bills monthly',
      toggle: _splitInstallments,
      onToggle: (v) => setState(() {
        _splitInstallments = v;
        if (v) _reimbursable = false;
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WebField(
            label: 'Months',
            child: WebChips<int>(
              key: WebKeys.ledgerDialogInstallmentMonths,
              options: const [
                WebChipOption(3, '3'),
                WebChipOption(6, '6'),
                WebChipOption(12, '12'),
                WebChipOption(24, '24'),
              ],
              value: _installmentMonths,
              onChanged: (m) => setState(() => _installmentMonths = m),
            ),
          ),
          const SizedBox(height: WebInsets.sm),
          WebField(
            label: 'Interest / month',
            child: WebChips<double>(
              key: WebKeys.ledgerDialogInstallmentRate,
              options: const [
                WebChipOption(0.0, '0 %'),
                WebChipOption(1.0, '1 %'),
                WebChipOption(1.5, '1.5 %'),
                WebChipOption(2.0, '2 %'),
                WebChipOption(3.0, '3 %'),
              ],
              value: _interestRate,
              onChanged: (r) => setState(() => _interestRate = r),
            ),
          ),
          const SizedBox(height: WebInsets.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (amount > 0)
                  Text.rich(
                    TextSpan(
                      text: '≈ ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 12.5,
                      ),
                      children: [
                        TextSpan(
                          text: '${formatPeso(monthly)} / month',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        TextSpan(text: ' for $_installmentMonths months'),
                      ],
                    ),
                  )
                else
                  Text('Enter an amount to preview the monthly due.',
                      style: small),
                if (amount > 0 && _interestRate > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Total interest ${formatPeso(totalInterest)} · '
                    'Total payable ${formatPeso(totalPayable)}',
                    style: small,
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  'Billed onto the card at statement close. Paying the card '
                  'is a transfer.',
                  style: small,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The payback date and debtor under the "I'll get this back" switch.
  Widget _reimbursableDetails(ThemeData theme, ColorScheme cs) {
    final date = _expectedReimbursementDate;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: WebField(
            label: 'Expected back by',
            helper: date == null ? 'ASAP shows it in this month' : null,
            child: _dateButton(
              key: WebKeys.ledgerDialogExpectedBack,
              label: date == null ? 'ASAP' : _kLongDate.format(date),
              onTap: _pickReimbursementDate,
              trailing: date == null
                  ? null
                  : IconButton(
                      tooltip: 'Back to ASAP',
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () =>
                          setState(() => _expectedReimbursementDate = null),
                    ),
            ),
          ),
        ),
        const SizedBox(width: WebInsets.md),
        Expanded(
          child: WebField(
            label: 'Who owes you?',
            optional: true,
            child: WebInput(
              key: WebKeys.ledgerDialogOwedBy,
              controller: _owedByController,
              hint: 'Name',
              maxLength: 40,
            ),
          ),
        ),
      ],
    );
  }
}

/// A muted one-line note inside a dialog body (the transfer explanation).
class _HelpNote extends StatelessWidget {
  final String text;
  const _HelpNote(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontSize: 12.5,
        ),
      ),
    );
  }
}
