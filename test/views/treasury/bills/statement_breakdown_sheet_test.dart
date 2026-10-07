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
import 'package:intermittent_fasting/views/treasury/bills/statement_breakdown_sheet.dart';
import 'package:intermittent_fasting/views/treasury/ledger/add_transaction_sheet.dart';
import '../../../mocks.mocks.dart';

/// A credit statement on the Bills tab lists what is on it, and each item
/// opens its transaction form.
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
            balance: 845.69,
            creditLimit: 20000,
            statementDay: 4,
            paymentDueDay: 15,
            colorHex: '#EE4D2D',
            icon: 'wallet',
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
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
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

  testWidgets('View items opens the statement, and an item opens its form',
      (tester) async {
    await pumpView(tester);

    final viewItems = find.text('View 3 items');
    expect(viewItems, findsOneWidget);
    expect(
        tester
            .getSize(find
                .ancestor(of: viewItems, matching: find.byType(InkWell))
                .first)
            .height,
        greaterThanOrEqualTo(44));

    await tester.tap(viewItems);
    await tester.pumpAndSettle();

    expect(find.byType(StatementBreakdownSheet), findsOneWidget);
    expect(find.text('Unpaid amount'), findsOneWidget);
    expect(find.text('Transaction total: 3 items'), findsOneWidget);
    expect(find.text('05 Sep – 04 Oct'), findsOneWidget);
    expect(find.text('Purchases · 3 items'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);

    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    final form =
        tester.widget<AddTransactionSheet>(find.byType(AddTransactionSheet));
    expect(form.existing?.id, 'b');
    expect(find.text('Edit Transaction'), findsOneWidget);
  });
}
