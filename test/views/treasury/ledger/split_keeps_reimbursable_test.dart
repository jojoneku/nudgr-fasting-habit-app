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

/// Plan 071 Phase 4 review fix: opening a reimbursable credit-card expense
/// via the row's Split action, then switching split off again, must not drop
/// "I'll get this back" (and its receivable) unseen.
final _visa = FinancialAccount(
  id: 'visa',
  name: 'Visa',
  category: AccountCategory.creditCard,
  balance: 0,
  colorHex: '#3366FF',
  icon: 'card',
);

final _lent = TransactionRecord(
  id: 'lent',
  date: DateTime(2026, 3, 15),
  accountId: 'visa',
  categoryId: '',
  amount: 900,
  type: TransactionType.outflow,
  description: 'Dinner for Ana',
  month: '2026-03',
  reimbursable: true,
  reimbursementReceivableId: 'rcv1',
  owedBy: 'Ana',
);

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter presenter;
  late List<String> deletedReceivables;
  late List<String> syncedReceivables;

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    deletedReceivables = [];
    syncedReceivables = [];
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    // Storage remembers what was saved, so a background reload sees the
    // same records as the presenter.
    var savedAccounts = [_visa];
    var savedTxns = <TransactionRecord>[_lent];
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

  Finder switchBeside(String label) => find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Row))
            .first,
        matching: find.byType(Switch),
      );

  testWidgets(
      'Split action, then split off: "I\'ll get this back" is back on and '
      'its receivable survives the save', (tester) async {
    await tester.runAsync(() async {
      presenter = LedgerPresenter(storage, stats);
      var guard = 0;
      while (presenter.isLoading && guard++ < 50) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    presenter
      ..onDeleteReimbursementReceivable = (id) async {
        deletedReceivables.add(id);
      }
      ..onUpdateReimbursementReceivable =
          (outflow, {updateExpectedDate = false, expectedDate}) async {
        syncedReceivables.add(outflow.reimbursementReceivableId!);
      };
    final existing = presenter.allTransactions.single;
    expect(presenter.rowActionsFor(existing).canSplit, isTrue);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => AppBottomSheet.show(
              context: ctx,
              title: 'Edit Transaction',
              body: AddTransactionSheet(
                presenter: presenter,
                existing: existing,
                initialSplit: true,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Opened with split on: the reimbursable switch is not offered.
    expect(tester.widget<Switch>(switchBeside('Convert to installments')).value,
        isTrue);
    expect(find.text("I'll get this back"), findsNothing);

    // Back out of the split.
    final splitSwitch = switchBeside('Convert to installments');
    await tester.ensureVisible(splitSwitch);
    await tester.pumpAndSettle();
    await tester.tap(splitSwitch);
    await tester.pumpAndSettle();

    // More options re-opened on its own, with "I'll get this back" on.
    expect(find.text("I'll get this back"), findsOneWidget);
    expect(tester.widget<Switch>(switchBeside("I'll get this back")).value,
        isTrue);

    final save = find.text('Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.byType(AddTransactionSheet), findsNothing);
    final saved = presenter.allTransactions.single;
    expect(saved.isInstallment, isFalse);
    expect(saved.reimbursable, isTrue);
    expect(saved.reimbursementReceivableId, 'rcv1');
    expect(saved.owedBy, 'Ana');
    expect(deletedReceivables, isEmpty);
    expect(syncedReceivables, contains('rcv1'));
  });
}
