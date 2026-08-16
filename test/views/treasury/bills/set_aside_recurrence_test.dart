import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intermittent_fasting/models/finance/bill.dart'
    show RecurrenceType;
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_budgeted_expense_sheet.dart';
import '../../../mocks.mocks.dart';

/// Recurrence is what makes a sinking fund come back next month
/// (`_autoGenerateRecurringBudgetedExpenses` keys off `isRecurring`). It used to
/// be settable only on web, so a fund created on the phone silently never
/// regenerated — and the phone gave you no way to see or fix that.
void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter presenter;
  const month = '2026-03';
  const nextMonth = '2026-04';

  BudgetedExpense setAside({
    bool isRecurring = false,
    double? nextMonthAmount,
  }) =>
      BudgetedExpense(
        id: 'braces',
        name: 'Braces Sinking Fund',
        budgetedType: SetAsideType.sinkingFund,
        month: month,
        allocatedAmount: 3000,
        categoryId: '',
        isRecurring: isRecurring,
        recurrenceType: isRecurring ? RecurrenceType.monthly : null,
        nextMonthAmount: nextMonthAmount,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = MockStorageService();
    stats = MockStatsPresenter();
    // Injected, not defaulted: `load()` awaits the notification service, and a
    // real one never settles inside a widget test's zone.
    notifications = MockNotificationService();
    when(notifications.cancelBillsReminder()).thenAnswer((_) async {});
    when(notifications.scheduleBillsReminder(any)).thenAnswer((_) async {});
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(storage.saveBills(any)).thenAnswer((_) async {});
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    ledger = LedgerPresenter(storage, stats);
    presenter = BillsReceivablesPresenter(storage, ledger, stats,
        notifications: notifications);
  });

  /// Pushes the sheet onto a route of its own so saving — which pops — has
  /// something to pop, the way it does in the app.
  Future<void> pumpSheet(
    WidgetTester tester, {
    BudgetedExpense? existing,
  }) async {
    if (existing != null) {
      when(storage.loadBudgetedExpenses()).thenAnswer((_) async => [existing]);
    }
    await ledger.load();
    await presenter.load();
    await presenter.setMonth(month);
    await tester.binding.setSurfaceSize(const Size(393, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                body: AddBudgetedExpenseSheet(
                  presenter: presenter,
                  existing: existing,
                ),
              ),
            )),
            child: const Text('open sheet'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('a set-aside marked recurring on mobile comes back next month',
      (tester) async {
    await pumpSheet(tester);

    await tester.enterText(
        find.byType(TextFormField).first, 'Braces Sinking Fund');
    await tester.enterText(find.byType(TextFormField).at(1), '3000');

    // The recurrence choice only appears once recurrence is on — off by
    // default, matching the model. (Field labels render uppercased.)
    expect(find.text('RECURRENCE'), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('RECURRENCE'), findsOneWidget);

    await save(tester, 'Add Expense');

    final created = presenter.budgetedExpenses.single;
    expect(created.isRecurring, isTrue);
    expect(created.recurrenceType, RecurrenceType.monthly);

    // The point of the flag: next month regenerates it.
    await presenter.setMonth(nextMonth);
    final regenerated = presenter.budgetedExpenses.single;
    expect(regenerated.name, 'Braces Sinking Fund');
    expect(regenerated.month, nextMonth);
    expect(regenerated.allocatedAmount, 3000);
    expect(regenerated.isRecurring, isTrue);
  });

  testWidgets('editing shows the saved recurrence and can switch it off',
      (tester) async {
    await pumpSheet(tester, existing: setAside(isRecurring: true));

    // State on file is reflected, not reset to the default.
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    expect(find.text('RECURRENCE'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await save(tester, 'Save');

    final saved = presenter.budgetedExpenses.single;
    expect(saved.isRecurring, isFalse);
    expect(saved.recurrenceType, isNull);

    // And it no longer regenerates.
    await presenter.setMonth(nextMonth);
    expect(presenter.budgetedExpenses, isEmpty);
  });

  testWidgets('editing preserves the staged next-month amount', (tester) async {
    // The sheet rebuilds a fresh BudgetedExpense rather than copyWith, so
    // anything it forgets to restate is dropped on save — nextMonthAmount used
    // to be one of them.
    await pumpSheet(tester,
        existing: setAside(isRecurring: true, nextMonthAmount: 4500));

    await tester.enterText(
        find.byType(TextFormField).first, 'Braces Sinking Fund v2');
    await save(tester, 'Save');

    expect(presenter.budgetedExpenses.single.nextMonthAmount, 4500);

    // Which is the amount next month's copy is generated at.
    await presenter.setMonth(nextMonth);
    expect(presenter.budgetedExpenses.single.allocatedAmount, 4500);
  });
}
