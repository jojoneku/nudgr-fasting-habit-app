import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/grocery/cart_item.dart';
import 'package:intermittent_fasting/models/grocery/item_unit.dart';
import 'package:intermittent_fasting/models/grocery/remembered_price.dart';
import 'package:intermittent_fasting/models/grocery/saved_trip.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/treasury_presenters.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 3: `getView` reads every finance screen.
///
/// Each test builds the real presenter graph on one small fixture and checks
/// the tool's output against the getters that screen renders. A screen that
/// moves to another getter without `FinanceViewReader` following it shows up
/// here as a figure the output no longer contains.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final now = toMonthKey(DateTime.now());
  final prev = previousMonth(now);

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late TreasuryPresenters t;

  FinancialAccount account(
          String id, String name, AccountCategory category, double balance,
          {double? creditLimit,
          int? statementDay,
          int? paymentDueDay,
          String? linkedAccountId}) =>
      FinancialAccount(
        id: id,
        name: name,
        category: category,
        balance: balance,
        colorHex: '#FFFFFF',
        icon: 'wallet',
        creditLimit: creditLimit,
        statementDay: statementDay,
        paymentDueDay: paymentDueDay,
        linkedAccountId: linkedAccountId,
      );

  FinanceCategory category(String id, String name, CategoryType type) =>
      FinanceCategory(
        id: id,
        name: name,
        type: type,
        icon: 'tag',
        colorHex: '#FFFFFF',
      );

  TransactionRecord txn(String id, String month, int day, String accountId,
          String categoryId, double amount, TransactionType type,
          {String? group, String? owedBy}) =>
      TransactionRecord(
        id: id,
        date: DateTime.parse('$month-${day.toString().padLeft(2, '0')}'),
        accountId: accountId,
        categoryId: categoryId,
        amount: amount,
        type: type,
        description: id,
        month: month,
        transferGroupId: group,
        reimbursable: owedBy != null,
        reimbursementReceivableId: owedBy,
      );

  Budget budget(String id, String month, String categoryId, double amount,
          String group) =>
      Budget(
        id: id,
        categoryId: categoryId,
        month: month,
        allocatedAmount: amount,
        group: group,
        budgetType: BudgetType.monthly,
      );

  setUp(() async {
    storage = MockStorageService();
    stats = MockStatsPresenter();

    final accounts = [
      account('bpi', 'BPI', AccountCategory.bank, 20000),
      account('fund', 'Emergency Fund', AccountCategory.savings, 5000),
      account('visa', 'Visa', AccountCategory.creditCard, 3000,
          creditLimit: 50000, statementDay: 15, paymentDueDay: 5),
      account('mom', "Mom's cash", AccountCategory.custodian, 2000,
          linkedAccountId: 'bpi'),
    ];
    final categories = [
      category('food', 'Food', CategoryType.expense),
      category('salary', 'Salary', CategoryType.income),
    ];
    final txns = [
      txn('sal', now, 1, 'bpi', 'salary', 30000, TransactionType.inflow),
      txn('f1', now, 1, 'bpi', 'food', 1200, TransactionType.outflow),
      txn('f2', now, 2, 'visa', 'food', 800, TransactionType.outflow),
      txn('x-out', now, 1, 'bpi', 'food', 2000, TransactionType.outflow,
          group: 'g1'),
      txn('x-in', now, 1, 'fund', 'food', 2000, TransactionType.inflow,
          group: 'g1'),
      txn('lend', now, 2, 'bpi', 'food', 500, TransactionType.outflow,
          owedBy: 'ana'),
      txn('sal0', prev, 1, 'bpi', 'salary', 25000, TransactionType.inflow),
      txn('f0', prev, 3, 'bpi', 'food', 3000, TransactionType.outflow),
    ];
    final budgets = [
      budget('b1', now, 'food', 5000, BudgetGroupDef.idVariableOptional),
      budget('b2', now, 'fund', 3000, BudgetGroupDef.idSavings),
      budget('b0', prev, 'food', 4000, BudgetGroupDef.idVariableOptional),
    ];
    final bills = [
      Bill(
          id: 'net',
          name: 'Internet',
          billType: BillType.utility,
          amount: 1500,
          dueDay: 28,
          month: now,
          categoryId: 'food'),
      Bill(
          id: 'rent',
          name: 'Rent',
          billType: BillType.other,
          amount: 8000,
          dueDay: 1,
          month: now,
          categoryId: 'food',
          isPaid: true,
          paidAmount: 8000),
      Bill(
          id: 'net0',
          name: 'Internet',
          billType: BillType.utility,
          amount: 1400,
          dueDay: 28,
          month: prev,
          categoryId: 'food',
          isPaid: true,
          paidAmount: 1400),
    ];
    final receivables = [
      Receivable(
          id: 'ana',
          name: 'Loan to Ana',
          receivableType: ReceivableType.reimbursement,
          amount: 1000,
          month: now,
          categoryId: 'salary'),
    ];
    final setAsides = [
      BudgetedExpense(
          id: 'braces',
          name: 'Braces',
          budgetedType: SetAsideType.goal,
          month: now,
          allocatedAmount: 3000,
          spentAmount: 1000,
          categoryId: ''),
    ];
    final installments = [
      Installment(
          id: 'phone',
          name: 'Phone',
          accountId: 'visa',
          totalAmount: 24000,
          monthlyAmount: 2000,
          totalMonths: 12,
          startMonth: prev,
          interestRate: 1),
      Installment(
          id: 'tv',
          name: 'TV',
          accountId: 'visa',
          totalAmount: 6000,
          monthlyAmount: 1000,
          totalMonths: 6,
          startMonth: prev,
          isActive: false),
    ];

    var summaries = <MonthlySummary>[];
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.loadBudgets()).thenAnswer((_) async => budgets);
    when(storage.saveBudgets(any)).thenAnswer((_) async {});
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.saveBudgetGroups(any)).thenAnswer((_) async {});
    when(storage.loadTransactions()).thenAnswer((_) async => txns);
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.loadFinanceCategories()).thenAnswer((_) async => categories);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadBills()).thenAnswer((_) async => bills);
    when(storage.saveBills(any)).thenAnswer((_) async {});
    when(storage.loadReceivables()).thenAnswer((_) async => receivables);
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => setAsides);
    when(storage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => summaries);
    when(storage.saveMonthlySummaries(any)).thenAnswer((inv) async {
      summaries = List<MonthlySummary>.from(
          inv.positionalArguments.first as List<MonthlySummary>);
    });
    when(storage.loadInstallments()).thenAnswer((_) async => installments);
    when(storage.saveInstallments(any)).thenAnswer((_) async {});
    when(storage.loadGroceryCart()).thenAnswer((_) async => [
          CartItem(
              id: 'c1',
              name: 'Rice',
              quantity: 2,
              unit: ItemUnit.kilogram,
              unitPrice: 55,
              priceState: PriceState.confirmed,
              addedAt: DateTime(2026, 10, 1)),
          CartItem(
              id: 'c2',
              name: 'Eggs',
              quantity: 1,
              unit: ItemUnit.pack,
              unitPrice: 120,
              priceState: PriceState.remembered,
              addedAt: DateTime(2026, 10, 1)),
          CartItem(
              id: 'c3',
              name: 'Basil',
              quantity: 1,
              unitPrice: null,
              priceState: PriceState.unknown,
              addedAt: DateTime(2026, 10, 1)),
        ]);
    when(storage.loadGroceryPriceMemory()).thenAnswer((_) async => [
          RememberedPrice(
              key: 'eggs',
              displayName: 'Eggs',
              lastPrice: 120,
              unit: ItemUnit.pack,
              lastSeen: DateTime(2026, 9, 20),
              timesSeen: 3),
        ]);
    when(storage.loadGroceryTripHistory()).thenAnswer((_) async => [
          SavedTrip(
              id: 'trip1',
              savedAt: DateTime(2026, 9, 20),
              items: const [],
              confirmedTotal: 840.5,
              estimatedTotal: 60,
              unpricedCount: 0,
              postedToLedger: true),
        ]);
    when(storage.loadGroceryBudget()).thenAnswer((_) async => 1000);
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});

    t = TreasuryPresenters(storage: storage, stats: stats);
    await Future.wait(t.loadAll());
    while (t.ledger.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });

  tearDown(() => t.dispose());

  Future<AiToolResult> getView(String view, [String? month]) =>
      t.financeActions.runRead(AiToolCall(
        id: 'tu_view',
        name: 'getView',
        input: {'view': view, if (month != null) 'month': month},
      ));

  Future<String> read(String view, [String? month]) async {
    final result = await getView(view, month);
    expect(result.ok, isTrue, reason: result.summary);
    return result.summary;
  }

  String peso(double v) => formatPeso(v);

  test('dashboard gives the Dashboard getters, for this month only', () async {
    final d = t.dashboard;
    final s = await read('dashboard');
    final next = d.nextMonthForecast;

    expect(s, contains('($now)'));
    expect(s, contains('NET WORTH: ${peso(d.netWorth)}'));
    expect(s, contains('Liquid cash: ${peso(d.totalLiquidCash)}'));
    expect(s, contains('Credit owed: ${peso(d.totalCreditOwed)}'));
    expect(s, contains('in ${peso(d.monthTotalInflow)}'));
    expect(s, contains('out ${peso(d.monthTotalOutflow)}'));
    expect(s, contains('Liquid Now: ${peso(d.totalLiquidCash)}'));
    expect(s, contains('To Receive: ${peso(d.pendingReceivables)}'));
    expect(s, contains('Upcoming Bills: ${peso(d.monthUnpaidBills)}'));
    expect(s,
        contains('Budget / Savings Due: ${peso(d.budgetedExpensesRemaining)}'));
    expect(
        s, contains('Budget Left: ${peso(d.budgetRemainingNetOfObligations)}'));
    expect(
        s, contains('Proj. Month-End Cash: ${peso(d.forecastedNetBalance)}'));
    expect(s, contains('Next Month Forecast (${next.monthName}'));
    expect(s, contains('${next.endingTitle}: ${next.endingLabel}'));
    expect(s, contains(next.changeLabel));
    expect(s, contains('Bills: ${peso(next.bills)}'));
    expect(s, contains('Installments: ${peso(next.installments)}'));

    // The Dashboard has no month picker, so another month is a plain refusal
    // that names where to look instead.
    final other = await getView('dashboard', prev);
    expect(other.ok, isFalse);
    expect(other.summary, contains('history'));
  });

  test('budget gives the Budget tab getters, for any month, without paging',
      () async {
    final b = t.budget;
    expect(b.selectedMonth, now);
    final s = await read('budget');

    expect(
        s,
        contains('SPENT: ${peso(b.totalSpent)} of '
            '${peso(b.totalAllocated)} (${formatPercent(b.percentUsed)} spent'));
    expect(s, contains('${peso(b.totalRemaining)} left'));
    expect(s, contains('Pace: ${b.paceLabel}'));
    for (final section in b.budgetSections) {
      expect(
          s, contains('${peso(section.spent)} / ${peso(section.allocated)}'));
      for (final row in section.rows) {
        expect(s, contains('${row.name}: '));
        expect(s, contains(peso(row.actual)));
        expect(s, contains(peso(row.allocated)));
        expect(s, contains(peso(row.left)));
      }
    }

    // Another month reads without moving the tab, and gives what the tab
    // shows once it is paged there.
    final past = await read('budget', prev);
    expect(b.selectedMonth, now);
    expect(t.monthScope.month, now);
    expect(past, contains('no pace pill'));
    b.setMonth(prev);
    expect(
        past,
        contains('SPENT: ${peso(b.totalSpent)} of '
            '${peso(b.totalAllocated)}'));
    for (final row in b.budgetSections.expand((s) => s.rows)) {
      expect(
          past,
          contains('${row.name}: spent ${peso(row.actual)} of '
              '${peso(row.allocated)}'));
    }
  });

  test('bills gives the Bills tab getters for the month asked', () async {
    final p = t.bills;
    final s = await read('bills');

    expect(s, contains('Pending: ${peso(p.totalBillsPending)}'));
    expect(s, contains('Paid: ${peso(p.totalBillsPaid)}'));
    expect(
        s, contains('Installments: ${peso(t.installments.totalDueThisMonth)}'));
    expect(
        s, contains('Receivables pending: ${peso(p.totalReceivablesPending)}'));
    for (final c in p.comingUpItems(t.installments)) {
      expect(
          s,
          contains('${c.name}: ${c.isInflow ? '+' : ''}'
              '${peso(c.amount)} · ${c.dateLabel}'));
    }
    for (final bill in p.bills) {
      expect(s, contains('${bill.name}: ${peso(bill.amount)}'));
      final statement = p.statementBreakdown(bill);
      if (statement != null) expect(s, contains(statement.periodLabel));
    }
    for (final r in p.receivables) {
      expect(s, contains('${r.name}: ${peso(r.amount)}'));
    }
    for (final e in p.budgetedExpenses) {
      expect(
          s,
          contains('${e.name}: ${peso(e.allocatedAmount)}, '
              'funded ${peso(e.spentAmount)}'));
    }

    final past = await read('bills', prev);
    expect(p.selectedMonth, now);
    expect(past, contains('Paid: ${peso(1400)}'));
    expect(past, isNot(contains('Rent')));
  });

  test('ledger gives the month totals the unfiltered Ledger shows', () async {
    final l = t.ledger;
    final s = await read('ledger');

    expect(s, contains('In: ${peso(l.filteredMonthInflow)}'));
    expect(s, contains('Out: ${peso(l.filteredMonthOutflow)}'));
    expect(s, contains('Net: ${formatPesoSigned(l.filteredMonthNet)}'));
    expect(s, contains(peso(l.outstandingOwedTotal)));
    expect(s, contains(peso(l.averageDailyOutflow)));
    // The ₱500 lent out is owed back, not spending.
    expect(l.outstandingOwedTotal, 500);

    final past = await read('ledger', prev);
    expect(l.selectedMonth, now);
    l.setMonth(prev);
    expect(past, contains('In: ${peso(l.filteredMonthInflow)}'));
    expect(past, contains('Out: ${peso(l.filteredMonthOutflow)}'));
    expect(past, contains(peso(l.averageDailyOutflow)));
  });

  test('history gives the overview and a closed month\'s summary', () async {
    final h = t.history;
    final s = await read('history', prev);
    final closed = h.summaries.firstWhere((m) => m.month == prev);

    expect(s, contains('AVG IN: ${peso(h.averageInflow)}'));
    expect(s, contains('AVG OUT: ${peso(h.averageOutflow)}'));
    expect(s, contains('AVG SAVED: ${peso(h.averageNetSavings)}'));
    expect(s, contains('Keeps ${formatPercent(h.averageSavingsRate)}'));
    expect(s, contains('${formatPesoSigned(h.cumulativeNetSavings)} net'));
    expect(s, contains('(closed)'));
    expect(s, contains('IN: ${peso(closed.totalInflow)}'));
    expect(s, contains('OUT: ${peso(closed.totalOutflow)}'));
    expect(s, contains('Saved ${formatPercent(closed.savingsRate!)}'));
    expect(s, contains('Account balances at close:'));
    for (final e in closed.accountSnapshots.entries) {
      final name = h.accounts.firstWhere((a) => a.id == e.key).name;
      expect(s, contains('$name: ${peso(e.value)}'));
    }

    final current = await read('history');
    expect(current, contains('in progress, not closed'));
    final older = await read('history', previousMonth(prev));
    expect(older, contains('has no closed summary'));
  });

  test('accounts gives balances, held, yours and credit terms', () async {
    final d = t.dashboard;
    final s = await read('accounts');

    expect(s, contains('Liquid cash: ${peso(d.totalLiquidCash)}'));
    expect(s, contains('Savings & goals: ${peso(d.totalSavingsAndGoals)}'));
    expect(s, contains('Credit available: ${peso(d.totalCreditAvailable)}'));
    expect(s, contains('Held for others: ${peso(d.totalHeldForOthers)}'));
    // BPI holds ₱2,000 for Mom: the row shows the rest as yours.
    expect(s, contains('${peso(d.heldAmountByAccountId['bpi']!)} held'));
    expect(s, contains('yours ${peso(d.yoursByAccountId['bpi']!)}'));
    expect(d.yoursByAccountId['bpi'], 18000);
    final visa = d.accounts.firstWhere((a) => a.id == 'visa');
    expect(s, contains('owe ${peso(visa.totalDebt)}'));
    expect(s, contains('limit ${peso(visa.creditLimit!)}'));
    expect(s, contains('available ${peso(visa.availableCredit!)}'));
    expect(s, contains('statement day 15'));
    expect(s, contains('due day 5'));
    expect(s, contains('(held for others in BPI)'));
  });

  test('installments gives every plan, cancelled ones flagged', () async {
    final p = t.installments;
    final s = await read('installments');

    expect(s, contains('Due in $now: ${peso(p.totalDueThisMonth)}'));
    for (final i in p.allInstallments) {
      expect(
          s,
          contains('${i.name} on Visa: ${peso(i.monthlyAmount)}/mo, '
              '${i.startMonth} to ${i.endMonth}, '
              '${p.paidCount(i.id)}/${i.totalMonths} paid, '
              '${peso(p.remainingAmount(i.id))} left, '
              'total interest ${peso(i.totalInterest)}, '
              'total payable ${peso(i.totalPayable)}'));
    }
    expect(s, contains('[cancelled]'));
  });

  test('grocery gives the cart, price book and last trips', () async {
    final g = t.groceryCart;
    final s = await read('grocery');

    expect(
        s,
        contains('Cart total: ${peso(g.grandTotal)} '
            '(${peso(g.confirmedTotal)} confirmed, ~${peso(g.estimatedTotal)} '
            'est, ${g.unpricedCount} unpriced)'));
    expect(s, contains('${peso(g.budgetRemaining!)} left of ${peso(1000)}'));
    expect(s, contains('Price book: ${g.priceBookSummary}'));
    expect(s, contains('Eggs: ${peso(120)}/pack, bought 3×'));
    expect(
        s,
        contains('${peso(g.tripHistory.first.total)}, 0 items, '
            'posted to the ledger'));
  });

  test('a bad view or month fails with a fix hint', () async {
    final view = await getView('netWorth');
    expect(view.ok, isFalse);
    expect(view.summary, contains('dashboard, budget'));
    final month = await getView('budget', 'October');
    expect(month.ok, isFalse);
    expect(month.summary, contains('YYYY-MM'));
  });
}
