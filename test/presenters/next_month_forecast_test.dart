import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// [TreasuryDashboardPresenter.nextMonthForecast]: next month's cash outlook,
/// starting from this month's projected end and counting each bill, statement,
/// installment, set-aside and budget exactly once.
///
/// "Today" is pinned to 2026-10-20, so the current month is October and the
/// month forecast is November.
void main() {
  final today = DateTime(2026, 10, 20);
  const oct = '2026-10';
  const nov = '2026-11';

  late MockStorageService storage;
  late List<FinancialAccount> accounts;
  late List<TransactionRecord> transactions;
  late List<Bill> bills;
  late List<Receivable> receivables;
  late List<Budget> budgets;
  late List<BudgetedExpense> setAsides;
  late List<Installment> plans;

  final bank = FinancialAccount(
    id: 'bank',
    name: 'Bank',
    category: AccountCategory.bank,
    balance: 50000,
    colorHex: '#000000',
    icon: 'bank',
  );

  FinancialAccount card({
    required int statementDay,
    required int dueDay,
    double balance = 0,
  }) =>
      FinancialAccount(
        id: 'card',
        name: 'Card',
        category: AccountCategory.creditCard,
        balance: balance,
        colorHex: '#000000',
        icon: 'card',
        statementDay: statementDay,
        paymentDueDay: dueDay,
      );

  Bill bill(
    String name,
    String month,
    double amount, {
    bool recurring = false,
    bool paid = false,
    double? nextMonthAmount,
    BillType type = BillType.utility,
    String categoryId = '',
    String? accountId,
    String? paymentNote,
    double? paidAmount,
  }) =>
      Bill(
        id: '$name-$month',
        name: name,
        billType: type,
        amount: amount,
        nextMonthAmount: nextMonthAmount,
        dueDay: 5,
        month: month,
        categoryId: categoryId,
        accountId: accountId,
        paymentNote: paymentNote,
        isRecurring: recurring,
        recurrenceType: recurring ? RecurrenceType.monthly : null,
        isPaid: paid,
        paidAmount: paidAmount,
      );

  Bill statement(String month, double amount, {double? paidAmount}) => bill(
        'Card statement',
        month,
        amount,
        type: BillType.creditCard,
        accountId: 'card',
        paymentNote: Bill.autoStatementNote,
        paidAmount: paidAmount,
      );

  Receivable receivable(
    String name,
    String month,
    double amount, {
    bool recurring = false,
    bool received = false,
  }) =>
      Receivable(
        id: '$name-$month',
        name: name,
        receivableType: ReceivableType.salary,
        amount: amount,
        month: month,
        categoryId: '',
        isRecurring: recurring,
        recurrenceType: recurring ? RecurrenceType.monthly : null,
        isReceived: received,
      );

  Budget budget(
    String categoryId,
    String month,
    double amount, {
    bool recurring = true,
    String group = BudgetGroupDef.idLivingExpense,
  }) =>
      Budget(
        id: '$categoryId-$month',
        categoryId: categoryId,
        month: month,
        allocatedAmount: amount,
        group: group,
        budgetType: BudgetType.monthly,
        isRecurring: recurring,
      );

  BudgetedExpense setAside(
    String name,
    String month,
    double amount, {
    bool recurring = true,
    String? destinationAccountId,
    double spent = 0,
  }) =>
      BudgetedExpense(
        id: '$name-$month',
        name: name,
        budgetedType: SetAsideType.goal,
        month: month,
        allocatedAmount: amount,
        spentAmount: spent,
        categoryId: '',
        destinationAccountId: destinationAccountId,
        isRecurring: recurring,
        recurrenceType: recurring ? RecurrenceType.monthly : null,
      );

  Installment plan({
    required String startMonth,
    required int months,
    required double monthly,
    String accountId = 'card',
  }) =>
      Installment(
        id: 'plan',
        name: 'Phone',
        accountId: accountId,
        totalAmount: monthly * months,
        monthlyAmount: monthly,
        totalMonths: months,
        startMonth: startMonth,
      );

  /// The ledger record of [plan]'s [number]th month, posted in [month].
  TransactionRecord posted(Installment plan, int number, String month) =>
      plan.chargeRecord(
        recordId: plan.chargeId(number),
        number: number,
        date: DateTime.parse('$month-15'),
        month: month,
        categoryId: 'phone',
      );

  setUp(() {
    storage = MockStorageService();
    accounts = [bank];
    transactions = [];
    bills = [];
    receivables = [];
    budgets = [];
    setAsides = [];
    plans = [];
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.loadTransactions()).thenAnswer((_) async => transactions);
    when(storage.loadBills()).thenAnswer((_) async => bills);
    when(storage.loadReceivables()).thenAnswer((_) async => receivables);
    when(storage.loadBudgets()).thenAnswer((_) async => budgets);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => setAsides);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => plans);
  });

  Future<TreasuryDashboardPresenter> build() async {
    final p =
        TreasuryDashboardPresenter(storage, null, null, null, () => today);
    await p.load();
    return p;
  }

  test('starts from this month\'s projected end and forecasts November',
      () async {
    bills = [bill('Water', oct, 800)];
    receivables = [receivable('Refund', oct, 1000)];
    final p = await build();
    final f = p.nextMonthForecast;

    expect(f.month, nov);
    expect(f.monthName, 'November 2026');
    expect(f.startingCash, p.forecastedNetBalance);
    expect(f.startingCash, 50000 + 1000 - 800);
    // Nothing recurs, so November adds nothing.
    expect(f.ending, f.startingCash);
    expect(f.change, 0);
    expect(f.changeLabel, '+₱0.00 vs Oct');
    expect(f.endingTitle, 'Projected end of Nov');
  });

  group('bills and receivables', () {
    test('a month not seeded yet repeats the recurring rows', () async {
      bills = [
        bill('Internet', oct, 999, recurring: true, nextMonthAmount: 1200),
        bill('Rent', oct, 15000, recurring: true, paid: true),
        bill('Repair', oct, 3000), // one-off: does not recur
      ];
      receivables = [
        receivable('Salary', oct, 30000, recurring: true, received: true),
      ];
      final f = (await build()).nextMonthForecast;

      // The staged next-month amount wins; paid this month still recurs.
      expect(f.bills, 1200 + 15000);
      expect(f.toReceive, 30000);
    });

    test('a seeded month counts its own rows, not the recurring copies again',
        () async {
      bills = [
        bill('Internet', oct, 999, recurring: true),
        bill('Rent', oct, 15000, recurring: true),
        bill('Internet', nov, 999, recurring: true),
        bill('Rent', nov, 15000, recurring: true, paid: true),
      ];
      receivables = [
        receivable('Salary', oct, 30000, recurring: true),
        receivable('Salary', nov, 30000, recurring: true),
      ];
      final f = (await build()).nextMonthForecast;

      expect(f.bills, 999); // Rent is paid ahead; Internet counted once
      expect(f.toReceive, 30000);
    });

    test('a recurring credit-card bill is not carried forward', () async {
      bills = [
        bill('BPI statement', oct, 10128.26,
            recurring: true, type: BillType.creditCard, accountId: 'card'),
      ];
      final f = (await build()).nextMonthForecast;

      expect(f.bills, 0);
    });
  });

  group('credit statements and installments', () {
    test('a statement filed under November counts once, installments inside',
        () async {
      // Closes the 15th, due the 5th: the Oct 15 statement is due Nov 5 and
      // is already filed under November, with this month's installment month
      // charged into it when it closed.
      final phone = plan(startMonth: '2026-09', months: 6, monthly: 2000);
      plans = [phone];
      transactions = [posted(phone, 1, '2026-09'), posted(phone, 2, oct)];
      accounts = [bank, card(statementDay: 15, dueDay: 5, balance: 9000)];
      bills = [
        // The auto statement alone does not seed November, so recurring
        // bills still repeat beside it.
        statement(nov, 8000, paidAmount: 3000),
        bill('Internet', oct, 999, recurring: true),
      ];
      final f = (await build()).nextMonthForecast;

      // What is left on the statement, plus the recurring bill.
      expect(f.bills, 5000 + 999);
      // The open cycle (Oct 16 – Nov 15) is due in December, not November.
      expect(f.installments, 0);
    });

    test('a cycle still open estimates the statement and its installments',
        () async {
      // Closes the 25th, due the 10th: the Oct 25 statement, due Nov 10, has
      // not closed on Oct 20, so no bill exists for it yet.
      final phone = plan(startMonth: oct, months: 6, monthly: 1500);
      plans = [phone];
      // The Sep 25 statement (due Oct 10) billed the first month already.
      transactions = [posted(phone, 1, '2026-09')];
      accounts = [bank, card(statementDay: 25, dueDay: 10, balance: 12000)];
      // ₱4,000 of the balance is still owed on October's statement.
      bills = [statement(oct, 6000, paidAmount: 2000)];
      final p = await build();
      final f = p.nextMonthForecast;

      // October's statement stays in this month's outlook...
      expect(p.monthUnpaidBills, 4000);
      // ...so November gets only the charges since it closed,
      expect(f.bills, 12000 - 4000);
      // plus the one installment month that bills at the Oct 25 close.
      expect(f.installments, 1500);
    });

    test('no estimate once the card has a bill filed for November', () async {
      final phone = plan(startMonth: oct, months: 6, monthly: 1500);
      plans = [phone];
      accounts = [bank, card(statementDay: 25, dueDay: 10, balance: 12000)];
      // A hand-keyed statement for the card's November due date.
      bills = [
        bill('My card bill', nov, 11000,
            type: BillType.creditCard, accountId: 'card'),
      ];
      final f = (await build()).nextMonthForecast;

      expect(f.bills, 11000);
      expect(f.installments, 0);
    });

    test('an account with no billing cycle pays its November month directly',
        () async {
      final bnpl = FinancialAccount(
        id: 'bnpl',
        name: 'PayLater',
        category: AccountCategory.bnpl,
        balance: 0,
        colorHex: '#000000',
        icon: 'card',
      );
      final phone =
          plan(startMonth: oct, months: 3, monthly: 1000, accountId: bnpl.id);
      accounts = [bank, bnpl];
      plans = [phone];
      transactions = [posted(phone, 1, oct)];
      expect((await build()).nextMonthForecast.installments, 1000);

      // Paid ahead: November is settled already.
      transactions = [posted(phone, 1, oct), posted(phone, 2, oct)];
      expect((await build()).nextMonthForecast.installments, 0);
    });
  });

  group('budgets and set-asides', () {
    test('November with no budget repeats this month\'s recurring rows',
        () async {
      budgets = [
        budget('food', oct, 10000),
        budget('fun', oct, 2000, recurring: false),
      ];
      final f = (await build()).nextMonthForecast;

      expect(f.budget, 10000);
      expect(f.budgetCarriedForward, isTrue);
      expect(f.budgetCaption, "Repeats this month's budget");
    });

    test('November\'s own budget wins', () async {
      budgets = [budget('food', oct, 10000), budget('food', nov, 8000)];
      final f = (await build()).nextMonthForecast;

      expect(f.budget, 8000);
      expect(f.budgetCarriedForward, isFalse);
    });

    test('a bill in a budgeted category is not reserved twice', () async {
      budgets = [budget('utilities', oct, 2000)];
      bills = [
        bill('Power', oct, 1500, recurring: true, categoryId: 'utilities')
      ];
      final f = (await build()).nextMonthForecast;

      expect(f.bills, 1500);
      expect(f.budget, 2000 - 1500);
    });

    test('set-asides repeat, except into a goal already funded', () async {
      final trip = FinancialAccount(
        id: 'trip',
        name: 'Trip',
        category: AccountCategory.goal,
        balance: 0,
        colorHex: '#000000',
        icon: 'goal',
        goalTarget: 20000,
      );
      final phone = FinancialAccount(
        id: 'phone',
        name: 'Phone',
        category: AccountCategory.goal,
        balance: 30000,
        colorHex: '#000000',
        icon: 'goal',
        goalTarget: 30000,
        goalFundedAt: DateTime(2026, 9, 1),
      );
      accounts = [bank, trip, phone];
      setAsides = [
        setAside('Trip fund', oct, 3000, destinationAccountId: trip.id),
        setAside('Phone fund', oct, 2500, destinationAccountId: phone.id),
        setAside('Gift', oct, 1000, recurring: false),
      ];
      // A savings budget into the same goal is the same peso as its set-aside.
      budgets = [
        budget(trip.id, oct, 3000, group: BudgetGroupDef.idSavings),
      ];
      final f = (await build()).nextMonthForecast;

      expect(f.setAsides, 3000);
      expect(f.budget, 0);
    });
  });

  test('the ending is the chain, and the change is against this month',
      () async {
    accounts = [bank, card(statementDay: 25, dueDay: 10, balance: 2000)];
    bills = [bill('Rent', oct, 15000, recurring: true)];
    receivables = [receivable('Salary', oct, 30000, recurring: true)];
    budgets = [budget('food', oct, 10000)];
    setAsides = [setAside('Trip fund', oct, 3000)];
    final p = await build();
    final f = p.nextMonthForecast;

    expect(f.startingCash, 50000 + 30000 - 15000 - 3000 - 10000);
    expect(f.toReceive, 30000);
    expect(f.bills, 15000 + 2000);
    expect(f.setAsides, 3000);
    expect(f.budget, 10000);
    expect(f.ending, f.startingCash + 30000 - 17000 - 3000 - 10000);
    expect(f.change, 0);

    // A heavier month reads as a drop against October.
    budgets = [budget('food', oct, 10000), budget('food', nov, 14000)];
    final heavier = (await build()).nextMonthForecast;
    expect(heavier.change, -4000);
    expect(heavier.changeIsNegative, isTrue);
    expect(heavier.changeLabel, '−₱4,000.00 vs Oct');
  });
}
