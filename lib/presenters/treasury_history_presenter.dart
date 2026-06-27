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

  // ─── Savings contributions (money set aside into pockets) ───────────────────────
  // Distinct from net savings (the income − expense surplus): this tracks money
  // that actually moved into a savings/goal/sinking-fund account via a transfer,
  // so it answers "how much did I put away this month?" rather than "how much of
  // my income survived?". Derived live from transfers — no category is involved.

  /// Net amount set aside into savings pockets for [month] (transfers in minus
  /// transfers back out). Computed live so the current, still-open month counts.
  double monthlySavingsContribution(String month) => _sumSavingsContribution(
        _allTransactions.where((t) => t.month == month).toList(),
      );

  /// Per-pocket breakdown for [month], one row per savings/goal/sinking-fund
  /// account that saw movement, richest first. Carries the account's name and
  /// colour so the view does no lookups in `build()`.
  List<SavingsPocketContribution> savingsContributionByPocket(String month) {
    final byId = _buildSavingsContributionByPocket(
      _allTransactions.where((t) => t.month == month).toList(),
    );
    final rows = <SavingsPocketContribution>[];
    byId.forEach((accountId, amount) {
      final acct = _accounts.where((a) => a.id == accountId).firstOrNull;
      rows.add(SavingsPocketContribution(
        accountId: accountId,
        name: acct?.name ?? 'Account',
        colorHex: acct?.colorHex,
        amount: amount,
      ));
    });
    rows.sort((a, b) => b.amount.compareTo(a.amount));
    return rows;
  }

  /// Average monthly savings contribution across all months with activity.
  double get averageSavingsContribution {
    final months = activeMonths;
    if (months.isEmpty) return 0;
    final total = months.fold(0.0, (s, m) => s + monthlySavingsContribution(m));
    return total / months.length;
  }

  /// Total set aside into pockets across every month with activity.
  double get cumulativeSavingsContribution =>
      activeMonths.fold(0.0, (s, m) => s + monthlySavingsContribution(m));

  // ─── Sheet-parity matrix (Plan 050 polish) ─────────────────────────────────────
  // Mirrors the Google Sheet's "Historical Summary" tab: months as columns,
  // with per-month Income/Expenses/Net/Savings-Rate/Cumulative, plus a
  // category×month spend breakdown. Computed live from raw transactions (not
  // just closed summaries) so the current month appears too.

  /// All 'YYYY-MM' months that have at least one transaction, oldest → newest.
  List<String> get activeMonths {
    final set = <String>{for (final t in _allTransactions) t.month};
    final list = set.toList()..sort();
    return list;
  }

  /// One column per active month: income, expenses, net, savings rate, and a
  /// running cumulative net (oldest → newest).
  List<MonthHistoryColumn> get monthMatrix {
    final months = activeMonths;
    var cumulative = 0.0;
    final cols = <MonthHistoryColumn>[];
    for (final m in months) {
      final monthTxns = _allTransactions.where((t) => t.month == m).toList();
      // Exclude internal transfer legs — moving money between your own accounts
      // is neither income nor an expense (mirrors the dashboard cash-flow getters).
      final txns = monthTxns.where((t) => t.transferGroupId == null);
      final income = txns
          .where((t) => t.type == TransactionType.inflow)
          .fold(0.0, (s, t) => s + t.amount);
      final expenses = txns
          .where((t) => t.type == TransactionType.outflow)
          .fold(0.0, (s, t) => s + t.amount);
      final net = income - expenses;
      cumulative += net;
      cols.add(MonthHistoryColumn(
        month: m,
        income: income,
        expenses: expenses,
        net: net,
        savingsRate: income > 0 ? net / income : null,
        cumulativeNet: cumulative,
        // Savings contribution needs the transfer legs, so compute from the full
        // month's transactions rather than the transfer-excluded `txns`.
        savingsContribution: _sumSavingsContribution(monthTxns),
      ));
    }
    return cols;
  }

  /// One row per spending category (descending by total spend), each carrying
  /// its spend in every active month — the sheet's category breakdown grid.
  List<CategoryHistoryRow> get categoryMatrix {
    final byCat = <String, Map<String, double>>{};
    for (final t in _allTransactions.where((t) =>
        t.type == TransactionType.outflow && t.transferGroupId == null)) {
      (byCat[t.categoryId] ??= {})[t.month] =
          (byCat[t.categoryId]?[t.month] ?? 0) + t.amount;
    }
    final rows = <CategoryHistoryRow>[];
    byCat.forEach((catId, byMonth) {
      final cat = _categories.where((c) => c.id == catId).firstOrNull;
      final total = byMonth.values.fold(0.0, (a, b) => a + b);
      rows.add(CategoryHistoryRow(
        categoryId: catId,
        name: cat?.name ?? 'Uncategorized',
        colorHex: cat?.colorHex,
        byMonth: byMonth,
        total: total,
      ));
    });
    rows.sort((a, b) => b.total.compareTo(a.total));
    return rows;
  }

  /// True when there are no transactions at all to build the matrix from.
  bool get hasNoMatrixData => _allTransactions.isEmpty;

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
    await repairTransferPollutedSummariesOnce();

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

  /// One-time repair for the transfer-exclusion fix. Earlier builds stamped each
  /// transfer leg with the first expense category and counted the outflow leg as
  /// spending, so any month the app auto-closed while transfers existed has an
  /// inflated [MonthlySummary] (income, expenses, and per-category spend). This
  /// recomputes ONLY those transfer-derived totals from the month's transactions
  /// — preserving the frozen [MonthlySummary.endingCash]/[MonthlySummary.netWorth]
  /// /[MonthlySummary.accountSnapshots] — and leaves spreadsheet-imported months
  /// (which carry no transaction rows, hence no transfer legs) untouched.
  /// Naturally idempotent: once corrected, the recompute matches the stored
  /// values and nothing is rewritten.
  Future<void> repairTransferPollutedSummariesOnce() async {
    var changed = false;
    final repaired = <MonthlySummary>[];
    for (final s in _summaries) {
      final txns = _allTransactions.where((t) => t.month == s.month).toList();
      // Only months that actually contain transfer legs can be polluted; this
      // skips legacy spreadsheet months, which have no underlying transactions.
      if (!txns.any((t) => t.transferGroupId != null)) {
        repaired.add(s);
        continue;
      }
      final inflow = _sumType(txns, TransactionType.inflow);
      final outflow = _sumType(txns, TransactionType.outflow);
      final categorySpend = _buildCategorySpend(txns);
      final savings = _sumSavingsContribution(txns);
      if (_closeEnough(inflow, s.totalInflow) &&
          _closeEnough(outflow, s.totalOutflow) &&
          _categorySpendClose(categorySpend, s.categorySpend) &&
          s.savingsContribution != null &&
          _closeEnough(savings, s.savingsContribution!)) {
        repaired.add(s);
        continue;
      }
      changed = true;
      repaired.add(s.copyWith(
        totalInflow: inflow,
        totalOutflow: outflow,
        netSavings: inflow - outflow,
        categorySpend: categorySpend,
        savingsContribution: savings,
      ));
    }
    if (!changed) return;
    _summaries = repaired;
    await _storage.saveMonthlySummaries(_summaries);
  }

  bool _closeEnough(double a, double b) => (a - b).abs() < 0.005;

  bool _categorySpendClose(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || !_closeEnough(entry.value, other)) return false;
    }
    return true;
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
      savingsContribution: _sumSavingsContribution(txns),
    );
  }

  double _sumType(List<TransactionRecord> txns, TransactionType type) => txns
      .where((t) => t.type == type && t.transferGroupId == null)
      .fold(0.0, (s, t) => s + t.amount);

  /// Set of account ids that are savings pockets (savings / goal / sinking
  /// fund), used to attribute transfer legs as savings contributions.
  Set<String> get _savingsPocketIds =>
      {for (final a in _accounts.where((a) => a.isSavingsPocket)) a.id};

  /// Net amount moved into savings pockets across [txns]: the inflow leg of a
  /// transfer that LANDS in a savings/goal/sinking-fund account counts as a
  /// contribution; an outflow leg LEAVING one counts against it (a withdrawal).
  /// Transfers between two pockets net to zero — not a new contribution. Only
  /// transfer legs (transferGroupId != null) are considered; ordinary income or
  /// spending never touches this figure.
  double _sumSavingsContribution(List<TransactionRecord> txns) {
    final pockets = _savingsPocketIds;
    var total = 0.0;
    for (final t in txns) {
      if (t.transferGroupId == null || !pockets.contains(t.accountId)) continue;
      total += t.type == TransactionType.inflow ? t.amount : -t.amount;
    }
    return total;
  }

  /// Per-pocket net contribution for [txns]: accountId → amount set aside this
  /// period (negative when more was withdrawn than added). Only pockets with a
  /// non-zero movement appear.
  Map<String, double> _buildSavingsContributionByPocket(
      List<TransactionRecord> txns) {
    final pockets = _savingsPocketIds;
    final result = <String, double>{};
    for (final t in txns) {
      if (t.transferGroupId == null || !pockets.contains(t.accountId)) continue;
      final delta = t.type == TransactionType.inflow ? t.amount : -t.amount;
      result[t.accountId] = (result[t.accountId] ?? 0.0) + delta;
    }
    result.removeWhere((_, v) => v == 0.0);
    return result;
  }

  Map<String, double> _buildAccountSnapshots() {
    return {
      for (final a in _accounts.where((a) => a.isActive)) a.id: a.balance,
    };
  }

  Map<String, double> _buildCategorySpend(List<TransactionRecord> txns) {
    final result = <String, double>{};
    for (final t in txns.where((t) =>
        t.type == TransactionType.outflow && t.transferGroupId == null)) {
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

/// One month column of the sheet-parity history matrix (Plan 050 polish).
class MonthHistoryColumn {
  final String month; // 'YYYY-MM'
  final double income;
  final double expenses;
  final double net;
  final double? savingsRate; // null when no income that month
  final double cumulativeNet;

  /// Net moved into savings/goal/sinking-fund pockets via transfers this month.
  final double savingsContribution;

  const MonthHistoryColumn({
    required this.month,
    required this.income,
    required this.expenses,
    required this.net,
    required this.savingsRate,
    required this.cumulativeNet,
    this.savingsContribution = 0,
  });
}

/// One savings-pocket row of a month's contribution breakdown — money set aside
/// into a single savings/goal/sinking-fund account. Pre-resolved (name, colour)
/// so the view does zero lookups in `build()`.
class SavingsPocketContribution {
  final String accountId;
  final String name;
  final String? colorHex;

  /// Net moved into this pocket for the month (negative = net withdrawal).
  final double amount;

  const SavingsPocketContribution({
    required this.accountId,
    required this.name,
    required this.colorHex,
    required this.amount,
  });
}

/// One category row of the category×month breakdown grid (Plan 050 polish).
class CategoryHistoryRow {
  final String categoryId;
  final String name;
  final String? colorHex;
  final Map<String, double> byMonth; // monthKey → spend
  final double total;

  const CategoryHistoryRow({
    required this.categoryId,
    required this.name,
    required this.colorHex,
    required this.byMonth,
    required this.total,
  });
}
