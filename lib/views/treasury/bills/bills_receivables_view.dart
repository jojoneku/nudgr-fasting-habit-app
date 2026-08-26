import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/category_icon.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/month_year_picker.dart';
import 'package:intermittent_fasting/views/treasury/shared/recurring_scope_field.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_bill_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_budgeted_expense_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_installment_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_receivable_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/batch_action_bar.dart';
import 'package:intermittent_fasting/views/treasury/bills/batch_settle_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/coming_up_timeline.dart';
import 'package:intermittent_fasting/views/treasury/bills/due_soon_stack.dart';
import 'package:intermittent_fasting/views/treasury/bills/new_entry_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/obligation_card.dart';
import 'package:intermittent_fasting/views/treasury/bills/undo_settlement_dialog.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The redesigned Bills tab: a swipeable due-soon stack, Pending/Paid/
/// Installments chips, a unified "Coming up" timeline, and titled sections of
/// Pay/Receive cards for bills, receivables, budgeted expenses, and
/// installments. The "Bills" title + month·year picker are rendered in an
/// in-page header (the shared Treasury app bar is hidden on this tab — see
/// `TreasuryModuleView`); credit cards live on the Dashboard under Accounts.
class BillsReceivablesView extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;

  const BillsReceivablesView({
    super.key,
    required this.presenter,
    required this.installmentPresenter,
  });

  @override
  State<BillsReceivablesView> createState() => _BillsReceivablesViewState();
}

/// The list a multi-select is running in. Selection is deliberately scoped to
/// one section: "mark these paid" means something different for a bill, a
/// receivable, and a set-aside, so a batch that mixed them could not ask a
/// single coherent question at confirmation time.
enum _BatchSection { bills, receivables, budgeted, installments }

class _BillsReceivablesViewState extends State<BillsReceivablesView> {
  /// Receivables section is in drag-to-rearrange mode. Off by default so the
  /// cards keep their Receive button and their tap-to-edit.
  bool _reorderingReceivables = false;

  /// Which section is in multi-select, or null when nothing is being selected.
  /// Transient like [_reorderingReceivables] — a selection is a gesture in
  /// progress, not state worth surviving a rebuild of the tab.
  _BatchSection? _batchSection;

  /// Ids picked in [_batchSection].
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    widget.presenter.load();
    widget.installmentPresenter.load();
  }

  // ─── Multi-select ────────────────────────────────────────────────────────

  bool get _selecting => _batchSection != null;

  /// True while [section] is the one being selected in — its rows show
  /// checkboxes.
  bool _picking(_BatchSection section) => _batchSection == section;

  /// True when another section owns the selection: [section]'s rows go inert so
  /// a stray tap can't edit or settle something outside the batch.
  bool _locked(_BatchSection section) => _selecting && _batchSection != section;

  /// Long-press entry point: starts a selection in [section] with [id] picked.
  void _startSelection(_BatchSection section, String id) {
    HapticFeedback.selectionClick();
    setState(() {
      _batchSection = section;
      _selectedIds
        ..clear()
        ..add(id);
    });
  }

  /// Picks / un-picks a row. Un-picking the last one leaves multi-select, so
  /// the way out is the same gesture that got you in.
  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
      if (_selectedIds.isEmpty) _batchSection = null;
    });
  }

  void _exitSelection() {
    setState(() {
      _batchSection = null;
      _selectedIds.clear();
    });
  }

  /// Picks every row of the active section, or clears when all are already
  /// picked.
  void _toggleSelectAll(List<String> ids) {
    setState(() {
      final all = ids.every(_selectedIds.contains);
      _selectedIds.clear();
      if (!all) _selectedIds.addAll(ids);
      if (_selectedIds.isEmpty) _batchSection = null;
    });
  }

  /// The selection props every card in a selectable section shares. Keeps the
  /// four builders below from repeating the same wiring.
  ({bool mode, bool selected, VoidCallback onToggle, VoidCallback onLongPress})
      _selectionFor(_BatchSection section, String id) => (
            mode: _picking(section),
            selected: _selectedIds.contains(id),
            onToggle: () => _toggleSelected(id),
            onLongPress: () => _startSelection(section, id),
          );

  /// Month is owned by the in-page picker (the shared app bar is hidden on this
  /// tab). Keep the bills and installment presenters in step.
  void _setMonth(String month) {
    // The selection belongs to the month it was made in — the picked rows are
    // about to leave the screen.
    _exitSelection();
    widget.presenter.setMonth(month);
    widget.installmentPresenter.setMonth(month);
  }

  // ─── Sheets ────────────────────────────────────────────────────────────────

  void _showAddBillSheet([Bill? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          AddBillSheet(presenter: widget.presenter, existing: existing),
    );
  }

  void _showAddReceivableSheet([Receivable? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          AddReceivableSheet(presenter: widget.presenter, existing: existing),
    );
  }

  void _showAddBudgetedExpenseSheet([BudgetedExpense? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddBudgetedExpenseSheet(
          presenter: widget.presenter, existing: existing),
    );
  }

  void _showMarkBillPaidSheet(Bill bill) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _MarkBillPaidSheet(bill: bill, presenter: widget.presenter),
    );
  }

  void _showMarkReceivedSheet(Receivable receivable) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MarkReceivedSheet(
          receivable: receivable, presenter: widget.presenter),
    );
  }

  void _showMarkExpensePaidSheet(BudgetedExpense expense) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _MarkExpensePaidSheet(expense: expense, presenter: widget.presenter),
    );
  }

  void _showAddInstallmentSheet([Installment? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddInstallmentSheet(
          presenter: widget.installmentPresenter, existing: existing),
    );
  }

  void _showMarkInstallmentPaidSheet(Installment installment) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MarkInstallmentPaidSheet(
          installment: installment, presenter: widget.installmentPresenter),
    );
  }

  /// Single FAB entry point — opens the unified "New entry" sheet where the user
  /// picks the type (bill / receivable / set-aside / installment).
  void _showNewEntrySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => NewEntrySheet(
        presenter: widget.presenter,
        installmentPresenter: widget.installmentPresenter,
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Resolves the category icon + theme-aware color for [categoryId]. Falls back
  /// to a type-appropriate icon and [fallback] color when the item has no linked
  /// category. Mirrors the ledger tiles' in-widget icon/color resolution.
  ///
  /// The palette slot comes from the category (via the presenter), not from the
  /// card's position: cards used to pass their row index, so two entries sharing
  /// a category could draw different colors and every color moved when the list
  /// re-sorted.
  ({IconData icon, Color color}) _catVisual(
    String categoryId, {
    required Color fallback,
  }) {
    final cat = widget.presenter.categoryById(categoryId);
    final icon = categoryIcon(cat?.name, cat?.type ?? CategoryType.expense);
    final color = cat != null
        ? resolveSliceColor(
            cat.colorHex,
            widget.presenter.categoryPaletteSlot(categoryId),
            brightness: Theme.of(context).brightness,
          )
        : fallback;
    return (icon: icon, color: color);
  }

  void _onComingUpTap(ComingUpItem item) {
    final s = item.source;
    if (s is Bill) {
      if (!s.isPaid) _showMarkBillPaidSheet(s);
    } else if (s is Receivable) {
      if (!s.isReceived) _showMarkReceivedSheet(s);
    } else if (s is BudgetedExpense) {
      if (!s.isPaid) _showMarkExpensePaidSheet(s);
    } else if (s is Installment) {
      if (!widget.installmentPresenter.isPaidForMonth(s.id)) {
        _showMarkInstallmentPaidSheet(s);
      }
    }
  }

  // ─── Undo a settlement ───────────────────────────────────────────────────
  //
  // Every settled row can be put back. Each handler asks first — reversing a
  // payment usually has to take the ledger entry with it, and only the user
  // knows whether the money actually moved — then reports the result, since the
  // row itself only changes from dimmed back to active.

  Future<void> _undoBillPayment(Bill bill) async {
    final choice = await showUndoSettlementDialog(
      context: context,
      title: 'Undo payment?',
      name: bill.name,
      entryLabel: 'bill',
      hasLedgerEntry: widget.presenter.billHasLedgerEntry(bill),
      ledgerEffect:
          '${formatPeso(bill.paidAmount ?? bill.amount)} goes back into '
          '${widget.presenter.accountName(bill.accountId) ?? 'your account'}.',
    );
    if (choice == null) return;
    await widget.presenter
        .markBillUnpaid(bill.id, removeTransaction: choice.removeTransaction);
    if (!mounted) return;
    AppToast.show(context, 'Marked "${bill.name}" unpaid.');
  }

  Future<void> _undoReceivableReceipt(Receivable receivable) async {
    final choice = await showUndoSettlementDialog(
      context: context,
      title: 'Undo receipt?',
      name: receivable.name,
      entryLabel: 'receivable',
      hasLedgerEntry: widget.presenter.receivableHasLedgerEntry(receivable),
      ledgerEffect:
          '${formatPeso(receivable.receivedAmount ?? receivable.amount)} is '
          'taken back out of the account it was deposited into.',
    );
    if (choice == null) return;
    await widget.presenter.markReceivableUnreceived(
      receivable.id,
      removeTransaction: choice.removeTransaction,
    );
    if (!mounted) return;
    AppToast.show(context, 'Marked "${receivable.name}" not received.');
  }

  Future<void> _undoExpenseFunding(BudgetedExpense expense) async {
    final choice = await showUndoSettlementDialog(
      context: context,
      title: 'Undo funding?',
      name: expense.name,
      entryLabel: 'set-aside',
      hasLedgerEntry: widget.presenter.expenseHasLedgerEntry(expense),
      ledgerEffect: '${formatPeso(expense.spentAmount)} is moved back to the '
          'account it was funded from.',
    );
    if (choice == null) return;
    await widget.presenter.markExpenseUnpaid(
      expense.id,
      removeTransaction: choice.removeTransaction,
    );
    if (!mounted) return;
    AppToast.show(context, 'Marked "${expense.name}" unfunded.');
  }

  Future<void> _undoInstallmentPayment(Installment installment) async {
    final choice = await showUndoSettlementDialog(
      context: context,
      title: 'Undo payment?',
      name: installment.name,
      entryLabel: 'installment payment',
      // An installment payment IS its ledger transaction — there is no separate
      // paid flag — so undoing always removes it. No keep-the-transaction
      // choice to offer, just a note saying what happens.
      hasLedgerEntry: false,
      ledgerEffect:
          'This month\'s payment transaction is removed and the account it '
          'was paid from is credited back.',
    );
    if (choice == null) return;
    await widget.installmentPresenter.markUnpaid(installment.id);
    if (!mounted) return;
    AppToast.show(context, 'Marked "${installment.name}" unpaid this month.');
  }

  Future<void> _confirmDelete({
    required String title,
    required String body,
    required VoidCallback onConfirm,
  }) async {
    final ok = await AppConfirmDialog.confirm(
      context: context,
      title: title,
      body: body,
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );
    if (ok) onConfirm();
  }

  /// Deleting a recurring row asks whether the months generated ahead of it go
  /// too. A plain confirm would silently orphan them: the bill disappears from
  /// the month you are looking at and quietly stays in the next three.
  Future<void> _confirmDeleteBill(Bill b) async {
    final scope = await confirmRecurringDelete(
      context: context,
      title: 'Delete Bill',
      name: b.name,
      futureMonthCount: widget.presenter.futureSeriesBills(b).length,
      isRecurring: b.isRecurring,
    );
    if (scope == null) return;
    await widget.presenter.deleteBill(
      b.id,
      applyToFuture: scope == RecurringScope.thisAndFuture,
    );
  }

  Future<void> _confirmDeleteReceivable(Receivable r) async {
    final scope = await confirmRecurringDelete(
      context: context,
      title: 'Delete Receivable',
      name: r.name,
      futureMonthCount: widget.presenter.futureSeriesReceivables(r).length,
      isRecurring: r.isRecurring,
    );
    if (scope == null) return;
    await widget.presenter.deleteReceivable(
      r.id,
      applyToFuture: scope == RecurringScope.thisAndFuture,
    );
  }

  Future<void> _confirmDeleteExpense(BudgetedExpense e) async {
    final scope = await confirmRecurringDelete(
      context: context,
      title: 'Delete Budgeted Expense',
      name: e.name,
      futureMonthCount: widget.presenter.futureSeriesExpenses(e).length,
      isRecurring: e.isRecurring,
    );
    if (scope == null) return;
    await widget.presenter.deleteBudgetedExpense(
      e.id,
      applyToFuture: scope == RecurringScope.thisAndFuture,
    );
  }

  // A bill's type is a subset of its category — shown as a small badge after
  // the name. Label is context-free; color needs the theme.
  String _billTypeLabel(BillType t) => switch (t) {
        BillType.creditCard => 'CC',
        BillType.installment => 'INSTALL',
        BillType.subscription => 'SUB',
        BillType.insurance => 'INS',
        BillType.govtContribution => 'GOV',
        BillType.utility => 'UTIL',
        BillType.other => 'OTHER',
      };

  Color _billTypeColor(BillType t) {
    final cs = Theme.of(context).colorScheme;
    return switch (t) {
      BillType.creditCard => cs.error,
      BillType.installment => context.appColors.gold,
      BillType.subscription => cs.primary,
      BillType.insurance => context.appColors.success,
      BillType.govtContribution => context.appColors.purple,
      BillType.utility => context.appColors.orange,
      BillType.other => cs.onSurfaceVariant,
    };
  }

  String _receivableTypeLabel(ReceivableType t) => switch (t) {
        ReceivableType.salary => 'SALARY',
        ReceivableType.reimbursement => 'REIMB',
        ReceivableType.business => 'BIZ',
        ReceivableType.other => 'OTHER',
      };

  Color _receivableTypeColor(ReceivableType t) {
    final cs = Theme.of(context).colorScheme;
    return switch (t) {
      ReceivableType.salary => context.appColors.success,
      ReceivableType.reimbursement => cs.primary,
      ReceivableType.business => context.appColors.gold,
      ReceivableType.other => cs.onSurfaceVariant,
    };
  }

  // ─── Batch actions ───────────────────────────────────────────────────────
  //
  // Everything below acts on the current selection. Each handler resolves the
  // picked rows from the presenter's live lists (so an id that vanished under
  // us is simply not there), asks once for whatever the whole batch shares,
  // hands the work to a presenter batch method, then reports what happened and
  // leaves selection mode.

  List<Bill> get _selectedBills =>
      widget.presenter.bills.where((b) => _selectedIds.contains(b.id)).toList();

  List<Receivable> get _selectedReceivables => widget.presenter.receivables
      .where((r) => _selectedIds.contains(r.id))
      .toList();

  List<BudgetedExpense> get _selectedExpenses =>
      widget.presenter.budgetedExpenses
          .where((e) => _selectedIds.contains(e.id))
          .toList();

  List<Installment> get _selectedInstallments =>
      widget.installmentPresenter.dueThisMonth
          .where((i) => _selectedIds.contains(i.id))
          .toList();

  /// Every row id of the section being selected in, in display order — what
  /// "Select all" picks.
  List<String> _sectionIds(_BatchSection section) => switch (section) {
        _BatchSection.bills => [for (final b in widget.presenter.bills) b.id],
        _BatchSection.receivables => [
            for (final r in widget.presenter.receivables) r.id
          ],
        _BatchSection.budgeted => [
            for (final e in widget.presenter.budgetedExpenses) e.id
          ],
        _BatchSection.installments => [
            for (final i in widget.installmentPresenter.dueThisMonth) i.id
          ],
      };

  /// What the action bar needs to render: the section's size, how many picked
  /// rows can still be settled, how many can be reversed, and the settle verb.
  /// Computed here so `build` stays declarative (Rule 1).
  ({int total, int settleable, int undoable, String verb}) _batchStatus(
      _BatchSection section) {
    switch (section) {
      case _BatchSection.bills:
        final picked = _selectedBills;
        return (
          total: widget.presenter.bills.length,
          settleable: picked.where((b) => !b.isPaid).length,
          undoable: picked.where((b) => b.isPaid).length,
          verb: 'Pay',
        );
      case _BatchSection.receivables:
        final picked = _selectedReceivables;
        return (
          total: widget.presenter.receivables.length,
          settleable: picked.where((r) => !r.isReceived).length,
          undoable: picked.where((r) => r.isReceived).length,
          verb: 'Receive',
        );
      case _BatchSection.budgeted:
        final picked = _selectedExpenses;
        return (
          total: widget.presenter.budgetedExpenses.length,
          settleable: picked.where((e) => !e.isPaid).length,
          undoable: picked.where((e) => e.isPaid).length,
          verb: 'Fund',
        );
      case _BatchSection.installments:
        final picked = _selectedInstallments;
        final paid = picked
            .where((i) => widget.installmentPresenter.isPaidForMonth(i.id))
            .length;
        return (
          total: widget.installmentPresenter.dueThisMonth.length,
          settleable: picked.length - paid,
          undoable: paid,
          verb: 'Pay',
        );
    }
  }

  /// Reports a finished batch and leaves selection mode. [skipped] rows are
  /// named explicitly — a batch that only half-applied must never read as a
  /// clean success.
  void _finishBatch(String message, {int skipped = 0}) {
    if (!mounted) return;
    _exitSelection();
    AppToast.show(
      context,
      skipped == 0
          ? message
          : '$message $skipped couldn\'t be done — check their accounts.',
    );
  }

  Future<void> _batchSettle() async {
    switch (_batchSection!) {
      case _BatchSection.bills:
        await _batchPayBills();
      case _BatchSection.receivables:
        await _batchReceiveReceivables();
      case _BatchSection.budgeted:
        await _batchFundExpenses();
      case _BatchSection.installments:
        await _batchPayInstallments();
    }
  }

  Future<void> _batchPayBills() async {
    final targets = _selectedBills.where((b) => !b.isPaid).toList();
    if (targets.isEmpty) return;
    final payers = widget.presenter.payerAccountsForAll(targets);
    final choice = await showBatchSettleSheet(
      context,
      kind: BatchSettleKind.bills,
      count: targets.length,
      total: targets.fold(0.0, (sum, b) => sum + b.amount),
      accounts: payers,
      initialAccountId: widget.presenter.preferredBatchPayerAccountId(targets),
    );
    if (choice == null) return;
    // With no eligible account there is nothing to debit, so the bills are
    // flagged paid without a ledger entry rather than failing.
    final record = !choice.alreadyInLedger && choice.accountId != null;
    final result = await widget.presenter.markBillsPaid(
      [for (final b in targets) b.id],
      accountId: record ? choice.accountId : null,
      paidDate: choice.date,
      recordInLedger: record,
    );
    _finishBatch(
      'Marked ${result.applied} ${_plural(result.applied, 'bill')} paid.',
      skipped: result.skipped,
    );
  }

  Future<void> _batchReceiveReceivables() async {
    final targets = _selectedReceivables.where((r) => !r.isReceived).toList();
    if (targets.isEmpty) return;
    final choice = await showBatchSettleSheet(
      context,
      kind: BatchSettleKind.receivables,
      count: targets.length,
      total: targets.fold(0.0, (sum, r) => sum + r.amount),
      accounts: widget.presenter.depositAccountsFor(targets.first),
      initialAccountId:
          widget.presenter.preferredDepositAccountId(targets.first),
    );
    if (choice == null) return;
    final record = !choice.alreadyInLedger && choice.accountId != null;
    final result = await widget.presenter.markReceivablesReceived(
      [for (final r in targets) r.id],
      accountId: record ? choice.accountId : null,
      receivedDate: choice.date,
      recordInLedger: record,
    );
    _finishBatch('Marked ${result.applied} received.');
  }

  Future<void> _batchFundExpenses() async {
    final targets = _selectedExpenses.where((e) => !e.isPaid).toList();
    if (targets.isEmpty) return;
    final funders = widget.presenter.setAsideFundingAccounts;
    if (funders.isEmpty) {
      AppToast.error(context, 'Add an account before funding.');
      return;
    }
    // Rows that already know where they are going keep their own destination;
    // the sheet only has to ask about the rest.
    final withDestination = targets
        .where(
            (e) => widget.presenter.preferredSetAsideDestinationId(e) != null)
        .length;
    final named = targets.map((e) => e.accountId).toSet();
    final choice = await showBatchSettleSheet(
      context,
      kind: BatchSettleKind.setAsides,
      count: targets.length,
      total: targets.fold(0.0, (sum, e) => sum + e.allocatedAmount),
      accounts: funders,
      destinations: widget.presenter.setAsideDestinationAccounts,
      initialAccountId: named.length == 1 ? named.first : null,
      savedDestinationCount: withDestination,
    );
    if (choice == null || choice.accountId == null) return;
    final result = await widget.presenter.markExpensesPaid(
      [for (final e in targets) e.id],
      accountId: choice.accountId!,
      toAccountId: choice.toAccountId,
      preferSavedDestination: choice.useSavedDestinations,
      paidDate: choice.date,
    );
    _finishBatch(
      'Funded ${result.applied} ${_plural(result.applied, 'set-aside')}.',
    );
  }

  Future<void> _batchPayInstallments() async {
    final targets = _selectedInstallments
        .where((i) => !widget.installmentPresenter.isPaidForMonth(i.id))
        .toList();
    if (targets.isEmpty) return;
    final choice = await showBatchSettleSheet(
      context,
      kind: BatchSettleKind.installments,
      count: targets.length,
      total: targets.fold(0.0, (sum, i) => sum + i.monthlyAmount),
    );
    if (choice == null) return;
    final applied = await widget.installmentPresenter
        .markManyPaid([for (final i in targets) i.id], date: choice.date);
    _finishBatch(
        'Paid $applied ${_plural(applied, 'installment')} this month.');
  }

  Future<void> _batchUndo() async {
    switch (_batchSection!) {
      case _BatchSection.bills:
        final targets = _selectedBills.where((b) => b.isPaid).toList();
        if (targets.isEmpty) return;
        final choice = await showUndoSettlementDialog(
          context: context,
          title: 'Undo ${targets.length} payments?',
          name: _batchName(targets.length, 'bill'),
          entryLabel: 'bill',
          hasLedgerEntry: targets.any(widget.presenter.billHasLedgerEntry),
          ledgerEffect:
              '${formatPeso(targets.fold(0.0, (s, b) => s + (b.paidAmount ?? b.amount)))} '
              'goes back into the accounts they were paid from.',
        );
        if (choice == null) return;
        final result = await widget.presenter.markBillsUnpaid(
          [for (final b in targets) b.id],
          removeTransaction: choice.removeTransaction,
        );
        _finishBatch(
            'Marked ${result.applied} ${_plural(result.applied, 'bill')} unpaid.');
      case _BatchSection.receivables:
        final targets =
            _selectedReceivables.where((r) => r.isReceived).toList();
        if (targets.isEmpty) return;
        final choice = await showUndoSettlementDialog(
          context: context,
          title: 'Undo ${targets.length} receipts?',
          name: _batchName(targets.length, 'receivable'),
          entryLabel: 'receivable',
          hasLedgerEntry:
              targets.any(widget.presenter.receivableHasLedgerEntry),
          ledgerEffect:
              '${formatPeso(targets.fold(0.0, (s, r) => s + (r.receivedAmount ?? r.amount)))} '
              'is taken back out of the accounts it was deposited into.',
        );
        if (choice == null) return;
        final result = await widget.presenter.markReceivablesUnreceived(
          [for (final r in targets) r.id],
          removeTransaction: choice.removeTransaction,
        );
        _finishBatch('Marked ${result.applied} not received.');
      case _BatchSection.budgeted:
        final targets = _selectedExpenses.where((e) => e.isPaid).toList();
        if (targets.isEmpty) return;
        final choice = await showUndoSettlementDialog(
          context: context,
          title: 'Undo ${targets.length} fundings?',
          name: _batchName(targets.length, 'set-aside'),
          entryLabel: 'set-aside',
          hasLedgerEntry: targets.any(widget.presenter.expenseHasLedgerEntry),
          ledgerEffect:
              '${formatPeso(targets.fold(0.0, (s, e) => s + e.spentAmount))} is '
              'moved back to the accounts it was funded from.',
        );
        if (choice == null) return;
        final result = await widget.presenter.markExpensesUnpaid(
          [for (final e in targets) e.id],
          removeTransaction: choice.removeTransaction,
        );
        _finishBatch(
            'Marked ${result.applied} ${_plural(result.applied, 'set-aside')} unfunded.');
      case _BatchSection.installments:
        final targets = _selectedInstallments
            .where((i) => widget.installmentPresenter.isPaidForMonth(i.id))
            .toList();
        if (targets.isEmpty) return;
        final choice = await showUndoSettlementDialog(
          context: context,
          title: 'Undo ${targets.length} payments?',
          name: _batchName(targets.length, 'installment payment'),
          entryLabel: 'installment payment',
          // An installment payment IS its transaction — there is no flag to
          // reverse on its own, so the transaction always goes with it.
          hasLedgerEntry: false,
          ledgerEffect: "This month's payment transactions are removed and the "
              'accounts they were paid from are credited back.',
        );
        if (choice == null) return;
        final applied = await widget.installmentPresenter
            .markManyUnpaid([for (final i in targets) i.id]);
        _finishBatch(
            'Marked $applied ${_plural(applied, 'installment')} unpaid this month.');
    }
  }

  Future<void> _batchDelete() async {
    final section = _batchSection!;
    final ids = _selectedIds.toList();
    final label = switch (section) {
      _BatchSection.bills => 'bill',
      _BatchSection.receivables => 'receivable',
      _BatchSection.budgeted => 'set-aside',
      _BatchSection.installments => 'installment',
    };
    final ok = await AppConfirmDialog.confirm(
      context: context,
      title: 'Delete ${ids.length} ${_plural(ids.length, label)}?',
      body: section == _BatchSection.installments
          ? 'Their linked payment transactions are removed too. This cannot be '
              'undone.'
          : 'This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );
    if (!ok) return;
    final deleted = switch (section) {
      _BatchSection.bills => await widget.presenter.deleteBills(ids),
      _BatchSection.receivables =>
        await widget.presenter.deleteReceivables(ids),
      _BatchSection.budgeted =>
        await widget.presenter.deleteBudgetedExpenses(ids),
      _BatchSection.installments =>
        await widget.installmentPresenter.deleteInstallments(ids),
    };
    _finishBatch('Deleted $deleted ${_plural(deleted, label)}.');
  }

  /// "3 bills" / "1 bill" — the subject line of a batch confirmation.
  String _batchName(int count, String noun) => '$count ${_plural(count, noun)}';

  String _plural(int count, String noun) => count == 1 ? noun : '${noun}s';

  // ─── Sections ────────────────────────────────────────────────────────────

  Widget _billsSection() {
    final bills = widget.presenter.bills;
    return _Section(
      title: 'Bills',
      count: bills.length,
      emptyMessage: 'No bills this month',
      children: [for (final b in bills) _cardPad(_billCard(b))],
    );
  }

  Widget _billCard(Bill b) {
    final v = _catVisual(b.categoryId, fallback: context.appColors.bills);
    final sel = _selectionFor(_BatchSection.bills, b.id);
    final locked = _locked(_BatchSection.bills);
    final String? note = b.isPaid
        ? 'Paid ${formatPeso(b.paidAmount ?? b.amount)}'
            '${b.paidDate != null ? ' · ${DateFormat('MMM d').format(b.paidDate!)}' : ''}'
        : b.isAutoStatement
            ? 'Auto-generated statement'
            : (b.paymentNote != null && b.paymentNote!.isNotEmpty
                ? b.paymentNote
                : null);
    return ObligationCard(
      key: ValueKey('bill_${b.id}'),
      icon: v.icon,
      iconColor: v.color,
      name: b.name,
      // "Other" carries no meaning now the type picker is gone — hide the badge
      // rather than stamp every manual bill with a noisy "OTHER".
      badgeLabel:
          b.billType == BillType.other ? null : _billTypeLabel(b.billType),
      badgeColor: _billTypeColor(b.billType),
      note: note,
      amount: b.amount,
      dateLabel:
          'due ${DateFormat('MMM d').format(widget.presenter.billDueDate(b))}',
      actionLabel: 'Pay',
      done: b.isPaid,
      onAction: b.isPaid || locked ? null : () => _showMarkBillPaidSheet(b),
      onUndo: b.isPaid && !locked ? () => _undoBillPayment(b) : null,
      undoLabel: 'Mark unpaid',
      onEdit: locked ? null : () => _showAddBillSheet(b),
      onDelete: locked ? null : () => _confirmDeleteBill(b),
      onLongPress: locked ? null : sel.onLongPress,
      selectionMode: sel.mode,
      selected: sel.selected,
      onSelectionToggle: sel.onToggle,
    );
  }

  /// Receivables, with a Reorder toggle in the section header once there are two
  /// or more still-owed entries to arrange. In reorder mode the still-owed rows
  /// become a [ReorderableListView] with an explicit drag handle — the cards'
  /// own tap/long-press (edit, delete) is suppressed so a drag can't fire them,
  /// and the default long-press drag is off for the same reason.
  Widget _receivablesSection() {
    final pending = widget.presenter.pendingReceivables;
    final received = widget.presenter.receivedReceivables;
    // Rearranging and selecting are both "act on the list as a whole" modes;
    // running them together would leave two competing meanings for a drag.
    final canReorder = pending.length > 1 && !_selecting;
    final reordering = _reorderingReceivables && canReorder;
    return _Section(
      title: 'Receivables',
      count: pending.length + received.length,
      emptyMessage: 'No receivables this month',
      trailing: canReorder
          ? _ReorderToggle(
              active: reordering,
              onToggle: () => setState(
                  () => _reorderingReceivables = !_reorderingReceivables),
              onReset: reordering && widget.presenter.hasManualReceivableOrder
                  ? widget.presenter.resetReceivableOrder
                  : null,
            )
          : null,
      children: [
        if (reordering)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: widget.presenter.reorderPendingReceivables,
            children: [
              for (int i = 0; i < pending.length; i++)
                _cardPad(
                  key: ValueKey('reorder_${pending[i].id}'),
                  _receivableCard(pending[i], dragIndex: i),
                ),
            ],
          )
        else
          for (final r in pending) _cardPad(_receivableCard(r)),
        for (final r in received) _cardPad(_receivableCard(r)),
      ],
    );
  }

  Widget _receivableCard(Receivable r, {int? dragIndex}) {
    final v = _catVisual(r.categoryId, fallback: context.appColors.success);
    final sel = _selectionFor(_BatchSection.receivables, r.id);
    // Reorder mode already suppresses every row action; multi-select in another
    // section does the same, for the same reason.
    final locked = _locked(_BatchSection.receivables) || dragIndex != null;
    final date = r.expectedDate;
    final dateLabel =
        date == null ? 'ASAP' : 'exp ${DateFormat('MMM d').format(date)}';
    final String? note = r.isReceived
        ? 'Received ${formatPeso(r.receivedAmount ?? r.amount)}'
            '${r.receivedDate != null ? ' · ${DateFormat('MMM d').format(r.receivedDate!)}' : ''}'
        : null;
    return ObligationCard(
      key: ValueKey('rec_${r.id}'),
      icon: v.icon,
      iconColor: v.color,
      name: r.name,
      badgeLabel: r.receivableType == ReceivableType.other
          ? null
          : _receivableTypeLabel(r.receivableType),
      badgeColor: _receivableTypeColor(r.receivableType),
      note: note,
      amount: r.amount,
      dateLabel: dateLabel,
      isInflow: true,
      actionLabel: 'Receive',
      done: r.isReceived,
      onAction: r.isReceived || locked ? null : () => _showMarkReceivedSheet(r),
      onUndo: r.isReceived && !locked ? () => _undoReceivableReceipt(r) : null,
      undoLabel: 'Mark not received',
      onEdit: locked ? null : () => _showAddReceivableSheet(r),
      onDelete: locked ? null : () => _confirmDeleteReceivable(r),
      onLongPress: locked ? null : sel.onLongPress,
      // A row being dragged is not a row being picked.
      selectionMode: sel.mode && dragIndex == null,
      selected: sel.selected,
      onSelectionToggle: sel.onToggle,
      dragHandle: dragIndex == null
          ? null
          : ReorderableDragStartListener(
              index: dragIndex,
              child: Tooltip(
                message: 'Drag to reorder',
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 22,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _budgetedSection() {
    final expenses = widget.presenter.budgetedExpenses;
    return _Section(
      title: 'Budgeted',
      count: expenses.length,
      emptyMessage: 'No budgeted expenses this month',
      children: [for (final e in expenses) _cardPad(_budgetedCard(e))],
    );
  }

  Widget _budgetedCard(BudgetedExpense e) {
    final v = _catVisual(e.categoryId, fallback: context.appColors.gold);
    final sel = _selectionFor(_BatchSection.budgeted, e.id);
    final locked = _locked(_BatchSection.budgeted);
    final accountName = widget.presenter.accountName(e.accountId);
    final destinationName =
        widget.presenter.accountName(e.destinationAccountId);
    // Say where the money is headed when the set-aside names a destination
    // ("BPI → Maya"), so the route is visible before you fund it.
    final String? route = accountName == null && destinationName == null
        ? null
        : destinationName == null
            ? 'Fund from $accountName'
            : accountName == null
                ? 'Set aside into $destinationName'
                : '$accountName → $destinationName';
    final String? note = e.isPaid
        ? 'Funded ${formatPeso(e.spentAmount)}'
        : (e.note != null && e.note!.isNotEmpty ? e.note : route);
    final progress = e.allocatedAmount > 0
        ? (e.spentAmount / e.allocatedAmount).clamp(0.0, 1.0)
        : null;
    return ObligationCard(
      key: ValueKey('bud_${e.id}'),
      icon: v.icon,
      iconColor: v.color,
      name: e.name,
      note: note,
      progress: progress,
      amount: e.allocatedAmount,
      dateLabel: e.budgetedType.label,
      actionLabel: 'Fund',
      done: e.isPaid,
      onAction: e.isPaid || locked ? null : () => _showMarkExpensePaidSheet(e),
      onUndo: e.isPaid && !locked ? () => _undoExpenseFunding(e) : null,
      undoLabel: 'Mark unfunded',
      onEdit: locked ? null : () => _showAddBudgetedExpenseSheet(e),
      onDelete: locked ? null : () => _confirmDeleteExpense(e),
      onLongPress: locked ? null : sel.onLongPress,
      selectionMode: sel.mode,
      selected: sel.selected,
      onSelectionToggle: sel.onToggle,
    );
  }

  Widget _installmentsSection() {
    final installments = widget.installmentPresenter.dueThisMonth;
    return _Section(
      title: 'Installments',
      count: installments.length,
      emptyMessage: 'No installments due this month',
      children: [
        for (final inst in installments) _cardPad(_installmentCard(inst)),
      ],
    );
  }

  Widget _installmentCard(Installment inst) {
    final sel = _selectionFor(_BatchSection.installments, inst.id);
    final locked = _locked(_BatchSection.installments);
    final paidThisMonth = widget.installmentPresenter.isPaidForMonth(inst.id);
    final count = widget.installmentPresenter.paidCount(inst.id);
    final dateLabel = paidThisMonth
        ? 'paid · $count/${inst.totalMonths}'
        : 'payment ${count + 1}/${inst.totalMonths}';
    final account = widget.installmentPresenter.accounts
        .where((a) => a.id == inst.accountId)
        .firstOrNull;
    return ObligationCard(
      key: ValueKey('inst_${inst.id}'),
      icon: Icons.credit_score_outlined,
      iconColor: context.appColors.purple,
      name: inst.name,
      note: account?.name,
      progress: widget.installmentPresenter.paymentProgress(inst.id),
      amount: inst.monthlyAmount,
      dateLabel: dateLabel,
      actionLabel: 'Pay',
      done: paidThisMonth,
      onAction: paidThisMonth || locked
          ? null
          : () => _showMarkInstallmentPaidSheet(inst),
      onUndo:
          paidThisMonth && !locked ? () => _undoInstallmentPayment(inst) : null,
      undoLabel: 'Mark unpaid this month',
      onEdit: locked ? null : () => _showAddInstallmentSheet(inst),
      onDelete: locked
          ? null
          : () => _confirmDelete(
                title: 'Delete Installment',
                body: 'Delete "${inst.name}"? All linked payment transactions '
                    'will also be removed.',
                onConfirm: () =>
                    widget.installmentPresenter.deleteInstallment(inst.id),
              ),
      onLongPress: locked ? null : sel.onLongPress,
      selectionMode: sel.mode,
      selected: sel.selected,
      onSelectionToggle: sel.onToggle,
    );
  }

  /// [key] belongs on the padding, not the card: `ReorderableListView` keys its
  /// direct children, which are these wrappers.
  Widget _cardPad(Widget child, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 8),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([widget.presenter, widget.installmentPresenter]),
      builder: (context, _) {
        final imminent = widget.presenter.imminentUnpaidBills;
        final comingUp =
            widget.presenter.comingUpItems(widget.installmentPresenter);
        final section = _batchSection;
        final status = section == null ? null : _batchStatus(section);
        return PopScope(
          // Back leaves multi-select before it leaves the tab.
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _exitSelection();
          },
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _BillsHeader(
                    monthKey: widget.presenter.selectedMonth,
                    onMonthChanged: _setMonth,
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        DueSoonStack(
                          presenter: widget.presenter,
                          onMarkPaid: _showMarkBillPaidSheet,
                          onEdit: _showAddBillSheet,
                        ),
                        if (imminent.isNotEmpty) const SizedBox(height: 16),
                        _StatChips(
                          presenter: widget.presenter,
                          installmentPresenter: widget.installmentPresenter,
                        ),
                        if (comingUp.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const _SectionLabel('Coming up'),
                          const SizedBox(height: 10),
                          ComingUpTimeline(
                              items: comingUp, onTap: _onComingUpTap),
                        ],
                        const SizedBox(height: 20),
                        _billsSection(),
                        const SizedBox(height: 18),
                        _receivablesSection(),
                        const SizedBox(height: 18),
                        _budgetedSection(),
                        const SizedBox(height: 18),
                        _installmentsSection(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // The batch bar takes the FAB's place while selecting: adding a new
            // entry mid-selection has no meaning, and the bar needs the room.
            floatingActionButton: _selecting
                ? null
                : FloatingActionButton(
                    onPressed: _showNewEntrySheet,
                    child: const Icon(Icons.add),
                  ),
            bottomNavigationBar: section == null || status == null
                ? null
                : BatchActionBar(
                    selectedCount: _selectedIds.length,
                    totalCount: status.total,
                    settleLabel: status.verb,
                    onSettle: status.settleable > 0 ? _batchSettle : null,
                    onUndo: status.undoable > 0 ? _batchUndo : null,
                    onDelete: _selectedIds.isEmpty ? null : _batchDelete,
                    onSelectAll: () => _toggleSelectAll(_sectionIds(section)),
                    onClose: _exitSelection,
                  ),
          ),
        );
      },
    );
  }
}

// ─── In-page header ───────────────────────────────────────────────────────────

/// The in-page Bills header — a large left-aligned "Bills" title with the
/// month·year picker on the right. Replaces the shared Treasury app bar, which
/// is hidden on this tab so the reference's header layout can show.
class _BillsHeader extends StatelessWidget {
  final String monthKey;
  final ValueChanged<String> onMonthChanged;

  const _BillsHeader({required this.monthKey, required this.onMonthChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Bills',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          MonthYearPill(monthKey: monthKey, onChanged: onMonthChanged),
        ],
      ),
    );
  }
}

// ─── Section scaffolding ──────────────────────────────────────────────────────

/// A plain bold section label (e.g. "Coming up").
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

/// A titled list section: bold title + count, then its cards (or an empty note).
class _Section extends StatelessWidget {
  final String title;
  final int count;
  final String emptyMessage;
  final List<Widget> children;

  /// Optional control pinned to the right of the header row (e.g. the
  /// receivables Reorder toggle).
  final Widget? trailing;

  const _Section({
    required this.title,
    required this.count,
    required this.emptyMessage,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 2),
          child: Row(
            children: [
              _SectionLabel(title),
              if (count > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$count',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (trailing != null) ...[const Spacer(), trailing!],
            ],
          ),
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              emptyMessage,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
            ),
          )
        else
          ...children,
      ],
    );
  }
}

/// Header control that puts the Receivables list into drag-to-rearrange mode.
/// While active it also offers "Auto", which throws the hand-set arrangement away
/// and returns the list to its expected-date order — shown only when there is an
/// arrangement to throw away.
class _ReorderToggle extends StatelessWidget {
  final bool active;
  final VoidCallback onToggle;
  final VoidCallback? onReset;

  const _ReorderToggle({
    required this.active,
    required this.onToggle,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (active && onReset != null)
          TextButton(
            onPressed: onReset,
            style: style.copyWith(
              foregroundColor: WidgetStatePropertyAll(cs.onSurfaceVariant),
            ),
            child: const Text('Auto'),
          ),
        TextButton.icon(
          onPressed: onToggle,
          style: style.copyWith(
            foregroundColor: WidgetStatePropertyAll(cs.primary),
          ),
          icon: Icon(active ? Icons.check_rounded : Icons.swap_vert_rounded,
              size: 17),
          label: Text(active ? 'Done' : 'Reorder'),
        ),
      ],
    );
  }
}

// ─── Stat chips (Pending / Paid / Installments) ───────────────────────────────

class _StatChips extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;

  const _StatChips(
      {required this.presenter, required this.installmentPresenter});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _StatChip(
          label: 'Pending',
          value: formatPesoCompact(presenter.totalBillsPending),
          color: colorScheme.error,
        ),
        const SizedBox(width: 8),
        _StatChip(
          label: 'Paid',
          value: formatPesoCompact(presenter.totalBillsPaid),
          color: context.appColors.success,
        ),
        const SizedBox(width: 8),
        _StatChip(
          label: 'Installments',
          value: formatPesoCompact(installmentPresenter.totalDueThisMonth),
          color: colorScheme.primary,
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 11),
        decoration: BoxDecoration(
          // Neutral surface with the status color as the outline (per reference),
          // rather than a colored fill.
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 1),
            Text(label,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ─── Mark Bill Paid Sheet ─────────────────────────────────────────────────────

class _MarkBillPaidSheet extends StatefulWidget {
  final Bill bill;
  final BillsReceivablesPresenter presenter;

  const _MarkBillPaidSheet({required this.bill, required this.presenter});

  @override
  State<_MarkBillPaidSheet> createState() => _MarkBillPaidSheetState();
}

class _MarkBillPaidSheetState extends State<_MarkBillPaidSheet> {
  final _amountController = TextEditingController();
  String? _selectedAccountId;
  DateTime _paidDate = DateTime.now();
  bool _isSubmitting = false;
  // When true the user already logged this expense in the ledger, so marking
  // paid should NOT create a transaction or debit an account.
  bool _alreadyInLedger = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.bill.amount.toStringAsFixed(2);
    // For CC/liability bills, restrict payer to non-liability accounts.
    final payers = widget.presenter.payerAccountsFor(widget.bill);
    final preferred = widget.bill.accountId;
    if (preferred != null && payers.any((a) => a.id == preferred)) {
      _selectedAccountId = preferred;
    } else if (payers.isNotEmpty) {
      _selectedAccountId = payers.first.id;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _paidDate = picked);
  }

  FinancialAccount? get _selectedAccount {
    for (final a in widget.presenter.payerAccountsFor(widget.bill)) {
      if (a.id == _selectedAccountId) return a;
    }
    return null;
  }

  Future<void> _pickAccount() async {
    final choice = await showAccountPicker(
      context,
      accounts: widget.presenter.payerAccountsFor(widget.bill),
      selectedId: _selectedAccountId,
    );
    if (choice != null) setState(() => _selectedAccountId = choice.id);
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    // An account is only needed when we're recording the payment in the ledger.
    if (!_alreadyInLedger && _selectedAccountId == null) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.presenter.markBillPaid(
        widget.bill.id,
        paidAmount: amount,
        accountId: _alreadyInLedger ? null : _selectedAccountId,
        paidDate: _paidDate,
        recordInLedger: !_alreadyInLedger,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mark Paid — ${widget.bill.name}',
                style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            AppTextField(
              controller: _amountController,
              label: 'Amount Paid',
              prefix: const Text('₱ '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _alreadyInLedger,
              onChanged: (v) => setState(() => _alreadyInLedger = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Already added to ledger'),
              subtitle: const Text(
                  "Just mark it paid — don't record a transaction or debit an account."),
            ),
            if (!_alreadyInLedger) ...[
              const SizedBox(height: 12),
              Builder(builder: (context) {
                final payers = widget.presenter.payerAccountsFor(widget.bill);
                if (payers.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SheetFieldLabel('Pay from'),
                    SheetAccountField(
                        account: _selectedAccount, onTap: _pickAccount),
                  ],
                );
              }),
            ],
            const SizedBox(height: 12),
            const SheetFieldLabel('Date'),
            SheetPickerBox(
              onTap: _pickDate,
              trailingIcon: Icons.calendar_today_outlined,
              child: Text(DateFormat('MMMM d, yyyy').format(_paidDate),
                  style: TextStyle(color: colorScheme.onSurface, fontSize: 14)),
            ),
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: 'Confirm Payment',
              onPressed: _isSubmitting ? null : _confirm,
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Mark Received Sheet ──────────────────────────────────────────────────────

class _MarkReceivedSheet extends StatefulWidget {
  final Receivable receivable;
  final BillsReceivablesPresenter presenter;

  const _MarkReceivedSheet({required this.receivable, required this.presenter});

  @override
  State<_MarkReceivedSheet> createState() => _MarkReceivedSheetState();
}

class _MarkReceivedSheetState extends State<_MarkReceivedSheet> {
  final _amountController = TextEditingController();
  String? _selectedAccountId;
  DateTime _receivedDate = DateTime.now();
  bool _isSubmitting = false;
  // When true the user already logged this income in the ledger, so marking
  // received should NOT create a transaction or credit an account.
  bool _alreadyInLedger = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.receivable.amount.toStringAsFixed(2);
    // Prefer the receivable's saved destination account, then a liquid one,
    // then anything eligible. The rule lives in the presenter so web and mobile
    // can't drift — this used to offer every account, archived and credit cards
    // included, while web offered only bank/ewallet/cash.
    _selectedAccountId =
        widget.presenter.preferredDepositAccountId(widget.receivable);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _receivedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _receivedDate = picked);
  }

  FinancialAccount? get _selectedAccount {
    for (final a in widget.presenter.accounts) {
      if (a.id == _selectedAccountId) return a;
    }
    return null;
  }

  Future<void> _pickAccount() async {
    final choice = await showAccountPicker(
      context,
      accounts: widget.presenter.depositAccountsFor(widget.receivable),
      selectedId: _selectedAccountId,
    );
    if (choice != null) setState(() => _selectedAccountId = choice.id);
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    // An account is only needed when we're recording the receipt in the ledger.
    if (!_alreadyInLedger && _selectedAccountId == null) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.presenter.markReceivableReceived(
        widget.receivable.id,
        receivedAmount: amount,
        accountId: _alreadyInLedger ? null : _selectedAccountId,
        receivedDate: _receivedDate,
        recordInLedger: !_alreadyInLedger,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mark Received — ${widget.receivable.name}',
                style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            AppTextField(
              controller: _amountController,
              label: 'Amount Received',
              prefix: const Text('₱ '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _alreadyInLedger,
              onChanged: (v) => setState(() => _alreadyInLedger = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Already added to ledger'),
              subtitle: const Text(
                  "Just mark it received — don't record a transaction or credit an account."),
            ),
            if (!_alreadyInLedger && widget.presenter.accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              const SheetFieldLabel('Account'),
              SheetAccountField(account: _selectedAccount, onTap: _pickAccount),
            ],
            const SizedBox(height: 12),
            const SheetFieldLabel('Date'),
            SheetPickerBox(
              onTap: _pickDate,
              trailingIcon: Icons.calendar_today_outlined,
              child: Text(DateFormat('MMMM d, yyyy').format(_receivedDate),
                  style: TextStyle(color: colorScheme.onSurface, fontSize: 14)),
            ),
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: 'Confirm Receipt',
              onPressed: _isSubmitting ? null : _confirm,
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Mark Expense Paid Sheet ──────────────────────────────────────────────────

class _MarkExpensePaidSheet extends StatefulWidget {
  final BudgetedExpense expense;
  final BillsReceivablesPresenter presenter;

  const _MarkExpensePaidSheet({required this.expense, required this.presenter});

  @override
  State<_MarkExpensePaidSheet> createState() => _MarkExpensePaidSheetState();
}

class _MarkExpensePaidSheetState extends State<_MarkExpensePaidSheet> {
  final _amountController = TextEditingController();
  String? _selectedAccountId;
  String? _selectedToAccountId;

  /// The destination question has been answered — with an account, or with an
  /// explicit "spend it". Kept apart from [_selectedToAccountId] because null is
  /// itself a valid answer.
  bool _destinationChosen = false;
  DateTime _paidDate = DateTime.now();
  bool _isSubmitting = false;

  /// Asset accounts money can be set aside into (savings/goals first), used to
  /// populate the "Set aside into" transfer destination.
  List<FinancialAccount> get _destinations =>
      widget.presenter.setAsideDestinationAccounts;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.expense.allocatedAmount.toStringAsFixed(2);
    // Default to the account the set-aside is assigned to, falling back to the
    // first account when none is set (or it no longer exists).
    final accounts = widget.presenter.accounts;
    final assigned = widget.expense.accountId;
    _selectedAccountId =
        assigned != null && accounts.any((a) => a.id == assigned)
            ? assigned
            : (accounts.isNotEmpty ? accounts.first.id : null);
    // Destination comes from the set-aside itself ("₱5k from BPI to Maya"), so
    // a route the user already decided is just confirmed. With none on file the
    // field stays empty and Confirm waits for an answer — this used to auto-pick
    // the first savings account, quietly parking money somewhere never named.
    _selectedToAccountId = widget.presenter.preferredSetAsideDestinationId(
      widget.expense,
      fromAccountId: _selectedAccountId,
    );
    _destinationChosen = _selectedToAccountId != null;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _paidDate = picked);
  }

  FinancialAccount? get _selectedFromAccount {
    for (final a in widget.presenter.accounts) {
      if (a.id == _selectedAccountId) return a;
    }
    return null;
  }

  FinancialAccount? get _selectedToAccount {
    for (final a in _destinations) {
      if (a.id == _selectedToAccountId) return a;
    }
    return null;
  }

  Future<void> _pickFrom() async {
    final choice = await showAccountPicker(
      context,
      accounts: widget.presenter.accounts,
      selectedId: _selectedAccountId,
    );
    if (choice != null) {
      setState(() {
        _selectedAccountId = choice.id;
        if (_selectedToAccountId == _selectedAccountId) {
          _selectedToAccountId = null; // can't transfer to itself
        }
      });
    }
  }

  Future<void> _pickTo() async {
    final dests =
        _destinations.where((a) => a.id != _selectedAccountId).toList();
    final choice = await showAccountPicker(
      context,
      accounts: dests,
      selectedId: _destinationChosen ? _selectedToAccountId : null,
      allowNone: true,
      noneLabel: 'Spend it (no transfer)',
    );
    if (choice != null) {
      setState(() {
        _selectedToAccountId = choice.id;
        _destinationChosen = true;
      });
    }
  }

  /// Where the money is going has to be settled before it moves — either into
  /// an account, or explicitly spent.
  bool get _canConfirm =>
      !_isSubmitting &&
      _selectedAccountId != null &&
      (_destinationChosen || _destinations.isEmpty);

  Future<void> _confirm() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    if (!_canConfirm) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.presenter.markExpensePaid(
        widget.expense.id,
        paidAmount: amount,
        accountId: _selectedAccountId!,
        toAccountId: _selectedToAccountId,
        paidDate: _paidDate,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mark Paid — ${widget.expense.name}',
                style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            AppTextField(
              controller: _amountController,
              label: 'Amount Paid',
              prefix: const Text('₱ '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            if (widget.presenter.accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              const SheetFieldLabel('Fund from'),
              SheetAccountField(
                  account: _selectedFromAccount, onTap: _pickFrom),
              const SizedBox(height: 12),
              const SheetFieldLabel('Set aside into'),
              SheetAccountField(
                account: _selectedToAccount,
                placeholder: _destinationChosen
                    ? 'Spend it (no transfer)'
                    : 'Choose where it goes',
                onTap: _pickTo,
              ),
            ],
            const SizedBox(height: 12),
            const SheetFieldLabel('Date'),
            SheetPickerBox(
              onTap: _pickDate,
              trailingIcon: Icons.calendar_today_outlined,
              child: Text(DateFormat('MMMM d, yyyy').format(_paidDate),
                  style: TextStyle(color: colorScheme.onSurface, fontSize: 14)),
            ),
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: 'Confirm Payment',
              onPressed: _canConfirm ? _confirm : null,
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Mark Installment Paid Sheet ──────────────────────────────────────────────

class _MarkInstallmentPaidSheet extends StatefulWidget {
  final Installment installment;
  final InstallmentPresenter presenter;

  const _MarkInstallmentPaidSheet({
    required this.installment,
    required this.presenter,
  });

  @override
  State<_MarkInstallmentPaidSheet> createState() =>
      _MarkInstallmentPaidSheetState();
}

class _MarkInstallmentPaidSheetState extends State<_MarkInstallmentPaidSheet> {
  late final TextEditingController _amountCtrl;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text: widget.installment.monthlyAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) return;
    setState(() => _saving = true);
    await widget.presenter.markPaid(
      widget.installment.id,
      overrideAmount: amount,
      date: _date,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final count = widget.presenter.paidCount(widget.installment.id) + 1;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                'Mark Payment $count/${widget.installment.totalMonths}',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                widget.installment.name,
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 20),
              const SheetFieldLabel('Amount'),
              AppTextField(
                controller: _amountCtrl,
                prefix: const Text('₱ '),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              const SheetFieldLabel('Date'),
              SheetPickerBox(
                trailingIcon: Icons.calendar_today_outlined,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: Text(DateFormat('MMMM d, yyyy').format(_date),
                    style:
                        TextStyle(color: colorScheme.onSurface, fontSize: 14)),
              ),
              const SizedBox(height: 20),
              AppPrimaryButton(
                label: 'Confirm Payment',
                onPressed: _saving ? null : _confirm,
                isLoading: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
