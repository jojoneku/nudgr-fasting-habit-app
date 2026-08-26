import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/utils/app_radii.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/bills/batch_settle_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/coming_up_timeline.dart';
import 'package:intermittent_fasting/views/treasury/bills/due_soon_hero.dart';
import 'package:intermittent_fasting/views/treasury/bills/due_soon_stack.dart';
import 'package:intermittent_fasting/views/treasury/bills/undo_settlement_dialog.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_badge_widget.dart';
import 'package:intermittent_fasting/views/treasury/shared/recurring_scope_field.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../../widgets/web_widgets.dart';

final _expectedDateFmt = DateFormat('MMM d, yyyy');

/// Web Bills & Receivables page (Plan 050-C).
///
/// Desktop redesign of the mobile [BillsReceivablesView] following the Claude
/// Design reference (`docs/design/treasury-web-reference/screens/bills.png`).
/// Reads exclusively from the injected presenters — no fabricated getters.
class WebBillsPage extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;

  const WebBillsPage({
    super.key,
    required this.presenter,
    required this.installmentPresenter,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Installments surface as bills only via the presenter's auto-generated
      // statements, but we still listen so counts stay live if it reloads.
      listenable: Listenable.merge([presenter, installmentPresenter]),
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(WebInsets.xxl),
        child: _BillsBody(
          presenter: presenter,
          installmentPresenter: installmentPresenter,
        ),
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

/// Which list a running batch selection belongs to. Only one section can be
/// selecting at a time — a batch settles through one account on one date, and a
/// selection spanning bills *and* receivables has no single meaning.
enum _BatchSection { bills, receivables, budgeted, installments }

class _BillsBody extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final InstallmentPresenter installmentPresenter;

  const _BillsBody({
    required this.presenter,
    required this.installmentPresenter,
  });

  @override
  State<_BillsBody> createState() => _BillsBodyState();
}

class _BillsBodyState extends State<_BillsBody> {
  /// The section currently selecting, or null when not in selection mode.
  _BatchSection? _section;

  /// Ids picked in [_section].
  final Set<String> _selectedIds = {};

  /// True while a batch is in flight, so a second click can't fire it twice.
  bool _busy = false;

  BillsReceivablesPresenter get presenter => widget.presenter;
  InstallmentPresenter get installmentPresenter => widget.installmentPresenter;

  bool _picking(_BatchSection section) => _section == section;
  bool _locked(_BatchSection section) =>
      _section != null && _section != section;

  void _start(_BatchSection section) => setState(() {
        _section = section;
        _selectedIds.clear();
      });

  void _exitSelection() => setState(() {
        _section = null;
        _selectedIds.clear();
      });

  void _toggle(String id) => setState(() {
        if (!_selectedIds.remove(id)) _selectedIds.add(id);
        // Emptying the selection leaves selection mode, same as mobile — an
        // empty batch bar has nothing to offer.
        if (_selectedIds.isEmpty) _section = null;
      });

  void _toggleAll(List<String> ids) => setState(() {
        final all = ids.isNotEmpty && ids.every(_selectedIds.contains);
        _selectedIds.clear();
        if (!all) _selectedIds.addAll(ids);
        if (_selectedIds.isEmpty) _section = null;
      });

  /// How [id] participates in the selection, or null when [section] isn't the
  /// one selecting — which is what makes a row render normally.
  WebRowSelection? _selectionFor(_BatchSection section, String id) {
    if (!_picking(section)) return null;
    return WebRowSelection(
      active: true,
      selected: _selectedIds.contains(id),
      onToggle: () => _toggle(id),
    );
  }

  /// The per-card "Select" / count / select-all control.
  Widget _selectControl(_BatchSection section, List<String> ids) =>
      WebBatchSelectControl(
        active: _picking(section),
        locked: _locked(section),
        selectedCount: _selectedIds.length,
        totalCount: ids.length,
        onStart: () => _start(section),
        onCancel: _exitSelection,
        onToggleAll: () => _toggleAll(ids),
      );

  /// The action bar under a selecting card, or null when it isn't selecting.
  Widget? _batchBar(_BatchSection section) {
    if (!_picking(section)) return null;
    final status = _batchStatus(section);
    return WebBatchBar(
      settleVerb: status.verb,
      selectedCount: _selectedIds.length,
      settleableCount: status.settleable,
      undoableCount: status.undoable,
      enabled: !_busy,
      onSettle: _batchSettle,
      onUndo: _batchUndo,
      onDelete: _batchDelete,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bills = presenter.bills;
    final unpaid = [...bills.where((b) => !b.isPaid)]
      ..sort((a, b) => a.dueDay.compareTo(b.dueDay));
    final paid = [...bills.where((b) => b.isPaid)]
      ..sort((a, b) => a.dueDay.compareTo(b.dueDay));
    final receivables = presenter.receivables;
    final pendingReceivables = receivables.where((r) => !r.isReceived).toList();

    final dueTotal = presenter.totalBillsPending;
    final paidTotal = presenter.totalBillsPaid;
    // All bills for the month (paid + unpaid). Budgeted expenses are NOT
    // surfaced on this page — they're an obligation shown on the dashboard's
    // "Current Obligations", so mixing them in here was confusing.
    final monthTotal = presenter.totalBillsAmount;
    final receiveTotal =
        pendingReceivables.fold(0.0, (sum, r) => sum + r.amount);

    final children = <Widget>[
      _Header(
        monthLabel: monthLabel(presenter.selectedMonth),
        subtitle:
            '${monthLabel(presenter.selectedMonth)} · ${unpaid.length} bills due, ${pendingReceivables.length} to receive',
        onAddBill: () => _onAddBill(context),
        onPrevMonth: () =>
            presenter.setMonth(previousMonth(presenter.selectedMonth)),
        onNextMonth: () =>
            presenter.setMonth(nextMonth(presenter.selectedMonth)),
      ),
      const SizedBox(height: WebInsets.xl),
    ];

    // The move the web page was missing: lead with what is about to come due,
    // not with a row of totals. Same DueSoonHero the phone renders — mobile
    // swipes a PageView through them, desktop has the width to show them at
    // once, so the deck becomes a row.
    final imminent = presenter.imminentUnpaidBills;
    if (imminent.isNotEmpty) {
      children
        ..add(_DueSoonRow(presenter: presenter, bills: imminent))
        ..add(const SizedBox(height: WebInsets.xl));
    }

    children
      ..add(_StatStrip(
        dueTotal: dueTotal,
        paidTotal: paidTotal,
        monthTotal: monthTotal,
        receiveTotal: receiveTotal,
        unpaidCount: unpaid.length,
        paidCount: paid.length,
        receivableCount: pendingReceivables.length,
      ))
      ..add(const SizedBox(height: WebInsets.xl));

    // "Coming up" — every obligation type on one timeline, the way the phone
    // shows it. Web had no equivalent: bills, receivables, set-asides and
    // installments were four separate cards you had to merge in your head.
    final comingUp = presenter.comingUpItems(installmentPresenter);
    if (comingUp.isNotEmpty) {
      children
        ..add(_ComingUpCard(
          items: comingUp,
          onTap: (item) => _openComingUpItem(context, item),
        ))
        ..add(const SizedBox(height: WebInsets.xl));
    }

    // Select-all covers every row of the section, in display order — including
    // the paid bills, which live in their own card further down but are the
    // same selection (that is what makes batch-undo reachable).
    final billIds = [
      for (final b in [...unpaid, ...paid]) b.id
    ];
    final receivableIds = [for (final r in receivables) r.id];
    final expenseIds = [for (final e in presenter.budgetedExpenses) e.id];
    final installmentIds = [
      for (final i in installmentPresenter.dueThisMonth) i.id
    ];

    final creditCards = presenter.creditAccounts;
    final upcomingCard = _UpcomingCard(
      presenter: presenter,
      unpaid: unpaid,
      dueTotal: dueTotal,
      batchControl: _selectControl(_BatchSection.bills, billIds),
      batchBar: _batchBar(_BatchSection.bills),
      selectionOf: (id) => _selectionFor(_BatchSection.bills, id),
    );
    final receivablesCard = _ReceivablesCard(
      presenter: presenter,
      receivables: receivables,
      pendingTotal: receiveTotal,
      batchControl: _selectControl(_BatchSection.receivables, receivableIds),
      batchBar: _batchBar(_BatchSection.receivables),
      selectionOf: (id) => _selectionFor(_BatchSection.receivables, id),
    );
    final budgetedCard = _BudgetedExpensesCard(
      presenter: presenter,
      expenses: presenter.budgetedExpenses,
      batchControl: _selectControl(_BatchSection.budgeted, expenseIds),
      batchBar: _batchBar(_BatchSection.budgeted),
      selectionOf: (id) => _selectionFor(_BatchSection.budgeted, id),
    );

    // Layout (top → bottom): Credit cards → [Upcoming bills | Set-asides] side
    // by side → Receivables → Installments → Paid. Bills and set-asides pair up
    // because they're the two "money leaving soon" obligations.
    if (creditCards.isNotEmpty) {
      children
        ..add(_WebCreditCardsCard(presenter: presenter, cards: creditCards))
        ..add(const SizedBox(height: WebInsets.xl));
    }
    // Installments follow the shared TreasuryMonthScope, so "due this month"
    // already lines up with the bills above — no month poke from `build` (which
    // mutated presenter state mid-frame to get the same effect).
    final installmentsCard = _InstallmentsCard(
      presenter: installmentPresenter,
      batchControl: _selectControl(_BatchSection.installments, installmentIds),
      batchBar: _batchBar(_BatchSection.installments),
      selectionOf: (id) => _selectionFor(_BatchSection.installments, id),
    );

    children
      ..add(_SideBySideCards(left: upcomingCard, right: budgetedCard))
      ..add(const SizedBox(height: WebInsets.xl));

    // How much still needs to land in each funding account to cover the unpaid
    // bills + unfunded set-asides above. Hidden when nothing is outstanding.
    final breakdown = presenter.fundingBreakdown();
    if (breakdown.isNotEmpty) {
      children
        ..add(_ByAccountCard(presenter: presenter, rows: breakdown))
        ..add(const SizedBox(height: WebInsets.xl));
    }

    children
      ..add(receivablesCard)
      ..add(const SizedBox(height: WebInsets.xl))
      ..add(installmentsCard);

    if (paid.isNotEmpty) {
      children
        ..add(const SizedBox(height: WebInsets.xl))
        ..add(_PaidCard(
          presenter: presenter,
          paid: paid,
          paidTotal: paidTotal,
          selectionOf: (id) => _selectionFor(_BatchSection.bills, id),
        ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  void _onAddBill(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _AddBillDialog(presenter: presenter),
    );
  }

  // ─── Batch actions ─────────────────────────────────────────────────────────
  //
  // Everything below acts on the current selection. Each handler resolves the
  // picked rows from the presenter's live lists (so an id that vanished under
  // us is simply not there), asks once for whatever the whole batch shares,
  // hands the work to a presenter batch method, then reports what happened and
  // leaves selection mode. Deliberately the same shape as the mobile view's
  // handlers, so the two can't drift on what a batch does.

  List<Bill> get _selectedBills =>
      presenter.bills.where((b) => _selectedIds.contains(b.id)).toList();

  List<Receivable> get _selectedReceivables =>
      presenter.receivables.where((r) => _selectedIds.contains(r.id)).toList();

  List<BudgetedExpense> get _selectedExpenses => presenter.budgetedExpenses
      .where((e) => _selectedIds.contains(e.id))
      .toList();

  List<Installment> get _selectedInstallments =>
      installmentPresenter.dueThisMonth
          .where((i) => _selectedIds.contains(i.id))
          .toList();

  /// What the action bar needs: how many picked rows can still be settled, how
  /// many can be reversed, and the settle verb. Computed here so `build` stays
  /// declarative (Rule 1).
  ({int settleable, int undoable, String verb}) _batchStatus(
      _BatchSection section) {
    switch (section) {
      case _BatchSection.bills:
        final picked = _selectedBills;
        return (
          settleable: picked.where((b) => !b.isPaid).length,
          undoable: picked.where((b) => b.isPaid).length,
          verb: 'Pay',
        );
      case _BatchSection.receivables:
        final picked = _selectedReceivables;
        return (
          settleable: picked.where((r) => !r.isReceived).length,
          undoable: picked.where((r) => r.isReceived).length,
          verb: 'Receive',
        );
      case _BatchSection.budgeted:
        final picked = _selectedExpenses;
        return (
          settleable: picked.where((e) => !e.isPaid).length,
          undoable: picked.where((e) => e.isPaid).length,
          verb: 'Fund',
        );
      case _BatchSection.installments:
        final picked = _selectedInstallments;
        final paid = picked
            .where((i) => installmentPresenter.isPaidForMonth(i.id))
            .length;
        return (
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

  /// Runs [action] with the bar disabled, so a second click during the await
  /// can't launch the same batch twice.
  Future<void> _runBatch(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _batchSettle() => _runBatch(() async {
        switch (_section!) {
          case _BatchSection.bills:
            await _batchPayBills();
          case _BatchSection.receivables:
            await _batchReceiveReceivables();
          case _BatchSection.budgeted:
            await _batchFundExpenses();
          case _BatchSection.installments:
            await _batchPayInstallments();
        }
      });

  Future<void> _batchPayBills() async {
    final targets = _selectedBills.where((b) => !b.isPaid).toList();
    if (targets.isEmpty) return;
    final choice = await showWebBatchSettleDialog(
      context,
      kind: BatchSettleKind.bills,
      count: targets.length,
      total: targets.fold(0.0, (sum, b) => sum + b.amount),
      accounts: presenter.payerAccountsForAll(targets),
      initialAccountId: presenter.preferredBatchPayerAccountId(targets),
    );
    if (choice == null) return;
    // With no eligible account there is nothing to debit, so the bills are
    // flagged paid without a ledger entry rather than failing.
    final record = !choice.alreadyInLedger && choice.accountId != null;
    final result = await presenter.markBillsPaid(
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
    final choice = await showWebBatchSettleDialog(
      context,
      kind: BatchSettleKind.receivables,
      count: targets.length,
      total: targets.fold(0.0, (sum, r) => sum + r.amount),
      accounts: presenter.depositAccountsFor(targets.first),
      initialAccountId: presenter.preferredDepositAccountId(targets.first),
    );
    if (choice == null) return;
    final record = !choice.alreadyInLedger && choice.accountId != null;
    final result = await presenter.markReceivablesReceived(
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
    final funders = presenter.setAsideFundingAccounts;
    if (funders.isEmpty) {
      AppToast.error(context, 'Add an account before funding.');
      return;
    }
    // Rows that already know where they are going keep their own destination;
    // the dialog only has to ask about the rest.
    final withDestination = targets
        .where((e) => presenter.preferredSetAsideDestinationId(e) != null)
        .length;
    final named = targets.map((e) => e.accountId).toSet();
    final choice = await showWebBatchSettleDialog(
      context,
      kind: BatchSettleKind.setAsides,
      count: targets.length,
      total: targets.fold(0.0, (sum, e) => sum + e.allocatedAmount),
      accounts: funders,
      destinations: presenter.setAsideDestinationAccounts,
      initialAccountId: named.length == 1 ? named.first : null,
      savedDestinationCount: withDestination,
    );
    if (choice == null || choice.accountId == null) return;
    final result = await presenter.markExpensesPaid(
      [for (final e in targets) e.id],
      accountId: choice.accountId!,
      toAccountId: choice.toAccountId,
      preferSavedDestination: choice.useSavedDestinations,
      paidDate: choice.date,
    );
    _finishBatch(
        'Funded ${result.applied} ${_plural(result.applied, 'set-aside')}.');
  }

  Future<void> _batchPayInstallments() async {
    final targets = _selectedInstallments
        .where((i) => !installmentPresenter.isPaidForMonth(i.id))
        .toList();
    if (targets.isEmpty) return;
    final choice = await showWebBatchSettleDialog(
      context,
      kind: BatchSettleKind.installments,
      count: targets.length,
      total: targets.fold(0.0, (sum, i) => sum + i.monthlyAmount),
    );
    if (choice == null) return;
    final applied = await installmentPresenter
        .markManyPaid([for (final i in targets) i.id], date: choice.date);
    _finishBatch(
        'Paid $applied ${_plural(applied, 'installment')} this month.');
  }

  Future<void> _batchUndo() => _runBatch(() async {
        switch (_section!) {
          case _BatchSection.bills:
            final targets = _selectedBills.where((b) => b.isPaid).toList();
            if (targets.isEmpty) return;
            final choice = await showUndoSettlementDialog(
              context: context,
              title: 'Undo ${targets.length} payments?',
              name: _batchName(targets.length, 'bill'),
              entryLabel: 'bill',
              hasLedgerEntry: targets.any(presenter.billHasLedgerEntry),
              ledgerEffect:
                  '${formatPeso(targets.fold(0.0, (s, b) => s + (b.paidAmount ?? b.amount)))} '
                  'goes back into the accounts they were paid from.',
            );
            if (choice == null) return;
            final result = await presenter.markBillsUnpaid(
              [for (final b in targets) b.id],
              removeTransaction: choice.removeTransaction,
            );
            _finishBatch('Marked ${result.applied} '
                '${_plural(result.applied, 'bill')} unpaid.');
          case _BatchSection.receivables:
            final targets =
                _selectedReceivables.where((r) => r.isReceived).toList();
            if (targets.isEmpty) return;
            final choice = await showUndoSettlementDialog(
              context: context,
              title: 'Undo ${targets.length} receipts?',
              name: _batchName(targets.length, 'receivable'),
              entryLabel: 'receivable',
              hasLedgerEntry: targets.any(presenter.receivableHasLedgerEntry),
              ledgerEffect:
                  '${formatPeso(targets.fold(0.0, (s, r) => s + (r.receivedAmount ?? r.amount)))} '
                  'is taken back out of the accounts it was deposited into.',
            );
            if (choice == null) return;
            final result = await presenter.markReceivablesUnreceived(
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
              hasLedgerEntry: targets.any(presenter.expenseHasLedgerEntry),
              ledgerEffect:
                  '${formatPeso(targets.fold(0.0, (s, e) => s + e.spentAmount))} '
                  'is moved back to the accounts it was funded from.',
            );
            if (choice == null) return;
            final result = await presenter.markExpensesUnpaid(
              [for (final e in targets) e.id],
              removeTransaction: choice.removeTransaction,
            );
            _finishBatch('Marked ${result.applied} '
                '${_plural(result.applied, 'set-aside')} unfunded.');
          case _BatchSection.installments:
            final targets = _selectedInstallments
                .where((i) => installmentPresenter.isPaidForMonth(i.id))
                .toList();
            if (targets.isEmpty) return;
            final choice = await showUndoSettlementDialog(
              context: context,
              title: 'Undo ${targets.length} payments?',
              name: _batchName(targets.length, 'installment payment'),
              entryLabel: 'installment payment',
              // An installment payment IS its transaction — there is no flag
              // to reverse on its own, so the transaction always goes with it.
              hasLedgerEntry: false,
              ledgerEffect:
                  "This month's payment transactions are removed and the "
                  'accounts they were paid from are credited back.',
            );
            if (choice == null) return;
            final applied = await installmentPresenter
                .markManyUnpaid([for (final i in targets) i.id]);
            _finishBatch('Marked $applied '
                '${_plural(applied, 'installment')} unpaid this month.');
        }
      });

  Future<void> _batchDelete() => _runBatch(() async {
        final section = _section!;
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
              ? 'Their linked payment transactions are removed too. This '
                  'cannot be undone.'
              : 'This cannot be undone.',
          confirmLabel: 'Delete',
          cancelLabel: 'Cancel',
          isDestructive: true,
        );
        if (!ok) return;
        final deleted = switch (section) {
          _BatchSection.bills => await presenter.deleteBills(ids),
          _BatchSection.receivables => await presenter.deleteReceivables(ids),
          _BatchSection.budgeted => await presenter.deleteBudgetedExpenses(ids),
          _BatchSection.installments =>
            await installmentPresenter.deleteInstallments(ids),
        };
        _finishBatch('Deleted $deleted ${_plural(deleted, label)}.');
      });

  /// Routes a "Coming up" row to the dialog for its own kind, resolved off
  /// [ComingUpItem.source].
  ///
  /// Deliberately different from the phone, which opens the *settle* sheet
  /// here. Web's settle flows other than a bill's still live inside their row
  /// widgets, and lifting three money-moving flows out of a 3k-line file to
  /// match a tap target is a change that deserves its own diff. Opening the
  /// item's editor is the same destination reachable from the sections below,
  /// so a tap is never a dead end.
  void _openComingUpItem(BuildContext context, ComingUpItem item) {
    final source = item.source;
    Widget? dialog;
    if (source is Bill) {
      dialog = _AddBillDialog(presenter: presenter, existing: source);
    } else if (source is Receivable) {
      dialog = _ReceivableDialog(presenter: presenter, existing: source);
    } else if (source is BudgetedExpense) {
      dialog = _BudgetedExpenseDialog(presenter: presenter, existing: source);
    } else if (source is Installment) {
      dialog =
          _InstallmentDialog(presenter: installmentPresenter, existing: source);
    }
    if (dialog == null) return;
    // Bound to a final so the builder closure captures a non-nullable Widget —
    // promotion of `dialog` doesn't reach inside the closure.
    final resolved = dialog;
    showDialog<void>(context: context, builder: (_) => resolved);
  }
}

/// "1 bill" / "3 bills" — batch messages count things constantly.
String _plural(int n, String singular) => n == 1 ? singular : '${singular}s';

/// Stand-in name for a multi-row undo dialog, which asks about a group rather
/// than a named entry.
String _batchName(int n, String singular) => '$n ${_plural(n, singular)}';

/// Places two cards side by side on wide viewports and stacks them (left above
/// right) once the page gets too narrow for two readable columns. On wide
/// viewports both cards stretch to the taller one's height (via IntrinsicHeight)
/// so the shorter list no longer leaves a ragged bottom edge next to its
/// neighbour.
class _SideBySideCards extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _SideBySideCards({required this.left, required this.right});

  /// Below this width two columns would each be too cramped, so we stack.
  static const double _stackBelow = 900;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _stackBelow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: WebInsets.xl),
              right,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: WebInsets.xl),
              Expanded(child: right),
            ],
          ),
        );
      },
    );
  }
}

// ─── Due-soon heroes ──────────────────────────────────────────────────────────

/// The phone's swipeable due-soon deck, re-proportioned for a desktop page: the
/// same [DueSoonHero] cards laid out side by side (two per row on a wide page,
/// one when narrow) instead of stacked behind a PageView. Swiping is a phone
/// affordance; on a monitor there is simply room to show them.
///
/// Reuses the mobile widget rather than a lookalike, so the gradient, the
/// overdue escalation, and the Mark-paid button can never drift between the two
/// surfaces. Actions route to the same dialogs the bill rows below use.
class _DueSoonRow extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final List<Bill> bills;

  const _DueSoonRow({required this.presenter, required this.bills});

  /// Below this width two heroes side by side would each be too cramped for the
  /// amount and the Mark-paid button to sit on one line.
  static const double _twoUpMin = 860;

  /// Beyond this many cards the row stops being a glance and starts being the
  /// list that already follows it. Nothing is lost by the cap — every bill
  /// beyond it is still in the Upcoming card further down the page.
  static const int _maxHeroes = 4;

  @override
  Widget build(BuildContext context) {
    final shown = bills.take(_maxHeroes).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= _twoUpMin ? 2 : 1;
        const gap = WebInsets.xl;
        final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final bill in shown)
              SizedBox(width: width, child: _hero(context, bill)),
          ],
        );
      },
    );
  }

  Widget _hero(BuildContext context, Bill bill) {
    final due = presenter.billDueInfo(bill);
    return DueSoonHero(
      billName: bill.name,
      amount: bill.amount,
      dueLabel: due.label,
      subtitle: dueSoonSubtitle(presenter, bill),
      overdue: due.overdue,
      onMarkPaid: () => _markBillPaidFlow(context, presenter, bill),
      onEdit: () => showDialog<void>(
        context: context,
        builder: (_) => _AddBillDialog(presenter: presenter, existing: bill),
      ),
    );
  }
}

// ─── Coming up ────────────────────────────────────────────────────────────────

/// The unified "Coming up" timeline, in a web card. The timeline itself is the
/// phone's [ComingUpTimeline] — the merged bill/receivable/set-aside/installment
/// list comes ready-made from the presenter, so both surfaces order and colour
/// it identically.
class _ComingUpCard extends StatelessWidget {
  final List<ComingUpItem> items;
  final void Function(ComingUpItem) onTap;

  const _ComingUpCard({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return WebCard(
      title: 'Coming up',
      description: 'Next ${items.length} across bills, receivables, '
          'set-asides and installments',
      child: ComingUpTimeline(items: items, onTap: onTap),
    );
  }
}

// ─── Add-bill dialog ────────────────────────────────────────────────────────

/// Desktop add-bill form (Plan 050). Mirrors the mobile [AddBillSheet]'s core
/// single-bill case: Name, Bill Type, Amount, Due Day, Payment Account, and
/// (expense) Category, then calls [BillsReceivablesPresenter.addBill] with a
/// freshly built [Bill] keyed to `presenter.selectedMonth`.
///
// Payment note and the recurring toggle are included: without them a bill
// added on web was silently one-off, so the same task produced a different
// result depending on which device you happened to use.
class _AddBillDialog extends StatefulWidget {
  final BillsReceivablesPresenter presenter;

  /// When non-null the dialog edits this bill in place via [updateBill];
  /// otherwise it creates a new one via [addBill].
  final Bill? existing;

  const _AddBillDialog({required this.presenter, this.existing});

  @override
  State<_AddBillDialog> createState() => _AddBillDialogState();
}

class _AddBillDialogState extends State<_AddBillDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _dueDayController = TextEditingController();

  final _paymentNoteController = TextEditingController();

  late BillType _billType;
  String? _selectedAccountId;
  String? _selectedCategoryId;
  bool _isRecurring = false;
  RecurrenceType _recurrenceType = RecurrenceType.monthly;
  bool _reminderOn = false;
  int _reminderDays = 2;
  bool _isSubmitting = false;

  /// How far this save reaches across the months already generated ahead —
  /// mirrors the mobile sheet, defaulting to carrying forward.
  RecurringScope _scope = RecurringScope.thisAndFuture;

  /// Later months the scope switch would touch, resolved once (Rule 1).
  late final int _futureMonthCount;

  /// Lead times offered for the due-date reminder, matching the mobile sheet's
  /// chips so the same bill can be set up identically on either platform.
  static const _reminderDayOptions = [1, 2, 3, 5, 7];

  bool get _wasRecurring => widget.existing?.isRecurring ?? false;

  bool get _dropsFutureMonths => !_isRecurring && _wasRecurring;

  bool get _showScopeField =>
      (_isRecurring || _wasRecurring) && _futureMonthCount > 0;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _billType = b?.billType ?? BillType.other;
    if (b != null) {
      _nameController.text = b.name;
      _amountController.text = b.amount == b.amount.roundToDouble()
          ? b.amount.round().toString()
          : b.amount.toString();
      _dueDayController.text = b.dueDay.toString();
      _selectedAccountId = b.accountId;
      _selectedCategoryId = b.categoryId.isEmpty ? null : b.categoryId;
      // Hide the internal auto-statement marker — it is not a user-facing note
      // (mirrors the mobile sheet).
      _paymentNoteController.text =
          b.isAutoStatement ? '' : (b.paymentNote ?? '');
      _isRecurring = b.isRecurring;
      _recurrenceType = b.recurrenceType ?? RecurrenceType.monthly;
      _reminderOn = b.reminderDaysBefore != null;
      _reminderDays = b.reminderDaysBefore ?? 2;
    }
    _futureMonthCount = widget.presenter.futureBillReach(
      month: b?.month ?? widget.presenter.selectedMonth,
      existing: b,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _dueDayController.dispose();
    _paymentNoteController.dispose();
    super.dispose();
  }

  String _recurrenceLabel(RecurrenceType r) => switch (r) {
        RecurrenceType.monthly => 'Monthly',
        RecurrenceType.weekly => 'Weekly',
        RecurrenceType.yearly => 'Yearly',
        RecurrenceType.custom => 'Custom',
      };

  /// Resolves the note to persist (mirrors the mobile sheet). A user-typed note
  /// wins; otherwise the auto-statement marker we hid from the field is
  /// re-applied, so editing an auto-generated statement doesn't strip its flag.
  /// On an edit, a cleared field persists as empty rather than null — `copyWith`
  /// reads null as "leave unchanged", which would silently bring the note back.
  String? _resolvePaymentNote() {
    final typed = _paymentNoteController.text.trim();
    if (typed.isNotEmpty) return typed;
    if (widget.existing?.isAutoStatement ?? false)
      return Bill.autoStatementNote;
    return widget.existing == null ? null : '';
  }

  List<FinanceCategory> get _expenseCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.expense)
      .toList();

  bool get _applyToFuture =>
      _showScopeField && _scope == RecurringScope.thisAndFuture;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final dueDay = int.parse(_dueDayController.text);
      final existing = widget.existing;
      if (existing == null) {
        final bill = Bill(
          id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
          name: _nameController.text.trim(),
          billType: _billType,
          amount: amount,
          dueDay: dueDay,
          month: widget.presenter.selectedMonth,
          categoryId: _selectedCategoryId ?? '',
          accountId: _selectedAccountId,
          paymentNote: _resolvePaymentNote(),
          isRecurring: _isRecurring,
          recurrenceType: _isRecurring ? _recurrenceType : null,
          reminderDaysBefore: _reminderOn ? _reminderDays : null,
        );
        await widget.presenter.addBill(bill, applyToFuture: _applyToFuture);
      } else {
        // Edit in place — copyWith preserves fields the form doesn't expose
        // (paid state, linked transaction).
        await widget.presenter.updateBill(
          existing.copyWith(
            name: _nameController.text.trim(),
            billType: _billType,
            amount: amount,
            dueDay: dueDay,
            categoryId: _selectedCategoryId ?? '',
            accountId: _selectedAccountId,
            paymentNote: _resolvePaymentNote(),
            isRecurring: _isRecurring,
            recurrenceType: _isRecurring ? _recurrenceType : null,
            // Now that the form owns this field, pass it explicitly on every
            // save. The sentinel copyWith used to leave it untouched, which
            // preserved a mobile-set reminder but also made switching it off
            // here impossible.
            reminderDaysBefore: _reminderOn ? _reminderDays : null,
          ),
          applyToFuture: _applyToFuture,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Previously a save failure left the dialog open with no message. (C7)
      if (mounted) AppToast.error(context, 'Could not save bill: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accounts =
        widget.presenter.accounts.where((a) => a.isActive).toList();
    final categories = _expenseCategories;

    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Bill' : 'Add Bill'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: WebInsets.md),
                DropdownButtonFormField<BillType>(
                  initialValue: _billType,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: BillType.values
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(_billTypeFormLabel(t))))
                      .toList(),
                  onChanged: (v) => setState(() => _billType = v ?? _billType),
                ),
                const SizedBox(height: WebInsets.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _amountController,
                        decoration: const InputDecoration(
                            labelText: 'Amount', prefixText: '₱ '),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          final p =
                              double.tryParse((v ?? '').replaceAll(',', ''));
                          if (p == null || p <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: WebInsets.md),
                    Expanded(
                      child: TextFormField(
                        controller: _dueDayController,
                        decoration:
                            const InputDecoration(labelText: 'Due day (1–31)'),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) =>
                            _submit(), // Enter submits (U6)
                        validator: (v) {
                          final d = int.tryParse(v ?? '');
                          if (d == null || d < 1 || d > 31) return '1–31';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                if (accounts.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    // Guard against a stored account that is no longer active —
                    // a value absent from `items` would assert. (edit case)
                    initialValue:
                        accounts.any((a) => a.id == _selectedAccountId)
                            ? _selectedAccountId
                            : null,
                    decoration: const InputDecoration(
                        labelText: 'Payment account (optional)'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('None')),
                      for (final a in accounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => setState(() => _selectedAccountId = v),
                  ),
                ],
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    initialValue:
                        categories.any((c) => c.id == _selectedCategoryId)
                            ? _selectedCategoryId
                            : null,
                    decoration:
                        const InputDecoration(labelText: 'Category (optional)'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('None')),
                      for (final c in categories)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                  ),
                ],
                const SizedBox(height: WebInsets.md),
                TextFormField(
                  controller: _paymentNoteController,
                  decoration: const InputDecoration(
                      labelText: 'Payment note (optional)'),
                  textInputAction: TextInputAction.done,
                ),
                // Recurrence — without it, a bill added here was silently
                // one-off and never came back next month, while the same bill
                // added on the phone recurred.
                const SizedBox(height: WebInsets.sm),
                SwitchListTile(
                  value: _isRecurring,
                  // Carrying an edit forward is the helpful default; carrying a
                  // *deletion* forward is not, so switching recurrence off
                  // leaves the scope opt-in (mirrors the mobile sheet).
                  onChanged: (v) => setState(() {
                    _isRecurring = v;
                    _scope = v
                        ? RecurringScope.thisAndFuture
                        : RecurringScope.thisMonthOnly;
                  }),
                  title: const Text('Recurring'),
                  subtitle: const Text('Auto-generate next month'),
                  secondary: Icon(Icons.autorenew_rounded, color: cs.primary),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_isRecurring) ...[
                  const SizedBox(height: WebInsets.sm),
                  DropdownButtonFormField<RecurrenceType>(
                    initialValue: _recurrenceType,
                    decoration: const InputDecoration(labelText: 'Recurrence'),
                    items: [
                      for (final r in RecurrenceType.values)
                        DropdownMenuItem(
                            value: r, child: Text(_recurrenceLabel(r))),
                    ],
                    onChanged: (v) =>
                        setState(() => _recurrenceType = v ?? _recurrenceType),
                  ),
                ],
                // How far this save reaches across the months already generated.
                if (_showScopeField) ...[
                  const SizedBox(height: WebInsets.sm),
                  RecurringScopeField(
                    futureMonthCount: _futureMonthCount,
                    month: widget.existing?.month ??
                        widget.presenter.selectedMonth,
                    value: _scope,
                    noun: 'amount',
                    removesFutureMonths: _dropsFutureMonths,
                    onChanged: (s) => setState(() => _scope = s),
                  ),
                ],
                // Per-bill reminder lead time. Mobile has had this since the
                // bill sheet shipped; on desktop the field existed on the model
                // but nothing could set it, so a bill created here never
                // reminded you and one created on the phone couldn't be turned
                // off here.
                const SizedBox(height: WebInsets.sm),
                SwitchListTile(
                  value: _reminderOn,
                  onChanged: (v) => setState(() => _reminderOn = v),
                  title: const Text('Remind me before due'),
                  secondary:
                      Icon(Icons.notifications_none_rounded, color: cs.primary),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_reminderOn) ...[
                  const SizedBox(height: WebInsets.xs),
                  Wrap(
                    spacing: WebInsets.sm,
                    children: [
                      for (final d in _reminderDayOptions)
                        ChoiceChip(
                          label: Text(d == 1 ? '1 day' : '$d days'),
                          selected: _reminderDays == d,
                          onSelected: (_) => setState(() => _reminderDays = d),
                        ),
                    ],
                  ),
                ],
                if (accounts.isEmpty && categories.isEmpty) ...[
                  const SizedBox(height: WebInsets.sm),
                  Text(
                    'Add an account or category in the app for richer bills.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Save' : 'Add Bill'),
        ),
      ],
    );
  }
}

String _billTypeFormLabel(BillType type) => switch (type) {
      BillType.installment => 'Installment',
      BillType.creditCard => 'Credit Card',
      BillType.subscription => 'Subscription',
      BillType.insurance => 'Insurance',
      BillType.govtContribution => 'Govt Contribution',
      BillType.utility => 'Utility',
      BillType.other => 'Other',
    };

// ─── Add/Edit-receivable dialog ───────────────────────────────────────────────

void _onAddReceivable(
    BuildContext context, BillsReceivablesPresenter presenter) {
  showDialog<void>(
    context: context,
    builder: (_) => _ReceivableDialog(presenter: presenter),
  );
}

/// Desktop add/edit-receivable form. Mirrors [_AddBillDialog]: Name, Type,
/// Amount, Expected day, destination account, and (income) Category, then calls
/// [BillsReceivablesPresenter.addReceivable] / `updateReceivable`.
class _ReceivableDialog extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final Receivable? existing;

  const _ReceivableDialog({required this.presenter, this.existing});

  @override
  State<_ReceivableDialog> createState() => _ReceivableDialogState();
}

class _ReceivableDialogState extends State<_ReceivableDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();

  late DateTime _expectedDate;
  late ReceivableType _type;
  String? _selectedAccountId;
  String? _selectedCategoryId;
  bool _isRecurring = false;
  RecurrenceType _recurrenceType = RecurrenceType.monthly;
  bool _isSubmitting = false;

  /// How far this save reaches — see [_AddBillDialog].
  RecurringScope _scope = RecurringScope.thisAndFuture;
  late final int _futureMonthCount;

  bool get _wasRecurring => widget.existing?.isRecurring ?? false;

  bool get _dropsFutureMonths => !_isRecurring && _wasRecurring;

  bool get _showScopeField =>
      (_isRecurring || _wasRecurring) && _futureMonthCount > 0;

  bool get _applyToFuture =>
      _showScopeField && _scope == RecurringScope.thisAndFuture;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _type = r?.receivableType ?? ReceivableType.salary;
    // A new receivable starts on today's date rather than in the month being
    // browsed, matching the mobile sheet.
    _expectedDate = r?.expectedDate ?? DateTime.now();
    if (r != null) {
      _nameController.text = r.name;
      _amountController.text = r.amount == r.amount.roundToDouble()
          ? r.amount.round().toString()
          : r.amount.toString();
      _selectedAccountId = r.accountId;
      _selectedCategoryId = r.categoryId.isEmpty ? null : r.categoryId;
      _isRecurring = r.isRecurring;
      _recurrenceType = r.recurrenceType ?? RecurrenceType.monthly;
    }
    _futureMonthCount = widget.presenter.futureReceivableReach(
      month: r?.month ?? widget.presenter.selectedMonth,
      existing: r,
    );
  }

  String _recurrenceLabel(RecurrenceType r) => switch (r) {
        RecurrenceType.monthly => 'Monthly',
        RecurrenceType.weekly => 'Weekly',
        RecurrenceType.yearly => 'Yearly',
        RecurrenceType.custom => 'Custom',
      };

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _incomeCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.income)
      .toList();

  Future<void> _pickExpectedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _expectedDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final existing = widget.existing;
      if (existing == null) {
        final receivable = Receivable(
          id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
          name: _nameController.text.trim(),
          receivableType: _type,
          amount: amount,
          // Day only — a stored time of day is invisible on the card yet used
          // to order same-day entries, same as the mobile sheet.
          expectedDate: DateUtils.dateOnly(_expectedDate),
          month: widget.presenter.selectedMonth,
          categoryId: _selectedCategoryId ?? '',
          accountId: _selectedAccountId,
          isRecurring: _isRecurring,
          recurrenceType: _isRecurring ? _recurrenceType : null,
        );
        await widget.presenter
            .addReceivable(receivable, applyToFuture: _applyToFuture);
      } else {
        await widget.presenter.updateReceivable(
          existing.copyWith(
            name: _nameController.text.trim(),
            receivableType: _type,
            amount: amount,
            // Day only — a stored time of day is invisible on the card yet used
            // to order same-day entries, same as the mobile sheet.
            expectedDate: DateUtils.dateOnly(_expectedDate),
            categoryId: _selectedCategoryId ?? '',
            accountId: _selectedAccountId,
            isRecurring: _isRecurring,
            recurrenceType: _isRecurring ? _recurrenceType : null,
          ),
          applyToFuture: _applyToFuture,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save receivable: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Same eligible set as the settle step, so a saved default can never be an
    // account mark-received would reject.
    final accounts = widget.presenter.depositAccountsFor(widget.existing);
    final categories = _incomeCategories;
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Receivable' : 'Add Receivable'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: WebInsets.md),
                DropdownButtonFormField<ReceivableType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: ReceivableType.values
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(_receivableTypeLabel(t))))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: WebInsets.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _amountController,
                        decoration: const InputDecoration(
                            labelText: 'Amount', prefixText: '₱ '),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          final p =
                              double.tryParse((v ?? '').replaceAll(',', ''));
                          if (p == null || p <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: WebInsets.md),
                    Expanded(
                      // A real date, like the mobile sheet picks. The day-number
                      // field this replaces was clamped into the selected month,
                      // so a receivable expected next month — the normal case
                      // for an invoice raised late in the month — could not be
                      // expressed here at all.
                      child: InputDecorator(
                        decoration:
                            const InputDecoration(labelText: 'Expected date'),
                        child: InkWell(
                          onTap: _pickExpectedDate,
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_outlined,
                                  size: 16, color: cs.onSurfaceVariant),
                              const SizedBox(width: WebInsets.sm),
                              Text(_expectedDateFmt.format(_expectedDate),
                                  style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (accounts.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    initialValue:
                        accounts.any((a) => a.id == _selectedAccountId)
                            ? _selectedAccountId
                            : null,
                    decoration: const InputDecoration(
                        labelText: 'Deposit account (optional)'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('None')),
                      for (final a in accounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => setState(() => _selectedAccountId = v),
                  ),
                ],
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    initialValue:
                        categories.any((c) => c.id == _selectedCategoryId)
                            ? _selectedCategoryId
                            : null,
                    decoration:
                        const InputDecoration(labelText: 'Category (optional)'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('None')),
                      for (final c in categories)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                  ),
                ],
                const SizedBox(height: WebInsets.sm),
                SwitchListTile(
                  value: _isRecurring,
                  // See [_AddBillDialog]: an edit carries forward by default,
                  // a deletion does not.
                  onChanged: (v) => setState(() {
                    _isRecurring = v;
                    _scope = v
                        ? RecurringScope.thisAndFuture
                        : RecurringScope.thisMonthOnly;
                  }),
                  title: const Text('Recurring'),
                  subtitle: const Text('Auto-generate next month'),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_isRecurring) ...[
                  const SizedBox(height: WebInsets.sm),
                  DropdownButtonFormField<RecurrenceType>(
                    initialValue: _recurrenceType,
                    decoration: const InputDecoration(labelText: 'Recurrence'),
                    items: RecurrenceType.values
                        .map((r) => DropdownMenuItem(
                            value: r, child: Text(_recurrenceLabel(r))))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _recurrenceType = v ?? _recurrenceType),
                  ),
                ],
                // How far this save reaches across the months already generated.
                if (_showScopeField) ...[
                  const SizedBox(height: WebInsets.sm),
                  RecurringScopeField(
                    futureMonthCount: _futureMonthCount,
                    month: widget.existing?.month ??
                        widget.presenter.selectedMonth,
                    value: _scope,
                    noun: 'amount',
                    removesFutureMonths: _dropsFutureMonths,
                    onChanged: (s) => setState(() => _scope = s),
                  ),
                ],
                if (accounts.isEmpty && categories.isEmpty) ...[
                  const SizedBox(height: WebInsets.sm),
                  Text(
                    'Add an account or income category in the app for richer receivables.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Save' : 'Add Receivable'),
        ),
      ],
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String monthLabel;
  final String subtitle;
  final VoidCallback onAddBill;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const _Header({
    required this.monthLabel,
    required this.subtitle,
    required this.onAddBill,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
    // "Bills", not "Bills & Receivables": the phone names the screen in one
    // word and lets the sections say what's in it. The month control sits on
    // the title's line, as it does on mobile.
    return WebPageHeader(
      title: 'Bills',
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WebMonthStepper(
            label: monthLabel,
            onPrev: onPrevMonth,
            onNext: onNextMonth,
          ),
          const SizedBox(width: WebInsets.sm),
          FilledButton.icon(
            onPressed: onAddBill,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Bill'),
          ),
        ],
      ),
    );
  }
}

// ─── Stat strip ───────────────────────────────────────────────────────────────

class _StatStrip extends StatelessWidget {
  final double dueTotal;
  final double paidTotal;
  final double monthTotal;
  final double receiveTotal;
  final int unpaidCount;
  final int paidCount;
  final int receivableCount;

  const _StatStrip({
    required this.dueTotal,
    required this.paidTotal,
    required this.monthTotal,
    required this.receiveTotal,
    required this.unpaidCount,
    required this.paidCount,
    required this.receivableCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tiles = <Widget>[
      WebStatTile(
        label: 'Due This Month',
        value: formatPeso(dueTotal),
        sub: '$unpaidCount unpaid',
        icon: Icons.receipt_long_outlined,
        valueColor: dueTotal > 0 ? cs.error : null,
      ),
      WebStatTile(
        label: 'Paid',
        value: formatPeso(paidTotal),
        sub: '$paidCount settled',
        icon: Icons.check_circle_outline,
        valueColor: cs.tertiary,
      ),
      WebStatTile(
        label: 'Total This Month',
        value: formatPeso(monthTotal),
        sub: '${unpaidCount + paidCount} bills',
        icon: Icons.description_outlined,
      ),
      WebStatTile(
        label: 'To Receive',
        value: formatPeso(receiveTotal),
        sub: '$receivableCount pending',
        icon: Icons.south_west,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 760 ? 4 : 2;
        const gap = WebInsets.lg;
        final tileWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles) SizedBox(width: tileWidth, child: t),
          ],
        );
      },
    );
  }
}

// ─── Upcoming card ────────────────────────────────────────────────────────────

class _UpcomingCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final List<Bill> unpaid;
  final double dueTotal;
  final Widget batchControl;
  final Widget? batchBar;
  final WebRowSelection? Function(String id) selectionOf;

  const _UpcomingCard({
    required this.presenter,
    required this.unpaid,
    required this.dueTotal,
    required this.batchControl,
    required this.batchBar,
    required this.selectionOf,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return WebCard(
      accentColor: cs.error,
      title: 'Upcoming',
      description:
          '${formatPeso(dueTotal)} across ${unpaid.length} ${unpaid.length == 1 ? 'bill' : 'bills'}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          batchControl,
          TextButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _AddBillDialog(presenter: presenter),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add bill'),
          ),
        ],
      ),
      // The batch bar lives here even when there are no unpaid bills to list:
      // paid bills are the same selection (they render in the Paid card), so
      // hiding the bar with the empty list would strand a selection made purely
      // to undo payments.
      child: unpaid.isEmpty
          ? Column(
              children: [
                const _EmptyHint('No bills due — you are all caught up.'),
                if (batchBar != null) batchBar!,
              ],
            )
          : Column(
              children: [
                for (var i = 0; i < unpaid.length; i++)
                  _BillRow(
                    presenter: presenter,
                    bill: unpaid[i],
                    showDivider: i > 0,
                    selection: selectionOf(unpaid[i].id),
                  ),
                if (batchBar != null) batchBar!,
                const SizedBox(height: WebInsets.md),
                Container(
                  padding: const EdgeInsets.only(top: WebInsets.md),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('DUE',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.7,
                          )),
                      Text(formatPeso(dueTotal),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.error,
                          )),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Paid card ──────────────────────────────────────────────────────────────

class _PaidCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final List<Bill> paid;
  final double paidTotal;

  /// Paid bills belong to the *bills* selection even though they render in
  /// their own card — selecting them here is how a batch undo is reached. The
  /// Select control lives on the Upcoming card, so this card has none of its
  /// own.
  final WebRowSelection? Function(String id) selectionOf;

  const _PaidCard({
    required this.presenter,
    required this.paid,
    required this.paidTotal,
    required this.selectionOf,
  });

  @override
  Widget build(BuildContext context) {
    return WebCard(
      title: 'Paid',
      description: '${formatPeso(paidTotal)} settled',
      child: Column(
        children: [
          for (var i = 0; i < paid.length; i++)
            _BillRow(
              presenter: presenter,
              bill: paid[i],
              showDivider: i > 0,
              selection: selectionOf(paid[i].id),
            ),
        ],
      ),
    );
  }
}

// ─── Bill row ─────────────────────────────────────────────────────────────────

class _BillRow extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final Bill bill;
  final bool showDivider;

  /// Non-null while this row's section is selecting: the settle checkbox
  /// becomes a selection box and the per-row menu is hidden, so a click during
  /// a batch can only ever mean "pick this row".
  final WebRowSelection? selection;

  const _BillRow({
    required this.presenter,
    required this.bill,
    required this.showDivider,
    this.selection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final paid = bill.isPaid;
    final accountName = _accountName(bill.accountId);

    final nameStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: paid ? cs.onSurfaceVariant : cs.onSurface,
      decoration: paid ? TextDecoration.lineThrough : null,
    );
    final amountStyle = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: paid ? cs.onSurfaceVariant : cs.onSurface,
    );

    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                top:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: WebInsets.md),
      child: Row(
        children: [
          if (selection != null)
            WebRowSelectBox(
              selected: selection!.selected,
              onTap: selection!.onToggle,
            )
          else
            _PaidCheckbox(
              checked: paid,
              tooltip: paid ? 'Mark unpaid' : 'Mark paid',
              onTap: paid ? () => _undoPaid(context) : () => _markPaid(context),
            ),
          const SizedBox(width: WebInsets.md),
          // The colour-tinted category badge is what carries a row's identity
          // on every mobile Treasury list; web rows were anonymous text. Same
          // widget, same palette slot, so a category looks the same on both.
          _billBadge(context),
          const SizedBox(width: WebInsets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(bill.name,
                          style: nameStyle, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: WebInsets.sm),
                    WebBadge(
                      _billTypeLabel(bill.billType),
                      tone: _billTypeTone(bill.billType),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Due ${_ordinal(bill.dueDay)}${accountName != null ? ' · $accountName' : ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: WebInsets.md),
          Text(formatPeso(bill.amount), style: amountStyle),
          if (selection == null)
            _RowActions(
              onEdit: () => _edit(context),
              onDelete: () => _delete(context),
              onUndo: paid ? () => _undoPaid(context) : null,
              undoLabel: 'Mark unpaid',
            ),
        ],
      ),
    );
  }

  /// Reverses a payment recorded by mistake — the bill returns to Pending and,
  /// unless the user keeps it, the transaction goes with it so the funding
  /// account's balance is restored.
  Future<void> _undoPaid(BuildContext context) async {
    final choice = await showUndoSettlementDialog(
      context: context,
      title: 'Undo payment?',
      name: bill.name,
      entryLabel: 'bill',
      hasLedgerEntry: presenter.billHasLedgerEntry(bill),
      ledgerEffect: '${formatPeso(bill.paidAmount ?? bill.amount)} goes back '
          'into ${_accountName(bill.accountId) ?? 'your account'}.',
    );
    if (choice == null) return;
    await presenter.markBillUnpaid(
      bill.id,
      removeTransaction: choice.removeTransaction,
    );
    if (!context.mounted) return;
    AppToast.show(context, 'Marked "${bill.name}" unpaid.');
  }

  void _edit(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _AddBillDialog(presenter: presenter, existing: bill),
    );
  }

  Future<void> _delete(BuildContext context) async {
    // A recurring bill is asked about by series, so the months generated ahead
    // aren't silently orphaned when this one goes.
    final scope = await confirmRecurringDelete(
      context: context,
      title: 'Delete bill?',
      name: bill.name,
      futureMonthCount: presenter.futureSeriesBills(bill).length,
      isRecurring: bill.isRecurring,
    );
    if (scope == null) return;
    await presenter.deleteBill(
      bill.id,
      applyToFuture: scope == RecurringScope.thisAndFuture,
    );
    if (!context.mounted) return;
    AppToast.show(context, 'Deleted "${bill.name}".');
  }

  String? _accountName(String? accountId) {
    if (accountId == null) return null;
    final match = presenter.accounts.where((a) => a.id == accountId).toList();
    return match.isEmpty ? null : match.first.name;
  }

  Future<void> _markPaid(BuildContext context) =>
      _markBillPaidFlow(context, presenter, bill);

  /// The row's leading category badge, resolved exactly as the mobile Bills tab
  /// resolves it: the category's palette slot for the tint (so the same
  /// category is the same colour on both surfaces) and the bills accent as the
  /// fallback for an uncategorised bill.
  Widget _billBadge(BuildContext context) {
    final category = presenter.categoryById(bill.categoryId);
    final color = category != null
        ? resolveSliceColor(
            category.colorHex,
            presenter.categoryPaletteSlot(bill.categoryId),
            brightness: Theme.of(context).brightness,
          )
        : context.appColors.bills;
    return CategoryBadge(
      iconKey: category?.icon,
      name: category?.name,
      type: category?.type ?? CategoryType.expense,
      color: color,
      size: 34,
      iconSize: 17,
    );
  }
}

/// The web mark-a-bill-paid flow: confirm, pick the funding account, then hand
/// off to [BillsReceivablesPresenter.markBillPaid]. Top-level because two
/// surfaces drive it — the bill row's checkbox and the due-soon hero's
/// "Mark paid" button — and a second copy would be a second set of rules for
/// which accounts may fund a statement.
Future<void> _markBillPaidFlow(
  BuildContext context,
  BillsReceivablesPresenter presenter,
  Bill bill,
) async {
  // Eligible funding accounts. payerAccountsFor excludes the liability itself
  // for a credit-card / credit-line / BNPL statement bill (you can't pay a
  // statement from the account it belongs to — markBillPaid throws for that),
  // which the old code hit by defaulting to bill.accountId. Restrict to
  // active liquid accounts as the fundable set.
  final payers = presenter
      .payerAccountsFor(bill)
      .where((a) => a.isActive && a.isLiquid)
      .toList();

  // Marking paid moves real money out of an account and can't be undone in
  // one click — confirm, let the user pick which account is debited, and
  // default to the account set on the bill when it's a valid payer, falling
  // back to the first eligible one. (Plan 052 U1/U2) Preferring bill.accountId
  // is safe here because payerAccountsFor already drops the liability itself
  // for credit-card/BNPL statement bills, so it can never re-select it. The
  // "already in ledger" toggle skips recording entirely for manual expenses.
  String? preferredAccountId = payers.isNotEmpty ? payers.first.id : null;
  if (bill.accountId != null && payers.any((a) => a.id == bill.accountId)) {
    preferredAccountId = bill.accountId;
  }

  // The shared settle dialog carries the amount and date the ad-hoc dialog
  // here never had, so a partial payment, an overpayment, or last month's
  // reconciliation is expressible on desktop the same way it is on mobile.
  // Because this flow is the one both surfaces call, the due-soon hero's
  // "Mark paid" button gets them too rather than staying fixed-amount.
  final result = await showWebSettleDialog(
    context,
    title: 'Mark "${bill.name}" paid',
    summary: 'Records the payment and debits the funding account. '
        'Adjust the amount for a partial payment or an overpayment.',
    confirmLabel: 'Mark paid',
    initialAmount: bill.amount,
    amountLabel: 'Amount paid',
    dateLabel: 'Payment date',
    accounts: payers,
    accountLabel: 'Pay from',
    initialAccountId: preferredAccountId,
    requiresAccount: true,
    showLedgerToggle: true,
    emptyAccountsMessage: 'Add a funding account before marking paid.',
    onSubmit: (r) => presenter.markBillPaid(
      bill.id,
      paidAmount: r.amount,
      accountId: r.accountId,
      paidDate: r.date,
      recordInLedger: r.recordInLedger,
    ),
  );
  if (result == null || !context.mounted) return;

  final payerName =
      _lookupAccountName(presenter, result.accountId) ?? 'your account';
  AppToast.success(
    context,
    !result.recordInLedger
        ? 'Marked "${bill.name}" paid.'
        : 'Paid ${formatPeso(result.amount)} for "${bill.name}" from $payerName.',
  );
}

String? _lookupAccountName(
    BillsReceivablesPresenter presenter, String? accountId) {
  final match = presenter.accounts.where((a) => a.id == accountId).toList();
  return match.isEmpty ? null : match.first.name;
}

// ─── Receivables card ─────────────────────────────────────────────────────────

class _ReceivablesCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final List<Receivable> receivables;
  final double pendingTotal;
  final Widget batchControl;
  final Widget? batchBar;
  final WebRowSelection? Function(String id) selectionOf;

  const _ReceivablesCard({
    required this.presenter,
    required this.receivables,
    required this.pendingTotal,
    required this.batchControl,
    required this.batchBar,
    required this.selectionOf,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pending = receivables.where((r) => !r.isReceived).toList();
    // Still-pending receivables float to the top; received ones sink below.
    final ordered = [...pending, ...receivables.where((r) => r.isReceived)];

    return WebCard(
      accentColor: Theme.of(context).colorScheme.tertiary,
      title: 'Receivables',
      description: 'Money owed to you',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          batchControl,
          OutlinedButton.icon(
            onPressed: () => _onAddReceivable(context, presenter),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Receivable'),
          ),
        ],
      ),
      child: receivables.isEmpty
          ? const _EmptyHint('Nothing owed to you this month.')
          : Column(
              children: [
                for (var i = 0; i < ordered.length; i++)
                  _ReceivableRow(
                    presenter: presenter,
                    receivable: ordered[i],
                    showDivider: i > 0,
                    selection: selectionOf(ordered[i].id),
                  ),
                if (batchBar != null) batchBar!,
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  Container(
                    padding: const EdgeInsets.only(top: WebInsets.md),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('PENDING',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.7,
                            )),
                        Text(formatPeso(pendingTotal),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.tertiary,
                            )),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ReceivableRow extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final Receivable receivable;
  final bool showDivider;
  final WebRowSelection? selection;

  const _ReceivableRow({
    required this.presenter,
    required this.receivable,
    required this.showDivider,
    this.selection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final received = receivable.isReceived;

    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                top:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: WebInsets.md),
      child: Row(
        children: [
          if (selection != null)
            WebRowSelectBox(
              selected: selection!.selected,
              onTap: selection!.onToggle,
            )
          else
            _PaidCheckbox(
              checked: received,
              tooltip: received ? 'Mark not received' : 'Mark received',
              onTap: received
                  ? () => _undoReceived(context)
                  : () => _markReceived(context),
            ),
          const SizedBox(width: WebInsets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  receivable.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: received ? cs.onSurfaceVariant : cs.onSurface,
                    decoration: received ? TextDecoration.lineThrough : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${receivable.expectedDate != null ? 'Due ${_ordinal(receivable.expectedDate!.day)}' : 'ASAP'} · ${_receivableTypeLabel(receivable.receivableType)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: WebInsets.md),
          Text(
            formatPeso(receivable.amount),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: received ? cs.onSurfaceVariant : cs.tertiary,
            ),
          ),
          if (selection == null)
            _RowActions(
              onEdit: () => _edit(context),
              onDelete: () => _delete(context),
              onUndo: received ? () => _undoReceived(context) : null,
              undoLabel: 'Mark not received',
            ),
        ],
      ),
    );
  }

  /// Reverses a receipt recorded by mistake — the entry returns to still-owed
  /// and, unless the user keeps it, the deposit is taken back out of the ledger
  /// so the account balance is restored.
  Future<void> _undoReceived(BuildContext context) async {
    final choice = await showUndoSettlementDialog(
      context: context,
      title: 'Undo receipt?',
      name: receivable.name,
      entryLabel: 'receivable',
      hasLedgerEntry: presenter.receivableHasLedgerEntry(receivable),
      ledgerEffect:
          '${formatPeso(receivable.receivedAmount ?? receivable.amount)} is '
          'taken back out of the account it was deposited into.',
    );
    if (choice == null) return;
    await presenter.markReceivableUnreceived(
      receivable.id,
      removeTransaction: choice.removeTransaction,
    );
    if (!context.mounted) return;
    AppToast.show(context, 'Marked "${receivable.name}" not received.');
  }

  void _edit(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _ReceivableDialog(presenter: presenter, existing: receivable),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final scope = await confirmRecurringDelete(
      context: context,
      title: 'Delete receivable?',
      name: receivable.name,
      futureMonthCount: presenter.futureSeriesReceivables(receivable).length,
      isRecurring: receivable.isRecurring,
    );
    if (scope == null) return;
    await presenter.deleteReceivable(
      receivable.id,
      applyToFuture: scope == RecurringScope.thisAndFuture,
    );
    if (!context.mounted) return;
    AppToast.show(context, 'Deleted "${receivable.name}".');
  }

  Future<void> _markReceived(BuildContext context) async {
    // Mirrors the bill mark-paid flow as an inflow, including letting the user
    // redirect the money at settle time — the destination used to be computed
    // silently and shown as read-only prose, so a deposit that didn't go to the
    // default account could not be recorded where it actually went.
    final destinations = presenter.depositAccountsFor(receivable);

    // Same shared settle dialog as bills, as an inflow: a client who paid only
    // part of an invoice, or paid it three weeks ago, is now recordable here
    // instead of only on the phone.
    final result = await showWebSettleDialog(
      context,
      title: 'Mark "${receivable.name}" received',
      summary: 'Records the deposit and credits the destination account. '
          'Adjust the amount if only part of it came in.',
      confirmLabel: 'Mark received',
      initialAmount: receivable.amount,
      amountLabel: 'Amount received',
      dateLabel: 'Date received',
      accounts: destinations,
      accountLabel: 'Deposit to',
      initialAccountId: presenter.preferredDepositAccountId(receivable),
      requiresAccount: true,
      showLedgerToggle: true,
      emptyAccountsMessage: 'Add an account before marking received.',
      onSubmit: (r) => presenter.markReceivableReceived(
        receivable.id,
        receivedAmount: r.amount,
        accountId: r.accountId,
        receivedDate: r.date,
        recordInLedger: r.recordInLedger,
      ),
    );
    if (result == null || !context.mounted) return;

    final accountName =
        presenter.accountName(result.accountId) ?? 'your account';
    AppToast.success(
      context,
      !result.recordInLedger
          ? 'Marked "${receivable.name}" received.'
          : 'Received ${formatPeso(result.amount)} for "${receivable.name}" into $accountName.',
    );
  }
}

// ─── Budgeted expenses (set-asides) ───────────────────────────────────────────

void _onAddBudgetedExpense(
    BuildContext context, BillsReceivablesPresenter presenter) {
  showDialog<void>(
    context: context,
    builder: (_) => _BudgetedExpenseDialog(presenter: presenter),
  );
}

/// Money set aside that isn't a bill or a budget category — savings/sinking-fund
/// contributions and one-off plans (gifts, outings). Marking one "funded" posts
/// an outflow that leaves your liquid cash, mirroring the mobile flow.
class _BudgetedExpensesCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final List<BudgetedExpense> expenses;
  final Widget batchControl;
  final Widget? batchBar;
  final WebRowSelection? Function(String id) selectionOf;

  const _BudgetedExpensesCard({
    required this.presenter,
    required this.expenses,
    required this.batchControl,
    required this.batchBar,
    required this.selectionOf,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pending = expenses.where((e) => !e.isPaid).toList();
    final pendingTotal = pending.fold(0.0, (sum, e) => sum + e.allocatedAmount);
    // Unfunded set-asides float to the top; funded ones sink below. Each group
    // keeps its incoming order (stable partition).
    final ordered = [...pending, ...expenses.where((e) => e.isPaid)];

    return WebCard(
      accentColor: cs.secondary,
      title: 'Budgeted Set-Asides',
      description: 'Savings, sinking funds & one-off plans',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          batchControl,
          OutlinedButton.icon(
            onPressed: () => _onAddBudgetedExpense(context, presenter),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Set-Aside'),
          ),
        ],
      ),
      child: expenses.isEmpty
          ? const _EmptyHint('No set-asides budgeted this month.')
          : Column(
              children: [
                for (var i = 0; i < ordered.length; i++)
                  _BudgetedExpenseRow(
                    presenter: presenter,
                    expense: ordered[i],
                    showDivider: i > 0,
                    selection: selectionOf(ordered[i].id),
                  ),
                if (batchBar != null) batchBar!,
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  Container(
                    padding: const EdgeInsets.only(top: WebInsets.md),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TO SET ASIDE',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.7,
                            )),
                        Text(formatPeso(pendingTotal),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.secondary,
                            )),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

// ─── By-account funding breakdown ─────────────────────────────────────────────

/// Summarises how much cash still needs to be in each funding account to cover
/// the unpaid bills + unfunded set-asides for the month — the "fund Maya with
/// ₱X so I can pay what's due" view. Reads the pre-aggregated rows from
/// [BillsReceivablesPresenter.fundingBreakdown]; no math happens here. (Rule 1)
class _ByAccountCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final List<
      ({
        FinancialAccount? account,
        double billsDue,
        double setAsides,
        double total,
        int count,
      })> rows;

  const _ByAccountCard({required this.presenter, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final grandTotal = rows.fold(0.0, (sum, r) => sum + r.total);

    return WebCard(
      accentColor: cs.primary,
      title: 'By Account',
      description: 'How much to move into each account to cover what\'s due',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++)
            _ByAccountRow(row: rows[i], showDivider: i > 0),
          const SizedBox(height: WebInsets.md),
          Container(
            padding: const EdgeInsets.only(top: WebInsets.md),
            decoration: BoxDecoration(
              border: Border(
                top:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TOTAL TO MOVE',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.7,
                    )),
                Text(formatPeso(grandTotal),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ByAccountRow extends StatelessWidget {
  final ({
    FinancialAccount? account,
    double billsDue,
    double setAsides,
    double total,
    int count,
  }) row;
  final bool showDivider;

  const _ByAccountRow({required this.row, required this.showDivider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final unassigned = row.account == null;
    final name = row.account?.name ?? 'Unassigned';
    final detail = [
      '${row.count} ${row.count == 1 ? 'item' : 'items'}',
      if (row.billsDue > 0) '${formatPeso(row.billsDue)} bills',
      if (row.setAsides > 0) '${formatPeso(row.setAsides)} set-asides',
    ].join(' · ');

    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                top:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: WebInsets.md),
      child: Row(
        children: [
          Icon(
            unassigned
                ? Icons.help_outline_rounded
                : Icons.account_balance_wallet_outlined,
            size: 18,
            color: unassigned ? cs.onSurfaceVariant : cs.primary,
          ),
          const SizedBox(width: WebInsets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  unassigned ? '$detail · no account set' : detail,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: WebInsets.md),
          Text(formatPeso(row.total),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: unassigned ? cs.onSurface : cs.primary,
              )),
        ],
      ),
    );
  }
}

class _BudgetedExpenseRow extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final BudgetedExpense expense;
  final bool showDivider;
  final WebRowSelection? selection;

  const _BudgetedExpenseRow({
    required this.presenter,
    required this.expense,
    required this.showDivider,
    this.selection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final funded = expense.isPaid;
    final accountName = presenter.accountName(expense.accountId);
    final subtitle = [
      expense.budgetedType.label,
      if (expense.note != null && expense.note!.trim().isNotEmpty)
        expense.note!.trim(),
      if (accountName != null) accountName,
    ].join(' · ');

    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                top:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: WebInsets.md),
      child: Row(
        children: [
          if (selection != null)
            WebRowSelectBox(
              selected: selection!.selected,
              onTap: selection!.onToggle,
            )
          else
            _PaidCheckbox(
              checked: funded,
              tooltip: funded ? 'Mark unfunded' : 'Mark funded',
              onTap: funded
                  ? () => _undoFunded(context)
                  : () => _markFunded(context),
            ),
          const SizedBox(width: WebInsets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  expense.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: funded ? cs.onSurfaceVariant : cs.onSurface,
                    decoration: funded ? TextDecoration.lineThrough : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: WebInsets.md),
          Text(
            formatPeso(expense.allocatedAmount),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: funded ? cs.onSurfaceVariant : cs.secondary,
            ),
          ),
          if (selection == null)
            _RowActions(
              onEdit: () => _edit(context),
              onDelete: () => _delete(context),
              onUndo: funded ? () => _undoFunded(context) : null,
              undoLabel: 'Mark unfunded',
            ),
        ],
      ),
    );
  }

  /// Reverses a funding recorded by mistake — the set-aside returns to unfunded
  /// and, unless the user keeps it, the outflow (or both legs of the transfer)
  /// is removed so the accounts it moved money between are restored.
  Future<void> _undoFunded(BuildContext context) async {
    final choice = await showUndoSettlementDialog(
      context: context,
      title: 'Undo funding?',
      name: expense.name,
      entryLabel: 'set-aside',
      hasLedgerEntry: presenter.expenseHasLedgerEntry(expense),
      ledgerEffect: '${formatPeso(expense.spentAmount)} is moved back to the '
          'account it was funded from.',
    );
    if (choice == null) return;
    await presenter.markExpenseUnpaid(
      expense.id,
      removeTransaction: choice.removeTransaction,
    );
    if (!context.mounted) return;
    AppToast.show(context, 'Marked "${expense.name}" unfunded.');
  }

  void _edit(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _BudgetedExpenseDialog(presenter: presenter, existing: expense),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final scope = await confirmRecurringDelete(
      context: context,
      title: 'Delete set-aside?',
      name: expense.name,
      futureMonthCount: presenter.futureSeriesExpenses(expense).length,
      isRecurring: expense.isRecurring,
    );
    if (scope == null) return;
    await presenter.deleteBudgetedExpense(
      expense.id,
      applyToFuture: scope == RecurringScope.thisAndFuture,
    );
    if (!context.mounted) return;
    AppToast.show(context, 'Deleted "${expense.name}".');
  }

  Future<void> _markFunded(BuildContext context) async {
    // Setting money aside is a transfer between your own accounts: it leaves the
    // funding source and lands in a savings/goal destination. The dialog lets you
    // pick both (plus a "spend instead" option for one-off plans), mirroring the
    // mobile flow.
    final payers = presenter.setAsideFundingAccounts;
    if (payers.isEmpty) {
      AppToast.error(context, 'Add an account before funding.');
      return;
    }

    // Destinations you can park money in — asset accounts, savings/goals first.
    final destinations = presenter.setAsideDestinationAccounts;

    // Source defaults to the assigned account (if still valid), else first liquid.
    String? fromId = payers.any((a) => a.id == expense.accountId)
        ? expense.accountId
        : payers.first.id;
    // Destination comes from the set-aside itself ("₱5k from BPI to Maya").
    // With none on file the field starts empty and Fund waits for an answer,
    // rather than auto-picking a savings account the user never named.
    String? toId = presenter.preferredSetAsideDestinationId(expense,
        fromAccountId: fromId);
    // Funding a sinking fund is rarely all-or-nothing — you put in what you can
    // this month. The shared settle dialog supplies the editable amount and the
    // date this flow never had; the destination picker rides along as its
    // optional second dropdown, keeping "spend it" a deliberate choice.
    final result = await showWebSettleDialog(
      context,
      title: 'Fund "${expense.name}"',
      summary: 'Moves money from one account into another. Setting money aside '
          'is recorded as a transfer, not spending. Adjust the amount to fund '
          'part of it.',
      confirmLabel: 'Fund',
      initialAmount: expense.allocatedAmount,
      amountLabel: 'Amount to set aside',
      dateLabel: 'Date',
      accounts: payers,
      accountLabel: 'Fund from',
      initialAccountId: fromId,
      requiresAccount: true,
      destination: WebSettleDestination(
        options: destinations,
        label: 'Set aside into',
        initialId: toId,
        initiallyChosen: toId != null,
      ),
      onSubmit: (r) => presenter.markExpensePaid(
        expense.id,
        paidAmount: r.amount,
        accountId: r.accountId!,
        toAccountId: r.destinationId,
        paidDate: r.date,
      ),
    );
    if (result == null || !context.mounted) return;

    final fromName = presenter.accountName(result.accountId) ?? 'your account';
    final toName = presenter.accountName(result.destinationId);
    AppToast.success(
      context,
      toName != null
          ? 'Transferred ${formatPeso(result.amount)} for "${expense.name}" from $fromName to $toName.'
          : 'Set aside ${formatPeso(result.amount)} for "${expense.name}" from $fromName.',
    );
  }
}

/// Desktop add/edit form for a budgeted set-aside. Mirrors the mobile
/// [AddBudgetedExpenseSheet]: Name, Type, Amount, optional Category, and a
/// free-text Note (e.g. "Maya Savings"). Calls
/// [BillsReceivablesPresenter.addBudgetedExpense] / `updateBudgetedExpense`.
class _BudgetedExpenseDialog extends StatefulWidget {
  final BillsReceivablesPresenter presenter;
  final BudgetedExpense? existing;

  const _BudgetedExpenseDialog({required this.presenter, this.existing});

  @override
  State<_BudgetedExpenseDialog> createState() => _BudgetedExpenseDialogState();
}

class _BudgetedExpenseDialogState extends State<_BudgetedExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  late SetAsideType _type;
  String? _selectedCategoryId;
  String? _selectedAccountId;
  String? _selectedDestinationId;
  bool _isRecurring = false;
  RecurrenceType _recurrenceType = RecurrenceType.monthly;
  bool _isSubmitting = false;

  /// How far this save reaches — see [_AddBillDialog].
  RecurringScope _scope = RecurringScope.thisAndFuture;
  late final int _futureMonthCount;

  bool get _wasRecurring => widget.existing?.isRecurring ?? false;

  bool get _dropsFutureMonths => !_isRecurring && _wasRecurring;

  bool get _showScopeField =>
      (_isRecurring || _wasRecurring) && _futureMonthCount > 0;

  bool get _applyToFuture =>
      _showScopeField && _scope == RecurringScope.thisAndFuture;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.budgetedType ?? SetAsideType.other;
    if (e != null) {
      _nameController.text = e.name;
      _amountController.text =
          e.allocatedAmount == e.allocatedAmount.roundToDouble()
              ? e.allocatedAmount.round().toString()
              : e.allocatedAmount.toString();
      _noteController.text = e.note ?? '';
      _selectedCategoryId = e.categoryId.isEmpty ? null : e.categoryId;
      _selectedAccountId = e.accountId;
      _selectedDestinationId = e.destinationAccountId;
      _isRecurring = e.isRecurring;
      _recurrenceType = e.recurrenceType ?? RecurrenceType.monthly;
    }
    _futureMonthCount = widget.presenter.futureExpenseReach(
      month: e?.month ?? widget.presenter.selectedMonth,
      existing: e,
    );
  }

  String _recurrenceLabel(RecurrenceType r) => switch (r) {
        RecurrenceType.monthly => 'Monthly',
        RecurrenceType.weekly => 'Weekly',
        RecurrenceType.yearly => 'Yearly',
        RecurrenceType.custom => 'Custom',
      };

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<FinanceCategory> get _expenseCategories => widget.presenter.categories
      .where((c) => c.type == CategoryType.expense)
      .toList();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final note = _noteController.text.trim();
      final existing = widget.existing;
      if (existing == null) {
        await widget.presenter.addBudgetedExpense(
          BudgetedExpense(
            id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
            name: _nameController.text.trim(),
            budgetedType: _type,
            month: widget.presenter.selectedMonth,
            allocatedAmount: amount,
            categoryId: _selectedCategoryId ?? '',
            note: note.isEmpty ? null : note,
            accountId: _selectedAccountId,
            destinationAccountId: _selectedDestinationId,
            isRecurring: _isRecurring,
            recurrenceType: _isRecurring ? _recurrenceType : null,
          ),
          applyToFuture: _applyToFuture,
        );
      } else {
        await widget.presenter.updateBudgetedExpense(
          existing.copyWith(
            name: _nameController.text.trim(),
            budgetedType: _type,
            allocatedAmount: amount,
            categoryId: _selectedCategoryId ?? '',
            note: note.isEmpty ? null : note,
            accountId: _selectedAccountId,
            destinationAccountId: _selectedDestinationId,
            isRecurring: _isRecurring,
            recurrenceType: _isRecurring ? _recurrenceType : null,
          ),
          applyToFuture: _applyToFuture,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save set-aside: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final categories = _expenseCategories;
    // Set-asides are funded out of spendable cash, so only offer liquid
    // accounts — funding debits one of these (mirrors the mark-funded flow).
    final liquidAccounts = widget.presenter.setAsideFundingAccounts;
    final destinationAccounts = widget.presenter.setAsideDestinationAccounts
        .where((a) => a.id != _selectedAccountId)
        .toList();
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Set-Aside' : 'Add Set-Aside'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Name (e.g. Travel Fund, Tanel Birthday)'),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: WebInsets.md),
                DropdownButtonFormField<SetAsideType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: SetAsideType.values
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: WebInsets.md),
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                      labelText: 'Amount', prefixText: '₱ '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final p = double.tryParse((v ?? '').replaceAll(',', ''));
                    if (p == null || p <= 0) return 'Must be > 0';
                    return null;
                  },
                ),
                const SizedBox(height: WebInsets.md),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                      labelText: 'Note (optional, e.g. Maya Savings)'),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (liquidAccounts.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    initialValue:
                        liquidAccounts.any((a) => a.id == _selectedAccountId)
                            ? _selectedAccountId
                            : null,
                    decoration: const InputDecoration(
                        labelText: 'Fund from account (optional)'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('None')),
                      for (final a in liquidAccounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => setState(() {
                      _selectedAccountId = v;
                      // The source can't also be the destination.
                      if (_selectedDestinationId == v) {
                        _selectedDestinationId = null;
                      }
                    }),
                  ),
                ],
                if (destinationAccounts.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    initialValue: destinationAccounts
                            .any((a) => a.id == _selectedDestinationId)
                        ? _selectedDestinationId
                        : null,
                    decoration: const InputDecoration(
                        labelText: 'Set aside into (optional)'),
                    items: [
                      // Naming it here decides "₱5,000 from BPI to Maya" once;
                      // leaving it blank means the funding dialog asks.
                      const DropdownMenuItem<String>(
                          value: null, child: Text('Decide when funding')),
                      for (final a in destinationAccounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) =>
                        setState(() => _selectedDestinationId = v),
                  ),
                ],
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: WebInsets.md),
                  DropdownButtonFormField<String>(
                    initialValue:
                        categories.any((c) => c.id == _selectedCategoryId)
                            ? _selectedCategoryId
                            : null,
                    decoration:
                        const InputDecoration(labelText: 'Category (optional)'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('None')),
                      for (final c in categories)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                  ),
                ],
                const SizedBox(height: WebInsets.sm),
                SwitchListTile(
                  value: _isRecurring,
                  // See [_AddBillDialog]: an edit carries forward by default,
                  // a deletion does not.
                  onChanged: (v) => setState(() {
                    _isRecurring = v;
                    _scope = v
                        ? RecurringScope.thisAndFuture
                        : RecurringScope.thisMonthOnly;
                  }),
                  title: const Text('Recurring'),
                  subtitle: const Text('Auto-generate next month'),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_isRecurring) ...[
                  const SizedBox(height: WebInsets.sm),
                  DropdownButtonFormField<RecurrenceType>(
                    initialValue: _recurrenceType,
                    decoration: const InputDecoration(labelText: 'Recurrence'),
                    items: RecurrenceType.values
                        .map((r) => DropdownMenuItem(
                            value: r, child: Text(_recurrenceLabel(r))))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _recurrenceType = v ?? _recurrenceType),
                  ),
                ],
                // How far this save reaches across the months already generated.
                if (_showScopeField) ...[
                  const SizedBox(height: WebInsets.sm),
                  RecurringScopeField(
                    futureMonthCount: _futureMonthCount,
                    month: widget.existing?.month ??
                        widget.presenter.selectedMonth,
                    value: _scope,
                    noun: 'allocation',
                    removesFutureMonths: _dropsFutureMonths,
                    onChanged: (s) => setState(() => _scope = s),
                  ),
                ],
                const SizedBox(height: WebInsets.md),
                Text(
                  'Funding a set-aside later debits a liquid account — the money '
                  'leaves your spendable cash.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Save' : 'Add Set-Aside'),
        ),
      ],
    );
  }
}

// ─── Installments card ────────────────────────────────────────────────────────

void _onAddInstallment(BuildContext context, InstallmentPresenter presenter) {
  showDialog<void>(
    context: context,
    builder: (_) => _InstallmentDialog(presenter: presenter),
  );
}

/// A purchase split into equal monthly payments (0% card plans, BNPL). Mirrors
/// the mobile `_InstallmentsSection`: lists the plans with a payment due this
/// month, shows the monthly cash load, and offers add / edit / delete plus
/// mark-paid (and undo) wired to [InstallmentPresenter].
class _InstallmentsCard extends StatelessWidget {
  final InstallmentPresenter presenter;
  final Widget batchControl;
  final Widget? batchBar;
  final WebRowSelection? Function(String id) selectionOf;

  const _InstallmentsCard({
    required this.presenter,
    required this.batchControl,
    required this.batchBar,
    required this.selectionOf,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final due = presenter.dueThisMonth;
    final load = presenter.monthlyInstallmentLoad;
    final paidTotal = presenter.totalPaidThisMonth;

    return WebCard(
      accentColor: cs.secondary,
      title: 'Installments',
      description: due.isEmpty
          ? 'No payments due this month'
          : '${formatPeso(load)} due across ${due.length} ${due.length == 1 ? 'plan' : 'plans'}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          batchControl,
          OutlinedButton.icon(
            onPressed: () => _onAddInstallment(context, presenter),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Installment'),
          ),
        ],
      ),
      child: due.isEmpty
          ? const _EmptyHint('No installment payments due this month.')
          : Column(
              children: [
                for (var i = 0; i < due.length; i++)
                  _InstallmentRow(
                    presenter: presenter,
                    installment: due[i],
                    showDivider: i > 0,
                    selection: selectionOf(due[i].id),
                  ),
                if (batchBar != null) batchBar!,
                const SizedBox(height: WebInsets.md),
                Container(
                  padding: const EdgeInsets.only(top: WebInsets.md),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('MONTHLY LOAD',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.7,
                          )),
                      Text('${formatPeso(paidTotal)} / ${formatPeso(load)}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.secondary,
                          )),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _InstallmentRow extends StatelessWidget {
  final InstallmentPresenter presenter;
  final Installment installment;
  final bool showDivider;
  final WebRowSelection? selection;

  const _InstallmentRow({
    required this.presenter,
    required this.installment,
    required this.showDivider,
    this.selection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final paid = presenter.isPaidForMonth(installment.id);
    final count = presenter.paidCount(installment.id);
    final remainingAmt = presenter.remainingAmount(installment.id);
    final progress = presenter.paymentProgress(installment.id);
    final accountName = presenter.accountName(installment.accountId);

    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                top:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: WebInsets.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selection != null)
            WebRowSelectBox(
              selected: selection!.selected,
              onTap: selection!.onToggle,
            )
          else
            _PaidCheckbox(
              checked: paid,
              tooltip: paid ? 'Mark unpaid this month' : 'Mark paid',
              onTap: paid ? () => _undoPaid(context) : () => _markPaid(context),
            ),
          const SizedBox(width: WebInsets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        installment.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: paid ? cs.onSurfaceVariant : cs.onSurface,
                          decoration: paid ? TextDecoration.lineThrough : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: WebInsets.sm),
                    WebBadge(
                      '$count/${installment.totalMonths}',
                      tone: WebBadgeTone.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: cs.secondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatPeso(remainingAmt)} left${accountName != null ? ' · $accountName' : ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: WebInsets.md),
          Text(
            '${formatPeso(installment.monthlyAmount)}/mo',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: paid ? cs.onSurfaceVariant : cs.onSurface,
            ),
          ),
          if (selection == null)
            _RowActions(
              onEdit: () => _edit(context),
              onDelete: () => _delete(context),
              onUndo: paid ? () => _undoPaid(context) : null,
              undoLabel: 'Mark unpaid this month',
            ),
        ],
      ),
    );
  }

  /// Reverses this month's payment. An installment has no paid flag of its own
  /// — the transaction IS the record — so undoing always removes it; the dialog
  /// confirms rather than offering a keep-the-transaction choice. It used to
  /// fire straight off the checkbox with no confirmation at all.
  Future<void> _undoPaid(BuildContext context) async {
    final choice = await showUndoSettlementDialog(
      context: context,
      title: 'Undo payment?',
      name: installment.name,
      entryLabel: 'installment payment',
      hasLedgerEntry: false,
      ledgerEffect: "This month's payment transaction is removed and "
          '${presenter.accountName(installment.accountId) ?? 'the account'} '
          'is credited back.',
    );
    if (choice == null) return;
    await presenter.markUnpaid(installment.id);
    if (!context.mounted) return;
    AppToast.show(context, 'Marked "${installment.name}" unpaid this month.');
  }

  void _edit(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _InstallmentDialog(presenter: presenter, existing: installment),
    );
  }

  Future<void> _markPaid(BuildContext context) async {
    final accountName =
        presenter.accountName(installment.accountId) ?? 'the linked account';
    // The bare `markPaid(id)` this replaced took the monthly amount dated today
    // and offered nothing else. An installment run can carry a catch-up month
    // or a rounded final payment, both of which need the amount and the date.
    // No account picker: an installment is always charged to its linked
    // account, so there is nothing to choose.
    final result = await showWebSettleDialog(
      context,
      title: 'Mark "${installment.name}" paid',
      summary: 'Records this month\'s payment on $accountName.',
      confirmLabel: 'Mark paid',
      initialAmount: installment.monthlyAmount,
      amountLabel: 'Amount paid',
      dateLabel: 'Payment date',
      scheduledNote: 'Monthly: ${formatPeso(installment.monthlyAmount)}',
      onSubmit: (r) => presenter.markPaid(
        installment.id,
        overrideAmount: r.amount,
        date: r.date,
      ),
    );
    if (result == null || !context.mounted) return;
    AppToast.success(
      context,
      'Recorded ${formatPeso(result.amount)} for "${installment.name}".',
    );
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete installment?'),
        content: Text(
            'Delete "${installment.name}"? All linked payment transactions '
            'will also be removed. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await presenter.deleteInstallment(installment.id);
    if (!context.mounted) return;
    AppToast.show(context, 'Deleted "${installment.name}".');
  }
}

// ─── Add/Edit-installment dialog ──────────────────────────────────────────────

/// Desktop add/edit form for an installment plan. Mirrors the mobile
/// [AddInstallmentSheet]: Name, Account, Total amount, Months, auto-computed
/// (editable) Monthly payment, Start month, and an optional Note. Calls
/// [InstallmentPresenter.addInstallment] / `updateInstallment`.
class _InstallmentDialog extends StatefulWidget {
  final InstallmentPresenter presenter;
  final Installment? existing;

  const _InstallmentDialog({required this.presenter, this.existing});

  @override
  State<_InstallmentDialog> createState() => _InstallmentDialogState();
}

class _InstallmentDialogState extends State<_InstallmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _totalController = TextEditingController();
  final _monthlyController = TextEditingController();
  final _noteController = TextEditingController();

  String? _accountId;
  int _totalMonths = 12;
  late String _startMonth;
  bool _monthlyManuallyEdited = false;
  bool _isSubmitting = false;

  static const _monthPresets = [3, 6, 12, 24];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _startMonth = e?.startMonth ?? widget.presenter.selectedMonth;
    if (e != null) {
      _nameController.text = e.name;
      _totalController.text = _trim(e.totalAmount);
      _monthlyController.text = _trim(e.monthlyAmount);
      _noteController.text = e.note ?? '';
      _accountId = e.accountId;
      _totalMonths = e.totalMonths;
      _monthlyManuallyEdited = true;
    } else {
      final accounts = widget.presenter.accounts;
      if (accounts.isNotEmpty) _accountId = accounts.first.id;
    }
    _totalController.addListener(_recomputeMonthly);
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

  void _recomputeMonthly() {
    if (_monthlyManuallyEdited) return;
    final total = double.tryParse(_totalController.text.replaceAll(',', ''));
    if (total != null && _totalMonths > 0) {
      _monthlyController.text = (total / _totalMonths).toStringAsFixed(2);
    }
  }

  void _onMonthsChanged(int months) {
    setState(() {
      _totalMonths = months;
      _monthlyManuallyEdited = false;
    });
    _recomputeMonthly();
  }

  void _adjustStartMonth(int delta) {
    final date = DateTime.parse('$_startMonth-01');
    final next = DateTime(date.year, date.month + delta);
    setState(() => _startMonth = toMonthKey(next));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _totalController.dispose();
    _monthlyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) return;
    setState(() => _isSubmitting = true);
    try {
      final total = double.parse(_totalController.text.replaceAll(',', ''));
      final monthly = double.parse(_monthlyController.text.replaceAll(',', ''));
      final note = _noteController.text.trim();
      final existing = widget.existing;
      final installment = Installment(
        id: existing?.id ??
            '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}',
        name: _nameController.text.trim(),
        accountId: _accountId!,
        totalAmount: total,
        monthlyAmount: monthly,
        totalMonths: _totalMonths,
        startMonth: _startMonth,
        note: note.isEmpty ? null : note,
        isActive: existing?.isActive ?? true,
      );
      if (existing == null) {
        await widget.presenter.addInstallment(installment);
      } else {
        await widget.presenter.updateInstallment(installment);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save installment: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accounts = widget.presenter.accounts;
    final isEdit = widget.existing != null;
    final isCustomMonths = !_monthPresets.contains(_totalMonths);

    return AlertDialog(
      title: Text(isEdit ? 'Edit Installment' : 'Add Installment'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Name (e.g. MacBook Pro, Braces)'),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: WebInsets.md),
                if (accounts.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: accounts.any((a) => a.id == _accountId)
                        ? _accountId
                        : null,
                    decoration: const InputDecoration(
                        labelText: 'Account (Credit / BNPL)'),
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => setState(() => _accountId = v),
                    validator: (v) => v == null ? 'Select an account' : null,
                  )
                else
                  Text(
                    'Add an account in the app before creating installments.',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                  ),
                const SizedBox(height: WebInsets.md),
                TextFormField(
                  controller: _totalController,
                  decoration: const InputDecoration(
                      labelText: 'Total amount', prefixText: '₱ '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final p = double.tryParse((v ?? '').replaceAll(',', ''));
                    if (p == null || p <= 0) return 'Must be > 0';
                    return null;
                  },
                ),
                const SizedBox(height: WebInsets.md),
                Text('Number of months',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: WebInsets.sm),
                Wrap(
                  spacing: WebInsets.sm,
                  children: [
                    for (final m in _monthPresets)
                      ChoiceChip(
                        label: Text('${m}mo'),
                        selected: _totalMonths == m,
                        onSelected: (_) => _onMonthsChanged(m),
                      ),
                    SizedBox(
                      width: 96,
                      child: TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Custom',
                          isDense: true,
                          filled: isCustomMonths,
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final parsed = int.tryParse(v);
                          if (parsed != null && parsed > 0) {
                            _onMonthsChanged(parsed);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WebInsets.md),
                TextFormField(
                  controller: _monthlyController,
                  decoration: const InputDecoration(
                      labelText: 'Monthly payment (auto, editable)',
                      prefixText: '₱ '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) =>
                      setState(() => _monthlyManuallyEdited = true),
                  validator: (v) {
                    final p = double.tryParse((v ?? '').replaceAll(',', ''));
                    if (p == null || p <= 0) return 'Must be > 0';
                    return null;
                  },
                ),
                const SizedBox(height: WebInsets.md),
                Text('Start month',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: WebInsets.sm),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _adjustStartMonth(-1),
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Previous month',
                    ),
                    Expanded(
                      child: Center(
                        child: Text(monthLabel(_startMonth),
                            style: theme.textTheme.bodyMedium),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _adjustStartMonth(1),
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Next month',
                    ),
                  ],
                ),
                const SizedBox(height: WebInsets.md),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                      labelText: 'Note (optional, e.g. 0% interest)'),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Save' : 'Add Installment'),
        ),
      ],
    );
  }
}

// ─── Credit cards live-balance card ──────────────────────────────────────────

class _WebCreditCardsCard extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final List<FinancialAccount> cards;

  const _WebCreditCardsCard({required this.presenter, required this.cards});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalOwed = cards.fold(0.0, (s, c) => s + c.currentPayable);
    return WebCard(
      accentColor: cs.error,
      title: 'Credit Cards',
      description: totalOwed > 0
          ? 'Total owed ${formatPeso(totalOwed)} · pay anytime'
          : 'No outstanding balance',
      child: cards.isEmpty
          ? const _EmptyHint('No credit card accounts.')
          : Column(
              children: [
                for (var i = 0; i < cards.length; i++)
                  _WebCreditCardRow(
                    presenter: presenter,
                    card: cards[i],
                    showDivider: i > 0,
                  ),
              ],
            ),
    );
  }
}

class _WebCreditCardRow extends StatelessWidget {
  final BillsReceivablesPresenter presenter;
  final FinancialAccount card;
  final bool showDivider;

  const _WebCreditCardRow({
    required this.presenter,
    required this.card,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final payable = card.currentPayable;
    final hasBalance = payable > 0;
    final utilization = card.utilization ?? 0.0;
    final available = card.availableCredit;

    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                top:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: WebInsets.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      card.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: WebInsets.sm),
                    WebBadge(
                      hasBalance ? 'Owe ${formatPeso(payable)}' : 'Clear',
                      tone: hasBalance
                          ? WebBadgeTone.danger
                          : WebBadgeTone.success,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (card.creditLimit != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          child: LinearProgressIndicator(
                            value: utilization.clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor: cs.surfaceContainerHighest,
                            color: utilization >= 0.9
                                ? cs.error
                                : utilization >= 0.7
                                    ? cs.tertiary
                                    : cs.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: WebInsets.sm),
                      Text(
                        available != null
                            ? '${formatPeso(available)} avail.'
                            : '${(utilization * 100).round()}% used',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    hasBalance ? 'No credit limit set' : 'No balance',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (hasBalance) ...[
            const SizedBox(width: WebInsets.md),
            FilledButton(
              onPressed: () => _showQuickPay(context),
              style: FilledButton.styleFrom(
                backgroundColor: cs.errorContainer,
                foregroundColor: cs.onErrorContainer,
              ),
              child: const Text('Pay Now'),
            ),
          ],
        ],
      ),
    );
  }

  void _showQuickPay(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _WebQuickPayDialog(card: card, presenter: presenter),
    );
  }
}

// ─── Quick-pay dialog (web) ───────────────────────────────────────────────────

class _WebQuickPayDialog extends StatefulWidget {
  final FinancialAccount card;
  final BillsReceivablesPresenter presenter;

  const _WebQuickPayDialog({required this.card, required this.presenter});

  @override
  State<_WebQuickPayDialog> createState() => _WebQuickPayDialogState();
}

class _WebQuickPayDialogState extends State<_WebQuickPayDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  String? _fromAccountId;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final payable = widget.card.currentPayable;
    _amountController = TextEditingController(
      text: payable == payable.roundToDouble()
          ? payable.round().toString()
          : payable.toStringAsFixed(2),
    );
    final payers = widget.presenter
        .payerAccountsFor(null)
        .where((a) => !a.isLiability && a.isActive)
        .toList();
    if (payers.isNotEmpty) _fromAccountId = payers.first.id;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  List<FinancialAccount> get _payers => widget.presenter
      .payerAccountsFor(null)
      .where((a) => !a.isLiability && a.isActive)
      .toList();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fromAccountId == null) return;
    setState(() => _saving = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      await widget.presenter.quickPayCard(
        accountId: widget.card.id,
        fromAccountId: _fromAccountId!,
        amount: amount,
        date: _date,
      );
      if (mounted) {
        Navigator.of(context).pop();
        AppToast.success(
            context, 'Paid ${formatPeso(amount)} to ${widget.card.name}.');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not record payment: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final payers = _payers;

    return AlertDialog(
      title: Text('Pay ${widget.card.name}'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _amountController,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Amount', prefixText: '₱ '),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final p = double.tryParse((v ?? '').replaceAll(',', ''));
                  if (p == null || p <= 0) return 'Must be > 0';
                  return null;
                },
              ),
              const SizedBox(height: WebInsets.md),
              if (payers.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey(_fromAccountId),
                  initialValue: payers.any((a) => a.id == _fromAccountId)
                      ? _fromAccountId
                      : null,
                  decoration: const InputDecoration(labelText: 'Pay from'),
                  items: payers
                      .map((a) =>
                          DropdownMenuItem(value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _fromAccountId = v),
                  validator: (v) => v == null ? 'Select an account' : null,
                )
              else
                Text(
                  'No liquid accounts available.',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                ),
              const SizedBox(height: WebInsets.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Date: ${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _pickDate,
                    child: const Text('Change'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _fromAccountId == null) ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Pay'),
        ),
      ],
    );
  }
}

// ─── Shared bits ──────────────────────────────────────────────────────────────

/// The settle toggle. Ticking it settles the row; un-ticking a settled one
/// reverses it, so a mis-click is undone the same way it was made instead of
/// being permanent. [tooltip] names whichever direction the next click goes.
class _PaidCheckbox extends StatelessWidget {
  final bool checked;
  final VoidCallback? onTap;
  final String? tooltip;

  const _PaidCheckbox(
      {required this.checked, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final box = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: checked ? cs.tertiary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(
            color: checked ? cs.tertiary : cs.outline,
            width: 1.5,
          ),
        ),
        child:
            checked ? Icon(Icons.check, size: 14, color: cs.onTertiary) : null,
      ),
    );
    if (tooltip == null || onTap == null) return box;
    return Tooltip(message: tooltip!, child: box);
  }
}

/// Trailing overflow menu shared by bill + receivable rows. Keeps edit/delete
/// out of the way until hovered/tapped so the row stays scannable. [onUndo] is
/// added for settled rows so reversing a settlement is discoverable from the
/// same menu as every other row action, not just the checkbox.
class _RowActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onUndo;
  final String? undoLabel;

  const _RowActions({
    required this.onEdit,
    required this.onDelete,
    this.onUndo,
    this.undoLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: Icon(Icons.more_vert, size: 18, color: cs.onSurfaceVariant),
      padding: EdgeInsets.zero,
      splashRadius: 20,
      onSelected: (v) {
        if (v == 'undo') onUndo?.call();
        if (v == 'edit') onEdit();
        if (v == 'delete') onDelete();
      },
      itemBuilder: (_) => [
        if (onUndo != null)
          PopupMenuItem(value: 'undo', child: Text(undoLabel ?? 'Undo')),
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: cs.error)),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String message;

  const _EmptyHint(this.message);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebInsets.lg),
      child: Center(
        child: Text(
          message,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _billTypeLabel(BillType type) => switch (type) {
      BillType.creditCard => 'Credit Card',
      BillType.installment => 'Installment',
      BillType.subscription => 'Subscription',
      BillType.insurance => 'Insurance',
      BillType.govtContribution => 'Govt',
      BillType.utility => 'Bills',
      BillType.other => 'Bills',
    };

String _receivableTypeLabel(ReceivableType type) => switch (type) {
      ReceivableType.salary => 'Salary',
      ReceivableType.reimbursement => 'Reimbursement',
      ReceivableType.business => 'Business',
      ReceivableType.other => 'Other',
    };

WebBadgeTone _billTypeTone(BillType type) => switch (type) {
      BillType.creditCard => WebBadgeTone.info,
      BillType.installment => WebBadgeTone.warning,
      _ => WebBadgeTone.neutral,
    };

String _ordinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}
