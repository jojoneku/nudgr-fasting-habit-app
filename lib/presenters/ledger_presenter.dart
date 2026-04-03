import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class LedgerPresenter extends ChangeNotifier {
  LedgerPresenter(StorageService storage, StatsPresenter stats)
      : _storage = storage,
        _stats = stats {
    load();
  }

  final StorageService _storage;
  final StatsPresenter _stats;

  bool _isLoading = true;
  String _selectedMonth = toMonthKey(DateTime.now());
  String? _selectedAccountId;

  List<FinancialAccount> _accounts = [];
  List<FinanceCategory> _categories = [];
  List<TransactionRecord> _allTransactions = [];

  // --- Public state ---

  bool get isLoading => _isLoading;
  String get selectedMonth => _selectedMonth;
  String? get selectedAccountId => _selectedAccountId;
  List<FinancialAccount> get accounts => _accounts;
  List<FinanceCategory> get categories => _categories;

  // --- Filtered summary ---

  double get filteredMonthInflow => _filteredTransactions
      .where((t) => t.type == TransactionType.inflow)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get filteredMonthOutflow => _filteredTransactions
      .where((t) => t.type == TransactionType.outflow)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get filteredAccountBalance {
    if (_selectedAccountId == null) return 0.0;
    final account = _accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
    return account?.balance ?? 0.0;
  }

  /// Transactions in [selectedMonth] filtered by [selectedAccountId].
  /// In "All" view: deduplicates transfers — keeps only the outflow leg.
  /// In single-account view: shows both legs belonging to that account.
  Map<DateTime, List<TransactionRecord>> get groupedTransactions {
    final txns = _filteredTransactions;
    final grouped = <DateTime, List<TransactionRecord>>{};
    for (final txn in txns) {
      final day = DateTime(txn.date.year, txn.date.month, txn.date.day);
      grouped.putIfAbsent(day, () => []).add(txn);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => b.date.compareTo(a.date));
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in sortedKeys) k: grouped[k]!};
  }

  // --- Filter controls ---

  void setMonth(String month) {
    _selectedMonth = month;
    notifyListeners();
  }

  void setAccount(String? id) {
    _selectedAccountId = id;
    notifyListeners();
  }

  // --- Load ---

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _accounts = await _storage.loadAccounts();
    _categories = await _storage.loadFinanceCategories();
    _allTransactions = await _storage.loadTransactions();

    _isLoading = false;
    notifyListeners();
  }

  // --- Transaction CRUD ---

  Future<void> addTransaction(TransactionRecord txn) async {
    final isFirstEver = _allTransactions.isEmpty;
    final isFirstToday = !_hasTransactionToday();

    _allTransactions = [..._allTransactions, txn];
    _applyBalanceDelta(txn.accountId, txn.amount, txn.type);
    await _saveAll();

    if (isFirstEver) await _stats.addXp(25);
    if (isFirstToday) await _stats.addXp(10);

    notifyListeners();
  }

  Future<void> addTransfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    required String categoryId,
    required String description,
    required DateTime date,
    String? note,
  }) async {
    final groupId = _generateId();
    final monthKey = toMonthKey(date);

    final outflow = TransactionRecord(
      id: _generateId(),
      date: date,
      accountId: fromAccountId,
      categoryId: categoryId,
      amount: amount,
      type: TransactionType.outflow,
      description: description,
      note: note,
      month: monthKey,
      transferToAccountId: toAccountId,
      transferGroupId: groupId,
    );
    final inflow = TransactionRecord(
      id: _generateId(),
      date: date,
      accountId: toAccountId,
      categoryId: categoryId,
      amount: amount,
      type: TransactionType.inflow,
      description: description,
      note: note,
      month: monthKey,
      transferGroupId: groupId,
    );

    _allTransactions = [..._allTransactions, outflow, inflow];
    _applyBalanceDelta(fromAccountId, amount, TransactionType.outflow);
    _applyBalanceDelta(toAccountId, amount, TransactionType.inflow);
    await _saveAll();
    notifyListeners();
  }

  Future<void> updateTransaction(TransactionRecord txn) async {
    final old = _allTransactions.firstWhere((t) => t.id == txn.id);
    _reverseBalanceDelta(old.accountId, old.amount, old.type);
    _applyBalanceDelta(txn.accountId, txn.amount, txn.type);
    _allTransactions = [
      for (final t in _allTransactions) t.id == txn.id ? txn : t,
    ];
    await _saveAll();
    notifyListeners();
  }

  Future<void> deleteTransaction(String id) async {
    final txn = _allTransactions.firstWhere((t) => t.id == id);
    _reverseBalanceDelta(txn.accountId, txn.amount, txn.type);
    _allTransactions = _allTransactions.where((t) => t.id != id).toList();
    await _saveAll();
    notifyListeners();
  }

  /// Upserts an account (used for filter chips and add-sheet in ledger view).
  Future<void> saveAccount(FinancialAccount account) async {
    final exists = _accounts.any((a) => a.id == account.id);
    _accounts = exists
        ? [for (final a in _accounts) a.id == account.id ? account : a]
        : [..._accounts, account];
    await _storage.saveAccounts(_accounts);
    notifyListeners();
  }

  // --- Category CRUD ---

  Future<void> addCategory(FinanceCategory category) async {
    _categories = [..._categories, category];
    await _storage.saveFinanceCategories(_categories);
    notifyListeners();
  }

  Future<void> deleteCategory(String id) async {
    _categories = _categories.where((c) => c.id != id).toList();
    await _storage.saveFinanceCategories(_categories);
    notifyListeners();
  }

  // --- Private helpers ---

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  bool _hasTransactionToday() {
    final today = DateTime.now();
    return _allTransactions.any((t) =>
        t.date.year == today.year &&
        t.date.month == today.month &&
        t.date.day == today.day);
  }

  void _applyBalanceDelta(
      String accountId, double amount, TransactionType type) {
    _accounts = [
      for (final a in _accounts)
        a.id == accountId
            ? a.copyWith(
                balance: type == TransactionType.inflow
                    ? a.balance + amount
                    : a.balance - amount,
              )
            : a,
    ];
  }

  void _reverseBalanceDelta(
      String accountId, double amount, TransactionType type) {
    _applyBalanceDelta(
      accountId,
      amount,
      type == TransactionType.inflow
          ? TransactionType.outflow
          : TransactionType.inflow,
    );
  }

  Future<void> _saveAll() async {
    await Future.wait([
      _storage.saveTransactions(_allTransactions),
      _storage.saveAccounts(_accounts),
    ]);
  }

  List<TransactionRecord> get _filteredTransactions {
    final inMonth =
        _allTransactions.where((t) => t.month == _selectedMonth).toList();

    if (_selectedAccountId != null) {
      return inMonth.where((t) => t.accountId == _selectedAccountId).toList();
    }

    // All-accounts view: deduplicate transfers — keep only outflow leg.
    return inMonth
        .where((t) =>
            t.transferGroupId == null || t.type == TransactionType.outflow)
        .toList();
  }
}
