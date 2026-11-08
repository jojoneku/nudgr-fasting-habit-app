import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/views/treasury/ledger/add_transaction_sheet.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_setup_view.dart';

import '../../mocks.mocks.dart';

/// Plan 072 forms: the account switch, and the transaction form's received
/// date on an account that posts when an order is received.
FinancialAccount _card(String id, String name, {bool postsOnReceipt = false}) =>
    FinancialAccount(
      id: id,
      name: name,
      category: AccountCategory.bnpl,
      balance: 500,
      creditLimit: 20000,
      statementDay: 4,
      paymentDueDay: 15,
      colorHex: '#EE4D2D',
      icon: 'wallet',
      postsOnReceipt: postsOnReceipt,
    );

void main() {
  group('account form', () {
    testWidgets('the switch saves "charges post when received"',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = MockStorageService();
      final card = _card('spay', 'SPayLater');
      when(storage.loadAccounts()).thenAnswer((_) async => [card]);
      when(storage.loadTransactions()).thenAnswer((_) async => []);
      when(storage.loadBills()).thenAnswer((_) async => []);
      when(storage.loadReceivables()).thenAnswer((_) async => []);
      when(storage.loadBudgets()).thenAnswer((_) async => []);
      when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
      when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
      when(storage.saveMonthlySummaries(any)).thenAnswer((_) async {});
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      final presenter = TreasuryDashboardPresenter(storage);
      await presenter.load();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AccountSetupView(presenter: presenter, existing: card),
        ),
      ));
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('account.postsOnReceipt'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = verify(storage.saveAccounts(captureAny)).captured.last
          as List<FinancialAccount>;
      expect(saved.single.postsOnReceipt, isTrue);
    });
  });

  group('transaction form', () {
    late MockStorageService storage;
    late MockStatsPresenter stats;
    late LedgerPresenter ledger;
    final today = DateTime.now();
    final ordered = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 2));

    TransactionRecord order(String id, String accountId) => TransactionRecord(
          id: id,
          date: ordered,
          accountId: accountId,
          categoryId: '',
          amount: 250,
          type: TransactionType.outflow,
          description: 'Order $id',
          month: '${ordered.year}-${ordered.month.toString().padLeft(2, '0')}',
        );

    setUp(() {
      storage = MockStorageService();
      stats = MockStatsPresenter();
      var savedTxns = [order('s', 'spay'), order('v', 'visa')];
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer((_) async => [
            _card('spay', 'SPayLater', postsOnReceipt: true),
            _card('visa', 'Visa'),
          ]);
      when(storage.loadTransactions()).thenAnswer((_) async => savedTxns);
      when(storage.saveTransactions(any)).thenAnswer((inv) async {
        savedTxns =
            List.of(inv.positionalArguments.first as List<TransactionRecord>);
      });
      when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(stats.stats).thenReturn(UserStats.initial());
    });

    Future<void> pumpEdit(WidgetTester tester, String id) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        ledger = LedgerPresenter(storage, stats);
        var guard = 0;
        while (ledger.isLoading && guard++ < 50) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      final existing = ledger.allTransactions.firstWhere((t) => t.id == id);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AddTransactionSheet(presenter: ledger, existing: existing),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final fold = find.byKey(const ValueKey('moreOptionsFold'));
      await tester.ensureVisible(fold);
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
    }

    testWidgets('a posts-on-receipt account offers and saves a received date',
        (tester) async {
      await pumpEdit(tester, 's');
      expect(find.byKey(const ValueKey('receivedDatePicker')), findsOneWidget);
      expect(find.text('Same as order date'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('receivedDatePicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Same as order date'), findsNothing);

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = ledger.allTransactions.firstWhere((t) => t.id == 's');
      expect(saved.date, ordered, reason: 'the order date stays');
      expect(saved.postedDate, DateTime(today.year, today.month, today.day));
    });

    testWidgets('other accounts do not show the field', (tester) async {
      await pumpEdit(tester, 'v');
      expect(find.byKey(const ValueKey('receivedDatePicker')), findsNothing);
      expect(find.text('Same as order date'), findsNothing);
    });
  });
}
