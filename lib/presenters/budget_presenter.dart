import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class BudgetPresenter extends ChangeNotifier {
  BudgetPresenter(
    StorageService storage,
    StatsPresenter stats,
  )   : _storage = storage,
        _stats = stats;

  final StorageService _storage;
  final StatsPresenter _stats;

  String _selectedMonth = toMonthKey(DateTime.now());
  List<Budget> _allBudgets = [];
  List<FinanceCategory> _categories = [];
  List<TransactionRecord> _allTransactions = [];

  // ─── Public state ────────────────────────────────────────────────────────────

  String get selectedMonth => _selectedMonth;

  void setMonth(String month) {
    _selectedMonth = month;
    notifyListeners();
  }

  // ─── Summary getters ─────────────────────────────────────────────────────────

  double get totalAllocated =>
      _budgetsForMonth.fold(0.0, (sum, b) => sum + b.allocatedAmount);

  double get totalSpent =>
      _outflowsForMonth.fold(0.0, (sum, t) => sum + t.amount);

  double get totalRemaining => totalAllocated - totalSpent;

  // ─── Category-level getters ───────────────────────────────────────────────────

  List<FinanceCategory> get allCategories => List.unmodifiable(_categories);

  List<FinanceCategory> get expenseCategories =>
      _categories.where((c) => c.type == CategoryType.expense).toList();

  /// Returns categories that have a budget set for the selected month, grouped by BudgetGroup.
  Map<BudgetGroup, List<FinanceCategory>> get categoriesByGroup {
    final result = <BudgetGroup, List<FinanceCategory>>{
      for (final g in BudgetGroup.values) g: [],
    };
    for (final b in _budgetsForMonth) {
      final matches = _categories.where((c) => c.id == b.categoryId);
      if (matches.isEmpty) continue;
      result[b.group]!.add(matches.first);
    }
    return result;
  }

  double sectionAllocated(BudgetGroup group) => _budgetsForMonth
      .where((b) => b.group == group)
      .fold(0.0, (sum, b) => sum + b.allocatedAmount);

  double sectionSpent(BudgetGroup group) {
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

  double spentFor(String categoryId) => _allTransactions
      .where((t) =>
          t.month == _selectedMonth &&
          t.categoryId == categoryId &&
          t.type == TransactionType.outflow)
      .fold(0.0, (sum, t) => sum + t.amount);

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
    await _storage.saveBudgets(_allBudgets);
    await _checkBudgetNotExceededXp();
    notifyListeners();
  }

  Future<void> removeBudget(String categoryId) async {
    _allBudgets = _allBudgets
        .where(
            (b) => !(b.categoryId == categoryId && b.month == _selectedMonth))
        .toList();
    await _storage.saveBudgets(_allBudgets);
    notifyListeners();
  }

  // ─── Load ─────────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _allBudgets = await _storage.loadBudgets();
    _categories = await _storage.loadFinanceCategories();
    _allTransactions = await _storage.loadTransactions();
    notifyListeners();
  }

  // ─── Private helpers ──────────────────────────────────────────────────────────

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  List<Budget> get _budgetsForMonth =>
      _allBudgets.where((b) => b.month == _selectedMonth).toList();

  List<TransactionRecord> get _outflowsForMonth => _allTransactions
      .where(
          (t) => t.month == _selectedMonth && t.type == TransactionType.outflow)
      .toList();

  Future<void> _checkBudgetNotExceededXp() async {
    if (totalAllocated <= 0) return;
    if (totalSpent <= totalAllocated) await _stats.addXp(30);
  }
}
