import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/services/notification_service.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/finance_flows.dart';
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
    // Guard against a cold-start race: BudgetPresenter subscribes to the ledger
    // in its constructor, and on startup every presenter's load() runs
    // concurrently. The ledger's load() notifies after loading transactions,
    // which fires _syncFromLedger -> _checkBudgetWarnings. If that happens
    // before our own load() has restored the persisted warned-keys, the warned
    // set is still empty and prefs are still defaults, so every over-threshold
    // budget re-fires its alert on launch (the symptom PR #274 only partly
    // fixed). Skip until load() has restored state.
    if (!_warnedKeysLoaded) return;
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
  List<BudgetGroupDef> _groups = BudgetGroupDef.defaultGroups;
  List<FinanceCategory> _categories = [];
  List<TransactionRecord> _allTransactions = [];
  List<FinancialAccount> _accounts = [];

  /// Tracks which budgets have already triggered a warning this session.
  /// Resets when spending drops below threshold so the warning re-fires next month.
  final Set<String> _warnedBudgets = {};

  /// True once [load] has restored the persisted warned-keys (and cached prefs).
  /// Until then [_checkBudgetWarnings] must not fire — see the guard there.
  bool _warnedKeysLoaded = false;

  /// Cached notification preferences — loaded in [load()] and used by [_syncFromLedger].
  NotificationPreferences _cachedNotifPrefs =
      NotificationPreferences.defaults();

  // ─── Public state ────────────────────────────────────────────────────────────

  String get selectedMonth => _selectedMonth;

  void setMonth(String month) {
    _selectedMonth = month;
    notifyListeners();
  }

  // ─── Group getters ────────────────────────────────────────────────────────────

  List<BudgetGroupDef> get groups => List.unmodifiable(_groups);

  List<BudgetGroupDef> get expenseGroups =>
      _groups.where((g) => !g.isSavings).toList();

  BudgetGroupDef? groupById(String id) =>
      _groups.where((g) => g.id == id).firstOrNull;

  bool _isSavingsGroup(String groupId) =>
      _groups.where((g) => g.id == groupId).firstOrNull?.isSavings ?? false;

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

  /// Human label for a group ID — shared by the web chart + table.
  String budgetGroupLabel(String groupId) =>
      _groups.where((g) => g.id == groupId).firstOrNull?.name ?? groupId;

  /// Ordered allocated-vs-spent figures per group that actually has a budget
  /// this month. Drives the web allocation bar chart so `build()` stays
  /// free of folds and filtering.
  List<WebBudgetGroupBar> get groupBars {
    final result = <WebBudgetGroupBar>[];
    for (final group in _groups) {
      final allocated = sectionAllocated(group.id);
      if (allocated <= 0) continue;
      result.add(WebBudgetGroupBar(
        groupId: group.id,
        label: group.name,
        allocated: allocated,
        spent: sectionSpent(group.id),
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
    for (final group in expenseGroups) {
      for (final cat in byGroup[group.id] ?? const <FinanceCategory>[]) {
        final budget = budgetFor(cat.id);
        final allocated = budget?.allocatedAmount ?? 0.0;
        final spent = spentFor(cat.id);
        rows.add(WebBudgetRow(
          targetId: cat.id,
          name: cat.name,
          groupId: group.id,
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
        groupId: BudgetGroupDef.idSavings,
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
  /// month, grouped by group ID string. The savings group is rendered separately
  /// via [savingsBudgets].
  Map<String, List<FinanceCategory>> get categoriesByGroup {
    final result = <String, List<FinanceCategory>>{
      for (final g in expenseGroups) g.id: [],
    };
    for (final b in _budgetsForMonth) {
      if (_isSavingsGroup(b.group)) continue;
      final matches = _categories.where((c) => c.id == b.categoryId);
      if (matches.isEmpty) continue;
      result.putIfAbsent(b.group, () => []).add(matches.first);
    }
    return result;
  }

  /// Savings/goal budgets for the selected month. Each entry pairs the budget
  /// with its target account. Filters out budgets whose account no longer
  /// exists.
  List<({Budget budget, FinancialAccount account})> get savingsBudgets {
    final result = <({Budget budget, FinancialAccount account})>[];
    for (final b in _budgetsForMonth.where((b) => _isSavingsGroup(b.group))) {
      final acct = _accounts.where((a) => a.id == b.categoryId).firstOrNull;
      if (acct != null) result.add((budget: b, account: acct));
    }
    return result;
  }

  double sectionAllocated(String groupId) => _budgetsForMonth
      .where((b) => b.group == groupId)
      .fold(0.0, (sum, b) => sum + b.allocatedAmount);

  double sectionSpent(String groupId) {
    if (_isSavingsGroup(groupId)) {
      return savingsBudgets.fold(
        0.0,
        (sum, e) => sum + contributedTo(e.account.id),
      );
    }
    final catIds = _budgetsForMonth
        .where((b) => b.group == groupId)
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

  double receivedFor(String categoryId) {
    final reimb = reimbursementReceivableIds(_allTransactions);
    return _allTransactions
        .where((t) =>
            t.month == _selectedMonth &&
            t.categoryId == categoryId &&
            isIncomeInflow(t, reimb))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

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
    if (budget != null && _isSavingsGroup(budget.group)) {
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
    String? group,
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
        group: group ?? BudgetGroupDef.idVariableOptional,
        budgetType: budgetType ?? BudgetType.monthly,
      );
      _allBudgets = [..._allBudgets, newBudget];
    }
    // Optimistic: repaint before persisting.
    notifyListeners();
    await _storage.saveBudgets(_allBudgets);
    await _checkBudgetNotExceededXp();
  }

  // ─── Group CRUD ───────────────────────────────────────────────────────────────

  Future<void> addGroup(String name) async {
    final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    final sortOrder =
        _groups.fold(0, (max, g) => g.sortOrder > max ? g.sortOrder : max) + 1;
    _groups = [
      ..._groups,
      BudgetGroupDef(
        id: id,
        name: name,
        isSavings: false,
        isBuiltIn: false,
        sortOrder: sortOrder,
      ),
    ];
    notifyListeners();
    await _saveGroups();
  }

  Future<void> renameGroup(String id, String name) async {
    _groups = [
      for (final g in _groups) g.id == id ? g.copyWith(name: name) : g,
    ];
    notifyListeners();
    await _saveGroups();
  }

  Future<void> deleteGroup(String id) async {
    // Reassign budgets in this group to the first non-savings built-in group.
    final fallback = expenseGroups.isNotEmpty
        ? expenseGroups.first.id
        : BudgetGroupDef.idVariableOptional;
    _allBudgets = [
      for (final b in _allBudgets)
        b.group == id ? b.copyWith(group: fallback) : b,
    ];
    _groups = _groups.where((g) => g.id != id).toList();
    notifyListeners();
    await _storage.saveBudgets(_allBudgets);
    await _saveGroups();
  }

  Future<void> _saveGroups() async {
    // Persist only non-defaults OR customised defaults (name changes).
    // We always save the full list so merge() on reload picks up overrides.
    await _storage.saveBudgetGroups(_groups);
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
    _groups = BudgetGroupDef.merge(await _storage.loadBudgetGroups());
    _categories = await _storage.loadFinanceCategories();
    _allTransactions = await _storage.loadTransactions();
    _accounts = await _storage.loadAccounts();
    _cachedNotifPrefs = await _storage.loadNotificationPreferences();
    // Restore which budgets have already warned (persisted across restarts) so
    // the over-threshold alert doesn't re-fire on every cold reopen.
    _warnedBudgets
      ..clear()
      ..addAll(await _storage.loadWarnedBudgetKeys());
    // Mark state restored BEFORE the first check so the guard in
    // _checkBudgetWarnings lets it run, while any earlier ledger-driven
    // _syncFromLedger calls (which lost the startup race) were correctly skipped.
    _warnedKeysLoaded = true;
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

/// Allocated-vs-spent totals for one group — feeds the web allocation
/// bar chart (Plan 050-D).
class WebBudgetGroupBar {
  final String groupId;
  final String label;
  final double allocated;
  final double spent;

  const WebBudgetGroupBar({
    required this.groupId,
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
  final String groupId;
  final double allocated;
  final double spent;
  final double remaining;

  /// Clamped 0.0–1.0 fill for the progress cell.
  final double progress;
  final bool isOver;

  const WebBudgetRow({
    required this.targetId,
    required this.name,
    required this.groupId,
    required this.allocated,
    required this.spent,
    required this.remaining,
    required this.progress,
    required this.isOver,
  });
}
