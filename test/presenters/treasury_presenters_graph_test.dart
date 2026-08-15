import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/treasury_presenters.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../mocks.mocks.dart';

/// The contract of [TreasuryPresenters]: a graph that is wired correctly by
/// construction.
///
/// This is the regression net for a whole class of bug — one page editing
/// something and the others not noticing. Each test names a connection the
/// module depends on. Adding a presenter to the graph without connecting it
/// should break something here.
void main() {
  // BillsReceivablesPresenter reaches for SharedPreferences during load; without
  // a binding it degrades gracefully but floods the output with warnings.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late MockStorageService storage;
  late MockStatsPresenter stats;

  late List<FinancialAccount> accounts;
  late List<Budget> budgets;
  late List<BudgetGroupDef> groups;

  FinancialAccount account(String id, {double balance = 1000}) =>
      FinancialAccount(
        id: id,
        name: id,
        category: AccountCategory.bank,
        balance: balance,
        colorHex: '#FFFFFF',
        icon: 'wallet',
      );

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    accounts = [account('bpi')];
    budgets = <Budget>[];
    groups = <BudgetGroupDef>[];

    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());

    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.saveAccounts(any)).thenAnswer((inv) async {
      accounts = List<FinancialAccount>.from(
          inv.positionalArguments.first as List<FinancialAccount>);
    });
    when(storage.loadBudgets()).thenAnswer((_) async => budgets);
    when(storage.saveBudgets(any)).thenAnswer((inv) async {
      budgets =
          List<Budget>.from(inv.positionalArguments.first as List<Budget>);
    });
    when(storage.loadBudgetGroups()).thenAnswer((_) async => groups);
    when(storage.saveBudgetGroups(any)).thenAnswer((inv) async {
      groups = List<BudgetGroupDef>.from(
          inv.positionalArguments.first as List<BudgetGroupDef>);
    });
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          FinanceCategory(
            id: 'food',
            name: 'Food',
            type: CategoryType.expense,
            icon: 'tag',
            colorHex: '#FFFFFF',
          ),
        ]);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.saveBills(any)).thenAnswer((_) async {});
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(storage.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadGroceryCart()).thenAnswer((_) async => []);
    when(storage.loadGroceryPriceMemory()).thenAnswer((_) async => []);
    when(storage.loadGroceryTripHistory()).thenAnswer((_) async => []);
    when(storage.loadGroceryBudget()).thenAnswer((_) async => null);
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
  });

  Future<TreasuryPresenters> build() async {
    final t = TreasuryPresenters(storage: storage, stats: stats);
    await Future.wait(t.loadAll());
    return t;
  }

  test('every month-aware presenter shares one month', () async {
    final t = await build();
    addTearDown(t.dispose);

    // Whichever page moves the month, the rest follow — a tab showing a
    // different month than the one you selected is the bug this prevents.
    t.ledger.setMonth('2026-01');

    expect(t.monthScope.month, '2026-01');
    expect(t.budget.selectedMonth, '2026-01');
    expect(t.bills.selectedMonth, '2026-01');
    expect(t.installments.selectedMonth, '2026-01');

    t.budget.setMonth('2026-04');

    expect(t.ledger.selectedMonth, '2026-04');
    expect(t.bills.selectedMonth, '2026-04');
    expect(t.installments.selectedMonth, '2026-04');
  });

  test('a budget edit reaches the dashboard', () async {
    final t = await build();
    addTearDown(t.dispose);
    t.budget.setMonth(toMonthKey(DateTime.now()));

    await t.budget.setBudget('food', 2500);

    expect(t.dashboard.totalBudgetAllocated, 2500);
  });

  test('a budget group added on the Budget page reaches the dashboard',
      () async {
    final t = await build();
    addTearDown(t.dispose);

    await t.budget.addGroup('Sinking Funds');

    expect(
        t.dashboard.budgetGroups.map((g) => g.name), contains('Sinking Funds'));
  });

  test('a bill added on the Bills page reaches the dashboard', () async {
    final t = await build();
    addTearDown(t.dispose);
    final live = toMonthKey(DateTime.now());
    t.bills.setMonth(live);

    expect(t.dashboard.hasBills, isFalse);

    await t.bills.addBill(Bill(
      id: 'b1',
      name: 'Internet',
      billType: BillType.utility,
      amount: 1899,
      dueDay: 15,
      month: live,
      categoryId: '',
    ));

    expect(t.dashboard.hasBills, isTrue);
    expect(t.dashboard.monthUnpaidBills, 1899);
  });

  test('a receivable added on the Bills page reaches the dashboard', () async {
    final t = await build();
    addTearDown(t.dispose);
    final live = toMonthKey(DateTime.now());
    t.bills.setMonth(live);

    await t.bills.addReceivable(Receivable(
      id: 'r1',
      name: 'Salary',
      receivableType: ReceivableType.salary,
      amount: 30000,
      month: live,
      categoryId: '',
    ));

    expect(t.dashboard.pendingReceivables, 30000);
  });

  test('a set-aside added on the Bills page reaches the dashboard', () async {
    final t = await build();
    addTearDown(t.dispose);
    final live = toMonthKey(DateTime.now());
    t.bills.setMonth(live);

    await t.bills.addBudgetedExpense(BudgetedExpense(
      id: 'e1',
      name: 'Emergency fund',
      budgetedType: SetAsideType.savings,
      month: live,
      allocatedAmount: 5000,
      categoryId: '',
    ));

    // Feeds "Budget / Savings Due" and the month-end projection.
    expect(t.dashboard.budgetedExpensesRemaining, 5000);
  });

  test('an account edit reaches the ledger, dashboard and budget', () async {
    final t = await build();
    addTearDown(t.dispose);

    await t.dashboard.updateAccount(account('bpi', balance: 9999));

    expect(t.ledger.accounts.single.balance, 9999);
    expect(t.dashboard.liquidAccounts.single.balance, 9999);
    // Bills and installments read accounts straight off the ledger.
    expect(t.bills.accounts.single.balance, 9999);
    expect(t.installments.accounts.single.balance, 9999);
  });

  test('the cart can post to the ledger', () async {
    final t = await build();
    addTearDown(t.dispose);

    // The cart writes a real transaction on checkout; without the ledger wired
    // it silently loses the trip.
    expect(t.groceryCart.canPostToLedger, isTrue);
    expect(t.groceryCart.ledgerAccounts, isNotEmpty);
  });

  test('dispose tears the whole graph down in dependency order', () async {
    final t = await build();

    // The presenters are cross-subscribed, so disposing an owner before its
    // subscribers would let a notify land on a disposed listener. Order is the
    // graph's responsibility, and getting it wrong throws here.
    expect(t.dispose, returnsNormally);
  });
}
