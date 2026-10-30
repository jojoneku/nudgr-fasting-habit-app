import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/widgets/finance/batch_review_card.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 4: every write of one Nudgy step is one list, with
/// Remove and in-place edit per row and one Approve all.

AiToolCall _call(String id, String name, Map<String, Object?> input) =>
    AiToolCall(id: id, name: name, input: input);

void main() {
  late MockBillsReceivablesPresenter bills;
  late LedgerPresenter ledger;
  late FinanceActionsExecutor executor;
  late List<List<AiToolResult>> answers;

  Future<void> setUpAll(WidgetTester tester) async {
    bills = MockBillsReceivablesPresenter();
    when(bills.selectedMonth).thenReturn('2026-09');
    when(bills.allBills).thenReturn([
      Bill(
        id: 'b1',
        name: 'Gym',
        billType: BillType.other,
        amount: 1500,
        dueDay: 5,
        month: '2026-09',
        categoryId: '',
        isRecurring: true,
      ),
    ]);
    when(bills.allReceivables).thenReturn([]);
    when(bills.allBudgetedExpenses).thenReturn([]);
    final storage = MockStorageService();
    final stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'gcash',
            name: 'GCash',
            category: AccountCategory.ewallet,
            balance: 1000,
            colorHex: '#FFFFFF',
            icon: 'wallet',
          ),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(stats.stats).thenReturn(UserStats.initial());
    await tester.runAsync(() async {
      ledger = LedgerPresenter(storage, stats);
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    executor = FinanceActionsExecutor(bills: bills, ledger: ledger);
    answers = [];
  }

  Future<void> open(WidgetTester tester, List<AiToolCall> calls,
      {ThemeData? theme}) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    executor.proposeBatch(calls).then(answers.add);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: executor,
          builder: (_, __) {
            final batch = executor.batch;
            return batch == null
                ? const SizedBox.shrink()
                : BatchReviewCard(
                    key: ValueKey(batch.id),
                    host: executor,
                    batch: batch,
                    ledger: ledger,
                  );
          },
        ),
      ),
    ));
    await tester.pump();
  }

  final three = [
    _call('t1', 'addBill', {'name': 'Internet', 'amount': 1299, 'dueDay': 20}),
    _call('t2', 'addReceivable', {'name': 'Mark - dinner', 'amount': 800}),
    _call('t3', 'addSetAside',
        {'name': 'Braces', 'amount': 3000, 'type': 'goal'}),
  ];

  testWidgets('three changes are one list with one Approve all',
      (tester) async {
    await setUpAll(tester);
    await open(tester, three);

    expect(find.text('Add bill: Internet, ₱1299'), findsOneWidget);
    expect(find.text('Add receivable: Mark - dinner, ₱800'), findsOneWidget);
    expect(find.text('Set aside ₱3000 for Braces'), findsOneWidget);
    expect(find.text('Approve all (3)'), findsOneWidget);
    verifyNever(bills.addBill(any, applyToFuture: anyNamed('applyToFuture')));
  });

  testWidgets('Approve all saves every row and answers every call',
      (tester) async {
    await setUpAll(tester);
    await open(tester, three);

    await tester.tap(find.text('Approve all (3)'));
    await tester.pumpAndSettle();

    verify(bills.addBill(any, applyToFuture: false)).called(1);
    verify(bills.addReceivable(any, applyToFuture: false)).called(1);
    verify(bills.addBudgetedExpense(any, applyToFuture: false)).called(1);
    expect(answers.single.map((r) => r.ok), [true, true, true]);
    expect(executor.batch, isNull);
  });

  testWidgets('Remove drops one row and reports it as not saved',
      (tester) async {
    await setUpAll(tester);
    await open(tester, three);

    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    expect(find.text('Approve all (2)'), findsOneWidget);

    await tester.tap(find.text('Approve all (2)'));
    await tester.pumpAndSettle();
    final results = answers.single;
    expect(results.first.ok, isFalse);
    expect(results.first.summary, contains('removed'));
    verifyNever(bills.addBill(any, applyToFuture: anyNamed('applyToFuture')));
  });

  testWidgets('Not now declines every row and writes nothing', (tester) async {
    await setUpAll(tester);
    await open(tester, three);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(answers.single.every((r) => r.summary.contains('declined')), isTrue);
    verifyNever(bills.addBill(any, applyToFuture: anyNamed('applyToFuture')));
  });

  testWidgets('an in-place edit changes what the row shows and saves',
      (tester) async {
    await setUpAll(tester);
    await open(tester, [three.first]);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change amount'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1499');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();

    expect(find.text('Add bill: Internet, ₱1499'), findsOneWidget);
    await tester.tap(find.text('Add it'));
    await tester.pumpAndSettle();
    final saved = verify(
            bills.addBill(captureAny, applyToFuture: anyNamed('applyToFuture')))
        .captured
        .single as Bill;
    expect(saved.amount, 1499);
  });

  testWidgets('a delete is red and Approve asks once more', (tester) async {
    await setUpAll(tester);
    await open(tester, [
      _call('d1', 'deleteBill', {'id': 'b1'})
    ]);

    final row = tester.widget<Container>(find
        .ancestor(
            of: find.text('Delete bill: Gym (₱1500)'),
            matching: find.byType(Container))
        .first);
    final cs =
        Theme.of(tester.element(find.byType(BatchReviewCard))).colorScheme;
    expect((row.decoration as BoxDecoration).color, cs.errorContainer);

    await tester.tap(find.text('Delete Bill'));
    await tester.pumpAndSettle();
    expect(find.text('Approve these changes?'), findsOneWidget);
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    verify(bills.deleteBill('b1', applyToFuture: false)).called(1);
  });

  testWidgets(
      'a recurring row starts at this month; widening it turns it T3 and '
      'reaches the write', (tester) async {
    await setUpAll(tester);
    await open(tester, [
      _call('e1', 'editBill', {'id': 'b1', 'amount': 1800}),
    ]);

    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Also changes every later month'), findsNothing);

    await tester.tap(find.text('Every month ahead'));
    await tester.pumpAndSettle();
    expect(find.text('Also changes every later month'), findsOneWidget);

    await tester.tap(find.text('Update Bill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    verify(bills.updateBill(any, applyToFuture: true)).called(1);
  });

  testWidgets('remove, edit and scope controls meet the 44px target',
      (tester) async {
    await setUpAll(tester);
    await open(tester, [
      _call('e1', 'editBill', {'id': 'b1', 'amount': 1800}),
    ]);
    for (final f in [
      find.byTooltip('Remove'),
      find.byTooltip('Edit'),
    ]) {
      final size = tester.getSize(f);
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    }
    final scope = tester.getSize(find
        .ancestor(of: find.text('This month'), matching: find.byType(InkWell))
        .first);
    expect(scope.height, greaterThanOrEqualTo(44));
  });

  testWidgets('renders in both themes', (tester) async {
    for (final theme in [
      ThemeData(colorScheme: const ColorScheme.dark(primary: AppColors.gold)),
      ThemeData(colorScheme: const ColorScheme.light()),
    ]) {
      await setUpAll(tester);
      await open(tester, three, theme: theme);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a row option is a checkbox that reports the tick',
      (tester) async {
    final ticks = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RowOptionTile(
          option: const RowOption(
            label: 'Also add a monthly set-aside in Bills',
            hint: 'Nothing in Bills moves money into it yet.',
            value: false,
            inputKey: '_addSetAside',
          ),
          onChanged: ticks.add,
        ),
      ),
    ));
    expect(find.text('Also add a monthly set-aside in Bills'), findsOneWidget);
    expect(tester.getSize(find.byType(CheckboxListTile)).height,
        greaterThanOrEqualTo(44));
    await tester.tap(find.byType(Checkbox));
    expect(ticks, [true]);
  });
}
