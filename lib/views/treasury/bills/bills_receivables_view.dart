import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/settle_request.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/recurring_scope_field.dart';
import 'package:intermittent_fasting/views/treasury/shared/settle_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_bill_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_budgeted_expense_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_installment_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_receivable_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/batch_action_bar.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_header.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_month_summary.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_tab_bodies.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_tab_chips.dart';
import 'package:intermittent_fasting/views/treasury/bills/credit_cards_card.dart';
import 'package:intermittent_fasting/views/treasury/bills/hero_bill_card.dart';
import 'package:intermittent_fasting/views/treasury/bills/new_entry_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/statement_breakdown_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/undo_settlement_dialog.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The Bills tab (Plan 071 Phase 6): each bill in one place.
///
/// From the top: the in-page header (title + month picker; the shared
/// Treasury app bar is hidden on this tab — see `TreasuryModuleView`), a hero
/// for the single most imminent unpaid bill, a collapsible "This month"
/// summary, a scrollable row of tabs with counts (Upcoming · Set-asides ·
/// Receivables · Installments · Paid), the open tab's cards, and the credit
/// cards card. The "Coming up" timeline is not shown here; the Dashboard and
/// the Hub still read it.
///
/// This file owns the sheets, dialogs and batch selection. The tab bodies and
/// row cards live in `bills_tab_bodies.dart`.
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

class _BillsReceivablesViewState extends State<BillsReceivablesView> {
  /// The open tab.
  BillsTab _tab = BillsTab.upcoming;

  /// Receivables tab is in drag-to-rearrange mode. Off by default so the
  /// cards keep their Receive button and their tap-to-edit.
  bool _reorderingReceivables = false;

  /// True while the open tab is in multi-select. A selection is scoped to
  /// one tab: "mark these paid" means something different for a bill, a
  /// receivable, and a set-aside, so a batch that mixed them could not ask a
  /// single coherent question at confirmation time. Switching tabs ends it.
  /// Transient like [_reorderingReceivables] — a selection is a gesture in
  /// progress, not state worth surviving a rebuild of the tab.
  bool _selecting = false;

  /// Ids picked in the open tab.
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    widget.presenter.load();
    widget.installmentPresenter.load();
  }

  // ─── Multi-select ────────────────────────────────────────────────────────

  /// Long-press entry point: starts a selection in the open tab with [id]
  /// picked.
  void _startSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      _selecting = true;
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
      if (_selectedIds.isEmpty) _selecting = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  /// Picks every row of the open tab, or clears when all are already picked.
  void _toggleSelectAll(List<String> ids) {
    setState(() {
      final all = ids.every(_selectedIds.contains);
      _selectedIds.clear();
      if (!all) _selectedIds.addAll(ids);
      if (_selectedIds.isEmpty) _selecting = false;
    });
  }

  /// Opens [tab]. A selection belongs to the tab it was made in, so moving
  /// to another tab ends it rather than carrying hidden picks along.
  void _setTab(BillsTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _selecting = false;
      _selectedIds.clear();
      _reorderingReceivables = false;
    });
  }

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

  // Each launcher keeps its own presenter call; the Settle sheet only
  // collects the input, and stays open with an error toast if the save fails.
  // Each returns true once the entry was settled.

  Future<bool> _showMarkBillPaidSheet(Bill bill) async {
    final presenter = widget.presenter;
    final result = await showSettleSheet(
      context,
      kind: SettleKind.bill,
      targets: [
        SettleTarget(
          id: bill.id,
          name: bill.name,
          // A part-paid credit statement prefills what is left, not the bill.
          amount: presenter.billAmountOwed(bill),
          dateLabel:
              'due ${DateFormat('MMM d').format(presenter.billDueDate(bill))}',
          accountId: bill.accountId,
        ),
      ],
      // For a card or other liability bill this is non-liability accounts only.
      payers: presenter.payerAccountsFor(bill),
      emptyPayersMessage: 'Add a funding account before marking paid.',
      onConfirm: (r) => presenter.markBillPaid(
        bill.id,
        paidAmount: r.amount,
        accountId: r.accountId,
        paidDate: r.date,
        recordInLedger: r.recordInLedger,
      ),
    );
    return result != null;
  }

  Future<bool> _showMarkReceivedSheet(Receivable receivable) async {
    final presenter = widget.presenter;
    final expected = receivable.expectedDate;
    final result = await showSettleSheet(
      context,
      kind: SettleKind.receivable,
      targets: [
        SettleTarget(
          id: receivable.id,
          name: receivable.name,
          amount: receivable.amount,
          dateLabel: expected == null
              ? 'ASAP'
              : 'expected ${DateFormat('MMM d').format(expected)}',
        ),
      ],
      // The eligible set and the default live in the presenter so web and
      // mobile can't drift.
      payers: presenter.depositAccountsFor(receivable),
      initialAccountId: presenter.preferredDepositAccountId(receivable),
      emptyPayersMessage: 'Add an account before marking received.',
      onConfirm: (r) => presenter.markReceivableReceived(
        receivable.id,
        receivedAmount: r.amount,
        accountId: r.accountId,
        receivedDate: r.date,
        recordInLedger: r.recordInLedger,
      ),
    );
    return result != null;
  }

  Future<bool> _showMarkExpensePaidSheet(BudgetedExpense expense) async {
    final presenter = widget.presenter;
    final funders = presenter.setAsideFundingAccounts;
    if (funders.isEmpty) {
      AppToast.error(context, 'Add an account before funding.');
      return false;
    }
    // Default to the account the set-aside is assigned to.
    final fromId = funders.any((a) => a.id == expense.accountId)
        ? expense.accountId
        : funders.first.id;
    // The destination comes from the set-aside itself. With none on file the
    // field starts empty and Fund waits for an answer — a destination is never
    // guessed.
    final toId = presenter.preferredSetAsideDestinationId(expense,
        fromAccountId: fromId);
    final result = await showSettleSheet(
      context,
      kind: SettleKind.setAside,
      targets: [
        SettleTarget(
          id: expense.id,
          name: expense.name,
          amount: expense.allocatedAmount,
          accountId: fromId,
          destinationId: toId,
        ),
      ],
      payers: funders,
      initialAccountId: fromId,
      destinations: presenter.setAsideDestinationAccounts,
      onConfirm: (r) => presenter.markExpensePaid(
        expense.id,
        paidAmount: r.amount,
        accountId: r.accountId!,
        toAccountId: r.destinationId,
        paidDate: r.date,
      ),
    );
    return result != null;
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
          presenter: widget.installmentPresenter,
          receivables: widget.presenter,
          existing: existing),
    );
  }

  Future<bool> _showMarkInstallmentPaidSheet(Installment installment) async {
    final presenter = widget.installmentPresenter;
    final next = presenter.paidCount(installment.id) + 1;
    // No account picker: an installment is always charged to its own card.
    final result = await showSettleSheet(
      context,
      kind: SettleKind.installment,
      targets: [
        SettleTarget(
          id: installment.id,
          // "Mark Laptop (3/12) paid" — which payment this is.
          name: '${installment.name} ($next/${installment.totalMonths})',
          amount: installment.monthlyAmount,
        ),
      ],
      payers: const [],
      onConfirm: (r) => presenter.markPaid(
        installment.id,
        overrideAmount: r.amount,
        date: r.date,
      ),
    );
    return result != null;
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

  /// A card payment is a transfer from a liquid account, through the shared
  /// card-payment Settle sheet (the same one the Dashboard opens).
  void _payCard(FinancialAccount card) => showCardPaymentSheet(
        context,
        card: card,
        presenter: widget.presenter,
      );

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

  void _confirmDeleteInstallment(Installment inst) => _confirmDelete(
        title: 'Delete Installment',
        body: 'Delete "${inst.name}"? All linked payment transactions '
            'will also be removed.',
        onConfirm: () => widget.installmentPresenter.deleteInstallment(inst.id),
      );

  void _showStatementItems(Bill b) => StatementBreakdownSheet.show(
        context,
        presenter: widget.presenter,
        bill: b,
      );

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

  /// Every row id of [tab], in display order — what "Select all" picks. The
  /// hero bill is listed in Upcoming's "Due soon" too, so it can be batched.
  List<String> _tabIds(BillsTab tab) => switch (tab) {
        BillsTab.upcoming => [
            for (final b in widget.presenter.unpaidBills) b.id,
          ],
        BillsTab.paid => [for (final b in widget.presenter.paidBills) b.id],
        BillsTab.receivables => [
            for (final r in widget.presenter.receivables) r.id
          ],
        BillsTab.setAsides => [
            for (final e in widget.presenter.budgetedExpenses) e.id
          ],
        BillsTab.installments => [
            for (final i in widget.installmentPresenter.dueThisMonth) i.id
          ],
      };

  /// What the action bar needs to render: the tab's size, how many picked
  /// rows can still be settled, how many can be reversed, and the settle verb.
  /// Computed here so `build` stays declarative (Rule 1).
  ({int total, int settleable, int undoable, String verb}) _batchStatus(
      BillsTab tab) {
    switch (tab) {
      case BillsTab.upcoming:
      case BillsTab.paid:
        final picked = _selectedBills;
        return (
          total: _tabIds(tab).length,
          settleable: picked.where((b) => !b.isPaid).length,
          undoable: picked.where((b) => b.isPaid).length,
          verb: 'Pay',
        );
      case BillsTab.receivables:
        final picked = _selectedReceivables;
        return (
          total: widget.presenter.receivables.length,
          settleable: picked.where((r) => !r.isReceived).length,
          undoable: picked.where((r) => r.isReceived).length,
          verb: 'Receive',
        );
      case BillsTab.setAsides:
        final picked = _selectedExpenses;
        return (
          total: widget.presenter.budgetedExpenses.length,
          settleable: picked.where((e) => !e.isPaid).length,
          undoable: picked.where((e) => e.isPaid).length,
          verb: 'Fund',
        );
      case BillsTab.installments:
        final picked = _selectedInstallments;
        return (
          total: widget.installmentPresenter.dueThisMonth.length,
          settleable:
              picked.where(widget.installmentPresenter.canMarkPaid).length,
          undoable:
              picked.where(widget.installmentPresenter.canMarkUnpaid).length,
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
    // The Settle sheet runs the save and stays open with an error toast when
    // it fails. This catch is the safety net for anything thrown outside the
    // sheet; the selection is kept, so the user can try again.
    try {
      switch (_tab) {
        case BillsTab.upcoming:
        case BillsTab.paid:
          await _batchPayBills();
        case BillsTab.receivables:
          await _batchReceiveReceivables();
        case BillsTab.setAsides:
          await _batchFundExpenses();
        case BillsTab.installments:
          await _batchPayInstallments();
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save: $e');
    }
  }

  /// A batch of one is the single flow — it honours an edited amount. It
  /// still reports like a batch ([message]) and leaves selection mode.
  Future<void> _settleOne(
    Future<bool> Function() open, {
    required String message,
  }) async {
    if (await open()) _finishBatch(message);
  }

  Future<void> _batchPayBills() async {
    final presenter = widget.presenter;
    final targets = _selectedBills.where((b) => !b.isPaid).toList();
    if (targets.isEmpty) return;
    if (targets.length == 1) {
      return _settleOne(
        () => _showMarkBillPaidSheet(targets.single),
        message: 'Marked 1 bill paid.',
      );
    }
    BatchResult? outcome;
    final result = await showSettleSheet(
      context,
      kind: SettleKind.bill,
      targets: [
        for (final b in targets)
          SettleTarget(
            id: b.id,
            name: b.name,
            amount: presenter.billAmountOwed(b),
            dateLabel: DateFormat('MMM d').format(presenter.billDueDate(b)),
          ),
      ],
      payers: presenter.payerAccountsForAll(targets),
      initialAccountId: presenter.preferredBatchPayerAccountId(targets),
      onConfirm: (r) async {
        // With no eligible account there is nothing to debit, so the bills
        // are flagged paid without a ledger entry rather than failing.
        final record = r.recordInLedger && r.accountId != null;
        outcome = await presenter.markBillsPaid(
          r.targetIds,
          accountId: record ? r.accountId : null,
          paidDate: r.date,
          recordInLedger: record,
        );
      },
    );
    final done = outcome;
    if (result == null || done == null) return;
    _finishBatch(
      'Marked ${done.applied} ${_plural(done.applied, 'bill')} paid.',
      skipped: done.skipped,
    );
  }

  Future<void> _batchReceiveReceivables() async {
    final presenter = widget.presenter;
    final targets = _selectedReceivables.where((r) => !r.isReceived).toList();
    if (targets.isEmpty) return;
    if (targets.length == 1) {
      return _settleOne(
        () => _showMarkReceivedSheet(targets.single),
        message: 'Marked 1 received.',
      );
    }
    BatchResult? outcome;
    final result = await showSettleSheet(
      context,
      kind: SettleKind.receivable,
      targets: [
        for (final r in targets)
          SettleTarget(
            id: r.id,
            name: r.name,
            amount: r.amount,
            dateLabel: r.expectedDate == null
                ? 'ASAP'
                : DateFormat('MMM d').format(r.expectedDate!),
          ),
      ],
      payers: presenter.depositAccountsFor(targets.first),
      initialAccountId: presenter.preferredDepositAccountId(targets.first),
      onConfirm: (r) async {
        final record = r.recordInLedger && r.accountId != null;
        outcome = await presenter.markReceivablesReceived(
          r.targetIds,
          accountId: record ? r.accountId : null,
          receivedDate: r.date,
          recordInLedger: record,
        );
      },
    );
    final done = outcome;
    if (result == null || done == null) return;
    _finishBatch('Marked ${done.applied} received.');
  }

  Future<void> _batchFundExpenses() async {
    final presenter = widget.presenter;
    final targets = _selectedExpenses.where((e) => !e.isPaid).toList();
    if (targets.isEmpty) return;
    final funders = presenter.setAsideFundingAccounts;
    if (funders.isEmpty) {
      AppToast.error(context, 'Add an account before funding.');
      return;
    }
    if (targets.length == 1) {
      return _settleOne(
        () => _showMarkExpensePaidSheet(targets.single),
        message: 'Funded 1 set-aside.',
      );
    }
    // Rows that already know where they are going keep their own destination;
    // the sheet only has to ask about the rest.
    final withDestination = targets
        .where((e) => presenter.preferredSetAsideDestinationId(e) != null)
        .length;
    final named = targets.map((e) => e.accountId).toSet();
    BatchResult? outcome;
    final result = await showSettleSheet(
      context,
      kind: SettleKind.setAside,
      targets: [
        for (final e in targets)
          SettleTarget(id: e.id, name: e.name, amount: e.allocatedAmount),
      ],
      payers: funders,
      destinations: presenter.setAsideDestinationAccounts,
      initialAccountId: named.length == 1 ? named.first : null,
      savedDestinationCount: withDestination,
      onConfirm: (r) async {
        final accountId = r.accountId;
        if (accountId == null) return;
        outcome = await presenter.markExpensesPaid(
          r.targetIds,
          accountId: accountId,
          toAccountId: r.destinationId,
          preferSavedDestination: r.useSavedDestinations,
          paidDate: r.date,
        );
      },
    );
    final done = outcome;
    if (result == null || done == null) return;
    _finishBatch(
      'Funded ${done.applied} ${_plural(done.applied, 'set-aside')}.',
    );
  }

  Future<void> _batchPayInstallments() async {
    final presenter = widget.installmentPresenter;
    final targets = _selectedInstallments.where(presenter.canMarkPaid).toList();
    if (targets.isEmpty) return;
    if (targets.length == 1) {
      return _settleOne(
        () => _showMarkInstallmentPaidSheet(targets.single),
        message: 'Paid 1 installment this month.',
      );
    }
    int? applied;
    final result = await showSettleSheet(
      context,
      kind: SettleKind.installment,
      targets: [
        for (final i in targets)
          SettleTarget(id: i.id, name: i.name, amount: i.monthlyAmount),
      ],
      payers: const [],
      onConfirm: (r) async {
        applied = await presenter.markManyPaid(r.targetIds, date: r.date);
      },
    );
    final done = applied;
    if (result == null || done == null) return;
    _finishBatch('Paid $done ${_plural(done, 'installment')} this month.');
  }

  Future<void> _batchUndo() async {
    switch (_tab) {
      case BillsTab.upcoming:
      case BillsTab.paid:
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
      case BillsTab.receivables:
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
      case BillsTab.setAsides:
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
      case BillsTab.installments:
        final targets = _selectedInstallments
            .where(widget.installmentPresenter.canMarkUnpaid)
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
    final section = _tab;
    final ids = _selectedIds.toList();
    final label = switch (section) {
      BillsTab.upcoming || BillsTab.paid => 'bill',
      BillsTab.receivables => 'receivable',
      BillsTab.setAsides => 'set-aside',
      BillsTab.installments => 'installment',
    };
    // Ticking a recurring row here has to ask the same question opening it
    // does, or the batch bar is the quiet way to leave a series running.
    // Installments are one record spanning months rather than a row per month,
    // so they have no series to scope and keep the plain confirm.
    final reach = switch (section) {
      BillsTab.upcoming ||
      BillsTab.paid =>
        widget.presenter.billBatchSeriesReach(ids),
      BillsTab.receivables => widget.presenter.receivableBatchSeriesReach(ids),
      BillsTab.setAsides => widget.presenter.expenseBatchSeriesReach(ids),
      BillsTab.installments => (recurring: 0, extraMonths: 0),
    };
    final scope = await confirmRecurringBatchDelete(
      context: context,
      title: 'Delete ${ids.length} ${_plural(ids.length, label)}?',
      selectedCount: ids.length,
      recurringCount: reach.recurring,
      extraMonthCount: reach.extraMonths,
      plainBody: section == BillsTab.installments
          ? 'Their linked payment transactions are removed too. This cannot be '
              'undone.'
          : 'This cannot be undone.',
      soleName: ids.length == 1 ? _batchSoleName(section, ids.first) : null,
    );
    if (scope == null) return;
    final applyToFuture = scope == RecurringScope.thisAndFuture;
    final deleted = switch (section) {
      BillsTab.upcoming ||
      BillsTab.paid =>
        await widget.presenter.deleteBills(ids, applyToFuture: applyToFuture),
      BillsTab.receivables => await widget.presenter
          .deleteReceivables(ids, applyToFuture: applyToFuture),
      BillsTab.setAsides => await widget.presenter
          .deleteBudgetedExpenses(ids, applyToFuture: applyToFuture),
      BillsTab.installments =>
        await widget.installmentPresenter.deleteInstallments(ids),
    };
    _finishBatch('Deleted $deleted ${_plural(deleted, label)}.');
  }

  /// The name of the only selected row, so a one-row batch delete reads as
  /// "Alphaus Salary repeats" rather than "1 of them repeats".
  String? _batchSoleName(BillsTab section, String id) {
    final names = switch (section) {
      BillsTab.upcoming || BillsTab.paid => [
          for (final b in widget.presenter.allBills)
            if (b.id == id) b.name
        ],
      BillsTab.receivables => [
          for (final r in widget.presenter.allReceivables)
            if (r.id == id) r.name
        ],
      BillsTab.setAsides => [
          for (final e in widget.presenter.allBudgetedExpenses)
            if (e.id == id) e.name
        ],
      BillsTab.installments => const <String>[],
    };
    return names.isEmpty ? null : names.first;
  }

  /// "3 bills" / "1 bill" — the subject line of a batch confirmation.
  String _batchName(int count, String noun) => '$count ${_plural(count, noun)}';

  String _plural(int count, String noun) => count == 1 ? noun : '${noun}s';

  // ─── Tabs ────────────────────────────────────────────────────────────────

  /// Every row action, wired to this state's sheets and dialogs.
  late final BillsRowActions _actions = BillsRowActions(
    payBill: _showMarkBillPaidSheet,
    undoBill: _undoBillPayment,
    editBill: _showAddBillSheet,
    deleteBill: _confirmDeleteBill,
    viewStatement: _showStatementItems,
    receive: _showMarkReceivedSheet,
    undoReceipt: _undoReceivableReceipt,
    editReceivable: _showAddReceivableSheet,
    deleteReceivable: _confirmDeleteReceivable,
    fund: _showMarkExpensePaidSheet,
    undoFunding: _undoExpenseFunding,
    editSetAside: _showAddBudgetedExpenseSheet,
    deleteSetAside: _confirmDeleteExpense,
    payInstallment: _showMarkInstallmentPaidSheet,
    undoInstallment: _undoInstallmentPayment,
    editInstallment: _showAddInstallmentSheet,
    deleteInstallment: _confirmDeleteInstallment,
  );

  BillsRowSelection get _selection => BillsRowSelection(
        active: _selecting,
        selectedIds: _selectedIds,
        onToggle: _toggleSelected,
        onStart: _startSelection,
      );

  /// The open tab's body.
  Widget _tabBody() => switch (_tab) {
        BillsTab.upcoming => UpcomingBillsTab(
            presenter: widget.presenter,
            actions: _actions,
            selection: _selection,
          ),
        BillsTab.setAsides => SetAsidesTab(
            presenter: widget.presenter,
            actions: _actions,
            selection: _selection,
          ),
        BillsTab.receivables => ReceivablesTab(
            presenter: widget.presenter,
            actions: _actions,
            selection: _selection,
            reordering: _reorderingReceivables,
            onToggleReorder: () => setState(
                () => _reorderingReceivables = !_reorderingReceivables),
          ),
        BillsTab.installments => InstallmentsTab(
            presenter: widget.presenter,
            installmentPresenter: widget.installmentPresenter,
            actions: _actions,
            selection: _selection,
          ),
        BillsTab.paid => PaidBillsTab(
            presenter: widget.presenter,
            actions: _actions,
            selection: _selection,
          ),
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([widget.presenter, widget.installmentPresenter]),
      builder: (context, _) {
        final status = _selecting ? _batchStatus(_tab) : null;
        // Outside the tabs, the hero and the card Pay buttons stand down
        // during a selection so a stray tap can't act outside the batch.
        final locked = _selecting;
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
                  BillsHeader(
                    monthKey: widget.presenter.selectedMonth,
                    onMonthChanged: _setMonth,
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        HeroBillCard(
                          presenter: widget.presenter,
                          onMarkPaid: locked ? null : _showMarkBillPaidSheet,
                          onEdit: locked ? null : _showAddBillSheet,
                        ),
                        BillsMonthSummary(
                          presenter: widget.presenter,
                          installmentPresenter: widget.installmentPresenter,
                        ),
                        const SizedBox(height: 16),
                        BillsTabChips(
                          selected: _tab,
                          counts: billsTabCountMap(widget.presenter
                              .tabCounts(widget.installmentPresenter)),
                          onSelected: _setTab,
                        ),
                        const SizedBox(height: 14),
                        _tabBody(),
                        const SizedBox(height: 20),
                        CreditCardsCard(
                          presenter: widget.presenter,
                          onPay: locked ? null : _payCard,
                        ),
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
            bottomNavigationBar: status == null
                ? null
                : BatchActionBar(
                    selectedCount: _selectedIds.length,
                    totalCount: status.total,
                    settleLabel: status.verb,
                    onSettle: status.settleable > 0 ? _batchSettle : null,
                    onUndo: status.undoable > 0 ? _batchUndo : null,
                    onDelete: _selectedIds.isEmpty ? null : _batchDelete,
                    onSelectAll: () => _toggleSelectAll(_tabIds(_tab)),
                    onClose: _exitSelection,
                  ),
          ),
        );
      },
    );
  }
}
