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
  /// configured percentage for the first time THIS MONTH. The warned set is
  /// keyed "YYYY-MM/budgetId" and persisted, so a warning fires once per
  /// month-crossing and does NOT re-fire every time the app is reopened (the
  /// previous in-memory-only set reset on each cold start → repeated alerts).
  Future<void> _checkBudgetWarnings(NotificationPreferences prefs) async {
    if (!prefs.budgetWarningEnabled) return;
    final threshold = prefs.budgetWarningPercent / 100.0;
    var changed = false;
    for (final budget in _budgetsForMonth) {
      final spent = spentFor(budget.categoryId);
      final limit = budget.allocatedAmount;
      if (limit <= 0) continue;
      final pct = spent / limit;
      final key = '$_selectedMonth/${budget.id}';
      if (pct >= threshold && !_warnedBudgets.contains(key)) {
        _warnedBudgets.add(key);
        changed = true;
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
      } else if (pct < threshold && _warnedBudgets.contains(key)) {
        // Dropped back below — allow it to warn again if it re-crosses.
        _warnedBudgets.remove(key);
        changed = true;
      }
    }
    if (changed) await _storage.saveWarnedBudgetKeys(_warnedBudgets);
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

  /// Fraction of the total allocation already spent (0.0–∞). Returns 0 when
  /// nothing is allocated so the UI can avoid a divide-by-zero in `build()`.
  double get percentUsed =>
      totalAllocated > 0 ? totalSpent / totalAllocated : 0.0;

  // ─── Web aggregates (Plan 050-D) ───────────────────────────────────────────────

  /// Human label for a [BudgetGroup] — shared by the web chart + table.
  static String budgetGroupLabel(BudgetGroup group) => switch (group) {
        BudgetGroup.nonNegotiables => 'Non-Negotiables',
        BudgetGroup.livingExpense => 'Living Expense',
        BudgetGroup.variableOptional => 'Variable / Optional',
        BudgetGroup.savings => 'Savings / Goals',
      };

  /// Ordered allocated-vs-spent figures per [BudgetGroup] that actually has a
  /// budget this month. Drives the web allocation bar chart so `build()` stays
  /// free of folds and filtering.
  List<WebBudgetGroupBar> get groupBars {
    final result = <WebBudgetGroupBar>[];
    for (final group in BudgetGroup.values) {
      final allocated = sectionAllocated(group);
      if (allocated <= 0) continue;
      result.add(WebBudgetGroupBar(
        group: group,
        label: budgetGroupLabel(group),
        allocated: allocated,
        spent: sectionSpent(group),
      ));
    }
    return result;
  }

  /// Flat, display-ready per-category/per-target budget rows for the web data
  /// table — already grouped (expense groups first, savings last) and with all
  /// math (spent, remaining, progress, over-budget) resolved here.
  List<WebBudgetRow> get budgetRows {
    final rows = <WebBudgetRow>[];
    final byGroup = categoriesByGroup;
    for (final group in BudgetGroup.values) {
      if (group == BudgetGroup.savings) continue;
      for (final cat in byGroup[group] ?? const <FinanceCategory>[]) {
        final budget = budgetFor(cat.id);
        final allocated = budget?.allocatedAmount ?? 0.0;
        final spent = spentFor(cat.id);
        rows.add(WebBudgetRow(
          targetId: cat.id,
          name: cat.name,
          group: group,
          allocated: allocated,
          spent: spent,
          remaining: allocated - spent,
          progress: allocated > 0 ? (spent / allocated).clamp(0.0, 1.0) : 0.0,
          isOver: allocated > 0 && spent > allocated,
        ));
      }
    }
    for (final entry in savingsBudgets) {
      final allocated = entry.budget.allocatedAmount;
      final contributed = contributedTo(entry.account.id);
      rows.add(WebBudgetRow(
        targetId: entry.account.id,
        name: entry.account.name,
        group: BudgetGroup.savings,
        allocated: allocated,
        spent: contributed,
        remaining: allocated - contributed,
        progress:
            allocated > 0 ? (contributed / allocated).clamp(0.0, 1.0) : 0.0,
        // Savings rows can never be "over" — exceeding the goal is good.
        isOver: false,
      ));
    }
    return rows;
  }

  /// True when there is at least one budget row to render this month.
  bool get hasBudgets => budgetRows.isNotEmpty;

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
            t.transferGroupId == null &&
            !t.reimbursable &&
            catIds.contains(t.categoryId))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// NET contributions into [accountId] this month: inflow legs add, outflow
  /// legs subtract (transfer legs included — a transfer leg's `accountId` is the
  /// endpoint it touches). Used for savings/goal progress. Netting means a
  /// transfer *between* two savings accounts contributes zero overall instead
  /// of inflating one side, keeping the Budget page and Dashboard in agreement.
  double contributedTo(String accountId) {
    var total = 0.0;
    for (final t in _allTransactions) {
      if (t.month != _selectedMonth) continue;
      if (t.accountId != accountId) continue;
      if (t.type == TransactionType.inflow) {
        total += t.amount;
      } else if (t.type == TransactionType.outflow) {
        total -= t.amount;
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
          t.type == TransactionType.inflow &&
          t.transferGroupId == null)
      .fold(0.0, (sum, t) => sum + t.amount);

  List<TransactionRecord> transactionsForCategory(String categoryId) =>
      _allTransactions
          .where((t) =>
              t.month == _selectedMonth &&
              t.categoryId == categoryId &&
              t.transferGroupId == null)
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
            t.type == TransactionType.outflow &&
            t.transferGroupId == null &&
            !t.reimbursable)
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
    BudgetGroup? group,
    BudgetType? budgetType,
  }) async {
    final existing = budgetFor(categoryId);
    if (existing != null) {
      // copyWith treats null as "keep", so omitting group/budgetType preserves
      // them, while passing a value (e.g. the inline Group dropdown) applies it.
      _allBudgets = [
        for (final b in _allBudgets)
          b.id == existing.id
              ? b.copyWith(
                  allocatedAmount: amount,
                  group: group,
                  budgetType: budgetType,
                )
              : b,
      ];
    } else {
      final newBudget = Budget(
        id: _generateId(),
        categoryId: categoryId,
        month: _selectedMonth,
        allocatedAmount: amount,
        group: group ?? BudgetGroup.variableOptional,
        budgetType: budgetType ?? BudgetType.monthly,
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
    // Restore which budgets have already warned (persisted across restarts) so
    // the over-threshold alert doesn't re-fire on every cold reopen.
    _warnedBudgets
      ..clear()
      ..addAll(await _storage.loadWarnedBudgetKeys());
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

/// Allocated-vs-spent totals for one [BudgetGroup] — feeds the web allocation
/// bar chart (Plan 050-D).
class WebBudgetGroupBar {
  final BudgetGroup group;
  final String label;
  final double allocated;
  final double spent;

  const WebBudgetGroupBar({
    required this.group,
    required this.label,
    required this.allocated,
    required this.spent,
  });
}

/// One display-ready budget row for the web Budget table (Plan 050-D). All
/// figures are pre-computed in [BudgetPresenter.budgetRows] so the view stays
/// math-free. [targetId] is the category id for expense rows and the account
/// id for savings rows (matching the edit-sheet's `preselectedCategoryId`).
class WebBudgetRow {
  final String targetId;
  final String name;
  final BudgetGroup group;
  final double allocated;
  final double spent;
  final double remaining;

  /// Clamped 0.0–1.0 fill for the progress cell.
  final double progress;
  final bool isOver;

  const WebBudgetRow({
    required this.targetId,
    required this.name,
    required this.group,
    required this.allocated,
    required this.spent,
    required this.remaining,
    required this.progress,
    required this.isOver,
  });
}
