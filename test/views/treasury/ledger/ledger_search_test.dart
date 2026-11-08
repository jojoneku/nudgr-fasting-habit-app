import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/treasury/ledger/ledger_view.dart';

import '../../../mocks.mocks.dart';

/// Plan 071 Phase 10a: the phone ledger's search — the header icon opens a
/// field and a "This month / All months" scope; typing narrows the list; the
/// wider scope finds older records, labelled with their full date.

const _open = ValueKey('ledgerSearchOpen');
const _field = ValueKey('ledgerSearchField');
const _close = ValueKey('ledgerSearchClose');
const _scopeMonth = ValueKey('ledgerSearchScopeMonth');
const _scopeAll = ValueKey('ledgerSearchScopeAll');

FinancialAccount _account(String id, String name) => FinancialAccount(
      id: id,
      name: name,
      category: AccountCategory.ewallet,
      balance: 1000,
      colorHex: '#3366FF',
      icon: 'wallet',
    );

final _food = FinanceCategory(
  id: 'food',
  name: 'Food',
  type: CategoryType.expense,
  icon: 'food',
  colorHex: '#FF8800',
);

TransactionRecord _txn(String id, DateTime date, String description,
        {double amount = 100}) =>
    TransactionRecord(
      id: id,
      date: date,
      accountId: 'gcash',
      categoryId: 'food',
      amount: amount,
      type: TransactionType.outflow,
      description: description,
      month: '${date.year}-${date.month.toString().padLeft(2, '0')}',
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
    // same records as the presenter.
    var savedAccounts = [_account('gcash', 'GCash')];
    var savedTxns = <TransactionRecord>[
      _txn('lunch', DateTime(2026, 3, 15), 'Jollibee lunch', amount: 245.5),
      _txn('grocery', DateTime(2026, 3, 12), 'SM Supermarket', amount: 1800),
      _txn('netflix', DateTime(2025, 12, 10), 'Netflix', amount: 549),
    ];
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
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [_food]);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(stats.stats).thenReturn(UserStats.initial());
  });

  Future<void> pumpLedger(WidgetTester tester, ThemeData theme) async {
    // A small phone: 360 × 640 dp.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      // Pinned to March 2026, so the list opens on the two March records.
      presenter = LedgerPresenter(storage, stats,
          clock: () => DateTime(2026, 3, 20, 12));
      var guard = 0;
      while (presenter.isLoading && guard++ < 50) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: LedgerView(presenter: presenter),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(_field), text);
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    final theme = dark ? ThemeData.dark() : ThemeData.light();
    final mode = dark ? 'dark' : 'light';

    testWidgets('typing a query narrows the list ($mode)', (tester) async {
      await pumpLedger(tester, theme);
      expect(find.text('Jollibee lunch'), findsOneWidget);
      expect(find.text('SM Supermarket'), findsOneWidget);
      expect(find.byKey(_field), findsNothing);

      // The icon is a full touch target.
      final iconSize = tester.getSize(find.byKey(_open));
      expect(iconSize.width, greaterThanOrEqualTo(44));
      expect(iconSize.height, greaterThanOrEqualTo(44));

      await tester.tap(find.byKey(_open));
      await tester.pumpAndSettle();
      expect(find.byKey(_field), findsOneWidget);
      expect(tester.getSize(find.byKey(_scopeMonth)).height,
          greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(_scopeAll)).height,
          greaterThanOrEqualTo(44));
      expect(
          tester.getSize(find.byKey(_close)).height, greaterThanOrEqualTo(44));

      // The open search leaves the list in view on a 640 dp screen.
      expect(tester.getRect(find.text('Jollibee lunch')).bottom,
          lessThan(640 - 72));

      await type(tester, 'LUNCH');
      expect(find.text('Jollibee lunch'), findsOneWidget);
      expect(find.text('SM Supermarket'), findsNothing);
      expect(find.text('1 match'), findsOneWidget);

      // Amounts match too.
      await type(tester, '1,800');
      expect(find.text('SM Supermarket'), findsOneWidget);
      expect(find.text('Jollibee lunch'), findsNothing);

      // Close clears the search and folds the field away.
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
      expect(find.byKey(_field), findsNothing);
      expect(presenter.isSearching, isFalse);
      expect(find.text('Jollibee lunch'), findsOneWidget);
      expect(find.text('SM Supermarket'), findsOneWidget);
    });

    testWidgets(
        'All months finds a record from another month, with its full date '
        '($mode)', (tester) async {
      await pumpLedger(tester, theme);
      await tester.tap(find.byKey(_open));
      await tester.pumpAndSettle();

      await type(tester, 'netflix');
      expect(find.text('Netflix'), findsNothing);
      expect(find.text('No transactions match "netflix"'), findsOneWidget);
      expect(find.textContaining('Try All months'), findsOneWidget);
      expect(find.text('Clear search'), findsOneWidget);

      await tester.tap(find.byKey(_scopeAll));
      await tester.pumpAndSettle();
      expect(presenter.searchAllMonths, isTrue);
      expect(find.text('Netflix'), findsOneWidget);
      // Another year: the day header carries the year.
      expect(
        find.text(DateFormat('EEEE, MMMM d, y').format(DateTime(2025, 12, 10))),
        findsOneWidget,
      );

      // Back to this month: gone again; Clear search empties the field.
      await tester.tap(find.byKey(_scopeMonth));
      await tester.pumpAndSettle();
      expect(find.text('Netflix'), findsNothing);
      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();
      expect(presenter.isSearching, isFalse);
      expect(
        tester.widget<TextField>(find.byKey(_field)).controller!.text,
        isEmpty,
      );
      expect(find.text('Jollibee lunch'), findsOneWidget);
    });
  }

  testWidgets(
      'an entry logged from the chat bar clears a search it does not match, '
      'and the field follows', (tester) async {
    await pumpLedger(tester, ThemeData.light());
    await tester.tap(find.byKey(_open));
    await tester.pumpAndSettle();
    await type(tester, 'netflix');
    expect(find.text('No transactions match "netflix"'), findsOneWidget);

    await tester.runAsync(() async {
      await presenter.sendChatInput('-500 food gcash');
      if (presenter.chatState.phase == ChatPhase.reviewing) {
        await presenter.confirmEntries();
      }
    });
    await tester.pumpAndSettle();

    final logged = presenter.allTransactions
        .firstWhere((t) => !{'lunch', 'grocery', 'netflix'}.contains(t.id));
    expect(presenter.isSearching, isFalse);
    expect(
      tester.widget<TextField>(find.byKey(_field)).controller!.text,
      isEmpty,
    );
    expect(find.text(logged.description), findsOneWidget);
  });
}
