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
import 'package:intermittent_fasting/presenters/treasury_month_scope.dart';
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
    TreasuryMonthScope? monthScope,
  ])  : _storage = storage,
        _stats = stats,
        _ledger = ledger,
        _monthScope = monthScope,
        _notifications = notifications ?? NotificationService() {
    _ledger?.addListener(_syncFromLedger);
    if (monthScope != null) {
      _selectedMonth = monthScope.month;
      monthScope.addListener(_adoptScopeMonth);
    }
  }

  final StorageService _storage;
  final StatsPresenter _stats;
  final LedgerPresenter? _ledger;
  final NotificationService _notifications;

  /// Shared "month being read" across the Treasury tabs; null when unshared.
  final TreasuryMonthScope? _monthScope;

  /// Another tab moved the shared month — follow it.
  void _adoptScopeMonth() {
    final month = _monthScope?.month;
    if (month == null || month == _selectedMonth) return;
    setMonth(month);
  }

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
    _monthScope?.removeListener(_adoptScopeMonth);
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
    _monthScope?.setMonth(month); // keep Ledger/Bills/Installments in step
    notifyListeners();
  }

  /// Every budget across all months — this presenter owns them.
  ///
  /// Exposed so presenters that need budget-derived figures can mirror the
  /// in-memory list off a notify (as [TreasuryDashboardPresenter] does) instead
  /// of keeping a private copy that only their own `load()` refreshed.
  List<Budget> get allBudgets => List.unmodifiable(_allBudgets);

  // ─── Group getters ────────────────────────────────────────────────────────────

  /// Groups, already merged with the built-in defaults.
  List<BudgetGroupDef> get groups => List.unmodifiable(_groups);

  List<BudgetGroupDef> get expenseGroups =>
      _groups.where((g) => !g.isSavings).toList();

  BudgetGroupDef? groupById(String id) =>
      _groups.where((g) => g.id == id).firstOrNull;

  /// Whether [groupId] names a savings group — the built-in one or a
  /// user-created group flagged `isSavings`. Public because the views decide
  /// off it too: a savings row is keyed by an *account* id rather than a
  /// category id, which changes how it is picked, labelled and totalled.
  bool isSavingsGroup(String groupId) =>
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

  // ─── Pace (Nudgr budget-cards redesign) ────────────────────────────────────────
  // Pure derivations for the ring hero's on-pace pill. Pace only makes sense for
  // the in-progress month; the view hides the pill for a past/future month.

  /// True when the selected month is the current calendar month.
  bool get isCurrentMonth => _selectedMonth == toMonthKey(DateTime.now());

  /// Fraction of the selected month elapsed (0–1): 1.0 for a past month, 0.0 for
  /// a future month, today/last-day for the current month. Keeps the date math
  /// out of `build()` (Rule 1) and makes pace unit-testable without the tree.
  double get monthElapsedFraction {
    final nowKey = toMonthKey(DateTime.now());
    if (_selectedMonth.compareTo(nowKey) < 0) return 1.0;
    if (_selectedMonth.compareTo(nowKey) > 0) return 0.0;
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return (now.day / lastDay).clamp(0.0, 1.0);
  }

  /// True when spending is at or under the month's elapsed pace (a small
  /// tolerance so being exactly on pace still reads as "ahead").
  bool get isAheadOfPace => percentUsed <= monthElapsedFraction + 0.02;

  // ─── Mobile Budget sections (Nudgr budget-cards redesign) ───────────────────────

  /// Ordered, display-ready sections for the mobile Budget card list. Groups
  /// follow `sortOrder` (Living → Savings → Variable → Essentials by
  /// default; a user's manage-groups order wins). Each section carries its
  /// resolved rows and spent/allocated totals; empty groups are omitted. Visual
  /// tokens (icon glyph, color) are left to the view — the presenter stays free
  /// of Flutter material types.
  List<BudgetSection> get budgetSections {
    final ordered = [..._groups]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final sections = <BudgetSection>[];
    var colorIndex = 0;
    for (final group in ordered) {
      final rows = <BudgetSectionRow>[];
      if (group.isSavings) {
        for (final entry
            in savingsBudgets.where((e) => e.budget.group == group.id)) {
          final account = entry.account;
          final allocated = entry.budget.allocatedAmount;
          final funded = fundedInto(account.id);
          rows.add(BudgetSectionRow(
            targetId: account.id,
            name: account.name,
            colorHex: account.colorHex,
            colorIndex: colorIndex++,
            categoryType: CategoryType.income,
            isSavings: true,
            isGoal: account.category == AccountCategory.goal,
            isIncome: false,
            iconKey: account.icon,
            accountCategory: account.category,
            budgetType: entry.budget.budgetType,
            allocated: allocated,
            actual: funded,
            withdrawn: withdrawnFrom(account.id),
            progress:
                allocated > 0 ? (funded / allocated).clamp(0.0, 1.0) : 0.0,
            // Savings rows can never be "over" — exceeding the goal is good.
            isOver: false,
            overBy: 0.0,
            met: allocated > 0 && funded >= allocated,
            transactions: _transactionsForAccount(account.id),
          ));
        }
      } else {
        for (final cat
            in categoriesByGroup[group.id] ?? const <FinanceCategory>[]) {
          final budget = budgetFor(cat.id);
          final allocated = budget?.allocatedAmount ?? 0.0;
          final isIncome = isCategoryIncome(cat.id);
          final actual = isIncome ? receivedFor(cat.id) : spentFor(cat.id);
          final isOver = allocated > 0 && actual > allocated && !isIncome;
          rows.add(BudgetSectionRow(
            targetId: cat.id,
            name: cat.name,
            colorHex: cat.colorHex,
            colorIndex: colorIndex++,
            categoryType: cat.type,
            isSavings: false,
            isGoal: false,
            isIncome: isIncome,
            budgetType: budget?.budgetType ?? BudgetType.monthly,
            allocated: allocated,
            actual: actual,
            progress:
                allocated > 0 ? (actual / allocated).clamp(0.0, 1.0) : 0.0,
            isOver: isOver,
            overBy: isOver ? actual - allocated : 0.0,
            met: false,
            transactions: transactionsForCategory(cat.id),
          ));
        }
      }
      if (rows.isEmpty) continue;
      sections.add(BudgetSection(
        groupId: group.id,
        name: group.name,
        isSavings: group.isSavings,
        allocated: sectionAllocated(group.id),
        spent: sectionSpent(group.id),
        rows: rows,
      ));
    }
    return sections;
  }

  /// Distinct months (YYYY-MM) that hold at least one budget, ascending. The
  /// month picker unions these in so every month with data stays reachable —
  /// preserving the old prev/next stepping's unbounded reach.
  List<String> get monthsWithBudgets =>
      _allBudgets.map((b) => b.month).toSet().toList()..sort();

  /// Non-transfer ledger entries touching [accountId] this month, newest first —
  /// the contributions/withdrawals shown when a savings card is expanded.
  List<TransactionRecord> _transactionsForAccount(String accountId) =>
      _allTransactions
          .where((t) =>
              t.month == _selectedMonth &&
              t.accountId == accountId &&
              t.transferGroupId == null)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

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
      final funded = fundedInto(entry.account.id);
      rows.add(WebBudgetRow(
        targetId: entry.account.id,
        name: entry.account.name,
        groupId: entry.budget.group,
        allocated: allocated,
        spent: funded,
        remaining: allocated - funded,
        withdrawn: withdrawnFrom(entry.account.id),
        progress: allocated > 0 ? (funded / allocated).clamp(0.0, 1.0) : 0.0,
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
      if (isSavingsGroup(b.group)) continue;
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
    for (final b in _budgetsForMonth.where((b) => isSavingsGroup(b.group))) {
      final acct = _accounts.where((a) => a.id == b.categoryId).firstOrNull;
      if (acct != null) result.add((budget: b, account: acct));
    }
    return result;
  }

  double sectionAllocated(String groupId) => _budgetsForMonth
      .where((b) => b.group == groupId)
      .fold(0.0, (sum, b) => sum + b.allocatedAmount);

  double sectionSpent(String groupId) {
    if (isSavingsGroup(groupId)) {
      // Scoped to this group: a user-created savings group and the built-in one
      // must not each report the other's rows.
      return savingsBudgets
          .where((e) => e.budget.group == groupId)
          .fold(0.0, (sum, e) => sum + fundedInto(e.account.id));
    }
    final catIds = _budgetsForMonth
        .where((b) => b.group == groupId)
        .map((b) => b.categoryId)
        .toSet();
    final excluded = excludedCashFlowCategoryIds(_categories);
    return _allTransactions
        .where((t) =>
            t.month == _selectedMonth &&
            catIds.contains(t.categoryId) &&
            isSpendingOutflow(t, excluded))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Money funded INTO [accountId] this month — what a savings budget measures
  /// itself against.
  ///
  /// Inflow legs only. A savings budget asks "did I set aside what I planned
  /// this month?", and spending a fund on the very thing it exists for is that
  /// fund working, not a failure to fund it. Netting withdrawals off answered a
  /// different question ("what is the balance doing?") in the progress slot,
  /// which drove rows negative: a Braces fund you paid the dentist from read as
  /// −₱1,800 saved, dragged the month's total spent down with it, and left the
  /// forecast reserving money already moved. The balance question is answered
  /// on the Accounts page, where it belongs.
  ///
  /// Legs of a transfer between two savings/goal accounts are skipped, which is
  /// what the old netting was really protecting: shuffling ₱3,000 from one fund
  /// into another funds neither, and counting the destination would inflate the
  /// month. Pair this with [withdrawnFrom] to show both directions.
  double fundedInto(String accountId) {
    var total = 0.0;
    for (final t in _allTransactions) {
      if (t.month != _selectedMonth) continue;
      if (t.accountId != accountId) continue;
      if (t.type != TransactionType.inflow) continue;
      if (_isInternalSavingsTransferLeg(t)) continue;
      total += t.amount;
    }
    return total;
  }

  /// Money that left [accountId] this month. Surfaced next to [fundedInto] so a
  /// withdrawal stays visible instead of being quietly netted away — the two
  /// answer different questions and neither substitutes for the other.
  ///
  /// Every outflow leg counts, including a move into another fund: that money
  /// did leave this one. Only the *receiving* side of such a move is discounted,
  /// by [fundedInto], and only to stop it inflating the month's funding.
  double withdrawnFrom(String accountId) {
    var total = 0.0;
    for (final t in _allTransactions) {
      if (t.month != _selectedMonth) continue;
      if (t.accountId != accountId) continue;
      if (t.type == TransactionType.outflow) total += t.amount;
    }
    return total;
  }

  /// True when [leg] is one side of a transfer whose *other* side is also a
  /// savings or goal account — money moved between two funds rather than into
  /// savings from outside.
  bool _isInternalSavingsTransferLeg(TransactionRecord leg) {
    final groupId = leg.transferGroupId;
    if (groupId == null) return false;
    for (final other in _allTransactions) {
      if (other.transferGroupId != groupId) continue;
      if (other.id == leg.id) continue;
      final account =
          _accounts.where((a) => a.id == other.accountId).firstOrNull;
      if (account == null) continue;
      return account.category == AccountCategory.savings ||
          account.category == AccountCategory.goal;
    }
    return false;
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
    final excluded = excludedCashFlowCategoryIds(_categories);
    return _allTransactions
        .where((t) =>
            t.month == _selectedMonth &&
            t.categoryId == categoryId &&
            isIncomeInflow(t, reimb, excluded))
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
    if (budget != null && isSavingsGroup(budget.group)) {
      // For savings rows the "categoryId" is actually a target account id —
      // count what was funded in, not spending against a category.
      return fundedInto(categoryId);
    }
    final excluded = excludedCashFlowCategoryIds(_categories);
    return _allTransactions
        .where((t) =>
            t.month == _selectedMonth &&
            t.categoryId == categoryId &&
            isSpendingOutflow(t, excluded))
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
    await _migrateLivingIntoEssentials();
    _categories = await _storage.loadFinanceCategories();
    _allTransactions = await _storage.loadTransactions();
    _accounts = await _storage.loadAccounts();
    // After the accounts load — the repair has to recognise account ids.
    await _repairOrphanedSavingsBudgets();
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

  /// One-time merge of the retired "Living" group into "Essentials": remap any
  /// budget still on the old group id and drop a stored override for it, then
  /// persist. Idempotent — a no-op once nothing references the old id (so it's
  /// cheap to run on every load).
  Future<void> _migrateLivingIntoEssentials() async {
    const oldId = BudgetGroupDef.idLivingExpense;
    const newId = BudgetGroupDef.idNonNegotiables;

    if (_allBudgets.any((b) => b.group == oldId)) {
      _allBudgets = [
        for (final b in _allBudgets)
          b.group == oldId ? b.copyWith(group: newId) : b,
      ];
      await _storage.saveBudgets(_allBudgets);
    }

    if (_groups.any((g) => g.id == oldId)) {
      _groups = _groups.where((g) => g.id != oldId).toList();
      await _storage.saveBudgetGroups(_groups);
    }
  }

  /// Re-homes savings budgets that were persisted under an *expense* group.
  ///
  /// The web add-row used to hold its Savings toggle and the group it writes in
  /// two separate fields; after one add the group reset to Variable while the
  /// toggle stayed on Savings, so the next entry was saved with an account id
  /// under an expense group. Such a row is invisible from both directions —
  /// [categoriesByGroup] finds no category for the id, [savingsBudgets] skips
  /// it for not being in a savings group — while its allocation still counted
  /// toward [totalAllocated]. The write path is fixed; this repairs the rows
  /// already on disk.
  ///
  /// Idempotent, so it is cheap to run on every load: once no budget points at
  /// an account from an expense group it is a no-op.
  Future<void> _repairOrphanedSavingsBudgets() async {
    final savingsAccountIds = {
      for (final a in _accounts)
        if (a.category == AccountCategory.savings ||
            a.category == AccountCategory.goal)
          a.id,
    };
    if (savingsAccountIds.isEmpty) return;

    // Requiring that no category owns the id too, so a category that somehow
    // shares an account's id is never dragged into the savings group.
    bool isOrphan(Budget b) =>
        !isSavingsGroup(b.group) &&
        savingsAccountIds.contains(b.categoryId) &&
        !_categories.any((c) => c.id == b.categoryId);

    if (!_allBudgets.any(isOrphan)) return;
    _allBudgets = [
      for (final b in _allBudgets)
        isOrphan(b) ? b.copyWith(group: BudgetGroupDef.idSavings) : b,
    ];
    await _storage.saveBudgets(_allBudgets);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────────

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  List<Budget> get _budgetsForMonth =>
      _allBudgets.where((b) => b.month == _selectedMonth).toList();

  Future<void> _checkBudgetNotExceededXp() async {
    if (!_warnedKeysLoaded) return; // don't award before persisted state loads
    if (totalAllocated <= 0) return;
    if (totalSpent > totalAllocated) return;
    // Award the "stayed within budget" XP at most ONCE per month. Without a
    // guard, every setBudget call (including re-saving an unchanged budget, or
    // the web group-dropdown path) farmed 30 XP each time, corrupting the RPG
    // economy. Persist the award via the warned-keys set so the cap survives
    // restarts; the key is namespaced so it never collides with a budget id
    // ('$month/$budgetId') and the warn/unwarn loop never touches it.
    final key = '$_selectedMonth/__xp_under_budget__';
    if (_warnedBudgets.contains(key)) return;
    _warnedBudgets.add(key);
    await _storage.saveWarnedBudgetKeys(_warnedBudgets);
    await _stats.addXp(30);
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

  /// Money that left a savings target this month. Zero for expense rows, whose
  /// outflows are the [spent] figure itself. Kept beside [spent] rather than
  /// netted into it: funding a goal and drawing it down are separate facts, and
  /// collapsing them made a fund you spent from read as never funded.
  final double withdrawn;

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
    this.withdrawn = 0.0,
  });
}

/// One display-ready budget row for the mobile Budget card list
/// ([BudgetPresenter.budgetSections]). All math is resolved in the presenter;
/// the card widget resolves only the visual tokens — the icon glyph from
/// [name]/[categoryType] (or the savings/goal glyph via [isSavings]/[isGoal])
/// and the color from [colorHex]/[colorIndex]. [targetId] is the category id for
/// expense rows and the account id for savings rows (matching the edit sheet's
/// `preselectedCategoryId`).
class BudgetSectionRow {
  final String targetId;
  final String name;
  final String colorHex;

  /// Stable index into the color palette for the near-white fallback in
  /// `resolveSliceColor` — unique per row within a `budgetSections` build.
  final int colorIndex;
  final CategoryType categoryType;
  final bool isSavings;
  final bool isGoal;
  final bool isIncome;

  /// Savings rows only: the target account's stored `FinancialAccount.icon`
  /// (a badge-catalog key, the monogram sentinel, or '' for the category
  /// default) and its [AccountCategory]. Carried so the card can draw the icon
  /// the user actually picked instead of one generic savings/goal glyph for
  /// every fund. Empty/null on expense and income rows, which resolve their
  /// glyph from [name]/[categoryType] instead.
  final String iconKey;
  final AccountCategory? accountCategory;

  /// The budget's cadence type — surfaced as a small badge (expense rows only),
  /// preserving the label the old category tile showed.
  final BudgetType budgetType;
  final double allocated;

  /// Spent (expense), received (income), or funded in (savings).
  final double actual;

  /// Savings only: money that left the target this month. Held apart from
  /// [actual] rather than netted into it — funding a goal and drawing it down
  /// are separate facts, and collapsing them made a fund you spent from read as
  /// never funded at all. Zero for expense and income rows.
  final double withdrawn;

  /// Clamped 0.0–1.0 fill for the progress bar.
  final double progress;
  final bool isOver;

  /// `actual - allocated` when over (expense only); 0 otherwise.
  final double overBy;

  /// Savings only: contributions reached or exceeded the goal.
  final bool met;
  final List<TransactionRecord> transactions;

  const BudgetSectionRow({
    required this.targetId,
    required this.name,
    required this.colorHex,
    required this.colorIndex,
    required this.categoryType,
    required this.isSavings,
    required this.isGoal,
    required this.isIncome,
    required this.budgetType,
    this.iconKey = '',
    this.accountCategory,
    required this.allocated,
    required this.actual,
    required this.progress,
    required this.isOver,
    required this.overBy,
    required this.met,
    required this.transactions,
    this.withdrawn = 0.0,
  });
}

/// A budget group with its resolved rows and section totals, ordered for the
/// mobile Budget list ([BudgetPresenter.budgetSections]).
class BudgetSection {
  final String groupId;
  final String name;
  final bool isSavings;
  final double allocated;
  final double spent;
  final List<BudgetSectionRow> rows;

  const BudgetSection({
    required this.groupId,
    required this.name,
    required this.isSavings,
    required this.allocated,
    required this.spent,
    required this.rows,
  });
}
