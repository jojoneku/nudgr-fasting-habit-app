import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/treasury/ledger/add_transaction_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

import '../../../mocks.mocks.dart';

/// Plan 071 Phase 0.1: Delete in the edit sheet must behave like swipe-delete.
/// Deleting one leg of a transfer takes its partner too (or the two balances
/// drift apart), and the Undo toast puts both legs back.
FinancialAccount _account(String id, double balance) => FinancialAccount(
      id: id,
      name: id,
      category: AccountCategory.ewallet,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

TransactionRecord _leg(String id, String accountId, TransactionType type) =>
    TransactionRecord(
      id: id,
      date: DateTime(2026, 3, 15),
      accountId: accountId,
      categoryId: '',
      amount: 300,
      type: type,
      description: 'Move $id',
      month: '2026-03',
      transferGroupId: 'g1',
    );

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter presenter;

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    // Storage remembers what was saved, so a background reload sees the
    // same balances and records as the presenter.
    var savedAccounts = [_account('gcash', 1000), _account('bpi', 5000)];
    var savedTxns = <TransactionRecord>[];
    when(storage.loadAccounts()).thenAnswer((_) async => savedAccounts);
    when(storage.saveAccounts(any)).thenAnswer((inv) async {
      savedAccounts =
          List.of(inv.positionalArguments.first as List<FinancialAccount>);
    });
    when(storage.loadTransactions()).thenAnswer((_) async => savedTxns);
    when(storage.saveTransactions(any)).thenAnswer((inv) async {
      savedTxns =
          List.of(inv.positionalArguments.first as List<TransactionRecord>);
    });
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(stats.stats).thenReturn(UserStats.initial());
  });

  double balanceOf(String id) =>
      presenter.accounts.firstWhere((a) => a.id == id).balance;

  testWidgets(
      'deleting a transfer leg removes both legs and Undo restores them',
      (tester) async {
    await tester.runAsync(() async {
      presenter = LedgerPresenter(storage, stats);
      var guard = 0;
      while (presenter.isLoading && guard++ < 50) {
        await Future<void>.delayed(Duration.zero);
      }
      await presenter
          .addTransaction(_leg('out', 'gcash', TransactionType.outflow));
      await presenter.addTransaction(_leg('in', 'bpi', TransactionType.inflow));
    });
    expect(balanceOf('gcash'), 700);
    expect(balanceOf('bpi'), 5300);
    final outLeg = presenter.allTransactions.firstWhere((t) => t.id == 'out');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => AppBottomSheet.show(
              context: ctx,
              title: 'Edit Transaction',
              body: AddTransactionSheet(presenter: presenter, existing: outLeg),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final delete = find.widgetWithText(OutlinedButton, 'Delete');
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();

    // Both legs gone, both balances back, no confirm dialog, sheet closed.
    expect(presenter.allTransactions, isEmpty);
    expect(balanceOf('gcash'), 1000);
    expect(balanceOf('bpi'), 5000);
    expect(find.byType(AddTransactionSheet), findsNothing);
    expect(find.text('Deleted transfer "Move out"'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(
        presenter.allTransactions.map((t) => t.id), containsAll(['out', 'in']));
    expect(balanceOf('gcash'), 700);
    expect(balanceOf('bpi'), 5300);
  });
}
