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
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
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

/// One bucket of [TreasuryDashboardPresenter.accountInventory]: a set of
/// accounts plus a plain statement of where the dashboard surfaces them.
@immutable
class AccountInventoryGroup {
  /// Bucket name, e.g. `'Cash & banks'`.
  final String title;

  /// Where these accounts show up, phrased for the user rather than the code.
  final String surfacedIn;

  /// True when the dashboard's Accounts section renders these as tiles.
  final bool onDashboard;

  final List<FinancialAccount> accounts;

  const AccountInventoryGroup({
    required this.title,
    required this.surfacedIn,
    required this.onDashboard,
    required this.accounts,
  });

  /// Summed balance of the bucket. For `Credit & BNPL` this is money **owed**,
  /// not money held — the dialog labels it accordingly.
  double get total => accounts.fold(0.0, (sum, a) => sum + a.balance);
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
  TreasuryDashboardPresenter(
    StorageService storage, [
    LedgerPresenter? ledger,
    BudgetPresenter? budget,
    BillsReceivablesPresenter? bills,
  ])  : _storage = storage,
        _ledger = ledger,
        _budget = budget,
        _billsPresenter = bills {
    load();
    _ledger?.addListener(_syncFromLedger);
    _budget?.addListener(_syncFromBudget);
    _billsPresenter?.addListener(_syncFromBills);
  }

  final StorageService _storage;
  final LedgerPresenter? _ledger;

  /// The owner of the budgets this presenter reports on. Optional so the
  /// dashboard still builds standalone (tests, single-screen mounts), where it
  /// falls back to whatever [load] read from storage.
  final BudgetPresenter? _budget;

  /// The owner of the bills, receivables and budgeted expenses this presenter
  /// reports on. Optional on the same terms as [_budget]. Named apart from the
  /// `_bills` list below, which is this presenter's mirrored copy.
  final BillsReceivablesPresenter? _billsPresenter;

  /// Mirror accounts/transactions/categories from LedgerPresenter so that
  /// dashboard summaries reflect ledger mutations without waiting for a tab
  /// switch or app restart.
  ///
  /// This is the pattern every slice of borrowed state follows here — see also
  /// [_syncFromBudget] and [_syncFromBills]. The rule: whoever displays data
  /// someone else owns subscribes to the owner. Never a private copy refreshed
  /// only by this presenter's own [load].
  void _syncFromLedger() {
    final ledger = _ledger;
    if (ledger == null) return;
    _accounts = ledger.accounts;
    _transactions = ledger.allTransactions;
    _categories = ledger.categories;
    notifyListeners();
  }

  /// Mirror budgets and groups from their owner, [BudgetPresenter].
  ///
  /// These used to be read only in [load], so an allocation edited on the
  /// Budget page left every budget-derived figure here stale: Budget Overview,
  /// "Budget Left", and — through [forecastedNetBalance] — the projected
  /// month-end cash on the Hub's Finance card, which never reloads on its own.
  ///
  /// Subscribing rather than having the budget presenter push means the
  /// dependency is declared once, here, by the presenter that actually needs
  /// it: a new budget mutation cannot forget to announce itself.
  void _syncFromBudget() {
    final budget = _budget;
    if (budget == null) return;
    final budgets = budget.allBudgets;
    final groups = budget.groups;
    // BudgetPresenter also notifies for month changes and its own ledger sync.
    // Skip the repaint when the mirrored data is unchanged, so those don't
    // rebuild the dashboard for nothing. Budget/BudgetGroupDef don't override
    // `==`, so this compares element identity — and every mutation rebuilds the
    // list with at least one fresh element, which is exactly the signal wanted.
    if (listEquals(budgets, _budgets) && listEquals(groups, _budgetGroups)) {
      return;
    }
    _budgets = budgets;
    _budgetGroups = groups;
    notifyListeners();
  }

  /// Mirror bills, receivables and budgeted expenses from their owner,
  /// [BillsReceivablesPresenter].
  ///
  /// The last slice to move off the push model: bills used to reload this
  /// presenter itself after each of its ~28 mutations, which every new mutation
  /// had to remember to do. Subscribing puts the dependency where it belongs —
  /// with the presenter that needs the data — and costs an in-memory list swap
  /// instead of a full re-read of storage.
  void _syncFromBills() {
    final owner = _billsPresenter;
    if (owner == null) return;
    final bills = owner.allBills;
    final receivables = owner.allReceivables;
    final expenses = owner.allBudgetedExpenses;
    // Same guard as _syncFromBudget: the owner also notifies for month changes
    // and selection state, which don't change what this presenter shows.
    if (listEquals(bills, _bills) &&
        listEquals(receivables, _receivables) &&
        listEquals(expenses, _budgetedExpenses)) {
      return;
    }
    _bills = bills;
    _receivables = receivables;
    _budgetedExpenses = expenses;
    notifyListeners();
  }

  @override
  void dispose() {
    _ledger?.removeListener(_syncFromLedger);
    _budget?.removeListener(_syncFromBudget);
    _billsPresenter?.removeListener(_syncFromBills);
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

  /// Where a credit account sits in its statement cycle, as a line under the
  /// due date. Null once the cycle has closed — the statement is a bill by then,
  /// so the Bills tab speaks for itself.
  ///
  /// Closes two gaps where the card looked fully configured but the Bills tab
  /// stayed empty:
  ///   - No statement day (or no due day) means the generator skips the account
  ///     entirely and it is never billed — silently, until now.
  ///   - A cycle that has not closed yet has no bill to find. The balance and
  ///     due date are both real, so the absence read as a missing statement.
  ({String label, bool warning})? creditCycleNote(FinancialAccount a) {
    if (!a.isLiability) return null;
    final stmtDay = a.statementDay;
    if (stmtDay == null || a.paymentDueDay == null) {
      return (
        label: 'Needs a statement day and due day to bill automatically',
        warning: true,
      );
    }
    final now = DateTime.now();
    if (now.day >= stmtDay.clamp(1, 28)) return null; // closed → it's a bill
    final closesOn = DateTime(now.year, now.month, stmtDay.clamp(1, 28));
    return (
      label: 'Statement closes ${monthDayLabel(closesOn)}',
      warning: false,
    );
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

  /// Active time-deposit accounts, earliest maturity first — money that unlocks
  /// on a future date. Powers the advisor's forward liquidity view.
  List<FinancialAccount> get timeDepositAccounts => _accounts
      .where((a) => a.isActive && a.category == AccountCategory.timeDeposit)
      .toList()
    ..sort((a, b) {
      final ad = a.maturityDate, bd = b.maturityDate;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });

  List<FinancialAccount> subAccountsOf(String parentId) =>
      _accounts.where((a) => a.parentAccountId == parentId).toList();

  /// Every account the treasury knows about, bucketed by where the dashboard
  /// surfaces it — the data behind the "All accounts" dialog.
  ///
  /// The Accounts section deliberately shows only top-level liquid and credit
  /// accounts, so savings pockets, goals, investments, sub-accounts, custodian
  /// money and archived accounts are all absent from it by design. There was no
  /// way to tell a *deliberately filtered* account from a *missing* one, which
  /// is exactly the doubt to remove.
  ///
  /// Buckets are assigned in order and each account lands in exactly one, so
  /// the dialog's counts add up to the real total with nothing double-listed.
  /// Empty buckets are dropped.
  List<AccountInventoryGroup> get accountInventory {
    final claimed = <String>{};
    final groups = <AccountInventoryGroup>[];

    void add(
      String title,
      String surfacedIn,
      bool onDashboard,
      Iterable<FinancialAccount> candidates,
    ) {
      final take = [
        for (final a in candidates)
          if (claimed.add(a.id)) a,
      ];
      if (take.isEmpty) return;
      groups.add(AccountInventoryGroup(
        title: title,
        surfacedIn: surfacedIn,
        onDashboard: onDashboard,
        accounts: take,
      ));
    }

    // The two buckets the Accounts section renders, in the order it renders
    // them, so the dialog reads as a superset of what's on screen.
    add('Cash & banks', 'Accounts tiles · Liquid Cash · Total Assets', true,
        liquidAccounts);
    add('Credit & BNPL', 'Accounts tiles · Credit section', true,
        creditAccounts);

    final topLevel =
        _accounts.where((a) => a.isActive && a.parentAccountId == null);
    add(
      'Savings, goals & time deposits',
      'Total Assets · Savings Goals card — no Accounts tile',
      false,
      topLevel.where((a) =>
          a.category == AccountCategory.savings ||
          a.category == AccountCategory.goal ||
          a.category == AccountCategory.timeDeposit),
    );
    add(
      'Investments',
      'Total Assets — no Accounts tile',
      false,
      topLevel.where((a) => a.category == AccountCategory.investment),
    );
    add(
      'Pockets inside another account',
      'Balance already counted inside the parent account',
      false,
      _accounts.where((a) => a.isActive && a.parentAccountId != null),
    );
    add(
      'Held for others',
      'Excluded from net worth — not your money',
      false,
      _accounts.where((a) => a.isActive && a.isCustodian),
    );
    add(
      'Archived',
      'Hidden everywhere until reactivated',
      false,
      _accounts.where((a) => !a.isActive),
    );

    return groups;
  }

  /// Total accounts across [accountInventory] — the figure the "All accounts"
  /// trigger shows. Kept here so the view never counts in `build()`.
  int get accountInventoryCount =>
      accountInventory.fold(0, (n, g) => n + g.accounts.length);

  /// How many of those the Accounts section actually renders as tiles.
  int get accountInventoryShownCount => accountInventory
      .where((g) => g.onDashboard)
      .fold(0, (n, g) => n + g.accounts.length);

  /// Total set aside in savings + goal pockets — powers the Setup
  /// "Savings & Goals" KPI. Matches the set of accounts the Setup page groups
  /// under that heading ([savingsAccounts] + [goalAccounts]).
  double get totalSavingsAndGoals => [
        ...savingsAccounts,
        ...goalAccounts,
      ].fold(0.0, (sum, a) => sum + a.balance);

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
    final heldInLiquid = liquidAccounts.fold(
      0.0,
      (sum, a) => sum + (held[a.id] ?? 0.0),
    );
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

  /// Still-outstanding receivables this month, soonest-expected first — lets the
  /// advisor itemise money coming in, not just a total.
  List<Receivable> get outstandingReceivables => _receivables
      .where((r) => r.month == _currentMonth && !r.isReceived)
      .toList()
    ..sort((a, b) {
      final ad = a.expectedDate, bd = b.expectedDate;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });

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
        .where(
          (t) => t.month == _currentMonth && isIncomeInflow(t, reimb, excluded),
        )
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double get monthTotalOutflow {
    final excluded = _excludedCategoryIds;
    return _transactions
        .where(
          (t) => t.month == _currentMonth && isSpendingOutflow(t, excluded),
        )
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Sum of top-level, non-liability, non-custodian account balances — the
  /// gross asset base (before deducting money held for others or liabilities).
  /// Only top-level accounts are summed: sub-account balances are already
  /// reflected in their parent via the propagation rule in
  /// [LedgerPresenter._applyBalanceDelta], so summing both would double-count.
  Iterable<FinancialAccount> get _assetAccounts => _accounts.where(
        (a) =>
            a.isActive &&
            !a.isLiability &&
            !a.isCustodian &&
            a.parentAccountId == null,
      );

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
            (e.allocatedAmount - e.spentAmount).clamp(0.0, double.infinity),
      );

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

  /// Bills already scheduled for NEXT month (recurring copies, credit-card
  /// statements filed forward). Powers the advisor's forward look — "what's
  /// coming after this month". Unpaid only.
  double get nextMonthUnpaidBills {
    final nm = nextMonth(_currentMonth);
    return _bills
        .where((b) => b.month == nm && !b.isPaid)
        .fold(0.0, (sum, b) => sum + b.amount);
  }

  /// Receivables expected NEXT month (money owed to you), still outstanding.
  double get nextMonthPendingReceivables {
    final nm = nextMonth(_currentMonth);
    return _receivables
        .where((r) => r.month == nm && !r.isReceived)
        .fold(0.0, (sum, r) => sum + r.amount);
  }

  /// Bills already PAID this month — the settled half of the present picture
  /// (the unpaid half is [upcomingBills]). Name + amount actually paid.
  List<({String name, double amount})> get paidBillsThisMonth => _bills
      .where((b) => b.month == _currentMonth && b.isPaid)
      .map((b) => (name: b.name, amount: b.paidAmount ?? b.amount))
      .toList();

  /// Receivables already RECEIVED this month (money that has landed). Name +
  /// amount actually received.
  List<({String name, double amount})> get receivedThisMonth => _receivables
      .where((r) => r.month == _currentMonth && r.isReceived)
      .map((r) => (name: r.name, amount: r.receivedAmount ?? r.amount))
      .toList();

  /// Set-asides / sinking funds for THIS month, itemized: name, allocated,
  /// amount funded so far, remaining to fund, and whether it's fully funded.
  List<({String name, double allocated, double funded, double remaining, bool isPaid})>
      get setAsidesThisMonth => _budgetedExpenses
          .where((e) => e.month == _currentMonth)
          .map((e) => (
                name: e.name,
                allocated: e.allocatedAmount,
                funded: e.spentAmount,
                remaining: (e.allocatedAmount - e.spentAmount)
                    .clamp(0.0, double.infinity),
                isPaid: e.isPaid,
              ))
          .toList();

  /// Per-closed-month bills & receivables + savings, oldest → newest, from the
  /// stored month-end summaries (line items aren't retained per closed month,
  /// so these are the month totals). Excludes the in-progress current month.
  List<
      ({
        String label,
        double billed,
        double billsPaid,
        double receivablesExpected,
        double received,
        double netSavings
      })> historicalLedger({int months = 6}) {
    final out = <({
      String label,
      double billed,
      double billsPaid,
      double receivablesExpected,
      double received,
      double netSavings
    })>[];
    for (final key in _lastNMonthKeys(months)) {
      if (key == _currentMonth) continue;
      final s = _summaryFor(key);
      if (s == null) continue;
      out.add((
        label: monthShortLabel(key),
        billed: s.totalBills,
        billsPaid: s.totalBillsPaid,
        receivablesExpected: s.totalReceivables,
        received: s.totalReceived,
        netSavings: s.netSavings,
      ));
    }
    return out;
  }

  /// Recurring monthly commitments — one entry per distinct recurring bill /
  /// receivable (deduped by name, preferring the current month's instance).
  /// Amount is the forward-looking one (`nextMonthAmount` when the user staged
  /// one). Lets the advisor plan any future month — e.g. "Internet ₱999 due the
  /// 15th" — even when that month hasn't been materialized in storage yet.
  /// `isInflow` marks money coming in (receivables) vs out (bills).
  List<({String name, double amount, int dueDay, bool isInflow})>
      get recurringCommitments {
    final bills = <String, Bill>{};
    for (final b in _bills.where((b) => b.isRecurring)) {
      final e = bills[b.name];
      if (e == null ||
          b.month == _currentMonth ||
          (e.month != _currentMonth && b.month.compareTo(e.month) > 0)) {
        bills[b.name] = b;
      }
    }
    final recs = <String, Receivable>{};
    for (final r in _receivables.where((r) => r.isRecurring)) {
      final e = recs[r.name];
      if (e == null ||
          r.month == _currentMonth ||
          (e.month != _currentMonth && r.month.compareTo(e.month) > 0)) {
        recs[r.name] = r;
      }
    }
    final out = <({String name, double amount, int dueDay, bool isInflow})>[
      for (final b in bills.values)
        (
          name: b.name,
          amount: b.nextMonthAmount ?? b.amount,
          dueDay: b.dueDay,
          isInflow: false,
        ),
      for (final r in recs.values)
        (
          name: r.name,
          amount: r.nextMonthAmount ?? r.amount,
          dueDay: r.expectedDate?.day ?? 1,
          isInflow: true,
        ),
    ];
    out.sort((a, b) => a.dueDay.compareTo(b.dueDay));
    return out.take(20).toList();
  }

  /// One-off obligations already scheduled for a FUTURE month — non-recurring,
  /// still-open bills and receivables the user planned ahead (recurring ones are
  /// covered by [recurringCommitments]; auto credit-card statements excluded).
  /// Sorted soonest month, then day. `day` is null when a receivable has no
  /// expected date.
  List<({String name, double amount, String month, int? day, bool isInflow})>
      get scheduledFutureObligations {
    final out = <({
      String name,
      double amount,
      String month,
      int? day,
      bool isInflow
    })>[];
    for (final b in _bills.where((b) =>
        !b.isPaid &&
        !b.isRecurring &&
        !b.isAutoStatement &&
        b.month.compareTo(_currentMonth) > 0)) {
      out.add((
        name: b.name,
        amount: b.amount,
        month: b.month,
        day: b.dueDay,
        isInflow: false,
      ));
    }
    for (final r in _receivables.where((r) =>
        !r.isReceived &&
        !r.isRecurring &&
        r.month.compareTo(_currentMonth) > 0)) {
      out.add((
        name: r.name,
        amount: r.amount,
        month: r.month,
        day: r.expectedDate?.day,
        isInflow: true,
      ));
    }
    out.sort((a, b) {
      final m = a.month.compareTo(b.month);
      if (m != 0) return m;
      return (a.day ?? 99).compareTo(b.day ?? 99);
    });
    return out.take(12).toList();
  }

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
        .where(
          (b) =>
              b.dueDay == today ||
              (b.dueDay == tomorrow && tomorrow <= lastDay),
        )
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

  /// True when [leg] is one side of a transfer whose *other* side is also a
  /// savings or goal account — money shuffled between two funds rather than
  /// moved into savings from outside.
  bool _isInternalSavingsTransferLeg(TransactionRecord leg) {
    final groupId = leg.transferGroupId;
    if (groupId == null) return false;
    for (final other in _transactions) {
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

  double _budgetSpentFor(Budget b) {
    if (_isSavingsGroup(b.group)) {
      // Savings budgets track what was funded INTO the target account (here the
      // "categoryId" is an account id): inflow legs only, minus the legs of a
      // transfer between two savings/goal accounts, which fund neither. Mirrors
      // `BudgetPresenter.fundedInto` so both surfaces report the same number.
      //
      // Withdrawals deliberately do not subtract. They used to, and it made the
      // forecast reserve money already moved: fund ₱3,000 into Braces, pay the
      // dentist ₱1,800 out of it, and the net ₱1,200 left ₱1,800 of the budget
      // reading as "still to set aside" — deducted from projected cash a second
      // time, on top of the withdrawal that had already reduced it.
      // [monthSavingsContributions] still nets, because "how much did savings
      // grow" is a different question from "did I fund the plan".
      var total = 0.0;
      for (final t in _transactions) {
        if (t.month != _currentMonth) continue;
        if (t.accountId != b.categoryId) continue;
        if (t.type != TransactionType.inflow) continue;
        if (_isInternalSavingsTransferLeg(t)) continue;
        total += t.amount;
      }
      return total;
    }
    // Only real spending eats a budget — [isSpendingOutflow] already excludes
    // reimbursables/loans, transfers, and excluded-from-totals categories
    // (consistent with headline Expenses and BudgetPresenter.spentFor).
    final excluded = _excludedCategoryIds;
    return _transactions
        .where(
          (t) =>
              t.month == _currentMonth &&
              t.categoryId == b.categoryId &&
              isSpendingOutflow(t, excluded),
        )
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double get totalBudgetRemaining =>
      (totalBudgetAllocated - totalBudgetSpent).clamp(0.0, double.infinity);

  /// Named obligations still outstanding this month, totalled per category:
  /// unpaid bills plus unfunded budgeted-expense set-asides. Both are already
  /// subtracted from the forecast in their own right — bills through
  /// [endingCash], set-asides through [budgetedExpensesRemaining] — so this map
  /// is what [_obligationBudgetOverlap] credits back where a category budget
  /// would otherwise reserve the same peso a second time.
  Map<String, double> get _outstandingObligationsByCategory {
    final byCategory = <String, double>{};
    for (final b in _bills) {
      if (b.month != _currentMonth || b.isPaid || b.categoryId.isEmpty) {
        continue;
      }
      byCategory[b.categoryId] = (byCategory[b.categoryId] ?? 0) + b.amount;
    }
    for (final e in _budgetedExpenses) {
      if (e.month != _currentMonth || e.isPaid || e.categoryId.isEmpty) {
        continue;
      }
      final unfunded =
          (e.allocatedAmount - e.spentAmount).clamp(0.0, double.infinity);
      if (unfunded <= 0) continue;
      byCategory[e.categoryId] = (byCategory[e.categoryId] ?? 0) + unfunded;
    }
    return byCategory;
  }

  /// Overlap between this month's named obligations and its category budgets,
  /// so the forecast doesn't deduct the same peso twice.
  ///
  /// An unpaid bill is already subtracted via [endingCash], and an unfunded
  /// set-aside via [budgetedExpensesRemaining]; if either one's category also
  /// carries a monthly budget, [totalBudgetRemaining] would subtract it again.
  /// We credit back the smaller of (obligations in that category) and (that
  /// category's remaining budget).
  ///
  /// Obligations are pooled per category *before* the clamp, which is the whole
  /// reason bills and set-asides can't each own a credit: a category holding a
  /// ₱2,000 bill and a ₱2,000 set-aside against ₱3,000 of remaining budget has
  /// only ₱3,000 of double-counting to undo, not ₱4,000.
  ///
  /// Savings groups are skipped — a savings budget's `categoryId` is an
  /// *account* id (see [_budgetSpentFor]), so it shares no key space with the
  /// category ids bills and set-asides carry.
  /// The slice of [budget] — a savings row — already reserved by an unfunded
  /// set-aside pointing at the same account.
  ///
  /// The general path above matches obligations by `categoryId`, which cannot
  /// see this: a savings budget's `categoryId` is an *account* id, while a
  /// set-aside's `categoryId` is an expense category. The key that does join
  /// them is `destinationAccountId` — where the set-aside's money lands.
  ///
  /// Without this, a ₱3,000 savings budget plus an unfunded ₱3,000 set-aside
  /// into the same goal reserved ₱6,000 against month-end cash: once through
  /// [budgetedExpensesRemaining] and again through [totalBudgetRemaining], with
  /// nothing credited back. The forecast read low for as long as the set-aside
  /// stayed unfunded — which is most of a month — and corrected itself only
  /// once funded, so it looked like the projection drifting rather than a
  /// double count.
  double _savingsSetAsideOverlap(Budget budget) {
    var owed = 0.0;
    for (final e in _budgetedExpenses) {
      if (e.month != _currentMonth || e.isPaid) continue;
      if (e.destinationAccountId != budget.categoryId) continue;
      owed += (e.allocatedAmount - e.spentAmount).clamp(0.0, double.infinity);
    }
    if (owed <= 0) return 0.0;
    final remaining = (budget.allocatedAmount - _budgetSpentFor(budget))
        .clamp(0.0, double.infinity);
    return owed < remaining ? owed : remaining;
  }

  double get _obligationBudgetOverlap {
    final obligations = _outstandingObligationsByCategory;
    if (obligations.isEmpty) return 0.0;
    var overlap = 0.0;
    for (final budget in _budgets.where((b) => b.month == _currentMonth)) {
      if (_isSavingsGroup(budget.group)) {
        overlap += _savingsSetAsideOverlap(budget);
        continue;
      }
      final owed = obligations[budget.categoryId];
      if (owed == null) continue;
      final remaining = (budget.allocatedAmount - _budgetSpentFor(budget))
          .clamp(0.0, double.infinity);
      overlap += owed < remaining ? owed : remaining;
    }
    // Never credit back more than [totalBudgetRemaining] actually deducted.
    // Each budget's remaining is clamped at zero individually here, while the
    // deduction is one clamp over the summed total — so a category overspent
    // elsewhere could otherwise let the credit exceed the charge and inflate
    // the forecast above your real cash.
    final cap = totalBudgetRemaining;
    return overlap < cap ? overlap : cap;
  }

  /// [totalBudgetRemaining] less the slice already reserved by an outstanding
  /// bill or unfunded set-aside in the same category — the budget's own
  /// marginal claim on month-end cash.
  ///
  /// This is what the Month-End Outlook grid shows as "Budget Left", so the
  /// tiles reconcile to [forecastedNetBalance] exactly:
  ///
  ///   liquid + toReceive − bills − setAsides − thisFigure = forecast
  ///
  /// Never negative: [_obligationBudgetOverlap] is capped at
  /// [totalBudgetRemaining].
  double get budgetRemainingNetOfObligations =>
      totalBudgetRemaining - _obligationBudgetOverlap;

  /// Projected month-end cash: current liquid + incoming receivables, minus
  /// everything still expected to leave this month —
  ///   • unpaid bills (already netted in [endingCash]),
  ///   • budgeted set-asides not yet funded ([budgetedExpensesRemaining]),
  ///   • the remaining monthly category budget you still plan to spend
  ///     ([totalBudgetRemaining]) — which shrinks as actual spending accrues,
  ///   • less [_obligationBudgetOverlap], so a bill or set-aside whose category
  ///     also carries a budget isn't reserved twice.
  ///
  /// Every term is surfaced as its own tile in the Month-End Outlook grid, so
  /// the drop from [totalLiquidCash] to this figure is always accountable.
  double get forecastedNetBalance =>
      endingCash -
      budgetedExpensesRemaining -
      totalBudgetRemaining +
      _obligationBudgetOverlap;

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

  /// Average monthly spend per category over the [months] complete months
  /// BEFORE the current one, keyed by category id.
  ///
  /// The current month is excluded on purpose: it is the thing being compared,
  /// and folding it in would drag the baseline toward whatever is being judged.
  /// Months with no spend on a category still count in the divisor — a category
  /// bought twice a year averages low, which is the honest reading.
  ///
  /// Divides by however many months of history actually exist, so a two-month-old
  /// ledger reports a two-month average rather than a figure quietly diluted by
  /// four empty months.
  ({Map<String, double> averages, int months}) categoryTrailingAverage({
    int months = 3,
  }) {
    final excluded = _excludedCategoryIds;
    final keys = <String>[];
    var cursor = previousMonth(_currentMonth);
    for (var i = 0; i < months; i++) {
      keys.add(cursor);
      cursor = previousMonth(cursor);
    }
    // Only count months the ledger could actually have covered.
    final firstMonth = _transactions.isEmpty
        ? null
        : _transactions
            .map((t) => t.month)
            .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
    final usable = firstMonth == null
        ? <String>[]
        : keys.where((k) => k.compareTo(firstMonth) >= 0).toList();
    if (usable.isEmpty) {
      return (averages: const <String, double>{}, months: 0);
    }
    final totals = <String, double>{};
    for (final t in _transactions) {
      if (!usable.contains(t.month)) continue;
      if (!isSpendingOutflow(t, excluded)) continue;
      totals[t.categoryId] = (totals[t.categoryId] ?? 0) + t.amount;
    }
    final divisor = usable.length;
    return (
      averages: {
        for (final e in totals.entries) e.key: e.value / divisor,
      },
      months: divisor,
    );
  }

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

  /// Most recent spending outflows (real expenses — transfers, reimbursables,
  /// and excluded categories filtered out), newest first, capped at [limit].
  /// Display-ready with the category name resolved so a caller (e.g. the AI
  /// advisor) can see where money actually went, not just monthly totals.
  List<({DateTime date, String description, double amount, String category})>
      recentSpending({int limit = 8}) {
    final excluded = _excludedCategoryIds;
    final txns = _transactions
        .where((t) => isSpendingOutflow(t, excluded))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final nameById = {for (final c in _categories) c.id: c.name};
    return [
      for (final t in txns.take(limit))
        (
          date: t.date,
          description: t.description,
          amount: t.amount,
          category: nameById[t.categoryId] ?? 'Uncategorized',
        ),
    ];
  }

  List<DailySpend> get last7DaysSpending => _lastNDaysSpending(7);

  /// Flexible — used by the full spending history sheet.
  List<DailySpend> lastNDaysSpending(int n) => _lastNDaysSpending(n);

  /// Daily spend for an inclusive whole-day range [start, end]. Powers the
  /// dashboard spending card's range selector (this month / last month / etc.).
  List<DailySpend> dailySpendForRange(DateTime start, DateTime end) {
    final excluded = _excludedCategoryIds;
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final count = e.difference(s).inDays + 1;
    return List.generate(count.clamp(1, 366), (i) {
      final day = DateTime(s.year, s.month, s.day + i);
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

  List<DailySpend> _lastNDaysSpending(int n) {
    final now = DateTime.now();
    final excluded = _excludedCategoryIds;
    return List.generate(n, (i) {
      final day = DateTime(now.year, now.month, now.day - (n - 1 - i));
      final total = _transactions
          .where(
            (t) =>
                isSpendingOutflow(t, excluded) &&
                t.date.year == day.year &&
                t.date.month == day.month &&
                t.date.day == day.day,
          )
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

  // --- Net-worth momentum (dashboard hero pill) ---
  //
  // Pure derivations over [netWorthTrend] — no stored state. Used by the redesign
  // hero's trend pill and "this month" line. Both return null when there is no
  // usable prior month-end, so the UI omits the pill rather than dividing by zero.

  /// Change in net worth versus the previous month-end. Null when fewer than two
  /// trend points exist.
  double? get netWorthMonthDelta {
    final trend = netWorthTrend(months: 2);
    if (trend.length < 2) return null;
    return trend.last.value - trend.first.value;
  }

  /// Net-worth month-over-month change as a fraction of the previous month-end
  /// (0.027 → +2.7%). Null when there is no prior point or its value is zero.
  double? get netWorthMonthDeltaPct {
    final trend = netWorthTrend(months: 2);
    if (trend.length < 2) return null;
    final base = trend.first.value;
    if (base == 0) return null;
    return (trend.last.value - trend.first.value) / base.abs();
  }

  /// Whole days remaining in the current calendar month (0 on the last day).
  int get daysLeftInMonth {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return (lastDay - now.day).clamp(0, lastDay);
  }

  /// Income vs expenses for the last [months] months, oldest → newest. The
  /// current month uses live totals; closed months come from their summary.
  /// Months with no summary are omitted.
  List<({String label, double income, double expense})> incomeExpenseTrend({
    int months = 6,
  }) {
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
      added.add(
        MonthlySummary(
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
        ),
      );
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
    _accounts = [for (final a in _accounts) a.id == account.id ? account : a];
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
    final hasTxns = _transactions.any(
      (t) => t.accountId == id || t.transferToAccountId == id,
    );
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
