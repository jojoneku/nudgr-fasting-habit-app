import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
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
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../../../mocks.mocks.dart';

/// A set-aside can name where its money is going ("₱5,000 from BPI to Maya").
/// When it does, funding just confirms the route; when it doesn't, funding asks
/// — it never picks a savings account on the user's behalf, which used to park
/// money somewhere they never named.
void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter presenter;
  late InstallmentPresenter installments;
  const month = '2026-03';

  FinancialAccount account(String id, String name, AccountCategory category) =>
      FinancialAccount(
        id: id,
        name: name,
        category: category,
        balance: id == 'bpi' ? 20000 : 0,
        colorHex: '#FFFFFF',
        icon: 'wallet',
      );

  BudgetedExpense setAside({String? destinationAccountId}) => BudgetedExpense(
        id: 'travel',
        name: 'Travel Fund',
        budgetedType: SetAsideType.goal,
        month: month,
        allocatedAmount: 5000,
        categoryId: '',
        accountId: 'bpi',
        destinationAccountId: destinationAccountId,
      );

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          account('bpi', 'BPI', AccountCategory.bank),
          account('maya', 'Maya', AccountCategory.savings),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
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

  Future<void> pumpView(WidgetTester tester, BudgetedExpense expense) async {
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => [expense]);
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

  Future<void> openFundSheet(WidgetTester tester) async {
    await tester.tap(find.descendant(
        of: find.byType(ObligationCard), matching: find.text('Fund')));
    await tester.pumpAndSettle();
  }

  bool confirmEnabled(WidgetTester tester) =>
      tester
          .widget<AppPrimaryButton>(
              find.widgetWithText(AppPrimaryButton, 'Confirm Payment'))
          .onPressed !=
      null;

  testWidgets('with no destination on file, funding asks before it moves money',
      (tester) async {
    await pumpView(tester, setAside());
    await openFundSheet(tester);

    expect(find.text('Choose where it goes'), findsOneWidget);
    expect(confirmEnabled(tester), isFalse,
        reason: 'the destination is an open question until it is answered');

    // Answer it: BPI → Maya.
    await tester.tap(find.text('Choose where it goes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maya').last);
    await tester.pumpAndSettle();
    expect(confirmEnabled(tester), isTrue);

    await tester.tap(find.text('Confirm Payment'));
    await tester.pumpAndSettle();

    expect(presenter.budgetedExpenses.single.isPaid, isTrue);
    expect(ledger.accounts.firstWhere((a) => a.id == 'maya').balance, 5000);
    expect(ledger.accounts.firstWhere((a) => a.id == 'bpi').balance, 15000);
  });

  testWidgets('"spend it" is an answer too', (tester) async {
    await pumpView(tester, setAside());
    await openFundSheet(tester);

    await tester.tap(find.text('Choose where it goes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spend it (no transfer)').last);
    await tester.pumpAndSettle();

    expect(confirmEnabled(tester), isTrue);
    await tester.tap(find.text('Confirm Payment'));
    await tester.pumpAndSettle();

    // A plain outflow: the money left BPI and landed nowhere.
    expect(ledger.accounts.firstWhere((a) => a.id == 'maya').balance, 0);
    expect(ledger.accounts.firstWhere((a) => a.id == 'bpi').balance, 15000);
  });

  testWidgets('a saved destination is pre-filled and ready to confirm',
      (tester) async {
    await pumpView(tester, setAside(destinationAccountId: 'maya'));

    // The route is visible on the row before you even open the sheet.
    expect(find.text('BPI → Maya'), findsOneWidget);

    await openFundSheet(tester);
    expect(find.text('Choose where it goes'), findsNothing);
    expect(confirmEnabled(tester), isTrue);

    await tester.tap(find.text('Confirm Payment'));
    await tester.pumpAndSettle();
    expect(ledger.accounts.firstWhere((a) => a.id == 'maya').balance, 5000);
  });
}
