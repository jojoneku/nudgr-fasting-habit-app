import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/treasury/ledger/add_transaction_sheet.dart';
import 'package:intermittent_fasting/views/treasury/ledger/ledger_view.dart';
import 'package:intermittent_fasting/views/treasury/ledger/transaction_list_tile.dart';

import '../../../mocks.mocks.dart';

/// Plan 071 Phase 4: ledger row notes, long-press row actions, Duplicate,
/// removable filter chips and the empty text.

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

TransactionRecord _txn(
  String id, {
  String? note,
  TransactionType type = TransactionType.outflow,
}) =>
    TransactionRecord(
      id: id,
      date: DateTime(2026, 3, 15),
      accountId: 'gcash',
      categoryId: 'food',
      amount: 245.5,
      type: type,
      description: 'Lunch $id',
      note: note,
      month: '2026-03',
    );

const _plainActions = LedgerRowActions(
  canSplit: false,
  splitLabel: 'Split into installments',
  canMarkReimbursable: false,
  reimbursableLabel: 'Mark "I\'ll get this back"',
);

Widget _tileHost(TransactionListTile tile, {ThemeData? theme}) => MaterialApp(
      theme: theme,
      home: Scaffold(body: ListView(children: [tile])),
    );

void main() {
  group('TransactionListTile', () {
    testWidgets('notes line shows only when a note exists, in both themes',
        (tester) async {
      for (final theme in [ThemeData.light(), ThemeData.dark()]) {
        await tester.pumpWidget(_tileHost(
          TransactionListTile(txn: _txn('a', note: '  split with Ana  ')),
          theme: theme,
        ));
        expect(find.byKey(const ValueKey('txnNoteLine')), findsOneWidget);
        expect(find.text('split with Ana'), findsOneWidget);

        await tester.pumpWidget(_tileHost(
          TransactionListTile(txn: _txn('b', note: '   ')),
          theme: theme,
        ));
        expect(find.byKey(const ValueKey('txnNoteLine')), findsNothing);

        await tester.pumpWidget(_tileHost(
          TransactionListTile(txn: _txn('c')),
          theme: theme,
        ));
        expect(find.byKey(const ValueKey('txnNoteLine')), findsNothing);
      }
    });

    Future<List<String>> menuLabels(
        WidgetTester tester, LedgerRowActions actions) async {
      await tester.pumpWidget(_tileHost(TransactionListTile(
        txn: _txn('a'),
        actions: actions,
        onTap: () {},
        onDelete: () {},
        onDuplicate: () {},
        onSplit: () {},
        onReimbursable: () {},
      )));
      await tester.longPress(find.text('Lunch a'));
      await tester.pumpAndSettle();
      final labels = [
        for (final l in [
          'Edit',
          'Duplicate',
          'Split into installments',
          'Edit installment plan',
          'Mark "I\'ll get this back"',
          'Edit "I\'ll get this back"',
          'Delete',
        ])
          if (find.text(l).evaluate().isNotEmpty) l,
      ];
      // Close the sheet before the next pump.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      return labels;
    }

    testWidgets('long-press menu follows the row actions', (tester) async {
      expect(await menuLabels(tester, _plainActions),
          ['Edit', 'Duplicate', 'Delete']);

      expect(
        await menuLabels(
          tester,
          const LedgerRowActions(
            canSplit: true,
            splitLabel: 'Split into installments',
            canMarkReimbursable: true,
            reimbursableLabel: 'Mark "I\'ll get this back"',
          ),
        ),
        [
          'Edit',
          'Duplicate',
          'Split into installments',
          'Mark "I\'ll get this back"',
          'Delete',
        ],
      );

      expect(
        await menuLabels(
          tester,
          const LedgerRowActions(
            canSplit: true,
            splitLabel: 'Edit installment plan',
            canMarkReimbursable: false,
            reimbursableLabel: 'Mark "I\'ll get this back"',
          ),
        ),
        ['Edit', 'Duplicate', 'Edit installment plan', 'Delete'],
      );
    });

    testWidgets('each menu item calls its own callback', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(_tileHost(TransactionListTile(
        txn: _txn('a'),
        actions: const LedgerRowActions(
          canSplit: true,
          splitLabel: 'Split into installments',
          canMarkReimbursable: true,
          reimbursableLabel: 'Mark "I\'ll get this back"',
        ),
        onTap: () => calls.add('edit'),
        onDelete: () => calls.add('delete'),
        onDuplicate: () => calls.add('duplicate'),
        onSplit: () => calls.add('split'),
        onReimbursable: () => calls.add('reimbursable'),
      )));
      for (final label in [
        'Duplicate',
        'Split into installments',
        'Mark "I\'ll get this back"',
        'Delete',
      ]) {
        await tester.longPress(find.text('Lunch a'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(calls, ['duplicate', 'split', 'reimbursable', 'delete']);
    });
  });

  group('with a real LedgerPresenter', () {
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
      var savedAccounts = [
        _account('gcash', 'GCash'),
        _account('bpi', 'BPI'),
      ];
      var savedTxns = <TransactionRecord>[
        _txn('a', note: 'with Ana'),
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

    Future<void> loadPresenter(WidgetTester tester) async {
      await tester.runAsync(() async {
        presenter = LedgerPresenter(storage, stats);
        var guard = 0;
        while (presenter.isLoading && guard++ < 50) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      presenter.setMonth('2026-03');
    }

    testWidgets(
        'Duplicate opens the sheet with the same amount, account and '
        'category, dated today', (tester) async {
      await loadPresenter(tester);
      final original = presenter.allTransactions.single;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AddTransactionSheet(
              presenter: presenter,
              duplicateOf: original,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('245.50'), findsOneWidget);
      expect(find.text('Lunch a'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text(DateFormat('MMMM d, yyyy').format(DateTime.now())),
          findsOneWidget);
      expect(find.text('March 15, 2026'), findsNothing);
      // A new entry, not an edit: no Delete, the log label.
      expect(find.widgetWithText(OutlinedButton, 'Delete'), findsNothing);
      expect(find.text('Log Transaction'), findsOneWidget);
      // The copied note opens "More options" on its own.
      expect(find.text('with Ana'), findsOneWidget);
    });

    testWidgets('More options stays shut on a blank entry', (tester) async {
      await loadPresenter(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AddTransactionSheet(presenter: presenter),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('More options'), findsOneWidget);
      expect(find.text('Note (optional)'), findsNothing);
      expect(find.text("I'll get this back"), findsNothing);
    });

    testWidgets('initialReimbursable opens More options with the switch on',
        (tester) async {
      await loadPresenter(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AddTransactionSheet(
              presenter: presenter,
              existing: _txn('a'),
              initialReimbursable: true,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text("I'll get this back"), findsOneWidget);
      final toggle = tester.widget<Switch>(find.descendant(
        of: find.ancestor(
          of: find.text("I'll get this back"),
          matching: find.byType(Row),
        ),
        matching: find.byType(Switch),
      ));
      expect(toggle.value, isTrue);
    });

    testWidgets(
        'filter chips remove one filter each, and the empty text '
        'switches with filters', (tester) async {
      await loadPresenter(tester);
      await tester.pumpWidget(MaterialApp(
        home: LedgerView(presenter: presenter),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Lunch a'), findsOneWidget);
      expect(find.byKey(const ValueKey('ledgerFilterChips')), findsNothing);

      // A filter that matches nothing: blame the filters, offer Clear.
      presenter.toggleAccountFilter('bpi');
      await tester.pumpAndSettle();
      expect(find.text('No transactions match these filters'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
      expect(find.byKey(const ValueKey('ledgerFilterChips')), findsOneWidget);

      // Removing the chip drops just that filter.
      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('ledgerFilterChips')),
        matching: find.text('BPI'),
      ));
      await tester.pumpAndSettle();
      expect(presenter.selectedAccountIds, isEmpty);
      expect(find.text('Lunch a'), findsOneWidget);

      // Clear filters from the empty state.
      presenter.toggleCategoryFilter('none');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear filters'));
      await tester.pumpAndSettle();
      expect(presenter.activeFilterCount, 0);
      expect(find.text('Lunch a'), findsOneWidget);

      // An empty month with no filters: the plain text, no "Tap +".
      presenter.setMonth('2026-04');
      await tester.pumpAndSettle();
      expect(find.text('No transactions this month'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing);
      expect(find.textContaining('Tap +'), findsNothing);
    });

    testWidgets('row shows its note and the long-press menu in the ledger',
        (tester) async {
      await loadPresenter(tester);
      await tester.pumpWidget(MaterialApp(
        home: LedgerView(presenter: presenter),
      ));
      await tester.pumpAndSettle();
      expect(find.text('with Ana'), findsOneWidget);

      await tester.longPress(find.text('Lunch a'));
      await tester.pumpAndSettle();
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Mark "I\'ll get this back"'), findsOneWidget);
      expect(find.text('Split into installments'), findsNothing);

      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(find.byType(AddTransactionSheet), findsOneWidget);
      expect(find.text('245.50'), findsOneWidget);
    });
  });
}
