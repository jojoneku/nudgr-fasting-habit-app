import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
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
import 'package:intermittent_fasting/utils/finance_flows.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/treasury_history_backfill.dart';

class DailySpend {
  final DateTime date;
  final double amount;
  const DailySpend(this.date, this.amount);
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
  List<BudgetGroupDef> _budgetGroups = BudgetGroupDef.defaultGroups;
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
    // Clamp the due day to the target month's length so day 29–31 doesn't
    // overflow into the next month (e.g. DateTime(2026, 2, 31) → Mar 3).
    DateTime dueOn(int year, int month) {
      final lastDay = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, day.clamp(1, lastDay));
    }

    var due = dueOn(now.year, now.month);
    if (due.isBefore(today)) due = dueOn(now.year, now.month + 1);
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

  /// Total set aside in savings + goal pockets — powers the Setup
  /// "Savings & Goals" KPI. Matches the set of accounts the Setup page groups
  /// under that heading ([savingsAccounts] + [goalAccounts]).
  double get totalSavingsAndGoals => [...savingsAccounts, ...goalAccounts]
      .fold(0.0, (sum, a) => sum + a.balance);

  /// Count of all active accounts (every role + sub-accounts) — for the Setup
  /// "Accounts" KPI tile.
  int get activeAccountCount => _accounts.where((a) => a.isActive).length;

  // --- Summary values ---

  /// Total cash that is actually yours — full parent balances minus money
  /// held for someone else (custodian accounts). Sub-account balances are
  /// already represented inside their parent, so summing parents alone
  /// covers the whole "yours + held" pool.
  double get totalLiquidCash {
    final parents = liquidAccounts.fold(0.0, (sum, a) => sum + a.balance);
    // Subtract only held money that actually sits INSIDE a liquid parent's
    // balance (a linked custodian). An unlinked custodian is a standalone
    // account never counted in `parents`, so subtracting it understated the
    // total; a custodian linked to a non-liquid account isn't liquid cash
    // either. heldAmountByAccountId keys held amounts by their linked account.
    final held = heldAmountByAccountId;
    final heldInLiquid =
        liquidAccounts.fold(0.0, (sum, a) => sum + (held[a.id] ?? 0.0));
    return parents - heldInLiquid;
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

  // Income/expense exclude internal transfer legs (moving your own money) AND
  // reimbursables/loans (money you'll get back is an asset, not spending; its
  // repayment inflow is your own money returning, not income). See
  // isSpendingOutflow / isIncomeInflow in utils/finance_flows.dart.

  /// Receivable ids spawned by reimbursable/loan outflows — used to exclude
  /// their repayment inflows from income.
  Set<String> get _reimbursementIds =>
      reimbursementReceivableIds(_transactions);

  /// Category ids the user flagged to exclude from cash-flow totals.
  Set<String> get _excludedCategoryIds =>
      excludedCashFlowCategoryIds(_categories);

  double get monthTotalInflow {
    final reimb = _reimbursementIds;
    final excluded = _excludedCategoryIds;
    return _transactions
        .where((t) =>
            t.month == _currentMonth && isIncomeInflow(t, reimb, excluded))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double get monthTotalOutflow {
    final excluded = _excludedCategoryIds;
    return _transactions
        .where(
            (t) => t.month == _currentMonth && isSpendingOutflow(t, excluded))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Sum of top-level, non-liability, non-custodian account balances — the
  /// gross asset base (before deducting money held for others or liabilities).
  /// Only top-level accounts are summed: sub-account balances are already
  /// reflected in their parent via the propagation rule in
  /// [LedgerPresenter._applyBalanceDelta], so summing both would double-count.
  Iterable<FinancialAccount> get _assetAccounts => _accounts.where((a) =>
      a.isActive &&
      !a.isLiability &&
      !a.isCustodian &&
      a.parentAccountId == null);

  double get totalAssets =>
      _assetAccounts.fold(0.0, (sum, a) => sum + a.balance);

  double get netWorth =>
      // Subtract only held money embedded in the asset base — i.e. linked
      // custodians whose balance sits inside a counted asset account. Unlinked
      // custodians are excluded from totalAssets entirely, so subtracting them
      // (as the old totalHeldForOthers did) double-counted and understated net
      // worth; their cash correctly nets to zero (not an asset, not subtracted).
      totalAssets - _heldInAssets - totalLiabilities;

  /// Held (custodian) money physically embedded in the [totalAssets] base.
  double get _heldInAssets {
    final held = heldAmountByAccountId;
    return _assetAccounts.fold(0.0, (sum, a) => sum + (held[a.id] ?? 0.0));
  }

  // --- Web dashboard parity getters (Plan 042 §6 / Plan 050) ---
  // Pure computation over already-loaded state; the mobile dashboard can
  // surface these too. No new storage keys.

  /// This month's income minus expenses.
  double get monthNetCashFlow => monthTotalInflow - monthTotalOutflow;

  /// Money actually saved this month: net flow INTO locked accounts
  /// (savings / goal / time-deposit / investment). A transfer from a spending
  /// account into savings lands as an inflow leg on the locked account (+);
  /// spending out of savings is an outflow leg on it (−); a transfer between
  /// two locked accounts nets to zero. Negative when you net-withdrew savings.
  double get monthSavingsContributions {
    final lockedIds = {
      for (final a in _accounts)
        if (a.isLocked) a.id,
    };
    var net = 0.0;
    for (final t in _transactions) {
      if (t.month != _currentMonth) continue;
      if (!lockedIds.contains(t.accountId)) continue;
      if (t.type == TransactionType.inflow) {
        net += t.amount;
      } else if (t.type == TransactionType.outflow) {
        net -= t.amount;
      }
    }
    return net;
  }

  /// Share of this month's income that you moved into savings accounts
  /// ([monthSavingsContributions] / [monthTotalInflow]). [monthTotalInflow]
  /// already excludes internal transfer legs, so it is true income. Null when
  /// there is no income to divide by — the UI shows "—" not a divide-by-zero.
  double? get savingsRate {
    final income = monthTotalInflow;
    if (income <= 0) return null;
    return monthSavingsContributions / income;
  }

  /// Still-to-set-aside portion of this month's budgeted expenses: each
  /// expense's remaining (allocated − already spent, never negative), excluding
  /// ones already settled. Uses `remaining` rather than the full allocation so
  /// money already spent isn't counted as still owed.
  double get budgetedExpensesRemaining => _budgetedExpenses
      .where((e) => e.month == _currentMonth && !e.isPaid)
      .fold(
          0.0,
          (sum, e) =>
              sum +
              (e.allocatedAmount - e.spentAmount).clamp(0.0, double.infinity));

  /// What you owe this month: unpaid bills only. Budgeted-expense set-asides are
  /// surfaced separately as "Budget / Savings Due" ([budgetedExpensesRemaining]),
  /// and liability balances are NOT added — a credit-card statement already
  /// shows up as a bill, so adding the liability too would double-count the same
  /// debt. Total debt still lives in [netWorth]. (Mirrors the reference sheet:
  /// Current Obligations = outstanding bills.)
  double get currentObligations => monthUnpaidBills;

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

  bool get hasBillImminent => imminentBill != null;

  /// First unpaid current-month bill due today or tomorrow. `tomorrow` is
  /// guarded against the month boundary so `today + 1` can't match a phantom
  /// 31st on a 30-day month.
  Bill? get imminentBill {
    final now = DateTime.now();
    final today = now.day;
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final tomorrow = today + 1;
    return upcomingBills
        .where((b) =>
            b.dueDay == today || (b.dueDay == tomorrow && tomorrow <= lastDay))
        .firstOrNull;
  }

  double get todayOutflow {
    final now = DateTime.now();
    final excluded = _excludedCategoryIds;
    return _transactions.where((t) {
      return isSpendingOutflow(t, excluded) &&
          t.date.year == now.year &&
          t.date.month == now.month &&
          t.date.day == now.day;
    }).fold(0.0, (sum, t) => sum + t.amount);
  }

  double get todayInflow {
    final now = DateTime.now();
    final reimb = _reimbursementIds;
    final excluded = _excludedCategoryIds;
    return _transactions.where((t) {
      return isIncomeInflow(t, reimb, excluded) &&
          t.date.year == now.year &&
          t.date.month == now.month &&
          t.date.day == now.day;
    }).fold(0.0, (sum, t) => sum + t.amount);
  }

  /// A bill is overdue when it's unpaid and its due date has passed. The bill's
  /// month is honoured: a future-month bill is never overdue, and a past-month
  /// unpaid bill always is — comparing only `dueDay` would mis-flag both.
  bool isBillOverdue(Bill bill) {
    if (bill.isPaid) return false;
    final now = DateTime.now();
    final nowKey = toMonthKey(now);
    if (bill.month.compareTo(nowKey) < 0) return true; // a past month, unpaid
    if (bill.month.compareTo(nowKey) > 0) return false; // a future month
    return bill.dueDay < now.day; // this month
  }

  // --- Budget ---

  bool get hasBudget =>
      _budgets.any((b) => b.month == _currentMonth) ||
      _budgetedExpenses.any((e) => e.month == _currentMonth);

  double get totalBudgetAllocated => _budgets
      .where((b) => b.month == _currentMonth)
      .fold(0.0, (sum, b) => sum + b.allocatedAmount);

  /// Actual money spent against this month's budgets — real ledger outflows per
  /// expense category (and contributions into the target account for savings
  /// budgets), mirroring the Budget page's `spentFor`. Previously this counted
  /// only set-aside rows' `spentAmount`, so [totalBudgetRemaining] reserved the
  /// full monthly budget even as you spent through it (the forecast never shrank
  /// during the month).
  double get totalBudgetSpent => _budgets
      .where((b) => b.month == _currentMonth)
      .fold(0.0, (sum, b) => sum + _budgetSpentFor(b));

  bool _isSavingsGroup(String groupId) =>
      _budgetGroups.where((g) => g.id == groupId).firstOrNull?.isSavings ??
      false;

  List<BudgetGroupDef> get budgetGroups => List.unmodifiable(_budgetGroups);

  /// Allocated/spent across EXPENSE budgets only (savings groups excluded).
  /// The dashboard Budget Overview lists expense groups and shows savings in a
  /// separate card, so its "Total" row must use these — otherwise the Total
  /// (which [totalBudgetAllocated]/[totalBudgetSpent] compute over *all* budgets
  /// for cash forecasting) never reconciles with the rows beneath it.
  double get totalExpenseBudgetAllocated => _budgets
      .where((b) => b.month == _currentMonth && !_isSavingsGroup(b.group))
      .fold(0.0, (sum, b) => sum + b.allocatedAmount);

  double get totalExpenseBudgetSpent => _budgets
      .where((b) => b.month == _currentMonth && !_isSavingsGroup(b.group))
      .fold(0.0, (sum, b) => sum + _budgetSpentFor(b));

  double _budgetSpentFor(Budget b) {
    if (_isSavingsGroup(b.group)) {
      // Savings budgets track NET contributions INTO the target account (here
      // the "categoryId" is an account id): inflow legs add, outflow legs
      // subtract. This mirrors [monthSavingsContributions] and the Budget
      // page's `contributedTo` so all three surfaces report the same number —
      // a transfer between two savings accounts nets to zero, not double-count.
      var total = 0.0;
      for (final t in _transactions) {
        if (t.month != _currentMonth) continue;
        if (t.accountId != b.categoryId) continue;
        if (t.type == TransactionType.inflow) {
          total += t.amount;
        } else if (t.type == TransactionType.outflow) {
          total -= t.amount;
        }
      }
      return total;
    }
    // Only real spending eats a budget — [isSpendingOutflow] already excludes
    // reimbursables/loans, transfers, and excluded-from-totals categories
    // (consistent with headline Expenses and BudgetPresenter.spentFor).
    final excluded = _excludedCategoryIds;
    return _transactions
        .where((t) =>
            t.month == _currentMonth &&
            t.categoryId == b.categoryId &&
            isSpendingOutflow(t, excluded))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double get totalBudgetRemaining =>
      (totalBudgetAllocated - totalBudgetSpent).clamp(0.0, double.infinity);

  /// Overlap between unpaid bills and category budgets, so the forecast doesn't
  /// deduct the same obligation twice. An unpaid bill is already subtracted via
  /// [endingCash]; if its category also carries a monthly budget, that budget's
  /// remaining would subtract it a second time. We credit back the smaller of
  /// (unpaid-bill total in that category) and (that category's remaining budget).
  double get _unpaidBillBudgetOverlap {
    final unpaidByCategory = <String, double>{};
    for (final b in _bills) {
      if (b.month != _currentMonth || b.isPaid || b.categoryId.isEmpty) {
        continue;
      }
      unpaidByCategory[b.categoryId] =
          (unpaidByCategory[b.categoryId] ?? 0) + b.amount;
    }
    if (unpaidByCategory.isEmpty) return 0.0;
    var overlap = 0.0;
    for (final budget in _budgets.where((b) => b.month == _currentMonth)) {
      if (_isSavingsGroup(budget.group)) continue;
      final unpaid = unpaidByCategory[budget.categoryId];
      if (unpaid == null) continue;
      final remaining = (budget.allocatedAmount - _budgetSpentFor(budget))
          .clamp(0.0, double.infinity);
      overlap += unpaid < remaining ? unpaid : remaining;
    }
    return overlap;
  }

  /// Projected month-end cash: current liquid + incoming receivables, minus
  /// everything still expected to leave this month —
  ///   • unpaid bills (already netted in [endingCash]),
  ///   • budgeted set-asides not yet funded ([budgetedExpensesRemaining]),
  ///   • the remaining monthly category budget you still plan to spend
  ///     ([totalBudgetRemaining]) — which shrinks as actual spending accrues.
  double get forecastedNetBalance =>
      endingCash -
      budgetedExpensesRemaining -
      totalBudgetRemaining +
      _unpaidBillBudgetOverlap;

  Map<String, double> get budgetAllocatedByGroup {
    final result = <String, double>{};
    for (final b in _budgets.where((b) => b.month == _currentMonth)) {
      result[b.group] = (result[b.group] ?? 0.0) + b.allocatedAmount;
    }
    return result;
  }

  /// Actual spending per group from real ledger outflows (and savings
  /// contributions), keyed by group ID. Previously read set-aside rows
  /// which returned zero for most users.
  Map<String, double> get budgetSpentByGroup {
    final result = <String, double>{};
    for (final b in _budgets.where((b) => b.month == _currentMonth)) {
      result[b.group] = (result[b.group] ?? 0.0) + _budgetSpentFor(b);
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
    final excluded = _excludedCategoryIds;
    final spendMap = <String, double>{};
    for (final t in _transactions) {
      if (t.month == _currentMonth && isSpendingOutflow(t, excluded)) {
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
    final excluded = _excludedCategoryIds;
    return List.generate(n, (i) {
      final day = DateTime(now.year, now.month, now.day - (n - 1 - i));
      final total = _transactions
          .where((t) =>
              isSpendingOutflow(t, excluded) &&
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
    await _syncAccountsToLedger();
  }

  Future<void> updateAccount(FinancialAccount account) async {
    _accounts = [
      for (final a in _accounts) a.id == account.id ? account : a,
    ];
    notifyListeners();
    await _storage.saveAccounts(_accounts);
    await _syncAccountsToLedger();
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
    await _syncAccountsToLedger();
  }

  /// Account CRUD persists straight to storage, but LedgerPresenter is the
  /// source of truth and re-mirrors its in-memory accounts onto this dashboard
  /// (and the budget) on every notify via [_syncFromLedger]. Without telling the
  /// ledger to re-read, a later unrelated ledger mutation would clobber the
  /// dashboard back to its stale account list — a just-added account vanishing,
  /// or a deleted one returning. Reloading keeps all three in step.
  Future<void> _syncAccountsToLedger() async {
    await _ledger?.reloadAccounts();
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _accounts = await _storage.loadAccounts();
    _transactions = await _storage.loadTransactions();
    _bills = await _storage.loadBills();
    _receivables = await _storage.loadReceivables();
    _budgets = await _storage.loadBudgets();
    _budgetGroups = BudgetGroupDef.merge(await _storage.loadBudgetGroups());
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
