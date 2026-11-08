import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/treasury/ledger/ledger_view.dart';

import '../../../mocks.mocks.dart';

/// The redesigned Ledger "Filter & sort" sheet on a 360×640 phone: a short
/// main sheet with one row per filter, pickers for accounts and categories,
/// and a live "Show N transactions" button.
FinancialAccount _account(String id, String name, AccountCategory c) =>
    FinancialAccount(
      id: id,
      name: name,
      category: c,
      balance: 1000,
      colorHex: '#3366FF',
      icon: 'wallet',
    );

FinanceCategory _category(String id, String name) => FinanceCategory(
      id: id,
      name: name,
      type: CategoryType.expense,
      icon: id,
      colorHex: '#FF8800',
    );

TransactionRecord _txn(String id, String accountId, String categoryId) =>
    TransactionRecord(
      id: id,
      date: DateTime(2026, 3, 15),
      accountId: accountId,
      categoryId: categoryId,
      amount: 120,
      type: TransactionType.outflow,
      description: 'Item $id',
      month: '2026-03',
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
    when(storage.loadAccounts()).thenAnswer((_) async => [
          _account('gcash', 'GCash', AccountCategory.ewallet),
          _account('bpi', 'BPI', AccountCategory.bank),
          _account('card', 'Visa', AccountCategory.creditCard),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          _category('food', 'Food'),
          _category('transport', 'Transport'),
          for (var i = 0; i < 8; i++) _category('c$i', 'Extra $i'),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => [
          _txn('a', 'gcash', 'food'),
          _txn('b', 'gcash', 'food'),
          _txn('c', 'bpi', 'transport'),
        ]);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(stats.stats).thenReturn(UserStats.initial());
  });

  Future<void> pumpLedger(WidgetTester tester,
      {ThemeData? theme, Size size = const Size(360, 640)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      presenter = LedgerPresenter(storage, stats);
      var guard = 0;
      while (presenter.isLoading && guard++ < 50) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    presenter.setMonth('2026-03');
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: LedgerView(presenter: presenter),
    ));
    await tester.pumpAndSettle();
  }

  /// Text inside the top-most sheet only (the ledger rows behind it also
  /// show account names).
  Finder inSheet(String text) => find.descendant(
      of: find.byType(BottomSheet).last, matching: find.text(text));

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('Filter & sort').first);
    await tester.pumpAndSettle();
  }

  for (final theme in [ThemeData.dark(), ThemeData.light()]) {
    final mode = theme.brightness.name;

    testWidgets(
        'the main sheet is short: sort, four rows, live button '
        '($mode)', (tester) async {
      await pumpLedger(tester, theme: theme);
      await openSheet(tester);

      expect(find.byKey(const ValueKey('ledgerSortControl')), findsOneWidget);
      for (final key in [
        'ledgerFilterMonth',
        'ledgerFilterDay',
        'ledgerFilterAccounts',
        'ledgerFilterCategories',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      // No wall of chips: account and category names are not on this sheet.
      expect(inSheet('GCash'), findsNothing);
      expect(inSheet('Transport'), findsNothing);
      expect(find.text('All accounts'), findsOneWidget);
      expect(find.text('All categories'), findsOneWidget);
      expect(find.text('Show 3 transactions'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Each row is a full-width, at-least-44 px target.
      final row = tester.getSize(find.byKey(const ValueKey('ledgerFilterDay')));
      expect(row.height, greaterThanOrEqualTo(44));
    });
  }

  testWidgets('picking an account narrows the list and updates the summary',
      (tester) async {
    await pumpLedger(tester);
    await openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('ledgerFilterAccounts')));
    await tester.pumpAndSettle();
    expect(find.text('CASH & BANK'), findsOneWidget);
    expect(find.text('CREDIT'), findsOneWidget);
    expect(find.text('2 this month'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ledgerFilterOption.bpi')));
    await tester.pumpAndSettle();
    expect(presenter.selectedAccountIds, {'bpi'});
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Back on the main sheet: the row names the pick, the button counts it.
    expect(inSheet('BPI'), findsOneWidget);
    expect(find.text('Show 1 transaction'), findsOneWidget);

    // The row's clear button drops just that filter.
    await tester.tap(find.byTooltip('Clear Accounts'));
    await tester.pumpAndSettle();
    expect(presenter.hasAccountFilter, isFalse);
    expect(find.text('Show 3 transactions'), findsOneWidget);
  });

  testWidgets('the category picker searches and lists used categories first',
      (tester) async {
    await pumpLedger(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('ledgerFilterCategories')));
    await tester.pumpAndSettle();

    expect(find.text('USED THIS MONTH'), findsOneWidget);
    expect(find.byKey(const ValueKey('ledgerCategorySearch')), findsOneWidget);

    await tester.enterText(
        find.descendant(
            of: find.byKey(const ValueKey('ledgerCategorySearch')),
            matching: find.byType(TextField)),
        'trans');
    await tester.pumpAndSettle();
    expect(inSheet('Transport'), findsOneWidget);
    expect(inSheet('Food'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('ledgerFilterOption.transport')));
    await tester.pumpAndSettle();
    expect(presenter.selectedCategoryIds, {'transport'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('sort and Reset', (tester) async {
    await pumpLedger(tester);
    await openSheet(tester);

    await tester.tap(find.text('Largest'));
    await tester.pumpAndSettle();
    expect(presenter.sortOption, LedgerSortOption.largest);

    await tester.tap(find.byKey(const ValueKey('ledgerFilterReset')));
    await tester.pumpAndSettle();
    expect(presenter.sortOption, LedgerSortOption.newest);
    expect(presenter.activeFilterCount, 0);
  });
}
