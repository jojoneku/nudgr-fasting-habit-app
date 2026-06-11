import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class TreasuryHistoryPresenter extends ChangeNotifier {
  TreasuryHistoryPresenter(StorageService storage) : _storage = storage;

  final StorageService _storage;

  bool _isLoading = false;
  List<MonthlySummary> _summaries = [];
  List<TransactionRecord> _allTransactions = [];
  List<Bill> _allBills = [];
  List<Receivable> _allReceivables = [];
  List<FinancialAccount> _accounts = [];
  List<FinanceCategory> _categories = [];

  // ─── Public state ────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;

  List<MonthlySummary> get summaries {
    final sorted = [..._summaries];
    sorted.sort((a, b) => b.month.compareTo(a.month));
    return sorted;
  }

  MonthlySummary? get currentMonthSummary =>
      _computeSummary(toMonthKey(DateTime.now()));

  List<FinanceCategory> get categories => List.unmodifiable(_categories);

  List<FinancialAccount> get accounts => List.unmodifiable(_accounts);

  /// True when there are no closed-month summaries to display yet.
  bool get hasNoSummaries => _summaries.isEmpty;

  // ─── Web derived data (Plan 050-E) ─────────────────────────────────────────────

  /// Summaries ordered oldest → newest, for left-to-right chart plotting.
  List<MonthlySummary> get summariesChronological {
    final sorted = [..._summaries];
    sorted.sort((a, b) => a.month.compareTo(b.month));
    return sorted;
  }

  /// Savings rate for a summary = net savings / total inflow. Returns 0 when
  /// there was no inflow that month.
  double savingsRate(MonthlySummary s) {
    if (s.totalInflow <= 0) return 0;
    return s.netSavings / s.totalInflow;
  }

  /// Trend points for the net-cash-flow chart, oldest → newest. Each point
  /// carries the parallel inflow / outflow so the view can plot multiple series
  /// without doing any math in `build()`.
  List<HistoryTrendPoint> get trendPoints {
    final chrono = summariesChronological;
    return [
      for (var i = 0; i < chrono.length; i++)
        HistoryTrendPoint(
          index: i.toDouble(),
          month: chrono[i].month,
          net: chrono[i].netSavings,
          inflow: chrono[i].totalInflow,
          outflow: chrono[i].totalOutflow,
        ),
    ];
  }

  /// Largest absolute value across net / inflow / outflow — used by the view to
  /// set the chart's vertical bounds without scanning the list in `build()`.
  double get trendMaxMagnitude {
    var maxMag = 0.0;
    for (final s in _summaries) {
      maxMag = [
        maxMag,
        s.netSavings.abs(),
        s.totalInflow.abs(),
        s.totalOutflow.abs(),
      ].reduce((a, b) => a > b ? a : b);
    }
    return maxMag == 0 ? 1 : maxMag;
  }

  /// Average monthly net savings across all closed months (0 when none).
  double get averageNetSavings {
    if (_summaries.isEmpty) return 0;
    final total = _summaries.fold(0.0, (s, m) => s + m.netSavings);
    return total / _summaries.length;
  }

  /// Average savings rate across all closed months (0 when none).
  double get averageSavingsRate {
    if (_summaries.isEmpty) return 0;
    final total = _summaries.fold(0.0, (s, m) => s + savingsRate(m));
    return total / _summaries.length;
  }

  /// Net savings summed across every closed month.
  double get cumulativeNetSavings =>
      _summaries.fold(0.0, (s, m) => s + m.netSavings);

  // ─── Load ─────────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _summaries = await _storage.loadMonthlySummaries();
    _allTransactions = await _storage.loadTransactions();
    _allBills = await _storage.loadBills();
    _allReceivables = await _storage.loadReceivables();
    _accounts = await _storage.loadAccounts();
    _categories = await _storage.loadFinanceCategories();

    await closePreviousMonthIfNeeded();

    _isLoading = false;
    notifyListeners();
  }

  // ─── Month close ──────────────────────────────────────────────────────────────

  Future<void> closePreviousMonthIfNeeded() async {
    final lastMonth = previousMonth(toMonthKey(DateTime.now()));
    final alreadyClosed = _summaries.any((s) => s.month == lastMonth);
    if (alreadyClosed) return;

    final hasBills = _allBills.any((b) => b.month == lastMonth);
    final hasTransactions = _allTransactions.any((t) => t.month == lastMonth);
    final hasReceivables = _allReceivables.any((r) => r.month == lastMonth);
    if (!hasBills && !hasTransactions && !hasReceivables) return;

    final summary = _computeSummary(lastMonth);
    if (summary == null) return;

    _summaries = [..._summaries, summary];
    await _storage.saveMonthlySummaries(_summaries);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────────

  MonthlySummary? _computeSummary(String month) {
    final txns = _allTransactions.where((t) => t.month == month).toList();
    final bills = _allBills.where((b) => b.month == month).toList();
    final receivables = _allReceivables.where((r) => r.month == month).toList();

    final totalInflow = _sumType(txns, TransactionType.inflow);
    final totalOutflow = _sumType(txns, TransactionType.outflow);
    final totalBills = bills.fold(0.0, (s, b) => s + b.amount);
    final totalBillsPaid = bills
        .where((b) => b.isPaid)
        .fold(0.0, (s, b) => s + (b.paidAmount ?? b.amount));
    final totalReceivables = receivables.fold(0.0, (s, r) => s + r.amount);
    final totalReceived = receivables
        .where((r) => r.isReceived)
        .fold(0.0, (s, r) => s + (r.receivedAmount ?? r.amount));

    final accountSnapshots = _buildAccountSnapshots();
    final endingCash = _accounts
        .where((a) => a.isActive && a.isLiquid)
        .fold(0.0, (s, a) => s + a.balance);
    final categorySpend = _buildCategorySpend(txns);

    return MonthlySummary(
      month: month,
      totalInflow: totalInflow,
      totalOutflow: totalOutflow,
      totalBills: totalBills,
      totalBillsPaid: totalBillsPaid,
      billCount: bills.length,
      billsPaidCount: bills.where((b) => b.isPaid).length,
      totalReceivables: totalReceivables,
      totalReceived: totalReceived,
      receivableCount: receivables.length,
      netSavings: totalInflow - totalOutflow,
      endingCash: endingCash,
      accountSnapshots: accountSnapshots,
      categorySpend: categorySpend,
    );
  }

  double _sumType(List<TransactionRecord> txns, TransactionType type) =>
      txns.where((t) => t.type == type).fold(0.0, (s, t) => s + t.amount);

  Map<String, double> _buildAccountSnapshots() {
    return {
      for (final a in _accounts.where((a) => a.isActive)) a.id: a.balance,
    };
  }

  Map<String, double> _buildCategorySpend(List<TransactionRecord> txns) {
    final result = <String, double>{};
    for (final t in txns.where((t) => t.type == TransactionType.outflow)) {
      result[t.categoryId] = (result[t.categoryId] ?? 0.0) + t.amount;
    }
    return result;
  }
}

/// A single plotted point in the History trend chart (Plan 050-E). Pre-computed
/// in [TreasuryHistoryPresenter.trendPoints] so the view does zero math.
class HistoryTrendPoint {
  /// Zero-based x position (oldest = 0).
  final double index;

  /// 'YYYY-MM' month key for this point.
  final String month;

  /// Net savings (inflow − outflow) for the month.
  final double net;
  final double inflow;
  final double outflow;

  const HistoryTrendPoint({
    required this.index,
    required this.month,
    required this.net,
    required this.inflow,
    required this.outflow,
  });
}
