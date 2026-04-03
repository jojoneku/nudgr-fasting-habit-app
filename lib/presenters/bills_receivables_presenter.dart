import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class BillsReceivablesPresenter extends ChangeNotifier {
  BillsReceivablesPresenter(
    StorageService storage,
    LedgerPresenter ledger,
    StatsPresenter stats,
  )   : _storage = storage,
        _ledger = ledger,
        _stats = stats;

  final StorageService _storage;
  final LedgerPresenter _ledger;
  final StatsPresenter _stats;

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

  double get totalBillsAmount =>
      bills.fold(0.0, (sum, b) => sum + b.amount);

  double get totalBillsPaid =>
      bills.where((b) => b.isPaid).fold(0.0, (sum, b) => sum + (b.paidAmount ?? b.amount));

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

  double get totalReceived =>
      receivables
          .where((r) => r.isReceived)
          .fold(0.0, (sum, r) => sum + (r.receivedAmount ?? r.amount));

  // ─── Budgeted Expense getters ─────────────────────────────────────────────────

  List<BudgetedExpense> get budgetedExpenses =>
      _allExpenses.where((e) => e.month == _selectedMonth).toList();

  // ─── Month navigation ─────────────────────────────────────────────────────────

  Future<void> setMonth(String month) async {
    _selectedMonth = month;
    await _autoGenerateRecurringIfNeeded(month);
    notifyListeners();
  }

  // ─── Load ─────────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _allBills = await _storage.loadBills();
    _allReceivables = await _storage.loadReceivables();
    _allExpenses = await _storage.loadBudgetedExpenses();
    notifyListeners();
  }

  // ─── Bill CRUD ────────────────────────────────────────────────────────────────

  Future<void> addBill(Bill bill) async {
    _allBills = [..._allBills, bill];
    await _storage.saveBills(_allBills);
    notifyListeners();
  }

  Future<void> updateBill(Bill bill) async {
    _allBills = [for (final b in _allBills) b.id == bill.id ? bill : b];
    await _storage.saveBills(_allBills);
    notifyListeners();
  }

  Future<void> deleteBill(String id) async {
    _allBills = _allBills.where((b) => b.id != id).toList();
    await _storage.saveBills(_allBills);
    notifyListeners();
  }

  Future<void> markBillPaid(
    String billId, {
    required double paidAmount,
    required String accountId,
    DateTime? paidDate,
  }) async {
    final bill = _allBills.firstWhere((b) => b.id == billId);
    final txn = _buildOutflowTxn(
      id: _generateId(),
      amount: paidAmount,
      accountId: accountId,
      categoryId: bill.categoryId,
      description: bill.name,
      date: paidDate ?? DateTime.now(),
      billId: bill.id,
    );
    await _ledger.addTransaction(txn);
    _updateBill(bill.copyWith(
      isPaid: true,
      paidDate: paidDate ?? DateTime.now(),
      paidAmount: paidAmount,
      transactionId: txn.id,
    ));
    await _storage.saveBills(_allBills);
    await _checkAllBillsPaidXp();
    notifyListeners();
  }

  // ─── Receivable CRUD ─────────────────────────────────────────────────────────

  Future<void> addReceivable(Receivable receivable) async {
    _allReceivables = [..._allReceivables, receivable];
    await _storage.saveReceivables(_allReceivables);
    notifyListeners();
  }

  Future<void> updateReceivable(Receivable receivable) async {
    _allReceivables = [
      for (final r in _allReceivables) r.id == receivable.id ? receivable : r,
    ];
    await _storage.saveReceivables(_allReceivables);
    notifyListeners();
  }

  Future<void> deleteReceivable(String id) async {
    _allReceivables = _allReceivables.where((r) => r.id != id).toList();
    await _storage.saveReceivables(_allReceivables);
    notifyListeners();
  }

  Future<void> markReceivableReceived(
    String receivableId, {
    required double receivedAmount,
    DateTime? receivedDate,
  }) async {
    final rec = _allReceivables.firstWhere((r) => r.id == receivableId);
    final txn = _buildInflowTxn(
      id: _generateId(),
      amount: receivedAmount,
      accountId: _ledger.accounts.isNotEmpty ? _ledger.accounts.first.id : '',
      categoryId: rec.categoryId,
      description: rec.name,
      date: receivedDate ?? DateTime.now(),
      receivableId: rec.id,
    );
    await _ledger.addTransaction(txn);
    _updateReceivable(rec.copyWith(
      isReceived: true,
      receivedDate: receivedDate ?? DateTime.now(),
      receivedAmount: receivedAmount,
      transactionId: txn.id,
    ));
    await _storage.saveReceivables(_allReceivables);
    notifyListeners();
  }

  // ─── Budgeted Expense CRUD ────────────────────────────────────────────────────

  Future<void> addBudgetedExpense(BudgetedExpense expense) async {
    _allExpenses = [..._allExpenses, expense];
    await _storage.saveBudgetedExpenses(_allExpenses);
    notifyListeners();
  }

  Future<void> updateBudgetedExpense(BudgetedExpense expense) async {
    _allExpenses = [
      for (final e in _allExpenses) e.id == expense.id ? expense : e,
    ];
    await _storage.saveBudgetedExpenses(_allExpenses);
    notifyListeners();
  }

  Future<void> deleteBudgetedExpense(String id) async {
    _allExpenses = _allExpenses.where((e) => e.id != id).toList();
    await _storage.saveBudgetedExpenses(_allExpenses);
    notifyListeners();
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
    await _storage.saveBudgetedExpenses(_allExpenses);
    notifyListeners();
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

  Future<void> _autoGenerateRecurringBills(String month) async {
    final existing = _allBills.where((b) => b.month == month).toList();
    if (existing.isNotEmpty) return;

    final prev = previousMonth(month);
    final recurringFromPrev = _allBills
        .where((b) => b.month == prev && b.isRecurring)
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
    final recurringFromPrev = _allReceivables
        .where((r) => r.month == prev && r.isRecurring)
        .toList();
    if (recurringFromPrev.isEmpty) return;

    final copies = recurringFromPrev.map((r) {
      final expectedDate = DateTime.parse('$month-${r.expectedDate.day.toString().padLeft(2, '0')}');
      return Receivable(
        id: _generateId(),
        name: r.name,
        receivableType: r.receivableType,
        amount: r.nextMonthAmount ?? r.amount,
        expectedDate: expectedDate,
        month: month,
        categoryId: r.categoryId,
        isRecurring: r.isRecurring,
        recurrenceType: r.recurrenceType,
      );
    });
    _allReceivables = [..._allReceivables, ...copies];
    await _storage.saveReceivables(_allReceivables);
  }
}
