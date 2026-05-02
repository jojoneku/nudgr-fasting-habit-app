import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class DailySpend {
  final DateTime date;
  final double amount;
  const DailySpend(this.date, this.amount);
}

class TreasuryDashboardPresenter extends ChangeNotifier {
  TreasuryDashboardPresenter(StorageService storage) : _storage = storage {
    load();
  }

  final StorageService _storage;

  bool _isLoading = true;
  List<FinancialAccount> _accounts = [];
  List<TransactionRecord> _transactions = [];
  List<Bill> _bills = [];
  List<Receivable> _receivables = [];
  List<Budget> _budgets = [];
  List<BudgetedExpense> _budgetedExpenses = [];
  List<FinanceCategory> _categories = [];
  String _currentMonth = toMonthKey(DateTime.now());

  // --- Public state ---

  bool get isLoading => _isLoading;
  String get currentMonth => _currentMonth;
  bool get hasAccounts => _accounts.any((a) => a.isActive);

  // --- Account views ---

  List<FinancialAccount> get liquidAccounts => _accounts
      .where((a) => a.isActive && a.isLiquid && a.parentAccountId == null)
      .toList();

  List<FinancialAccount> get liabilityAccounts =>
      _accounts.where((a) => a.isActive && a.isLiability).toList();

  List<FinancialAccount> get goalAccounts => _accounts
      .where((a) => a.isActive && a.category == AccountCategory.goal)
      .toList();

  List<FinancialAccount> get savingsAccounts => _accounts
      .where((a) => a.isActive && a.category == AccountCategory.savings)
      .toList();

  List<FinancialAccount> subAccountsOf(String parentId) =>
      _accounts.where((a) => a.parentAccountId == parentId).toList();

  // --- Summary values ---

  double get totalLiquidCash =>
      liquidAccounts.fold(0.0, (sum, a) => sum + a.balance);

  double get totalLiabilities =>
      liabilityAccounts.fold(0.0, (sum, a) => sum + a.balance);

  double get pendingReceivables => _receivables
      .where((r) => r.month == _currentMonth && !r.isReceived)
      .fold(0.0, (sum, r) => sum + r.amount);

  double get monthUnpaidBills => _bills
      .where((b) => b.month == _currentMonth && !b.isPaid)
      .fold(0.0, (sum, b) => sum + b.amount);

  double get endingCash =>
      totalLiquidCash + pendingReceivables - monthUnpaidBills;

  double get monthTotalInflow => _transactions
      .where(
          (t) => t.month == _currentMonth && t.type == TransactionType.inflow)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get monthTotalOutflow => _transactions
      .where(
          (t) => t.month == _currentMonth && t.type == TransactionType.outflow)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get netWorth {
    final assets = _accounts
        .where((a) => a.isActive && !a.isLiability && !a.isCustodian)
        .fold(0.0, (sum, a) => sum + a.balance);
    return assets - totalLiabilities;
  }

  List<FinancialAccount> get custodianAccounts =>
      _accounts.where((a) => a.isActive && a.isCustodian).toList();

  /// Returns the total held (custodian) amount linked to each liquid account id.
  Map<String, double> get heldAmountByAccountId {
    final result = <String, double>{};
    for (final c in custodianAccounts) {
      if (c.linkedAccountId != null) {
        result[c.linkedAccountId!] =
            (result[c.linkedAccountId!] ?? 0.0) + c.balance;
      }
    }
    return result;
  }

  // --- Bills ---

  List<Bill> get upcomingBills =>
      _bills.where((b) => b.month == _currentMonth && !b.isPaid).toList()
        ..sort((a, b) => a.dueDay.compareTo(b.dueDay));

  bool get hasBills => upcomingBills.isNotEmpty;

  bool get hasBillImminent {
    final today = DateTime.now().day;
    return upcomingBills.any((b) => b.dueDay == today || b.dueDay == today + 1);
  }

  Bill? get imminentBill {
    final today = DateTime.now().day;
    return upcomingBills
        .where((b) => b.dueDay == today || b.dueDay == today + 1)
        .firstOrNull;
  }

  double get todayOutflow {
    final now = DateTime.now();
    return _transactions.where((t) {
      return t.type == TransactionType.outflow &&
          t.date.year == now.year &&
          t.date.month == now.month &&
          t.date.day == now.day;
    }).fold(0.0, (sum, t) => sum + t.amount);
  }

  bool isBillOverdue(Bill bill) => bill.dueDay < DateTime.now().day;

  // --- Budget ---

  bool get hasBudget =>
      _budgets.any((b) => b.month == _currentMonth) ||
      _budgetedExpenses.any((e) => e.month == _currentMonth);

  double get totalBudgetAllocated => _budgets
      .where((b) => b.month == _currentMonth)
      .fold(0.0, (sum, b) => sum + b.allocatedAmount);

  double get totalBudgetSpent => _budgetedExpenses
      .where((e) => e.month == _currentMonth)
      .fold(0.0, (sum, e) => sum + e.spentAmount);

  double get totalBudgetRemaining =>
      (totalBudgetAllocated - totalBudgetSpent).clamp(0.0, double.infinity);

  double get forecastedNetBalance => endingCash - totalBudgetRemaining;

  Map<BudgetGroup, double> get budgetAllocatedByGroup {
    final result = <BudgetGroup, double>{};
    for (final b in _budgets.where((b) => b.month == _currentMonth)) {
      result[b.group] = (result[b.group] ?? 0.0) + b.allocatedAmount;
    }
    return result;
  }

  Map<BudgetGroup, double> get budgetSpentByGroup {
    final result = <BudgetGroup, double>{};
    for (final e in _budgetedExpenses.where((e) => e.month == _currentMonth)) {
      final budget = _budgets
          .where(
              (b) => b.month == _currentMonth && b.categoryId == e.categoryId)
          .firstOrNull;
      if (budget != null) {
        result[budget.group] = (result[budget.group] ?? 0.0) + e.spentAmount;
      }
    }
    return result;
  }

  // --- Category spend (pie chart) ---

  /// Returns top expense categories by spend for the current month.
  /// Each entry: (category, amount). Sorted descending. Max 6 slices + "Other".
  List<(FinanceCategory, double)> get categorySpendThisMonth =>
      _categorySpendRanked(limit: 10);

  /// All categories with spend, no limit — used by the full breakdown sheet.
  List<(FinanceCategory, double)> get allCategorySpendThisMonth =>
      _categorySpendRanked(limit: null);

  bool get hasCategorySpend => categorySpendThisMonth.isNotEmpty;

  List<(FinanceCategory, double)> _categorySpendRanked({required int? limit}) {
    final spendMap = <String, double>{};
    for (final t in _transactions) {
      if (t.month == _currentMonth && t.type == TransactionType.outflow) {
        spendMap[t.categoryId] = (spendMap[t.categoryId] ?? 0.0) + t.amount;
      }
    }
    if (spendMap.isEmpty) return [];

    final sorted = spendMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final resolved = <(FinanceCategory, double)>[];
    double otherTotal = 0.0;

    for (int i = 0; i < sorted.length; i++) {
      final cat = _categories.where((c) => c.id == sorted[i].key).firstOrNull;
      if ((limit == null || i < limit) && cat != null) {
        resolved.add((cat, sorted[i].value));
      } else {
        otherTotal += sorted[i].value;
      }
    }

    if (otherTotal > 0 && limit != null) {
      final other = FinanceCategory(
        id: '__other__',
        name: 'Other',
        type: CategoryType.expense,
        icon: 'dots-horizontal',
        colorHex: '#607D8B',
      );
      resolved.add((other, otherTotal));
    }

    return resolved;
  }

  // --- Spending analytics ---

  List<DailySpend> get last7DaysSpending => _lastNDaysSpending(7);

  /// Flexible — used by the full spending history sheet.
  List<DailySpend> lastNDaysSpending(int n) => _lastNDaysSpending(n);

  List<DailySpend> _lastNDaysSpending(int n) {
    final now = DateTime.now();
    return List.generate(n, (i) {
      final day = DateTime(now.year, now.month, now.day - (n - 1 - i));
      final total = _transactions
          .where((t) =>
              t.type == TransactionType.outflow &&
              t.date.year == day.year &&
              t.date.month == day.month &&
              t.date.day == day.day)
          .fold(0.0, (sum, t) => sum + t.amount);
      return DailySpend(day, total);
    });
  }

  double get avgDailySpend7 {
    final days = last7DaysSpending;
    final nonZero = days.where((d) => d.amount > 0).toList();
    if (nonZero.isEmpty) return 0.0;
    return nonZero.fold(0.0, (s, d) => s + d.amount) / nonZero.length;
  }

  double get peakDaySpend7 =>
      last7DaysSpending.fold(0.0, (max, d) => d.amount > max ? d.amount : max);

  DateTime? get peakSpendDay {
    final days = last7DaysSpending;
    if (days.every((d) => d.amount == 0)) return null;
    return days.reduce((a, b) => a.amount >= b.amount ? a : b).date;
  }

  // --- Account CRUD ---

  Future<void> addAccount(FinancialAccount account) async {
    _accounts = [..._accounts, account];
    await _storage.saveAccounts(_accounts);
    notifyListeners();
  }

  Future<void> updateAccount(FinancialAccount account) async {
    _accounts = [
      for (final a in _accounts) a.id == account.id ? account : a,
    ];
    await _storage.saveAccounts(_accounts);
    notifyListeners();
  }

  /// Throws [StateError('has_sub_accounts')] if the account has sub-accounts.
  Future<void> deleteAccount(String id) async {
    final hasSubs = _accounts.any((a) => a.parentAccountId == id);
    if (hasSubs) throw StateError('has_sub_accounts');
    _accounts = _accounts.where((a) => a.id != id).toList();
    await _storage.saveAccounts(_accounts);
    notifyListeners();
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _accounts = await _storage.loadAccounts();
    _transactions = await _storage.loadTransactions();
    _bills = await _storage.loadBills();
    _receivables = await _storage.loadReceivables();
    _budgets = await _storage.loadBudgets();
    _budgetedExpenses = await _storage.loadBudgetedExpenses();
    _categories = await _storage.loadFinanceCategories();
    _currentMonth = toMonthKey(DateTime.now());

    _isLoading = false;
    notifyListeners();
  }
}
