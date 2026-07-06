import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/services/notification_service.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/safe_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lifecycle status of a bill relative to today — drives the web status badge
/// so the view never computes due-date conditionals in `build` (Rule 1).
enum BillStatus { paid, overdue, dueSoon, unpaid }

class BillsReceivablesPresenter extends ChangeNotifier with SafeNotifier {
  BillsReceivablesPresenter(
    StorageService storage,
    LedgerPresenter ledger,
    StatsPresenter stats, {
    TreasuryDashboardPresenter? dashboard,
    BudgetPresenter? budget,
    NotificationService? notifications,
  })  : _storage = storage,
        _ledger = ledger,
        _stats = stats,
        _dashboard = dashboard,
        _budget = budget,
        _notifications = notifications ?? NotificationService() {
    // Receivables live here, so let the ledger delegate reimbursement-receivable
    // create/delete back to this presenter (keeps the in-memory list
    // authoritative instead of racing direct storage writes).
    _ledger.onSpawnReimbursementReceivable = createReimbursementReceivable;
    _ledger.onDeleteReimbursementReceivable = deleteReceivable;
    _ledger.onUpdateReimbursementReceivable = updateReimbursementReceivable;
  }

  final StorageService _storage;
  final LedgerPresenter _ledger;
  final StatsPresenter _stats;
  final TreasuryDashboardPresenter? _dashboard;
  final BudgetPresenter? _budget;
  final NotificationService _notifications;

  /// Refresh the dashboard and budget presenters' bill/receivable/expense
  /// state after this presenter mutates storage. Ledger sync handles the
  /// transaction/account fan-out automatically via the listener chain.
  Future<void> _notifyDependents() async {
    _syncReimbursementsToLedger();
    await Future.wait([
      if (_dashboard != null) _dashboard.load(),
      if (_budget != null) _budget.load(),
    ]);
  }

  /// Pushes the set of still-outstanding reimbursement receivables to the
  /// ledger so its "owed to you" total is sourced from authoritative receivable
  /// state (existence + received flag) rather than guessed from inflow legs.
  /// A reimbursement receivable drops out of the set the moment it's received,
  /// so paybacks recorded with or without a ledger entry both clear the owed.
  void _syncReimbursementsToLedger() {
    _ledger.setOutstandingReimbursementIds({
      for (final r in _allReceivables)
        if (r.receivableType == ReceivableType.reimbursement && !r.isReceived)
          r.id,
    });
  }

  String _selectedMonth = toMonthKey(DateTime.now());
  List<Bill> _allBills = [];
  List<Receivable> _allReceivables = [];
  List<BudgetedExpense> _allExpenses = [];

  /// Persisted one-time-XP-award guards (see [StorageService.keyAwardedXpKeys]).
  /// Without this, the all-bills-paid +50 XP was re-awardable via unpay/re-pay
  /// (or by adding one more bill and paying it).
  final Set<String> _awardedXpKeys = {};
  bool _awardedXpLoaded = false;

  // ─── Public state ────────────────────────────────────────────────────────────

  String get selectedMonth => _selectedMonth;

  // ─── Delegate getters for sheets ─────────────────────────────────────────────

  List<FinancialAccount> get accounts => _ledger.accounts;
  List<FinanceCategory> get categories => _ledger.categories;

  // ─── Bill getters ────────────────────────────────────────────────────────────

  /// Bills for the selected month, ordered unpaid-first then by due day, so the
  /// actionable items rise to the top and paid bills sink to the bottom.
  List<Bill> get bills =>
      _allBills.where((b) => b.month == _selectedMonth).toList()
        ..sort((a, b) {
          if (a.isPaid != b.isPaid) return a.isPaid ? 1 : -1;
          final byDue = a.dueDay.compareTo(b.dueDay);
          return byDue != 0 ? byDue : a.name.compareTo(b.name);
        });

  double get totalBillsAmount => bills.fold(0.0, (sum, b) => sum + b.amount);

  double get totalBillsPaid => bills
      .where((b) => b.isPaid)
      .fold(0.0, (sum, b) => sum + (b.paidAmount ?? b.amount));

  double get totalBillsPending =>
      bills.where((b) => !b.isPaid).fold(0.0, (sum, b) => sum + b.amount);

  double get totalNextMonth {
    final billsNm = _allBills
        .where((b) => b.month == _selectedMonth)
        .fold(0.0, (sum, b) => sum + (b.nextMonthAmount ?? 0.0));
    final receivablesNm = _allReceivables
        .where((r) => r.month == _selectedMonth)
        .fold(0.0, (sum, r) => sum + (r.nextMonthAmount ?? 0.0));
    final expensesNm = _allExpenses
        .where((e) => e.month == _selectedMonth)
        .fold(0.0, (sum, e) => sum + (e.nextMonthAmount ?? 0.0));
    return billsNm + receivablesNm + expensesNm;
  }

  // ─── Receivable getters ───────────────────────────────────────────────────────

  /// Receivables for the selected month, ordered not-yet-received-first then by
  /// expected date (the receivable analog of a due day). Entries with no set
  /// date ("ASAP") surface ahead of dated ones within the same status bucket.
  List<Receivable> get receivables =>
      _allReceivables.where((r) => r.month == _selectedMonth).toList()
        ..sort((a, b) {
          if (a.isReceived != b.isReceived) return a.isReceived ? 1 : -1;
          final ad = a.expectedDate;
          final bd = b.expectedDate;
          if (ad == null && bd == null) return a.name.compareTo(b.name);
          if (ad == null) return -1;
          if (bd == null) return 1;
          final byDate = ad.compareTo(bd);
          return byDate != 0 ? byDate : a.name.compareTo(b.name);
        });

  double get totalReceivablesAmount =>
      receivables.fold(0.0, (sum, r) => sum + r.amount);

  double get totalReceived => receivables
      .where((r) => r.isReceived)
      .fold(0.0, (sum, r) => sum + (r.receivedAmount ?? r.amount));

  /// Outstanding (not-yet-received) receivable amount for the selected month —
  /// the web KPI strip's "Pending receivables".
  double get totalReceivablesPending =>
      receivables.where((r) => !r.isReceived).fold(0.0, (s, r) => s + r.amount);

  // ─── Web helpers (Plan 050-C) ─────────────────────────────────────────────────

  /// Human-readable account name for [accountId] (e.g. the bill's funding
  /// account), or null when unset/unknown. Keeps account lookups out of `build`.
  String? accountName(String? accountId) {
    if (accountId == null) return null;
    final match = accounts.where((a) => a.id == accountId).firstOrNull;
    return match?.name;
  }

  /// Money still to move *into* each funding account this month: the sum of
  /// still-due bills paid from it plus still-unfunded set-asides assigned to it.
  /// This answers "how much do I need to have in Maya to cover what's coming?"
  ///
  /// Buckets by [Bill.accountId] / [BudgetedExpense.accountId]; items with no
  /// assigned account fall into a single trailing `account == null` bucket.
  /// Sorted by descending total, with the unassigned bucket always last. All
  /// aggregation lives here so the view can render without doing math. (Rule 1)
  List<
      ({
        FinancialAccount? account,
        double billsDue,
        double setAsides,
        double total,
        int count,
      })> fundingBreakdown() {
    // key: accountId or '' for unassigned → mutable running totals.
    final bills = <String, double>{};
    final setAsides = <String, double>{};
    final counts = <String, int>{};

    for (final b in this.bills.where((b) => !b.isPaid)) {
      final key = b.accountId ?? '';
      bills[key] = (bills[key] ?? 0) + b.amount;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    for (final e in budgetedExpenses.where((e) => !e.isPaid)) {
      final key = e.accountId ?? '';
      setAsides[key] = (setAsides[key] ?? 0) + e.allocatedAmount;
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final keys = {...bills.keys, ...setAsides.keys};
    final rows = [
      for (final key in keys)
        (
          account: key.isEmpty
              ? null
              : accounts.where((a) => a.id == key).firstOrNull,
          billsDue: bills[key] ?? 0,
          setAsides: setAsides[key] ?? 0,
          total: (bills[key] ?? 0) + (setAsides[key] ?? 0),
          count: counts[key] ?? 0,
        ),
    ];

    // Largest obligation first; the unassigned bucket (null account) sinks to
    // the bottom regardless of size so real accounts lead.
    rows.sort((a, b) {
      if ((a.account == null) != (b.account == null)) {
        return a.account == null ? 1 : -1;
      }
      return b.total.compareTo(a.total);
    });
    return rows;
  }

  /// Lifecycle status of a bill relative to today, used to drive the web status
  /// badge without conditionals in `build`.
  BillStatus billStatus(Bill bill) {
    if (bill.isPaid) return BillStatus.paid;
    final now = DateTime.now();
    final dueDay = bill.dueDay.clamp(1, 28);
    // Only compare day-of-month against today for the current month — past or
    // future months have no meaningful "overdue/due-soon" relative to now.
    if (bill.month == toMonthKey(now)) {
      if (now.day > dueDay) return BillStatus.overdue;
      if (dueDay - now.day <= 5) return BillStatus.dueSoon;
    }
    return BillStatus.unpaid;
  }

  // ─── Budgeted Expense getters ─────────────────────────────────────────────────

  /// Budgeted expenses for the selected month, ordered unpaid-first. These have
  /// no due day, so the secondary sort is alphabetical by name.
  List<BudgetedExpense> get budgetedExpenses =>
      _allExpenses.where((e) => e.month == _selectedMonth).toList()
        ..sort((a, b) {
          if (a.isPaid != b.isPaid) return a.isPaid ? 1 : -1;
          return a.name.compareTo(b.name);
        });

  // ─── Month navigation ─────────────────────────────────────────────────────────

  Future<void> setMonth(String month) async {
    _selectedMonth = month;
    await _autoGenerateRecurringIfNeeded(month);
    // Re-run close-date detection so navigating into the current real month
    // (e.g., day 1 of a new month) sees the statement without requiring a
    // full reload.
    await _autoGenerateCreditStatements();
    safeNotify();
  }

  // ─── Load ─────────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _allBills = await _storage.loadBills();
    _allReceivables = await _storage.loadReceivables();
    _allExpenses = await _storage.loadBudgetedExpenses();
    _awardedXpKeys
      ..clear()
      ..addAll(await _storage.loadAwardedXpKeys());
    _awardedXpLoaded = true;

    // One-time removal of stale future-month credit-card statement copies the
    // recurring auto-copy used to proliferate before it excluded credit cards.
    await _cleanupFutureRecurringCreditStatements();

    // Schedule or cancel monthly bills reminder based on user preferences.
    final prefs = await _storage.loadNotificationPreferences();
    if (prefs.billsReminderEnabled && _allBills.isNotEmpty) {
      await _notifications.scheduleBillsReminder(prefs.billsReminderDayOfMonth);
    } else {
      await _notifications.cancelBillsReminder();
    }

    // Snapshot closed credit statements into bills, reconcile paid-off cards,
    // and (re)schedule per-account due-date reminders.
    await _autoGenerateCreditStatements();
    await _syncCreditDueReminders(prefs.billsReminderEnabled);

    // Make the ledger's "owed to you" total authoritative from the moment
    // receivables are loaded, not just after the next mutation.
    _syncReimbursementsToLedger();

    safeNotify();
  }

  bool _isAutoStatement(Bill b) => b.isAutoStatement;

  /// SharedPreferences flag gating the one-time cleanup below so it runs once
  /// (on the upgrade that shipped the fix) and never deletes a recurring
  /// credit-card bill a user might deliberately create in a future month later.
  static const String _kFutureRecurringCcCleanupDone =
      'bills.cleanup.future_recurring_cc_v1';

  /// Removes the stale future-month credit-card statement copies left behind by
  /// the old recurring auto-copy (which proliferated a frozen amount onto every
  /// future month). Scoped tightly to avoid touching anything the user acted on:
  /// only future-month, recurring, credit-card, unpaid, un-transacted bills.
  /// Runs at most once; safely no-ops in tests where SharedPreferences is absent.
  Future<void> _cleanupFutureRecurringCreditStatements() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kFutureRecurringCcCleanupDone) ?? false) return;
      final currentMonth = toMonthKey(DateTime.now());
      final before = _allBills.length;
      _allBills = _allBills
          .where((b) => !(b.billType == BillType.creditCard &&
              b.isRecurring &&
              !b.isPaid &&
              b.transactionId == null &&
              b.month.compareTo(currentMonth) > 0))
          .toList();
      if (_allBills.length != before) {
        await _storage.saveBills(_allBills);
      }
      await prefs.setBool(_kFutureRecurringCcCleanupDone, true);
    } catch (e) {
      debugPrint('BillsReceivablesPresenter: CC cleanup skipped: $e');
    }
  }

  // ─── Bill CRUD ────────────────────────────────────────────────────────────────

  Future<void> addBill(Bill bill) async {
    _allBills = [..._allBills, bill];
    safeNotify();
    await _storage.saveBills(_allBills);
    await _notifyDependents();
  }

  Future<void> updateBill(Bill bill) async {
    _allBills = [for (final b in _allBills) b.id == bill.id ? bill : b];
    safeNotify();
    await _storage.saveBills(_allBills);
    await _notifyDependents();
  }

  Future<void> deleteBill(String id) async {
    _allBills = _allBills.where((b) => b.id != id).toList();
    safeNotify();
    await _storage.saveBills(_allBills);
    await _notifyDependents();
  }

  /// Marks [billId] paid. When [recordInLedger] is true (default) this also
  /// debits [accountId] via a ledger transaction (or a transfer for credit-card
  /// statements). Pass `recordInLedger: false` when the user already logged the
  /// expense in the ledger manually — the bill is still flagged paid, but no
  /// transaction is created and no account is touched (so [accountId] is
  /// optional and ignored in that case).
  Future<void> markBillPaid(
    String billId, {
    required double paidAmount,
    String? accountId,
    DateTime? paidDate,
    bool recordInLedger = true,
  }) async {
    final bill = _allBills.firstWhere((b) => b.id == billId);
    final date = paidDate ?? DateTime.now();

    String? txnId;
    if (recordInLedger) {
      assert(accountId != null,
          'accountId is required when recording the payment in the ledger');
      final acct = accountId!;
      // Paying down ANY liability statement (credit card, credit line, BNPL) is
      // a *transfer*: cash leaves the funding account and the liability's owed
      // balance goes down. A plain outflow would shrink cash without clearing
      // the debt AND wrongly count as spending — the original charge already
      // booked the expense. So route any payment whose target account is a
      // liability through addTransfer, regardless of the bill's type.
      final liability =
          _ledger.accounts.where((a) => a.id == bill.accountId).firstOrNull;
      // A liability statement can never be paid FROM that same liability
      // account — that would book a plain outflow whose sign-flip *increases*
      // the owed balance and double-counts as spend. Require a funding account.
      if (liability != null &&
          liability.isLiability &&
          acct == bill.accountId) {
        throw ArgumentError(
            'Cannot pay a liability statement from the same liability account; '
            'choose a cash/funding account.');
      }
      if (liability != null &&
          liability.isLiability &&
          acct != bill.accountId) {
        await _ledger.addTransfer(
          fromAccountId: acct,
          toAccountId: bill.accountId!,
          amount: paidAmount,
          description: bill.name,
          date: date,
        );
      } else {
        final txn = _buildOutflowTxn(
          id: _generateId(),
          amount: paidAmount,
          accountId: acct,
          categoryId: bill.categoryId,
          description: bill.name,
          date: date,
          billId: bill.id,
        );
        await _ledger.addTransaction(txn);
        txnId = txn.id;
      }
    }
    _updateBill(bill.copyWith(
      isPaid: true,
      paidDate: date,
      paidAmount: paidAmount,
      transactionId: txnId,
    ));
    safeNotify();
    await _storage.saveBills(_allBills);
    await _checkAllBillsPaidXp();
    await _notifyDependents();
  }

  // ─── Receivable CRUD ─────────────────────────────────────────────────────────

  Future<void> addReceivable(Receivable receivable) async {
    _allReceivables = [..._allReceivables, receivable];
    safeNotify();
    await _storage.saveReceivables(_allReceivables);
    await _notifyDependents();
  }

  /// Creates the reimbursement receivable linked to a reimbursable [outflow].
  /// Wired onto the ledger as [LedgerPresenter.onSpawnReimbursementReceivable].
  /// The receivable reuses the outflow's pre-generated id so the two stay
  /// linked; settling it later flows through [markReceivableReceived] like any
  /// other receivable, writing the offsetting inflow.
  Future<void> createReimbursementReceivable(
    TransactionRecord outflow,
    DateTime? expectedDate,
  ) async {
    final receivableId = outflow.reimbursementReceivableId;
    if (receivableId == null) return;
    await addReceivable(Receivable(
      id: receivableId,
      name: _reimbursementReceivableName(outflow),
      receivableType: ReceivableType.reimbursement,
      amount: outflow.amount,
      expectedDate: expectedDate,
      // Bucket into the month you'll be paid back when a date is set (e.g. a
      // company's fixed reimbursement-run day → it surfaces in that month);
      // otherwise into the month the debt arose, so an ASAP/no-date entry shows
      // up immediately. The list is month-filtered, so a wrong bucket hides the
      // entry — which is what made a just-logged reimbursable look untracked.
      month: expectedDate != null ? toMonthKey(expectedDate) : outflow.month,
      categoryId: outflow.categoryId,
      reimbursementForTxnId: outflow.id,
    ));
  }

  /// Re-syncs the linked receivable after a reimbursable [outflow] is edited:
  /// keeps its amount/name in step with the expense so "what you're owed" never
  /// drifts from what you actually spent. No-op if the receivable is gone or
  /// has already been received (don't disturb a settled payback). Wired onto
  /// the ledger as [LedgerPresenter.onUpdateReimbursementReceivable].
  Future<void> updateReimbursementReceivable(TransactionRecord outflow) async {
    final receivableId = outflow.reimbursementReceivableId;
    if (receivableId == null) return;
    final existing =
        _allReceivables.where((r) => r.id == receivableId).firstOrNull;
    if (existing == null || existing.isReceived) return;
    await updateReceivable(existing.copyWith(
      name: _reimbursementReceivableName(outflow),
      amount: outflow.amount,
      categoryId: outflow.categoryId,
    ));
  }

  /// Display name for a reimbursement receivable: prefers "<who owes you> —
  /// <expense>", falling back to the expense description, then a generic label.
  String _reimbursementReceivableName(TransactionRecord outflow) {
    final desc = outflow.description.trim();
    final who = outflow.owedBy?.trim() ?? '';
    if (who.isNotEmpty && desc.isNotEmpty) return '$who — $desc';
    if (who.isNotEmpty) return 'Reimbursement from $who';
    if (desc.isNotEmpty) return desc;
    return 'Reimbursement';
  }

  Future<void> updateReceivable(Receivable receivable) async {
    _allReceivables = [
      for (final r in _allReceivables) r.id == receivable.id ? receivable : r,
    ];
    safeNotify();
    await _storage.saveReceivables(_allReceivables);
    await _notifyDependents();
  }

  Future<void> deleteReceivable(String id) async {
    _allReceivables = _allReceivables.where((r) => r.id != id).toList();
    safeNotify();
    await _storage.saveReceivables(_allReceivables);
    await _notifyDependents();
  }

  /// Marks [receivableId] received. When [recordInLedger] is true (default) this
  /// also credits [accountId] via a ledger inflow. Pass `recordInLedger: false`
  /// when the user already logged the income in the ledger manually — the
  /// receivable is still flagged received, but no transaction is created and no
  /// account is touched (so [accountId] is optional and ignored in that case).
  Future<void> markReceivableReceived(
    String receivableId, {
    required double receivedAmount,
    String? accountId,
    DateTime? receivedDate,
    bool recordInLedger = true,
  }) async {
    final rec = _allReceivables.firstWhere((r) => r.id == receivableId);
    final date = receivedDate ?? DateTime.now();
    String? txnId;
    if (recordInLedger) {
      assert(accountId != null,
          'accountId is required when recording the receipt in the ledger');
      final txn = _buildInflowTxn(
        id: _generateId(),
        amount: receivedAmount,
        accountId: accountId!,
        categoryId: rec.categoryId,
        description: rec.name,
        date: date,
        receivableId: rec.id,
      );
      await _ledger.addTransaction(txn);
      txnId = txn.id;
    }
    _updateReceivable(rec.copyWith(
      isReceived: true,
      receivedDate: date,
      receivedAmount: receivedAmount,
      transactionId: txnId,
    ));
    safeNotify();
    await _storage.saveReceivables(_allReceivables);
    await _notifyDependents();
  }

  // ─── Budgeted Expense CRUD ────────────────────────────────────────────────────

  Future<void> addBudgetedExpense(BudgetedExpense expense) async {
    _allExpenses = [..._allExpenses, expense];
    safeNotify();
    await _storage.saveBudgetedExpenses(_allExpenses);
    await _notifyDependents();
  }

  Future<void> updateBudgetedExpense(BudgetedExpense expense) async {
    _allExpenses = [
      for (final e in _allExpenses) e.id == expense.id ? expense : e,
    ];
    safeNotify();
    await _storage.saveBudgetedExpenses(_allExpenses);
    await _notifyDependents();
  }

  Future<void> deleteBudgetedExpense(String id) async {
    _allExpenses = _allExpenses.where((e) => e.id != id).toList();
    safeNotify();
    await _storage.saveBudgetedExpenses(_allExpenses);
    await _notifyDependents();
  }

  /// Marks a set-aside funded. Setting money aside is normally a *transfer*
  /// between your own accounts: cash leaves [accountId] (the funding source) and
  /// lands in [toAccountId] (a savings/goal destination), so it must never count
  /// as spending — hence the transfer, not an outflow. When [toAccountId] is null
  /// (or equals the source) it falls back to a plain outflow, for one-off plans
  /// that really are spent (gifts, etc.).
  Future<void> markExpensePaid(
    String expenseId, {
    required double paidAmount,
    required String accountId,
    String? toAccountId,
    DateTime? paidDate,
  }) async {
    final expense = _allExpenses.firstWhere((e) => e.id == expenseId);
    final date = paidDate ?? DateTime.now();

    String? txnId;
    if (toAccountId != null && toAccountId != accountId) {
      // Transfer legs carry the reserved transfer category (neither income nor
      // expense) and a shared group id; the expense keeps no single txn id, the
      // same way a credit-card bill paid via transfer does.
      await _ledger.addTransfer(
        fromAccountId: accountId,
        toAccountId: toAccountId,
        amount: paidAmount,
        description: expense.name,
        date: date,
      );
    } else {
      final txn = _buildOutflowTxn(
        id: _generateId(),
        amount: paidAmount,
        accountId: accountId,
        categoryId: expense.categoryId,
        description: expense.name,
        date: date,
      );
      await _ledger.addTransaction(txn);
      txnId = txn.id;
    }
    _updateExpense(expense.copyWith(
      isPaid: true,
      spentAmount: paidAmount,
      transactionId: txnId,
    ));
    safeNotify();
    await _storage.saveBudgetedExpenses(_allExpenses);
    await _notifyDependents();
  }

  // ─── Private helpers ──────────────────────────────────────────────────────────

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  void _updateBill(Bill updated) {
    _allBills = [for (final b in _allBills) b.id == updated.id ? updated : b];
  }

  void _updateReceivable(Receivable updated) {
    _allReceivables = [
      for (final r in _allReceivables) r.id == updated.id ? updated : r,
    ];
  }

  void _updateExpense(BudgetedExpense updated) {
    _allExpenses = [
      for (final e in _allExpenses) e.id == updated.id ? updated : e,
    ];
  }

  TransactionRecord _buildOutflowTxn({
    required String id,
    required double amount,
    required String accountId,
    required String categoryId,
    required String description,
    required DateTime date,
    String? billId,
  }) {
    return TransactionRecord(
      id: id,
      date: date,
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
      type: TransactionType.outflow,
      description: description,
      month: toMonthKey(date),
      billId: billId,
    );
  }

  TransactionRecord _buildInflowTxn({
    required String id,
    required double amount,
    required String accountId,
    required String categoryId,
    required String description,
    required DateTime date,
    String? receivableId,
  }) {
    return TransactionRecord(
      id: id,
      date: date,
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
      type: TransactionType.inflow,
      description: description,
      month: toMonthKey(date),
      receivableId: receivableId,
    );
  }

  Future<void> _checkAllBillsPaidXp() async {
    if (!_awardedXpLoaded) return; // don't award before the guard set loads
    final monthBills = bills;
    if (monthBills.isEmpty) return;
    // Re-read updated state — bills getter reads from _allBills which was updated
    final allPaid = monthBills.every((b) => b.isPaid);
    if (!allPaid) return;
    // Award the "all bills paid" XP at most once per month. Without the guard,
    // unpay/re-pay (or adding one more bill and paying it) farmed 50 XP each
    // time. markUnpaid never rescinds the award — the simplest non-exploitable
    // rule (you earned it once that month).
    final key = 'bills.allPaid/$_selectedMonth';
    if (_awardedXpKeys.contains(key)) return;
    _awardedXpKeys.add(key);
    await _storage.saveAwardedXpKeys(_awardedXpKeys);
    await _stats.addXp(50);
  }

  Future<void> _autoGenerateRecurringIfNeeded(String month) async {
    await _autoGenerateRecurringBills(month);
    await _autoGenerateRecurringReceivables(month);
    await _autoGenerateRecurringBudgetedExpenses(month);
  }

  /// Snapshots closed credit statements into bills for all months up to today.
  /// Runs close-date detection across every month since the oldest existing
  /// statement, so a multi-month gap (app was closed on statement day) gets
  /// backfilled on the next open. Never generates for future months.
  ///
  /// Current month: uses live `currentPayable`.
  /// Past months: generates a ₱0 placeholder only when a balance still exists
  /// today — actual historical balances are not recoverable, so the placeholder
  /// reminds the user to review rather than silently mis-stating the amount.
  Future<void> _autoGenerateCreditStatements() async {
    final now = DateTime.now();
    final currentMonthKey = toMonthKey(now);
    final categoryId = _defaultCreditCategoryId();
    if (categoryId == null) return;
    var changed = false;

    final creditAccts = _ledger.accounts.where((a) =>
        a.isActive &&
        a.isLiability &&
        a.statementDay != null &&
        a.paymentDueDay != null);

    // Determine the earliest month to backfill from (one after the oldest
    // existing auto-statement, or the current month when there are none).
    final existingMonths =
        _allBills.where(_isAutoStatement).map((b) => b.month).toList()..sort();
    final startMonth = existingMonths.isEmpty
        ? currentMonthKey
        : nextMonth(existingMonths.first);

    // Build the list of months to evaluate (startMonth … currentMonth).
    final monthsToCheck = <String>[];
    var cursor = startMonth;
    while (cursor.compareTo(currentMonthKey) <= 0) {
      monthsToCheck.add(cursor);
      cursor = nextMonth(cursor);
    }

    for (final month in monthsToCheck) {
      final isCurrentMonth = month == currentMonthKey;

      for (final a in creditAccts) {
        final existing = _allBills
            .where((b) =>
                _isAutoStatement(b) && b.accountId == a.id && b.month == month)
            .firstOrNull;

        // Reconcile current-month statement when the card is fully cleared.
        if (isCurrentMonth &&
            existing != null &&
            !existing.isPaid &&
            a.currentPayable <= 0) {
          _updateBill(existing.copyWith(
            isPaid: true,
            paidDate: now,
            paidAmount: existing.amount,
          ));
          changed = true;
          continue;
        }
        if (existing != null) continue;

        // For current month: statement day must have passed.
        if (isCurrentMonth && now.day < a.statementDay!.clamp(1, 28)) continue;
        // For either month type: skip if nothing is currently owed (no point
        // generating a ₱0 placeholder — the card was either fully paid or never
        // used in that cycle).
        if (a.currentPayable <= 0) continue;

        // For past months: amount is 0 (historical balance unknown).
        final amount = isCurrentMonth ? a.currentPayable : 0.0;

        _allBills = [
          ..._allBills,
          Bill(
            id: _generateId(),
            name: '${a.name} statement',
            billType: BillType.creditCard,
            amount: amount,
            dueDay: a.paymentDueDay!.clamp(1, 28),
            month: month,
            categoryId: categoryId,
            accountId: a.id,
            paymentNote: Bill.autoStatementNote,
          ),
        ];
        changed = true;
      }
    }

    if (changed) await _storage.saveBills(_allBills);
  }

  // ─── Credit account helpers ───────────────────────────────────────────────────

  /// All active liability accounts (credit card, credit line, BNPL).
  List<FinancialAccount> get creditAccounts =>
      _ledger.accounts.where((a) => a.isActive && a.isLiability).toList();

  /// Non-liability accounts eligible to fund payment of [bill]. For a bill
  /// whose target account is a liability (CC, BNPL) the payer must be a
  /// non-liability account — you can't pay a CC from itself. For other bills
  /// all accounts are returned.
  List<FinancialAccount> payerAccountsFor(Bill? bill) {
    final targetId = bill?.accountId;
    if (targetId == null) return _ledger.accounts;
    final targetIsLiability = _ledger.accounts
        .where((a) => a.id == targetId)
        .any((a) => a.isLiability);
    if (!targetIsLiability) return _ledger.accounts;
    return _ledger.accounts.where((a) => !a.isLiability).toList();
  }

  /// Pays down a credit card balance directly without requiring a statement
  /// bill. Cash leaves [fromAccountId] and the card's owed balance decreases
  /// via [LedgerPresenter.addTransfer] (same path as paying a CC bill).
  Future<void> quickPayCard({
    required String accountId,
    required String fromAccountId,
    required double amount,
    DateTime? date,
  }) async {
    final account =
        _ledger.accounts.where((a) => a.id == accountId).firstOrNull;
    if (account == null || !account.isLiability) return;
    await _ledger.addTransfer(
      fromAccountId: fromAccountId,
      toAccountId: accountId,
      amount: amount,
      description: '${account.name} payment',
      date: date ?? DateTime.now(),
    );
    await _notifyDependents();
  }

  /// (Re)schedules or cancels per-account payment-due reminders, respecting the
  /// global bills-reminder toggle.
  Future<void> _syncCreditDueReminders(bool enabled) async {
    final creditAccounts = _ledger.accounts
        .where((a) => a.isActive && a.isLiability && a.paymentDueDay != null);
    for (final a in creditAccounts) {
      if (enabled) {
        await _notifications.scheduleCreditDueReminder(
          accountId: a.id,
          accountName: a.name,
          dueDay: a.paymentDueDay!,
        );
      } else {
        await _notifications.cancelCreditDueReminder(a.id);
      }
    }
  }

  /// First expense category (or any category) to satisfy [Bill.categoryId];
  /// null when the user has no categories yet.
  String? _defaultCreditCategoryId() {
    final cats = _ledger.categories;
    if (cats.isEmpty) return null;
    final expense = cats.where((c) => c.type == CategoryType.expense).toList();
    return (expense.isEmpty ? cats.first : expense.first).id;
  }

  Future<void> _autoGenerateRecurringBills(String month) async {
    // Auto-generated credit statements don't count as "user already has bills",
    // otherwise a closed statement would suppress recurring-bill copies.
    final existing = _allBills
        .where((b) => b.month == month && !_isAutoStatement(b))
        .toList();
    if (existing.isNotEmpty) return;

    final prev = previousMonth(month);
    // Credit-card statements are handled by the live auto-statement snapshot
    // (real balance for the current month, nothing for the future). Copying a
    // recurring credit-card bill forward would stamp a frozen amount onto every
    // future month the user opens — the proliferation bug — so exclude them.
    final recurringFromPrev = _allBills
        .where((b) =>
            b.month == prev &&
            b.isRecurring &&
            b.billType != BillType.creditCard)
        .toList();
    if (recurringFromPrev.isEmpty) return;

    final copies = recurringFromPrev.map((b) => Bill(
          id: _generateId(),
          name: b.name,
          billType: b.billType,
          amount: b.nextMonthAmount ?? b.amount,
          dueDay: b.dueDay,
          month: month,
          categoryId: b.categoryId,
          accountId: b.accountId,
          paymentNote: b.paymentNote,
          isRecurring: b.isRecurring,
          recurrenceType: b.recurrenceType,
        ));
    _allBills = [..._allBills, ...copies];
    await _storage.saveBills(_allBills);
  }

  Future<void> _autoGenerateRecurringReceivables(String month) async {
    final existing = _allReceivables.where((r) => r.month == month).toList();
    if (existing.isNotEmpty) return;

    final prev = previousMonth(month);
    final recurringFromPrev =
        _allReceivables.where((r) => r.month == prev && r.isRecurring).toList();
    if (recurringFromPrev.isEmpty) return;

    final parts = month.split('-');
    final year = int.parse(parts[0]);
    final monthNum = int.parse(parts[1]);
    final lastDay = DateTime(year, monthNum + 1, 0).day;
    final copies = recurringFromPrev.map((r) {
      // Clamp the day to the target month's length so a 31st-of-the-month
      // receivable copied into February doesn't silently drift into March.
      // A recurring entry without a set day defaults to the 1st.
      final day = (r.expectedDate?.day ?? 1).clamp(1, lastDay);
      final expectedDate = DateTime(year, monthNum, day);
      return Receivable(
        id: _generateId(),
        name: r.name,
        receivableType: r.receivableType,
        amount: r.nextMonthAmount ?? r.amount,
        expectedDate: expectedDate,
        month: month,
        categoryId: r.categoryId,
        accountId: r.accountId,
        isRecurring: r.isRecurring,
        recurrenceType: r.recurrenceType,
      );
    });
    _allReceivables = [..._allReceivables, ...copies];
    await _storage.saveReceivables(_allReceivables);
  }

  Future<void> _autoGenerateRecurringBudgetedExpenses(String month) async {
    // Only seed a month that has no set-asides yet, so we never duplicate the
    // user's own entries. Mirrors the recurring-bills flow.
    final existing = _allExpenses.where((e) => e.month == month).toList();
    if (existing.isNotEmpty) return;

    final prev = previousMonth(month);
    final recurringFromPrev =
        _allExpenses.where((e) => e.month == prev && e.isRecurring).toList();
    if (recurringFromPrev.isEmpty) return;

    final copies = recurringFromPrev.map((e) => BudgetedExpense(
          id: _generateId(),
          name: e.name,
          budgetedType: e.budgetedType,
          month: month,
          // Carry the pre-set next-month amount when the user staged one,
          // otherwise repeat this month's allocation. Never copy spentAmount —
          // the new month starts unfunded.
          allocatedAmount: e.nextMonthAmount ?? e.allocatedAmount,
          categoryId: e.categoryId,
          note: e.note,
          accountId: e.accountId,
          isRecurring: e.isRecurring,
          recurrenceType: e.recurrenceType,
        ));
    _allExpenses = [..._allExpenses, ...copies];
    await _storage.saveBudgetedExpenses(_allExpenses);
  }
}
