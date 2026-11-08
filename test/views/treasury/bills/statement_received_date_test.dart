import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_receivables_view.dart';
import '../../../mocks.mocks.dart';

/// Plan 072: on a "posts on receipt" account (Shopee PayLater) the statement
/// asks for the received date of orders near the close, and a received date
/// moves an order to the statement it was billed on.
void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter presenter;
  late InstallmentPresenter installments;

  TransactionRecord purchase(
          String id, DateTime date, double amount, String description) =>
      TransactionRecord(
        id: id,
        date: date,
        accountId: 'spay',
        categoryId: 'cat-shop',
        amount: amount,
        type: TransactionType.outflow,
        description: description,
        month: '${date.year}-${date.month.toString().padLeft(2, '0')}',
      );

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'spay',
            name: 'SPayLater',
            category: AccountCategory.bnpl,
            balance: 945.69,
            creditLimit: 20000,
            statementDay: 4,
            paymentDueDay: 15,
            colorHex: '#EE4D2D',
            icon: 'wallet',
            postsOnReceipt: true,
          ),
          FinancialAccount(
            id: 'bank',
            name: 'MariBank',
            category: AccountCategory.bank,
            balance: 50000,
            colorHex: '#123456',
            icon: 'bank',
          ),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => [
          purchase('a', DateTime(2026, 9, 5), 20.09, 'Phone case'),
          purchase('b', DateTime(2026, 9, 18), 449.35, 'Groceries'),
          purchase('c', DateTime(2026, 10, 4), 376.25, 'Shoes'),
          purchase('d', DateTime(2026, 9, 28), 100, 'Lamp'),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          FinanceCategory(
            id: 'cat-shop',
            name: 'Shopping',
            colorHex: '#3366FF',
            icon: 'bag',
            type: CategoryType.expense,
          ),
        ]);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(storage.loadDismissedStatementKeys())
        .thenAnswer((_) async => <String>{});
    when(storage.saveDismissedStatementKeys(any)).thenAnswer((_) async {});
    when(storage.saveBills(any)).thenAnswer((_) async {});
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveTransactions(any)).thenAnswer((inv) async {
      final saved =
          List.of(inv.positionalArguments.first as List<TransactionRecord>);
      when(storage.loadTransactions()).thenAnswer((_) async => saved);
    });
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    ledger = LedgerPresenter(storage, stats);
    installments = InstallmentPresenter(storage, ledger, stats);
    presenter = BillsReceivablesPresenter(
      storage,
      ledger,
      stats,
      notifications: MockNotificationService(),
      installments: installments,
      clock: () => DateTime(2026, 10, 7),
    );
  });

  Future<void> pumpView(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await ledger.load();
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: BillsReceivablesView(
        presenter: presenter,
        installmentPresenter: installments,
      ),
    ));
    await tester.pumpAndSettle();
    await presenter.setMonth('2026-10');
    await tester.pumpAndSettle();
  }

  testWidgets(
      'orders near the close ask for a received date; a later one '
      'moves to the next statement', (tester) async {
    await pumpView(tester);
    await tester.tap(find.text('View 4 items'));
    await tester.pumpAndSettle();

    // Lamp (Sep 28) and Shoes (Oct 4) are within 14 days of the Oct 4 close.
    expect(
        find.byKey(const ValueKey('statement.receivedNotice')), findsOneWidget);
    expect(
        find.textContaining('2 orders may post when received'), findsOneWidget);
    expect(find.byKey(const ValueKey('statement.orderDay.d')), findsOneWidget);
    expect(find.byKey(const ValueKey('statement.orderDay.c')), findsOneWidget);
    expect(find.byKey(const ValueKey('statement.orderDay.a')), findsNothing);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('statement.orderDay.c')))
            .height,
        greaterThanOrEqualTo(44));

    // Shoes was received on its order day: one order left to confirm.
    await tester.tap(find.byKey(const ValueKey('statement.orderDay.c')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('1 order may post when received'), findsOneWidget);

    // Lamp arrived Oct 6, after the close: it leaves this statement.
    await ledger.setPostedDate('d', DateTime(2026, 10, 6));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('statement.receivedNotice')), findsNothing);
    expect(find.text('Lamp'), findsNothing);
    expect(find.text('Purchases · 3 items'), findsOneWidget);
    expect(find.text('₱845.69'), findsWidgets,
        reason: 'the statement amount drops by the moved order');
  });

  testWidgets('"All received on order day" clears the notice', (tester) async {
    await pumpView(tester);
    await tester.tap(find.text('View 4 items'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('statement.allOrderDay')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('statement.receivedNotice')), findsNothing);
    expect(find.text('Purchases · 4 items'), findsOneWidget);
  });
}
