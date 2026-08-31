import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../mocks.mocks.dart';

/// A 'YYYY-MM' key [delta] months from now (delta may be negative).
String _monthKey(int delta) {
  final now = DateTime.now();
  return toMonthKey(DateTime(now.year, now.month + delta));
}

/// Marking a set-aside (or a bill, or a salary) recurring is a promise that it
/// comes back on its own. Two holes in the generator kept breaking that promise
/// in the two situations people actually hit, which is why a recurring
/// sinking fund still felt like something you re-created by hand every month:
///
///  1. Generation hung off [BillsReceivablesPresenter.setMonth] alone, so the
///     month the app *opened* on was never seeded. Reopen the app on the 1st
///     and the new month is blank — the rows only appear if you happen to tap
///     to another month and back.
///  2. Generation read strictly the month before, so one skipped month ended
///     the series for good: away in October, and November seeds from an empty
///     October, and December from an empty November, forever.
///
/// These pin both, across all three row types — a set-aside, a bill and a
/// receivable recur by the same pass.
void main() {
  final thisMonth = _monthKey(0);
  final lastMonth = _monthKey(-1);
  final threeMonthsAgo = _monthKey(-3);

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;

  late List<Bill> bills;
  late List<Receivable> receivables;
  late List<BudgetedExpense> expenses;

  BudgetedExpense fund({
    required String id,
    required String month,
    bool isRecurring = true,
  }) =>
      BudgetedExpense(
        id: id,
        name: 'Braces Fund',
        budgetedType: SetAsideType.sinkingFund,
        month: month,
        allocatedAmount: 3000,
        categoryId: 'health',
        isRecurring: isRecurring,
        recurrenceType: isRecurring ? RecurrenceType.monthly : null,
        seriesId: isRecurring ? 'e1' : null,
      );

  Bill rent({required String id, required String month}) => Bill(
        id: id,
        name: 'Rent',
        billType: BillType.other,
        amount: 15000,
        dueDay: 5,
        month: month,
        categoryId: 'home',
        isRecurring: true,
        recurrenceType: RecurrenceType.monthly,
        seriesId: 'b1',
      );

  Receivable salary({required String id, required String month}) => Receivable(
        id: id,
        name: 'Salary',
        receivableType: ReceivableType.salary,
        amount: 40000,
        expectedDate: DateTime.parse('$month-15'),
        month: month,
        categoryId: 'pay',
        isRecurring: true,
        recurrenceType: RecurrenceType.monthly,
        seriesId: 'r1',
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    bills = <Bill>[];
    receivables = <Receivable>[];
    expenses = <BudgetedExpense>[];

    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    when(notifications.cancelBillsReminder()).thenAnswer((_) async {});
    when(notifications.scheduleBillsReminder(any)).thenAnswer((_) async {});

    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          FinanceCategory(
            id: 'health',
            name: 'Health',
            type: CategoryType.expense,
            icon: 'tag',
            colorHex: '#FFFFFF',
          ),
        ]);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(storage.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(storage.loadInstallments()).thenAnswer((_) async => []);

    when(storage.loadBills()).thenAnswer((_) async => bills);
    when(storage.saveBills(any)).thenAnswer((inv) async {
      bills = List<Bill>.from(inv.positionalArguments.first as List<Bill>);
    });
    when(storage.loadReceivables()).thenAnswer((_) async => receivables);
    when(storage.saveReceivables(any)).thenAnswer((inv) async {
      receivables = List<Receivable>.from(
          inv.positionalArguments.first as List<Receivable>);
    });
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => expenses);
    when(storage.saveBudgetedExpenses(any)).thenAnswer((inv) async {
      expenses = List<BudgetedExpense>.from(
          inv.positionalArguments.first as List<BudgetedExpense>);
    });
  });

  /// A presenter that has only been loaded — no month navigation at all, which
  /// is exactly the state the app is in the moment it opens.
  Future<BillsReceivablesPresenter> justOpened() async {
    final ledger = LedgerPresenter(storage, stats);
    final presenter = BillsReceivablesPresenter(
      storage,
      ledger,
      stats,
      notifications: notifications,
    );
    await presenter.load();
    var guard = 0;
    while (ledger.isLoading && guard++ < 50) {
      await Future<void>.delayed(Duration.zero);
    }
    return presenter;
  }

  group('the month the app opens on is seeded', () {
    test('a recurring set-aside is there without paging away and back',
        () async {
      expenses = [fund(id: 'e-last', month: lastMonth)];

      final p = await justOpened();

      expect(p.selectedMonth, thisMonth);
      expect(
        p.budgetedExpenses.map((e) => e.name),
        ['Braces Fund'],
        reason: 'load() used to leave the opening month blank, so the fund '
            'looked like it had never recurred',
      );
      expect(p.budgetedExpenses.single.isRecurring, isTrue,
          reason: 'the copy keeps recurring, or the series dies here');
      expect(p.budgetedExpenses.single.seriesId, 'e1');
    });

    test('so is a recurring bill and a recurring receivable', () async {
      bills = [rent(id: 'b-last', month: lastMonth)];
      receivables = [salary(id: 'r-last', month: lastMonth)];

      final p = await justOpened();

      expect(p.bills.map((b) => b.name), ['Rent']);
      expect(p.receivables.map((r) => r.name), ['Salary']);
    });

    test('a one-off set-aside is left behind', () async {
      expenses = [fund(id: 'e-last', month: lastMonth, isRecurring: false)];

      final p = await justOpened();

      expect(p.budgetedExpenses, isEmpty,
          reason: 'only the recurring flag carries a row forward');
    });

    test('a month the user already has rows in is never topped up', () async {
      expenses = [
        fund(id: 'e-last', month: lastMonth),
        fund(id: 'e-this', month: thisMonth),
      ];

      final p = await justOpened();

      expect(p.budgetedExpenses.map((e) => e.id), ['e-this'],
          reason: 'seeding a month that already holds something would '
              'duplicate the user’s own row');
    });
  });

  group('a skipped month does not end the series', () {
    test('a set-aside seeds from the last month that has rows', () async {
      // The app was last opened three months ago; the two months between were
      // never visited, so they hold nothing at all.
      expenses = [fund(id: 'e-old', month: threeMonthsAgo)];

      final p = await justOpened();

      expect(
        p.budgetedExpenses.map((e) => e.name),
        ['Braces Fund'],
        reason: 'reading strictly the month before found an empty month and '
            'gave up, which killed the series permanently',
      );
    });

    test('and so do bills and receivables', () async {
      bills = [rent(id: 'b-old', month: threeMonthsAgo)];
      receivables = [salary(id: 'r-old', month: threeMonthsAgo)];

      final p = await justOpened();

      expect(p.bills.map((b) => b.name), ['Rent']);
      expect(p.receivables.map((r) => r.name), ['Salary']);
    });

    test('the skipped month itself still seeds when it is opened later',
        () async {
      expenses = [fund(id: 'e-old', month: threeMonthsAgo)];

      final p = await justOpened();
      await p.setMonth(lastMonth);

      expect(p.budgetedExpenses.map((e) => e.name), ['Braces Fund'],
          reason: 'paging back into a month that was never visited should '
              'fill it in from its own nearest predecessor');
    });

    test('nothing is invented when there is no earlier month at all', () async {
      expenses = [fund(id: 'e-this', month: thisMonth)];

      final p = await justOpened();

      expect(p.budgetedExpenses.map((e) => e.id), ['e-this']);
      expect(expenses.map((e) => e.id), ['e-this'],
          reason: 'a brand-new series has nothing behind it to repeat');
    });
  });
}
