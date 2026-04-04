import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

// Auto-created system category for installment payments.
const _installmentCategoryId = '__installment__';

class InstallmentPresenter extends ChangeNotifier {
  InstallmentPresenter(
      StorageService storage, LedgerPresenter ledger, StatsPresenter stats)
      : _storage = storage,
        _ledger = ledger,
        _stats = stats {
    load();
  }

  final StorageService _storage;
  final LedgerPresenter _ledger;
  final StatsPresenter _stats;

  bool _isLoading = true;
  String _selectedMonth = toMonthKey(DateTime.now());
  List<Installment> _installments = [];

  // ─── Public state ─────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String get selectedMonth => _selectedMonth;
  List<FinancialAccount> get accounts => _ledger.accounts;

  void setMonth(String month) {
    _selectedMonth = month;
    notifyListeners();
  }

  // ─── Installment views ────────────────────────────────────────────────────────

  List<Installment> get installments =>
      _installments.where((i) => i.isActive).toList();

  List<Installment> get dueThisMonth => _installments
      .where((i) => i.isActive && i.isDueIn(_selectedMonth))
      .toList();

  bool isPaidForMonth(String installmentId) => _ledger.allTransactions.any(
        (t) => t.installmentId == installmentId && t.month == _selectedMonth,
      );

  int paidCount(String installmentId) => _ledger.allTransactions
      .where((t) => t.installmentId == installmentId)
      .length;

  int remainingMonths(String installmentId) {
    final inst = _findById(installmentId);
    return (inst.totalMonths - paidCount(installmentId))
        .clamp(0, inst.totalMonths);
  }

  double remainingAmount(String installmentId) {
    final inst = _findById(installmentId);
    return remainingMonths(installmentId) * inst.monthlyAmount;
  }

  double get totalDueThisMonth =>
      dueThisMonth.fold(0.0, (sum, i) => sum + i.monthlyAmount);

  double get totalPaidThisMonth => dueThisMonth
      .where((i) => isPaidForMonth(i.id))
      .fold(0.0, (sum, i) => sum + i.monthlyAmount);

  // ─── Load ─────────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _installments = await _storage.loadInstallments();
    _isLoading = false;
    notifyListeners();
  }

  // ─── CRUD ─────────────────────────────────────────────────────────────────────

  Future<void> addInstallment(Installment i) async {
    _installments = [..._installments, i];
    await _storage.saveInstallments(_installments);
    notifyListeners();
  }

  Future<void> updateInstallment(Installment i) async {
    _installments = [
      for (final inst in _installments) inst.id == i.id ? i : inst
    ];
    await _storage.saveInstallments(_installments);
    notifyListeners();
  }

  Future<void> deleteInstallment(String id) async {
    final linked =
        _ledger.allTransactions.where((t) => t.installmentId == id).toList();
    for (final txn in linked) {
      await _ledger.deleteTransaction(txn.id);
    }
    _installments = _installments.where((i) => i.id != id).toList();
    await _storage.saveInstallments(_installments);
    notifyListeners();
  }

  // ─── Mark paid / unpaid ───────────────────────────────────────────────────────

  Future<void> markPaid(
    String installmentId, {
    double? overrideAmount,
    DateTime? date,
  }) async {
    if (isPaidForMonth(installmentId)) return;
    final inst = _findById(installmentId);
    await _ensureInstallmentCategory();

    final count = paidCount(installmentId) + 1;
    final txn = TransactionRecord(
      id: _generateId(),
      date: date ?? DateTime.now(),
      accountId: inst.accountId,
      categoryId: _installmentCategoryId,
      amount: overrideAmount ?? inst.monthlyAmount,
      type: TransactionType.outflow,
      description: '${inst.name} — Payment $count/${inst.totalMonths}',
      month: _selectedMonth,
      installmentId: installmentId,
    );
    await _ledger.addTransaction(txn);

    if (count >= inst.totalMonths) await _stats.addXp(50);

    final allDuePaid = dueThisMonth.every(
      (i) => i.id == installmentId || isPaidForMonth(i.id),
    );
    if (allDuePaid && dueThisMonth.isNotEmpty) await _stats.addXp(20);

    notifyListeners();
  }

  Future<void> markUnpaid(String installmentId) async {
    final txn = _ledger.allTransactions.firstWhere(
      (t) => t.installmentId == installmentId && t.month == _selectedMonth,
      orElse: () => throw StateError('no_txn'),
    );
    await _ledger.deleteTransaction(txn.id);
    notifyListeners();
  }

  // ─── Private helpers ──────────────────────────────────────────────────────────

  Installment _findById(String id) =>
      _installments.firstWhere((i) => i.id == id);

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  Future<void> _ensureInstallmentCategory() async {
    final exists =
        _ledger.categories.any((c) => c.id == _installmentCategoryId);
    if (!exists) {
      await _ledger.addCategory(const FinanceCategory(
        id: _installmentCategoryId,
        name: 'Installment',
        type: CategoryType.expense,
        icon: 'credit_card',
        colorHex: '#9C27B0',
      ));
    }
  }
}
