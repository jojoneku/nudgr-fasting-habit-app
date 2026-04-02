import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

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
      .where((t) =>
          t.month == _currentMonth && t.type == TransactionType.inflow)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get monthTotalOutflow => _transactions
      .where((t) =>
          t.month == _currentMonth && t.type == TransactionType.outflow)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get netWorth {
    final assets = _accounts
        .where((a) => a.isActive && !a.isLiability)
        .fold(0.0, (sum, a) => sum + a.balance);
    return assets - totalLiabilities;
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
    _currentMonth = toMonthKey(DateTime.now());

    _isLoading = false;
    notifyListeners();
  }
}
