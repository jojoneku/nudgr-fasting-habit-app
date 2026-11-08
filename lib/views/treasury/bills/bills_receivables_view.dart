import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/settle_request.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/category_icon.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/month_stepper_pill.dart';
import 'package:intermittent_fasting/views/treasury/shared/month_year_picker.dart';
import 'package:intermittent_fasting/views/treasury/shared/recurring_scope_field.dart';
import 'package:intermittent_fasting/views/treasury/shared/settle_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/start_month_review_card.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_bill_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_budgeted_expense_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_installment_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_receivable_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/batch_action_bar.dart';
import 'package:intermittent_fasting/views/treasury/bills/coming_up_timeline.dart';
import 'package:intermittent_fasting/views/treasury/bills/due_soon_stack.dart';
import 'package:intermittent_fasting/views/treasury/bills/new_entry_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/obligation_card.dart';
import 'package:intermittent_fasting/views/treasury/bills/statement_breakdown_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/statement_bill_card.dart';
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
      if (widget.installmentPresenter.canMarkPaid(s)) {
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
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save: $e');
    }
  }

  /// A batch of one is the single flow — it honours an edited amount.
  Future<void> _settleOne(Future<bool> Function() open) async {
    if (await open()) _exitSelection();
  }

  Future<void> _batchPayBills() async {
    final presenter = widget.presenter;
    final targets = _selectedBills.where((b) => !b.isPaid).toList();
    if (targets.isEmpty) return;
    if (targets.length == 1) {
      return _settleOne(() => _showMarkBillPaidSheet(targets.single));
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
      return _settleOne(() => _showMarkReceivedSheet(targets.single));
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
      return _settleOne(() => _showMarkExpensePaidSheet(targets.single));
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
      return _settleOne(() => _showMarkInstallmentPaidSheet(targets.single));
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
    final section = _batchSection!;
    final ids = _selectedIds.toList();
    final label = switch (section) {
      _BatchSection.bills => 'bill',
      _BatchSection.receivables => 'receivable',
      _BatchSection.budgeted => 'set-aside',
      _BatchSection.installments => 'installment',
    };
    // Ticking a recurring row here has to ask the same question opening it
    // does, or the batch bar is the quiet way to leave a series running.
    // Installments are one record spanning months rather than a row per month,
    // so they have no series to scope and keep the plain confirm.
    final reach = switch (section) {
      _BatchSection.bills => widget.presenter.billBatchSeriesReach(ids),
      _BatchSection.receivables =>
        widget.presenter.receivableBatchSeriesReach(ids),
      _BatchSection.budgeted => widget.presenter.expenseBatchSeriesReach(ids),
      _BatchSection.installments => (recurring: 0, extraMonths: 0),
    };
    final scope = await confirmRecurringBatchDelete(
      context: context,
      title: 'Delete ${ids.length} ${_plural(ids.length, label)}?',
      selectedCount: ids.length,
      recurringCount: reach.recurring,
      extraMonthCount: reach.extraMonths,
      plainBody: section == _BatchSection.installments
          ? 'Their linked payment transactions are removed too. This cannot be '
              'undone.'
          : 'This cannot be undone.',
      soleName: ids.length == 1 ? _batchSoleName(section, ids.first) : null,
    );
    if (scope == null) return;
    final applyToFuture = scope == RecurringScope.thisAndFuture;
    final deleted = switch (section) {
      _BatchSection.bills =>
        await widget.presenter.deleteBills(ids, applyToFuture: applyToFuture),
      _BatchSection.receivables => await widget.presenter
          .deleteReceivables(ids, applyToFuture: applyToFuture),
      _BatchSection.budgeted => await widget.presenter
          .deleteBudgetedExpenses(ids, applyToFuture: applyToFuture),
      _BatchSection.installments =>
        await widget.installmentPresenter.deleteInstallments(ids),
    };
    _finishBatch('Deleted $deleted ${_plural(deleted, label)}.');
  }

  /// The name of the only selected row, so a one-row batch delete reads as
  /// "Alphaus Salary repeats" rather than "1 of them repeats".
  String? _batchSoleName(_BatchSection section, String id) {
    final names = switch (section) {
      _BatchSection.bills => [
          for (final b in widget.presenter.allBills)
            if (b.id == id) b.name
        ],
      _BatchSection.receivables => [
          for (final r in widget.presenter.allReceivables)
            if (r.id == id) r.name
        ],
      _BatchSection.budgeted => [
          for (final e in widget.presenter.allBudgetedExpenses)
            if (e.id == id) e.name
        ],
      _BatchSection.installments => const <String>[],
    };
    return names.isEmpty ? null : names.first;
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
    final sel = _selectionFor(_BatchSection.bills, b.id);
    final locked = _locked(_BatchSection.bills);
    final statement = widget.presenter.statementCard(b);
    if (statement != null) {
      return StatementBillCard(
        key: ValueKey('bill_${b.id}'),
        view: statement,
        onPay: locked ? null : () => _showMarkBillPaidSheet(b),
        onUndo: widget.presenter.hasUndoablePayment(b) && !locked
            ? () => _undoBillPayment(b)
            : null,
        onViewItems: locked ? null : () => _showStatementItems(b),
        onEdit: locked ? null : () => _showAddBillSheet(b),
        onLongPress: locked ? null : sel.onLongPress,
        selectionMode: sel.mode,
        selected: sel.selected,
        onSelectionToggle: sel.onToggle,
      );
    }
    final v = _catVisual(b.categoryId, fallback: context.appColors.bills);
    final String? note = widget.presenter.statementProgressNote(b) ??
        (b.isPaid
            ? 'Paid ${formatPeso(b.paidAmount ?? b.amount)}'
                '${b.paidDate != null ? ' · ${DateFormat('MMM d').format(b.paidDate!)}' : ''}'
            : b.isAutoStatement
                ? 'Auto-generated statement'
                : (b.paymentNote != null && b.paymentNote!.isNotEmpty
                    ? b.paymentNote
                    : null));
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
      progress: widget.presenter.statementProgressFraction(b),
      dateLabel:
          'due ${DateFormat('MMM d').format(widget.presenter.billDueDate(b))}',
      actionLabel: 'Pay',
      done: b.isPaid,
      onAction: b.isPaid || locked ? null : () => _showMarkBillPaidSheet(b),
      onUndo: widget.presenter.hasUndoablePayment(b) && !locked
          ? () => _undoBillPayment(b)
          : null,
      undoLabel: 'Mark unpaid',
      onEdit: locked ? null : () => _showAddBillSheet(b),
      onDelete: locked ? null : () => _confirmDeleteBill(b),
      onLongPress: locked ? null : sel.onLongPress,
      selectionMode: sel.mode,
      selected: sel.selected,
      onSelectionToggle: sel.onToggle,
      // Credit statements list what is on them: purchases, installment
      // months, refunds and repayments, each opening its transaction form.
      detailLabel: widget.presenter.statementItemsLabel(b),
      onDetail: locked ? null : () => _showStatementItems(b),
    );
  }

  void _showStatementItems(Bill b) => StatementBreakdownSheet.show(
        context,
        presenter: widget.presenter,
        bill: b,
      );

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
    // On a card with statements a month is paid by paying its statement, so
    // the row follows that statement instead of calling a billed month paid.
    final onStatement = widget.presenter.installmentStatementStatus(inst);
    final statementBill = onStatement?.statement;
    final paidThisMonth = onStatement?.paid ??
        widget.installmentPresenter.isPaidForMonth(inst.id);
    final canPay = widget.installmentPresenter.canMarkPaid(inst);
    final canUndo = widget.installmentPresenter.canMarkUnpaid(inst);
    final account = widget.installmentPresenter.accounts
        .where((a) => a.id == inst.accountId)
        .firstOrNull;
    return ObligationCard(
      key: ValueKey('inst_${inst.id}'),
      icon: Icons.credit_score_outlined,
      iconColor: context.appColors.purple,
      name: inst.name,
      // On a card with statements the note says why there is no Pay button:
      // the month can only be paid with the whole statement.
      note: onStatement?.note ?? account?.name,
      // Paid months only: a month billed onto an open statement is not paid.
      progress: onStatement?.progress ??
          widget.installmentPresenter.paymentProgress(inst.id),
      amount: inst.monthlyAmount,
      dateLabel:
          onStatement?.label ?? widget.installmentPresenter.statusLabel(inst),
      actionLabel: 'Pay',
      done: paidThisMonth,
      // A plan on a card with statements is billed at close and paid with the
      // statement, so its row offers neither Pay nor Undo.
      onAction:
          canPay && !locked ? () => _showMarkInstallmentPaidSheet(inst) : null,
      onUndo: canUndo && !locked ? () => _undoInstallmentPayment(inst) : null,
      undoLabel: 'Mark unpaid this month',
      detailLabel: onStatement?.linkLabel,
      onDetail: statementBill == null || locked
          ? null
          : () => _showStatementItems(statementBill),
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
                        StartMonthReviewCard(
                          presenter: widget.installmentPresenter,
                          margin: const EdgeInsets.only(bottom: 12),
                        ),
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

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showMonthYearPicker(context, monthKey: monthKey);
    if (selected != null && selected != monthKey) onMonthChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canPop = Navigator.canPop(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 20, 8, 12, 4),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
            ),
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
          MonthStepperPill(
            month: monthKey,
            onTap: () => _openPicker(context),
            onMonthChanged: onMonthChanged,
          ),
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
