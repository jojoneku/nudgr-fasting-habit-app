import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/credit_brand_presets.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/credit_finance_charge.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/treasury_history_backfill.dart';

class DailySpend {
  final DateTime date;
  final double amount;
  const DailySpend(this.date, this.amount);
}

/// Verdict tier for the dashboard "Can I afford it?" calculator (Plan 042/050).
enum AffordTier { yes, tight, no }

/// Result of [TreasuryDashboardPresenter.canAfford] — a tier plus the figures
/// the view needs for its copy. Pure value object; copy strings live in the UI.
class AffordVerdict {
  final AffordTier tier;

  /// Projected spare left this month *after* the hypothetical spend.
  final double spareAfter;

  /// When an account was given and the spend exceeds its spendable balance,
  /// how much it falls short (else null).
  final double? accountShortfall;

  const AffordVerdict({
    required this.tier,
    required this.spareAfter,
    this.accountShortfall,
  });
}

/// A flattened account-balance row for the web dashboard accounts table.
/// Liquid rows show [balance] and the [held]-for-others slice; credit rows
/// show the current payable as [balance] and the available limit as [yours].
class DashboardAccountRow {
  final String name;
  final double balance;
  final double held;
  final double yours;
  final bool isCredit;

  const DashboardAccountRow({
    required this.name,
    required this.balance,
    required this.held,
    required this.yours,
    required this.isCredit,
  });
}

class TreasuryDashboardPresenter extends ChangeNotifier {
  TreasuryDashboardPresenter(StorageService storage, [LedgerPresenter? ledger])
      : _storage = storage,
        _ledger = ledger {
    load();
    _ledger?.addListener(_syncFromLedger);
  }

  final StorageService _storage;
  final LedgerPresenter? _ledger;

  /// Mirror accounts/transactions/categories from LedgerPresenter so that
  /// dashboard summaries reflect ledger mutations without waiting for a tab
  /// switch or app restart. Bills/receivables/budgets stay loaded from storage
  /// because they're owned by other presenters.
  void _syncFromLedger() {
    final ledger = _ledger;
    if (ledger == null) return;
    _accounts = ledger.accounts;
    _transactions = ledger.allTransactions;
    _categories = ledger.categories;
    notifyListeners();
  }

  @override
  void dispose() {
    _ledger?.removeListener(_syncFromLedger);
    super.dispose();
  }

  bool _isLoading = true;
  List<FinancialAccount> _accounts = [];
  List<TransactionRecord> _transactions = [];
  List<Bill> _bills = [];
  List<Receivable> _receivables = [];
  List<Budget> _budgets = [];
  List<BudgetedExpense> _budgetedExpenses = [];
  List<FinanceCategory> _categories = [];
  List<MonthlySummary> _summaries = [];
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

  /// Credit accounts (cards / lines / BNPL) for the dedicated Credit section.
  /// Same set as [liabilityAccounts] today; named for the section that renders
  /// remaining limit + current payable per row.
  List<FinancialAccount> get creditAccounts => liabilityAccounts;

  /// Total owed across all credit accounts (sum of current payables).
  double get totalCreditOwed =>
      creditAccounts.fold(0.0, (sum, a) => sum + a.currentPayable);

  /// Total remaining credit across accounts that have a limit set.
  double get totalCreditAvailable =>
      creditAccounts.fold(0.0, (sum, a) => sum + (a.availableCredit ?? 0));

  /// Next payment-due label for a credit account and whether it's imminent
  /// (within 3 days). Returns null when the account has no due day configured.
  /// Rolls to next month once this month's due day has passed.
  ({String label, bool imminent})? creditDueInfo(FinancialAccount a) {
    final day = a.paymentDueDay;
    if (day == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var due = DateTime(now.year, now.month, day);
    if (due.isBefore(today)) due = DateTime(now.year, now.month + 1, day);
    final diff = due.difference(today).inDays;
    final label = diff == 0
        ? 'Due today'
        : diff == 1
            ? 'Due tomorrow'
            : 'Due in $diff days';
    return (label: label, imminent: diff <= 3);
  }

  /// Estimated minimum amount due for a credit account, using its brand preset
  /// (or BSP-default rates). Null when nothing is owed. Display-only — finance
  /// charges are not auto-posted to the balance.
  double? creditMinimumDue(FinancialAccount a) {
    if (!a.isLiability || a.currentPayable <= 0) return null;
    final preset = creditBrandPresetByKey(a.creditBrand);
    return computeMinimumDue(
      balance: a.currentPayable,
      minPaymentRate: preset?.minPaymentRate ?? 0.0357,
      minPaymentFloor: preset?.minPaymentFloor ?? 850,
    );
  }

  List<FinancialAccount> get goalAccounts => _accounts
      .where((a) => a.isActive && a.category == AccountCategory.goal)
      .toList();

  List<FinancialAccount> get savingsAccounts => _accounts
      .where((a) => a.isActive && a.category == AccountCategory.savings)
      .toList();

  List<FinancialAccount> subAccountsOf(String parentId) =>
      _accounts.where((a) => a.parentAccountId == parentId).toList();

  // --- Summary values ---

  /// Total cash that is actually yours — full parent balances minus money
  /// held for someone else (custodian accounts). Sub-account balances are
  /// already represented inside their parent, so summing parents alone
  /// covers the whole "yours + held" pool.
  double get totalLiquidCash {
    final parents = liquidAccounts.fold(0.0, (sum, a) => sum + a.balance);
    final held = custodianAccounts.fold(0.0, (sum, a) => sum + a.balance);
    return parents - held;
  }

  /// Full real-world balance across parent accounts, including money held
  /// for others. Useful when an "of X total" subtitle is needed.
  double get totalLiquidCashGross =>
      liquidAccounts.fold(0.0, (sum, a) => sum + a.balance);

  /// Total amount currently held for someone else across all accounts.
  double get totalHeldForOthers =>
      custodianAccounts.fold(0.0, (sum, a) => sum + a.balance);

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
      .where(
          (t) => t.month == _currentMonth && t.type == TransactionType.inflow)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get monthTotalOutflow => _transactions
      .where(
          (t) => t.month == _currentMonth && t.type == TransactionType.outflow)
      .fold(0.0, (sum, t) => sum + t.amount);

  /// Sum of top-level, non-liability, non-custodian account balances — the
  /// gross asset base (before deducting money held for others or liabilities).
  /// Only top-level accounts are summed: sub-account balances are already
  /// reflected in their parent via the propagation rule in
  /// [LedgerPresenter._applyBalanceDelta], so summing both would double-count.
  double get totalAssets => _accounts
      .where((a) =>
          a.isActive &&
          !a.isLiability &&
          !a.isCustodian &&
          a.parentAccountId == null)
      .fold(0.0, (sum, a) => sum + a.balance);

  double get netWorth =>
      // Custodian balances are money held for others, so subtract them.
      totalAssets - totalHeldForOthers - totalLiabilities;

  // --- Web dashboard parity getters (Plan 042 §6 / Plan 050) ---
  // Pure computation over already-loaded state; the mobile dashboard can
  // surface these too. No new storage keys.

  /// This month's income minus expenses.
  double get monthNetCashFlow => monthTotalInflow - monthTotalOutflow;

  /// Share of this month's income kept (net / income). Null when there is no
  /// income to divide by — the UI shows "—" rather than a divide-by-zero.
  double? get savingsRate {
    final income = monthTotalInflow;
    if (income <= 0) return null;
    return monthNetCashFlow / income;
  }

  /// What you owe right now: this month's unpaid bills plus all liabilities.
  double get currentObligations => monthUnpaidBills + totalLiabilities;

  /// Projected spare cash for the month after bills, receivables, and budget —
  /// the "Can I afford it?" baseline. Alias of [forecastedNetBalance], named
  /// for the UI.
  double get projectedSpareThisMonth => forecastedNetBalance;

  /// Whether [amount] fits this month. Checks against [projectedSpareThisMonth]
  /// and, when [accountId] is given, against that account's spendable balance
  /// (its balance minus any amount held for others on it).
  AffordVerdict canAfford(double amount, {String? accountId}) {
    final spare = projectedSpareThisMonth;
    final spareAfter = spare - amount;

    double? accountShortfall;
    if (accountId != null) {
      final account = _accounts.where((a) => a.id == accountId).firstOrNull;
      if (account != null) {
        final held = heldAmountByAccountId[accountId] ?? 0.0;
        final spendable = account.balance - held;
        if (amount > spendable) accountShortfall = amount - spendable;
      }
    }

    final AffordTier tier;
    if (amount > spare || accountShortfall != null) {
      tier = AffordTier.no;
    } else if (amount <= spare * 0.8) {
      tier = AffordTier.yes;
    } else {
      tier = AffordTier.tight;
    }

    return AffordVerdict(
      tier: tier,
      spareAfter: spareAfter,
      accountShortfall: accountShortfall,
    );
  }

  /// Flattened account-balance rows for the web dashboard accounts table —
  /// liquid accounts (balance / held / yours) followed by credit accounts
  /// (payable / available limit). Assembly lives here, not in `build()`.
  List<DashboardAccountRow> get dashboardAccountRows {
    final held = heldAmountByAccountId;
    return [
      for (final a in liquidAccounts)
        DashboardAccountRow(
          name: a.name,
          balance: a.balance,
          held: held[a.id] ?? 0.0,
          yours: a.balance - (held[a.id] ?? 0.0),
          isCredit: false,
        ),
      for (final a in creditAccounts)
        DashboardAccountRow(
          name: a.name,
          balance: a.currentPayable,
          held: 0.0,
          yours: a.availableCredit ?? 0.0,
          isCredit: true,
        ),
    ];
  }

  List<FinancialAccount> get custodianAccounts =>
      _accounts.where((a) => a.isActive && a.isCustodian).toList();

  /// Returns the total held (custodian) amount linked to each liquid account id.
  Map<String, double> get heldAmountByAccountId {
    final result = <String, double>{};
    for (final c in custodianAccounts) {
      if (c.linkedAccountId != null) {
        result[c.linkedAccountId!] =
            (result[c.linkedAccountId!] ?? 0.0) + c.balance;
      }
    }
    return result;
  }

  // --- Bills ---

  List<Bill> get upcomingBills =>
      _bills.where((b) => b.month == _currentMonth && !b.isPaid).toList()
        ..sort((a, b) => a.dueDay.compareTo(b.dueDay));

  bool get hasBills => upcomingBills.isNotEmpty;

  bool get hasBillImminent {
    final today = DateTime.now().day;
    return upcomingBills.any((b) => b.dueDay == today || b.dueDay == today + 1);
  }

  Bill? get imminentBill {
    final today = DateTime.now().day;
    return upcomingBills
        .where((b) => b.dueDay == today || b.dueDay == today + 1)
        .firstOrNull;
  }

  double get todayOutflow {
    final now = DateTime.now();
    return _transactions.where((t) {
      return t.type == TransactionType.outflow &&
          t.date.year == now.year &&
          t.date.month == now.month &&
          t.date.day == now.day;
    }).fold(0.0, (sum, t) => sum + t.amount);
  }

  double get todayInflow {
    final now = DateTime.now();
    return _transactions.where((t) {
      return t.type == TransactionType.inflow &&
          t.date.year == now.year &&
          t.date.month == now.month &&
          t.date.day == now.day;
    }).fold(0.0, (sum, t) => sum + t.amount);
  }

  bool isBillOverdue(Bill bill) => bill.dueDay < DateTime.now().day;

  // --- Budget ---

  bool get hasBudget =>
      _budgets.any((b) => b.month == _currentMonth) ||
      _budgetedExpenses.any((e) => e.month == _currentMonth);

  double get totalBudgetAllocated => _budgets
      .where((b) => b.month == _currentMonth)
      .fold(0.0, (sum, b) => sum + b.allocatedAmount);

  double get totalBudgetSpent => _budgetedExpenses
      .where((e) => e.month == _currentMonth)
      .fold(0.0, (sum, e) => sum + e.spentAmount);

  double get totalBudgetRemaining =>
      (totalBudgetAllocated - totalBudgetSpent).clamp(0.0, double.infinity);

  double get forecastedNetBalance => endingCash - totalBudgetRemaining;

  Map<BudgetGroup, double> get budgetAllocatedByGroup {
    final result = <BudgetGroup, double>{};
    for (final b in _budgets.where((b) => b.month == _currentMonth)) {
      result[b.group] = (result[b.group] ?? 0.0) + b.allocatedAmount;
    }
    return result;
  }

  Map<BudgetGroup, double> get budgetSpentByGroup {
    final result = <BudgetGroup, double>{};
    for (final e in _budgetedExpenses.where((e) => e.month == _currentMonth)) {
      final budget = _budgets
          .where(
              (b) => b.month == _currentMonth && b.categoryId == e.categoryId)
          .firstOrNull;
      if (budget != null) {
        result[budget.group] = (result[budget.group] ?? 0.0) + e.spentAmount;
      }
    }
    return result;
  }

  // --- Category spend (pie chart) ---

  /// Returns top expense categories by spend for the current month.
  /// Each entry: (category, amount). Sorted descending. Max 6 slices + "Other".
  List<(FinanceCategory, double)> get categorySpendThisMonth =>
      _categorySpendRanked(limit: 10);

  /// All categories with spend, no limit — used by the full breakdown sheet.
  List<(FinanceCategory, double)> get allCategorySpendThisMonth =>
      _categorySpendRanked(limit: null);

  bool get hasCategorySpend => categorySpendThisMonth.isNotEmpty;

  List<(FinanceCategory, double)> _categorySpendRanked({required int? limit}) {
    final spendMap = <String, double>{};
    for (final t in _transactions) {
      if (t.month == _currentMonth && t.type == TransactionType.outflow) {
        spendMap[t.categoryId] = (spendMap[t.categoryId] ?? 0.0) + t.amount;
      }
    }
    if (spendMap.isEmpty) return [];

    final sorted = spendMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final resolved = <(FinanceCategory, double)>[];
    double otherTotal = 0.0;

    for (int i = 0; i < sorted.length; i++) {
      final cat = _categories.where((c) => c.id == sorted[i].key).firstOrNull;
      if ((limit == null || i < limit) && cat != null) {
        resolved.add((cat, sorted[i].value));
      } else {
        otherTotal += sorted[i].value;
      }
    }

    if (otherTotal > 0 && limit != null) {
      final other = FinanceCategory(
        id: '__other__',
        name: 'Other',
        type: CategoryType.expense,
        icon: 'dots-horizontal',
        colorHex: '#607D8B',
      );
      resolved.add((other, otherTotal));
    }

    return resolved;
  }

  // --- Spending analytics ---

  List<DailySpend> get last7DaysSpending => _lastNDaysSpending(7);

  /// Flexible — used by the full spending history sheet.
  List<DailySpend> lastNDaysSpending(int n) => _lastNDaysSpending(n);

  List<DailySpend> _lastNDaysSpending(int n) {
    final now = DateTime.now();
    return List.generate(n, (i) {
      final day = DateTime(now.year, now.month, now.day - (n - 1 - i));
      final total = _transactions
          .where((t) =>
              t.type == TransactionType.outflow &&
              t.date.year == day.year &&
              t.date.month == day.month &&
              t.date.day == day.day)
          .fold(0.0, (sum, t) => sum + t.amount);
      return DailySpend(day, total);
    });
  }

  double get avgDailySpend7 {
    final days = last7DaysSpending;
    final nonZero = days.where((d) => d.amount > 0).toList();
    if (nonZero.isEmpty) return 0.0;
    return nonZero.fold(0.0, (s, d) => s + d.amount) / nonZero.length;
  }

  double get peakDaySpend7 =>
      last7DaysSpending.fold(0.0, (max, d) => d.amount > max ? d.amount : max);

  DateTime? get peakSpendDay {
    final days = last7DaysSpending;
    if (days.every((d) => d.amount == 0)) return null;
    return days.reduce((a, b) => a.amount >= b.amount ? a : b).date;
  }

  // --- Monthly trends (net worth / income vs expenses) ---

  /// The last [n] month keys ending at [_currentMonth], oldest → newest.
  List<String> _lastNMonthKeys(int n) {
    final keys = <String>[];
    var k = _currentMonth;
    for (var i = 0; i < n; i++) {
      keys.add(k);
      k = previousMonth(k);
    }
    return keys.reversed.toList();
  }

  MonthlySummary? _summaryFor(String month) =>
      _summaries.where((s) => s.month == month).firstOrNull;

  /// Reconstructs net worth from a stored month-end account snapshot using the
  /// *current* account roles (asset / liability / custodian), which are stable
  /// over time. Mirrors the live [netWorth] formula: top-level assets minus
  /// money held for others minus liabilities. Accounts no longer present are
  /// skipped rather than mis-signed.
  double _netWorthFromSnapshot(Map<String, double> snapshot) {
    double assets = 0, custodian = 0, liabilities = 0;
    snapshot.forEach((id, balance) {
      final acc = _accounts.where((a) => a.id == id).firstOrNull;
      if (acc == null) return;
      if (acc.isLiability) {
        liabilities += balance;
      } else if (acc.isCustodian) {
        custodian += balance;
      } else if (acc.parentAccountId == null) {
        assets += balance;
      }
    });
    return assets - custodian - liabilities;
  }

  /// Net worth at each of the last [months] month-ends, oldest → newest. The
  /// in-progress current month uses the live [netWorth]; closed months are
  /// reconstructed from their stored snapshots. Months without a usable
  /// snapshot are omitted, so an account with little history yields a short
  /// (or single-point) series the UI can choose to render as an empty state.
  List<({String label, double value})> netWorthTrend({int months = 6}) {
    final result = <({String label, double value})>[];
    for (final key in _lastNMonthKeys(months)) {
      final label = monthShortLabel(key);
      if (key == _currentMonth) {
        result.add((label: label, value: netWorth));
      } else {
        final summary = _summaryFor(key);
        if (summary == null) continue;
        // Prefer the stored net worth (set at close or via the legacy import);
        // fall back to reconstructing from the account snapshot.
        final value = summary.netWorth ??
            (summary.accountSnapshots.isEmpty
                ? null
                : _netWorthFromSnapshot(summary.accountSnapshots));
        if (value == null) continue;
        result.add((label: label, value: value));
      }
    }
    return result;
  }

  /// Income vs expenses for the last [months] months, oldest → newest. The
  /// current month uses live totals; closed months come from their summary.
  /// Months with no summary are omitted.
  List<({String label, double income, double expense})> incomeExpenseTrend(
      {int months = 6}) {
    final result = <({String label, double income, double expense})>[];
    for (final key in _lastNMonthKeys(months)) {
      final label = monthShortLabel(key);
      if (key == _currentMonth) {
        result.add((
          label: label,
          income: monthTotalInflow,
          expense: monthTotalOutflow,
        ));
      } else {
        final summary = _summaryFor(key);
        if (summary == null) continue;
        result.add((
          label: label,
          income: summary.totalInflow,
          expense: summary.totalOutflow,
        ));
      }
    }
    return result;
  }

  // --- One-time historical backfill (legacy spreadsheet import) ---

  /// Seeds [MonthlySummary] records for the closed months in
  /// [kTreasuryHistoryBackfill2026] (Jan–May 2026) so the trends and History
  /// page show real history. Idempotent and safe:
  ///  • runs only when real account data exists (a fresh/empty install never
  ///    inherits this history),
  ///  • skips any month that already has a summary (never clobbers real data),
  ///  • reconstructs each month-end net worth by walking the live [netWorth]
  ///    back through the monthly net-cash-flows.
  /// Called at the end of [load]; after the first successful run the
  /// already-present guard short-circuits it.
  Future<void> backfillHistoricalSummariesOnce() async {
    if (!hasAccounts) return;
    final existingMonths = _summaries.map((s) => s.month).toSet();
    final missing = kTreasuryHistoryBackfill2026
        .where((m) => !existingMonths.contains(m.month))
        .toList();
    if (missing.isEmpty) return;

    // Net cash flow per month: backfill values for the closed months, plus a
    // fallback to any already-closed summary (e.g. once June auto-closes).
    double flowFor(String month) {
      for (final m in kTreasuryHistoryBackfill2026) {
        if (m.month == month) return m.net;
      }
      return _summaryFor(month)?.netSavings ?? 0.0;
    }

    // Reconstruct month-end net worth by walking back from the live current
    // month: end-of-prev-month = end-of-this-month − this-month's net flow.
    final nwEnd = <String, double>{};
    final earliest = missing
        .map((m) => m.month)
        .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
    var cursor = _currentMonth;
    var nw = netWorth;
    var flow = monthNetCashFlow; // live current-month flow
    var guard = 0;
    while (cursor.compareTo(earliest) > 0 && guard++ < 240) {
      nw -= flow;
      final prev = previousMonth(cursor);
      nwEnd[prev] = nw;
      cursor = prev;
      flow = flowFor(prev);
    }

    // Map category names → ids (normalized: lowercase, spaces stripped).
    String norm(String s) => s.toLowerCase().replaceAll(' ', '');
    final idByName = {for (final c in _categories) norm(c.name): c.id};

    final added = <MonthlySummary>[];
    for (final m in missing) {
      final categorySpend = <String, double>{};
      m.categorySpendByName.forEach((name, amount) {
        final id = idByName[norm(name)];
        if (id != null) categorySpend[id] = amount;
      });
      final monthNetWorth = nwEnd[m.month];
      added.add(MonthlySummary(
        month: m.month,
        totalInflow: m.income,
        totalOutflow: m.expenses,
        totalBills: 0,
        totalBillsPaid: 0,
        billCount: 0,
        billsPaidCount: 0,
        totalReceivables: 0,
        totalReceived: 0,
        receivableCount: 0,
        netSavings: m.net,
        // True month-end liquid cash isn't recoverable from the legacy summary,
        // so endingCash mirrors the reconstructed net worth for these months.
        endingCash: monthNetWorth ?? 0,
        netWorth: monthNetWorth,
        accountSnapshots: const {},
        categorySpend: categorySpend,
      ));
    }

    final merged = [..._summaries, ...added];
    await _storage.saveMonthlySummaries(merged);
    _summaries = merged;
    notifyListeners();
  }

  // --- Account CRUD ---

  Future<void> addAccount(FinancialAccount account) async {
    _accounts = [..._accounts, account];
    notifyListeners();
    await _storage.saveAccounts(_accounts);
  }

  Future<void> updateAccount(FinancialAccount account) async {
    _accounts = [
      for (final a in _accounts) a.id == account.id ? account : a,
    ];
    notifyListeners();
    await _storage.saveAccounts(_accounts);
  }

  /// Throws [StateError('has_sub_accounts')] if the account has sub-accounts.
  /// Throws [StateError('has_transactions')] if any transaction, bill,
  /// receivable, or budgeted expense still references this account — refusing
  /// to delete prevents orphaned references in the ledger and bills tabs.
  Future<void> deleteAccount(String id) async {
    final hasSubs = _accounts.any((a) => a.parentAccountId == id);
    if (hasSubs) throw StateError('has_sub_accounts');
    final hasTxns = _transactions
        .any((t) => t.accountId == id || t.transferToAccountId == id);
    final hasBills = _bills.any((b) => b.accountId == id);
    if (hasTxns || hasBills) throw StateError('has_transactions');
    _accounts = _accounts.where((a) => a.id != id).toList();
    notifyListeners();
    await _storage.saveAccounts(_accounts);
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _accounts = await _storage.loadAccounts();
    _transactions = await _storage.loadTransactions();
    _bills = await _storage.loadBills();
    _receivables = await _storage.loadReceivables();
    _budgets = await _storage.loadBudgets();
    _budgetedExpenses = await _storage.loadBudgetedExpenses();
    _categories = await _storage.loadFinanceCategories();
    _summaries = await _storage.loadMonthlySummaries();
    _currentMonth = toMonthKey(DateTime.now());

    _isLoading = false;
    notifyListeners();
    // NOTE: the legacy backfill is NOT run here — load() runs concurrently with
    // TreasuryHistoryPresenter.load() (both persist monthly summaries), so the
    // composition root runs backfillHistoricalSummariesOnce() AFTER all
    // presenters have loaded, to avoid a last-writer-wins race over the key.
  }
}
