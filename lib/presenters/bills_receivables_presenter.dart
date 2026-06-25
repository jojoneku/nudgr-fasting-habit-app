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

  // ─── Public state ────────────────────────────────────────────────────────────

  String get selectedMonth => _selectedMonth;

  // ─── Delegate getters for sheets ─────────────────────────────────────────────

  List<FinancialAccount> get accounts => _ledger.accounts;
  List<FinanceCategory> get categories => _ledger.categories;

  // ─── Bill getters ────────────────────────────────────────────────────────────

  List<Bill> get bills =>
      _allBills.where((b) => b.month == _selectedMonth).toList();

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

  List<Receivable> get receivables =>
      _allReceivables.where((r) => r.month == _selectedMonth).toList();

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

  List<BudgetedExpense> get budgetedExpenses =>
      _allExpenses.where((e) => e.month == _selectedMonth).toList();

  // ─── Month navigation ─────────────────────────────────────────────────────────

  Future<void> setMonth(String month) async {
    _selectedMonth = month;
    await _autoGenerateRecurringIfNeeded(month);
    safeNotify();
  }

  // ─── Load ─────────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _allBills = await _storage.loadBills();
    _allReceivables = await _storage.loadReceivables();
    _allExpenses = await _storage.loadBudgetedExpenses();

    // Schedule or cancel monthly bills reminder based on user preferences.
    final prefs = await _storage.loadNotificationPreferences();
    if (prefs.billsReminderEnabled && _allBills.isNotEmpty) {
      await _notifications.scheduleBillsReminder(prefs.billsReminderDayOfMonth);
    } else {
      await _notifications.cancelBillsReminder();
    }

    // Snapshot closed credit statements into bills, reconcile paid-off cards,
    // and (re)schedule per-account due-date reminders.
    await _autoGenerateCreditStatements(_selectedMonth);
    await _syncCreditDueReminders(prefs.billsReminderEnabled);

    // Make the ledger's "owed to you" total authoritative from the moment
    // receivables are loaded, not just after the next mutation.
    _syncReimbursementsToLedger();

    safeNotify();
  }

  /// Marker stored in [Bill.paymentNote] so auto-generated credit statements are
  /// distinguishable from user-created bills (e.g. excluded from the recurring
  /// auto-copy guard).
  static const String _autoStatementMarker = '__auto_statement__';

  bool _isAutoStatement(Bill b) =>
      b.billType == BillType.creditCard &&
      b.paymentNote == _autoStatementMarker;

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
    DateTime expectedDate,
  ) async {
    final receivableId = outflow.reimbursementReceivableId;
    if (receivableId == null) return;
    await addReceivable(Receivable(
      id: receivableId,
      name: _reimbursementReceivableName(outflow),
      receivableType: ReceivableType.reimbursement,
      amount: outflow.amount,
      expectedDate: expectedDate,
      month: toMonthKey(expectedDate),
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

  Future<void> markExpensePaid(
    String expenseId, {
    required double paidAmount,
    required String accountId,
    DateTime? paidDate,
  }) async {
    final expense = _allExpenses.firstWhere((e) => e.id == expenseId);
    final txn = _buildOutflowTxn(
      id: _generateId(),
      amount: paidAmount,
      accountId: accountId,
      categoryId: expense.categoryId,
      description: expense.name,
      date: paidDate ?? DateTime.now(),
    );
    await _ledger.addTransaction(txn);
    _updateExpense(expense.copyWith(
      isPaid: true,
      spentAmount: paidAmount,
      transactionId: txn.id,
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
      month: _selectedMonth,
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
      month: _selectedMonth,
      receivableId: receivableId,
    );
  }

  Future<void> _checkAllBillsPaidXp() async {
    final monthBills = bills;
    if (monthBills.isEmpty) return;
    // Re-read updated state — bills getter reads from _allBills which was updated
    final allPaid = monthBills.every((b) => b.isPaid);
    if (allPaid) await _stats.addXp(50);
  }

  Future<void> _autoGenerateRecurringIfNeeded(String month) async {
    await _autoGenerateRecurringBills(month);
    await _autoGenerateRecurringReceivables(month);
  }

  /// Snapshots a closed credit statement into a bill (once per account/month)
  /// and reconciles auto-statements that have since been paid off. Runs only for
  /// the current real month — never backfills history.
  Future<void> _autoGenerateCreditStatements(String month) async {
    if (month != toMonthKey(DateTime.now())) return;
    final now = DateTime.now();
    final categoryId = _defaultCreditCategoryId();
    var changed = false;

    final creditAccounts = _ledger.accounts.where((a) =>
        a.isActive &&
        a.isLiability &&
        a.statementDay != null &&
        a.paymentDueDay != null);

    for (final a in creditAccounts) {
      final matches = _allBills
          .where((b) =>
              _isAutoStatement(b) && b.accountId == a.id && b.month == month)
          .toList();
      final existing = matches.isEmpty ? null : matches.first;

      // Reconcile: a fully paid-off card clears its outstanding statement.
      if (existing != null && !existing.isPaid && a.currentPayable <= 0) {
        _updateBill(existing.copyWith(
          isPaid: true,
          paidDate: now,
          paidAmount: existing.amount,
        ));
        changed = true;
        continue;
      }
      if (existing != null) continue;

      // Generate only once the statement day has passed and a balance is owed.
      if (now.day < a.statementDay!.clamp(1, 28)) continue;
      if (a.currentPayable <= 0) continue;
      if (categoryId == null) continue; // need a valid category for a bill

      _allBills = [
        ..._allBills,
        Bill(
          id: _generateId(),
          name: '${a.name} statement',
          billType: BillType.creditCard,
          amount: a.currentPayable,
          dueDay: a.paymentDueDay!.clamp(1, 28),
          month: month,
          categoryId: categoryId,
          accountId: a.id,
          paymentNote: _autoStatementMarker,
        ),
      ];
      changed = true;
    }

    if (changed) await _storage.saveBills(_allBills);
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
    final recurringFromPrev =
        _allBills.where((b) => b.month == prev && b.isRecurring).toList();
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
      final day = r.expectedDate.day.clamp(1, lastDay);
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
}
