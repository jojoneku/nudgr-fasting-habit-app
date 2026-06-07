import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/services/notification_service.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class BudgetPresenter extends ChangeNotifier {
  BudgetPresenter(
    StorageService storage,
    StatsPresenter stats, [
    LedgerPresenter? ledger,
    NotificationService? notifications,
  ])  : _storage = storage,
        _stats = stats,
        _ledger = ledger,
        _notifications = notifications ?? NotificationService() {
    _ledger?.addListener(_syncFromLedger);
  }

  final StorageService _storage;
  final StatsPresenter _stats;
  final LedgerPresenter? _ledger;
  final NotificationService _notifications;

  /// Pull transactions, accounts, and categories from LedgerPresenter so
  /// budget totals stay in sync after ledger mutations or mark-paid flows.
  void _syncFromLedger() {
    final ledger = _ledger;
    if (ledger == null) return;
    _allTransactions = ledger.allTransactions;
    _categories = ledger.categories;
    _accounts = ledger.accounts;
    notifyListeners();
    // Check budget warning thresholds asynchronously after sync.
    _checkBudgetWarnings(_cachedNotifPrefs);
  }

  /// Fire a budget-over-threshold warning for any budget that crossed the
  /// configured percentage for the first time this session.
  Future<void> _checkBudgetWarnings(NotificationPreferences prefs) async {
    if (!prefs.budgetWarningEnabled) return;
    final threshold = prefs.budgetWarningPercent / 100.0;
    for (final budget in _budgetsForMonth) {
      final spent = spentFor(budget.categoryId);
      final limit = budget.allocatedAmount;
      if (limit <= 0) continue;
      final pct = spent / limit;
      if (pct >= threshold && !_warnedBudgets.contains(budget.id)) {
        _warnedBudgets.add(budget.id);
        final catName = _categories
            .where((c) => c.id == budget.categoryId)
            .map((c) => c.name)
            .firstOrNull;
        await _notifications.showBudgetWarning(
          budget.id,
          catName ?? budget.categoryId,
          spent,
          limit,
          prefs.budgetWarningPercent,
        );
      } else if (pct < threshold) {
        // Reset so the warning fires again next time spending crosses the threshold.
        _warnedBudgets.remove(budget.id);
      }
    }
  }

  @override
  void dispose() {
    _ledger?.removeListener(_syncFromLedger);
    super.dispose();
  }

  String _selectedMonth = toMonthKey(DateTime.now());
  List<Budget> _allBudgets = [];
  List<FinanceCategory> _categories = [];
  List<TransactionRecord> _allTransactions = [];
  List<FinancialAccount> _accounts = [];

  /// Tracks which budgets have already triggered a warning this session.
  /// Resets when spending drops below threshold so the warning re-fires next month.
  final Set<String> _warnedBudgets = {};

  /// Cached notification preferences — loaded in [load()] and used by [_syncFromLedger].
  NotificationPreferences _cachedNotifPrefs =
      NotificationPreferences.defaults();

  // ─── Public state ────────────────────────────────────────────────────────────

  String get selectedMonth => _selectedMonth;

  void setMonth(String month) {
    _selectedMonth = month;
    notifyListeners();
  }

  // ─── Summary getters ─────────────────────────────────────────────────────────

  double get totalAllocated =>
      _budgetsForMonth.fold(0.0, (sum, b) => sum + b.allocatedAmount);

  /// Total "spent" across all budget rows. For expense rows that's outflows
  /// against the matched category; for savings rows it's contributions into
  /// the matched account.
  double get totalSpent =>
      _budgetsForMonth.fold(0.0, (sum, b) => sum + spentFor(b.categoryId));

  double get totalRemaining => totalAllocated - totalSpent;

  // ─── Category-level getters ───────────────────────────────────────────────────

  List<FinanceCategory> get allCategories => List.unmodifiable(_categories);

  List<FinanceCategory> get expenseCategories =>
      _categories.where((c) => c.type == CategoryType.expense).toList();

  /// Savings + goal accounts available as budget targets. Only active accounts.
  List<FinancialAccount> get savingsTargets => _accounts
      .where((a) =>
          a.isActive &&
          (a.category == AccountCategory.savings ||
              a.category == AccountCategory.goal))
      .toList();

  /// Returns categories that have an *expense* budget set for the selected
  /// month, grouped by BudgetGroup. The `savings` group is rendered separately
  /// via [savingsBudgets].
  Map<BudgetGroup, List<FinanceCategory>> get categoriesByGroup {
    final result = <BudgetGroup, List<FinanceCategory>>{
      for (final g in BudgetGroup.values)
        if (g != BudgetGroup.savings) g: [],
    };
    for (final b in _budgetsForMonth) {
      if (b.group == BudgetGroup.savings) continue;
      final matches = _categories.where((c) => c.id == b.categoryId);
      if (matches.isEmpty) continue;
      result[b.group]!.add(matches.first);
    }
    return result;
  }

  /// Savings/goal budgets for the selected month. Each entry pairs the budget
  /// with its target account. Filters out budgets whose account no longer
  /// exists.
  List<({Budget budget, FinancialAccount account})> get savingsBudgets {
    final result = <({Budget budget, FinancialAccount account})>[];
    for (final b
        in _budgetsForMonth.where((b) => b.group == BudgetGroup.savings)) {
      final acct = _accounts.where((a) => a.id == b.categoryId).firstOrNull;
      if (acct != null) result.add((budget: b, account: acct));
    }
    return result;
  }

  double sectionAllocated(BudgetGroup group) => _budgetsForMonth
      .where((b) => b.group == group)
      .fold(0.0, (sum, b) => sum + b.allocatedAmount);

  double sectionSpent(BudgetGroup group) {
    if (group == BudgetGroup.savings) {
      return savingsBudgets.fold(
        0.0,
        (sum, e) => sum + contributedTo(e.account.id),
      );
    }
    final catIds = _budgetsForMonth
        .where((b) => b.group == group)
        .map((b) => b.categoryId)
        .toSet();
    return _allTransactions
        .where((t) =>
            t.month == _selectedMonth &&
            t.type == TransactionType.outflow &&
            catIds.contains(t.categoryId))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Contributions into [accountId] this month — inflows + the receiving leg
  /// of transfers. Used for savings/goal progress.
  double contributedTo(String accountId) {
    var total = 0.0;
    for (final t in _allTransactions) {
      if (t.month != _selectedMonth) continue;
      if (t.type == TransactionType.inflow && t.accountId == accountId) {
        total += t.amount;
      } else if (t.type == TransactionType.transfer &&
          t.transferToAccountId == accountId) {
        total += t.amount;
      }
    }
    return total;
  }

  bool isCategoryIncome(String categoryId) {
    try {
      return _categories.firstWhere((c) => c.id == categoryId).type ==
          CategoryType.income;
    } catch (_) {
      return false;
    }
  }

  double receivedFor(String categoryId) => _allTransactions
      .where((t) =>
          t.month == _selectedMonth &&
          t.categoryId == categoryId &&
          t.type == TransactionType.inflow)
      .fold(0.0, (sum, t) => sum + t.amount);

  List<TransactionRecord> transactionsForCategory(String categoryId) =>
      _allTransactions
          .where((t) => t.month == _selectedMonth && t.categoryId == categoryId)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  Budget? budgetFor(String categoryId) {
    try {
      return _budgetsForMonth.firstWhere((b) => b.categoryId == categoryId);
    } catch (_) {
      return null;
    }
  }

  double spentFor(String categoryId) {
    final budget = budgetFor(categoryId);
    if (budget?.group == BudgetGroup.savings) {
      // For savings rows the "categoryId" is actually a target account id —
      // count contributions, not outflows.
      return contributedTo(categoryId);
    }
    return _allTransactions
        .where((t) =>
            t.month == _selectedMonth &&
            t.categoryId == categoryId &&
            t.type == TransactionType.outflow)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double remainingFor(String categoryId) {
    final budget = budgetFor(categoryId);
    if (budget == null) return 0.0;
    return budget.allocatedAmount - spentFor(categoryId);
  }

  bool isOverBudget(String categoryId) {
    final budget = budgetFor(categoryId);
    if (budget == null) return false;
    return spentFor(categoryId) > budget.allocatedAmount;
  }

  // ─── Budget upsert / remove ───────────────────────────────────────────────────

  Future<void> setBudget(
    String categoryId,
    double amount, {
    BudgetGroup group = BudgetGroup.variableOptional,
    BudgetType budgetType = BudgetType.monthly,
  }) async {
    final existing = budgetFor(categoryId);
    if (existing != null) {
      _allBudgets = [
        for (final b in _allBudgets)
          b.id == existing.id ? b.copyWith(allocatedAmount: amount) : b,
      ];
    } else {
      final newBudget = Budget(
        id: _generateId(),
        categoryId: categoryId,
        month: _selectedMonth,
        allocatedAmount: amount,
        group: group,
        budgetType: budgetType,
      );
      _allBudgets = [..._allBudgets, newBudget];
    }
    // Optimistic: repaint before persisting.
    notifyListeners();
    await _storage.saveBudgets(_allBudgets);
    await _checkBudgetNotExceededXp();
  }

  Future<void> removeBudget(String categoryId) async {
    _allBudgets = _allBudgets
        .where(
            (b) => !(b.categoryId == categoryId && b.month == _selectedMonth))
        .toList();
    notifyListeners();
    await _storage.saveBudgets(_allBudgets);
  }

  // ─── Load ─────────────────────────────────────────────────────────────────────

  Future<void> addCategory(FinanceCategory category) async {
    final ledger = _ledger;
    if (ledger != null) {
      // Delegate so other presenters (Ledger view, Bills view) pick it up
      // through the ledger's listener fan-out.
      await ledger.addCategory(category);
      return;
    }
    _categories = [..._categories, category];
    notifyListeners();
    await _storage.saveFinanceCategories(_categories);
  }

  Future<void> load() async {
    _allBudgets = await _storage.loadBudgets();
    _categories = await _storage.loadFinanceCategories();
    _allTransactions = await _storage.loadTransactions();
    _accounts = await _storage.loadAccounts();
    _cachedNotifPrefs = await _storage.loadNotificationPreferences();
    notifyListeners();
    await _checkBudgetWarnings(_cachedNotifPrefs);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────────

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  List<Budget> get _budgetsForMonth =>
      _allBudgets.where((b) => b.month == _selectedMonth).toList();

  Future<void> _checkBudgetNotExceededXp() async {
    if (totalAllocated <= 0) return;
    if (totalSpent <= totalAllocated) await _stats.addXp(30);
  }
}
