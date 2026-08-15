import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_receivables_view.dart';
import 'package:intermittent_fasting/views/treasury/bills/obligation_card.dart';
import '../../../mocks.mocks.dart';

/// Multi-select on the Bills tab: long-press a row to start picking, act on the
/// lot from the bar at the bottom. Selection is scoped to the section it began
/// in, because "mark these paid" asks a different question of a bill than of a
/// set-aside.
void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter presenter;
  late InstallmentPresenter installments;
  const month = '2026-03';

  Bill bill(String name, {double amount = 500}) => Bill(
        id: name,
        name: name,
        billType: BillType.utility,
        amount: amount,
        dueDay: 10,
        month: month,
        categoryId: '',
      );

  BudgetedExpense setAside(String name) => BudgetedExpense(
        id: name,
        name: name,
        budgetedType: SetAsideType.savings,
        month: month,
        allocatedAmount: 1000,
        categoryId: '',
      );

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'bpi',
            name: 'BPI',
            category: AccountCategory.bank,
            balance: 20000,
            colorHex: '#FFFFFF',
            icon: 'wallet',
          ),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
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
    presenter = BillsReceivablesPresenter(storage, ledger, stats);
    installments = InstallmentPresenter(storage, ledger, stats);
  });

  Future<void> pumpView(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: BillsReceivablesView(
        presenter: presenter,
        installmentPresenter: installments,
      ),
    ));
    await tester.pumpAndSettle();
    await presenter.setMonth(month);
    await tester.pumpAndSettle();
  }

  /// The card carrying [name] — scoped to the cards, since the "Coming up"
  /// timeline above the sections lists the same entries.
  Finder card(String name) => find.ancestor(
        of: find.text(name),
        matching: find.byType(ObligationCard),
      );

  testWidgets('long-press starts a selection and the bar takes over',
      (tester) async {
    when(storage.loadBills())
        .thenAnswer((_) async => [bill('Meralco'), bill('Maynilad')]);
    await pumpView(tester);

    // Nothing selected: the FAB is there and the rows keep their Pay buttons.
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('1 of 2 selected'), findsNothing);

    await tester.longPress(
        find.descendant(of: card('Meralco'), matching: find.text('Meralco')));
    await tester.pumpAndSettle();

    expect(find.text('1 of 2 selected'), findsOneWidget);
    // The bar replaces the FAB — adding an entry mid-selection means nothing.
    expect(find.byType(FloatingActionButton), findsNothing);
    // Row actions step aside so a stray tap can't settle anything (the bar's
    // own Pay button is the only one left).
    expect(
      find.descendant(
          of: find.byType(ObligationCard), matching: find.text('Pay')),
      findsNothing,
    );

    // A second tap picks, a third un-picks.
    await tester.tap(
        find.descendant(of: card('Maynilad'), matching: find.text('Maynilad')));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 selected'), findsOneWidget);

    await tester.tap(
        find.descendant(of: card('Maynilad'), matching: find.text('Maynilad')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 selected'), findsOneWidget);

    // Un-picking the last row leaves selection the same way you entered it.
    await tester.tap(
        find.descendant(of: card('Meralco'), matching: find.text('Meralco')));
    await tester.pumpAndSettle();
    expect(find.textContaining('selected'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('Select all picks the section, and closing clears it',
      (tester) async {
    when(storage.loadBills())
        .thenAnswer((_) async => [bill('Meralco'), bill('Maynilad')]);
    await pumpView(tester);

    await tester.longPress(
        find.descendant(of: card('Meralco'), matching: find.text('Meralco')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 selected'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('selected'), findsNothing);
    expect(find.text('Pay'), findsNWidgets(2));
  });

  testWidgets('a selection in one section leaves the others alone',
      (tester) async {
    when(storage.loadBills()).thenAnswer((_) async => [bill('Meralco')]);
    when(storage.loadBudgetedExpenses())
        .thenAnswer((_) async => [setAside('Travel Fund')]);
    await pumpView(tester);

    await tester.longPress(
        find.descendant(of: card('Meralco'), matching: find.text('Meralco')));
    await tester.pumpAndSettle();

    // The bar counts the bills section only, and the set-aside's own action is
    // withheld rather than firing outside the batch.
    expect(find.text('1 of 1 selected'), findsOneWidget);
    expect(find.text('Fund'), findsNothing);
  });

  testWidgets('the batch bar pays the whole selection through one sheet',
      (tester) async {
    when(storage.loadBills()).thenAnswer((_) async =>
        [bill('Meralco', amount: 500), bill('Maynilad', amount: 300)]);
    await pumpView(tester);

    await tester.longPress(
        find.descendant(of: card('Meralco'), matching: find.text('Meralco')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();

    // Undo has nothing to reverse while both rows are still open.
    final undo = tester.widget<OutlinedButton>(find.ancestor(
      of: find.text('Undo'),
      matching: find.byType(OutlinedButton),
    ));
    expect(undo.onPressed, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Pay'));
    await tester.pumpAndSettle();
    expect(find.text('Mark 2 bills paid'), findsOneWidget);

    await tester.tap(find.text('Mark 2 paid'));
    await tester.pumpAndSettle();

    expect(presenter.bills.every((b) => b.isPaid), isTrue);
    expect(ledger.accounts.first.balance, 19200);
    // The batch finishes by leaving selection mode.
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('the batch bar deletes the whole selection after one confirm',
      (tester) async {
    when(storage.loadBills())
        .thenAnswer((_) async => [bill('Meralco'), bill('Maynilad')]);
    await pumpView(tester);

    await tester.longPress(
        find.descendant(of: card('Meralco'), matching: find.text('Meralco')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 bills?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(presenter.bills, isEmpty);
    expect(find.textContaining('selected'), findsNothing);
  });
}
