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
import 'package:intermittent_fasting/utils/safe_notifier.dart';

// Auto-created system category for installment payments.
const _installmentCategoryId = '__installment__';

class InstallmentPresenter extends ChangeNotifier with SafeNotifier {
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

  /// Persisted one-time-XP-award guards (see [StorageService.keyAwardedXpKeys]).
  /// Without this, the completion (+50) and all-due-paid (+20) XP were
  /// re-awardable via markUnpaid/markPaid cycles.
  final Set<String> _awardedXpKeys = {};
  bool _awardedXpLoaded = false;

  // ─── Public state ─────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String get selectedMonth => _selectedMonth;
  List<FinancialAccount> get accounts => _ledger.accounts;

  void setMonth(String month) {
    _selectedMonth = month;
    safeNotify();
  }

  /// Adopt [month] as the selected month WITHOUT notifying listeners. Safe to
  /// call from a `build` method (e.g. the web bills page keeps the installment
  /// view aligned with the month the user is browsing). A no-op — and crucially
  /// no rebuild loop — when the month already matches.
  void syncMonth(String month) {
    if (_selectedMonth == month) return;
    _selectedMonth = month;
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

  /// Fraction of payments made (0–1) for [installmentId], for progress bars.
  /// Kept here so views never compute it in `build`.
  double paymentProgress(String installmentId) {
    final inst = _findById(installmentId);
    if (inst.totalMonths <= 0) return 0.0;
    return (paidCount(installmentId) / inst.totalMonths).clamp(0.0, 1.0);
  }

  double get totalDueThisMonth =>
      dueThisMonth.fold(0.0, (sum, i) => sum + i.monthlyAmount);

  double get totalPaidThisMonth => dueThisMonth
      .where((i) => isPaidForMonth(i.id))
      .fold(0.0, (sum, i) => sum + i.monthlyAmount);

  // ─── Web helpers (Plan 050-C) ─────────────────────────────────────────────────

  /// Monthly installment cash load for the selected month — the web KPI strip's
  /// "Installment load". Alias of [totalDueThisMonth] for intent at the call site.
  double get monthlyInstallmentLoad => totalDueThisMonth;

  /// Human-readable account name for [accountId], or null when unknown. Keeps
  /// account lookups out of `build`.
  String? accountName(String? accountId) {
    if (accountId == null) return null;
    final match = accounts.where((a) => a.id == accountId).firstOrNull;
    return match?.name;
  }

  // ─── Load ─────────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _isLoading = true;
    safeNotify();
    _installments = await _storage.loadInstallments();
    _awardedXpKeys
      ..clear()
      ..addAll(await _storage.loadAwardedXpKeys());
    _awardedXpLoaded = true;
    _isLoading = false;
    safeNotify();
  }

  /// Grants [xp] for [key] at most once (persisted), so unpay/re-pay cycles
  /// can't farm the completion / all-due-paid awards.
  Future<void> _awardOnce(String key, int xp) async {
    if (!_awardedXpLoaded) return;
    if (_awardedXpKeys.contains(key)) return;
    _awardedXpKeys.add(key);
    await _storage.saveAwardedXpKeys(_awardedXpKeys);
    await _stats.addXp(xp);
  }

  // ─── CRUD ─────────────────────────────────────────────────────────────────────

  Future<void> addInstallment(Installment i) async {
    _installments = [..._installments, i];
    safeNotify();
    await _storage.saveInstallments(_installments);
  }

  Future<void> updateInstallment(Installment i) async {
    _installments = [
      for (final inst in _installments) inst.id == i.id ? i : inst
    ];
    safeNotify();
    await _storage.saveInstallments(_installments);
  }

  Future<void> deleteInstallment(String id) async {
    final linked =
        _ledger.allTransactions.where((t) => t.installmentId == id).toList();
    for (final txn in linked) {
      await _ledger.deleteTransaction(txn.id);
    }
    _installments = _installments.where((i) => i.id != id).toList();
    safeNotify();
    await _storage.saveInstallments(_installments);
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

    if (count >= inst.totalMonths) {
      await _awardOnce('installment.complete/$installmentId', 50);
    }

    final allDuePaid = dueThisMonth.every(
      (i) => i.id == installmentId || isPaidForMonth(i.id),
    );
    if (allDuePaid && dueThisMonth.isNotEmpty) {
      await _awardOnce('installment.allDuePaid/$_selectedMonth', 20);
    }

    safeNotify();
  }

  Future<void> markUnpaid(String installmentId) async {
    final txn = _ledger.allTransactions.firstWhere(
      (t) => t.installmentId == installmentId && t.month == _selectedMonth,
      orElse: () => throw StateError('no_txn'),
    );
    await _ledger.deleteTransaction(txn.id);
    safeNotify();
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
      await _ledger.addCategory(FinanceCategory(
        id: _installmentCategoryId,
        name: 'Installment',
        type: CategoryType.expense,
        icon: 'credit_card',
        colorHex: '#9C27B0',
      ));
    }
  }
}
