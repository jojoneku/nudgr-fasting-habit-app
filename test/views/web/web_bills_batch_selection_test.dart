import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/pages/bills/web_bills_page.dart';

import '../../mocks.mocks.dart';

/// Batch selection on the web Bills page, end to end.
///
/// The desktop page had no selection at all, so a month of bills had to be
/// settled one dialog at a time. The dialog itself is covered in
/// web_batch_settle_test; these pin the wiring — that picking rows produces a
/// selection with the right counts, that only one section can select at once,
/// and that confirming actually settles through the presenter.
const _month = '2026-03';

FinancialAccount _account(String id, {double balance = 20000}) =>
    FinancialAccount(
      id: id,
      name: 'Account $id',
      category: AccountCategory.ewallet,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

Bill _bill(String id, {double amount = 500, bool isPaid = false}) => Bill(
      id: id,
      name: 'Bill $id',
      billType: BillType.utility,
      amount: amount,
      dueDay: 10,
      month: _month,
      categoryId: 'food',
      isPaid: isPaid,
      paidAmount: isPaid ? amount : null,
      paidDate: isPaid ? DateTime(2026, 3, 5) : null,
    );

Receivable _receivable(String id, {double amount = 400}) => Receivable(
      id: id,
      name: 'Receivable $id',
      receivableType: ReceivableType.salary,
      amount: amount,
      expectedDate: DateTime(2026, 3, 20),
      month: _month,
      categoryId: 'salary',
    );

BudgetedExpense _setAside(String id, {double amount = 300}) => BudgetedExpense(
      id: id,
      name: 'Set-aside $id',
      budgetedType: SetAsideType.savings,
      month: _month,
      allocatedAmount: amount,
      categoryId: 'food',
    );

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts())
        .thenAnswer((_) async => [_account('bpi'), _account('maya')]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => <Installment>[]);
    when(storage.saveBills(any)).thenAnswer((_) async {});
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(storage.saveInstallments(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  });

  /// Builds the presenter graph on the real clock. `testWidgets` runs on a fake
  /// one, where the ledger's async load would never settle — so the whole setup
  /// goes through [WidgetTester.runAsync].
  Future<(BillsReceivablesPresenter, InstallmentPresenter)> build(
      WidgetTester tester) async {
    late BillsReceivablesPresenter bills;
    late InstallmentPresenter installments;
    await tester.runAsync(() async {
      final ledger = LedgerPresenter(storage, stats);
      bills = BillsReceivablesPresenter(storage, ledger, stats);
      installments = InstallmentPresenter(storage, ledger, stats);
      await bills.load();
      await bills.setMonth(_month);
      await installments.load();
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    return (bills, installments);
  }

  /// Pumps the page at a viewport wide enough for the desktop layout.
  Future<void> pumpPage(
    WidgetTester tester,
    BillsReceivablesPresenter bills,
    InstallmentPresenter installments,
  ) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildWebDarkTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebBillsPage(
            presenter: bills,
            installmentPresenter: installments,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The "Select" button belonging to the section whose card carries [label].
  /// Each card has its own, so they have to be told apart by ancestor.
  Finder selectButtonNear(String cardTitle) => find.descendant(
        of: find.ancestor(
          of: find.text(cardTitle),
          matching: find.byType(Row),
        ).first,
        matching: find.widgetWithText(TextButton, 'Select'),
      );

  group('entering selection', () {
    testWidgets('Select swaps the row checkboxes for selection boxes',
        (tester) async {
      when(storage.loadBills())
          .thenAnswer((_) async => [_bill('b1'), _bill('b2')]);
      final (bills, installments) = await build(tester);
      await pumpPage(tester, bills, installments);

      expect(find.byType(Checkbox), findsNothing);

      await tester.tap(find.text('Select').first);
      await tester.pumpAndSettle();

      // One selection box per unpaid bill row.
      expect(find.byType(Checkbox), findsNWidgets(2));
    });

    testWidgets('picking rows shows the bar with settle/undo counts split',
        (tester) async {
      when(storage.loadBills()).thenAnswer((_) async => [
            _bill('b1'),
            _bill('b2'),
            _bill('b3', isPaid: true),
          ]);
      final (bills, installments) = await build(tester);
      await pumpPage(tester, bills, installments);

      await tester.tap(find.text('Select').first);
      await tester.pumpAndSettle();
      // Two unpaid, plus the paid one from the Paid card below.
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pumpAndSettle();

      expect(find.text('Pay 1'), findsOneWidget);
      expect(find.text('Undo 1'), findsOneWidget);
      expect(find.text('Delete 2'), findsOneWidget);
    });

    testWidgets('clearing the last row leaves selection mode', (tester) async {
      when(storage.loadBills()).thenAnswer((_) async => [_bill('b1')]);
      final (bills, installments) = await build(tester);
      await pumpPage(tester, bills, installments);

      await tester.tap(find.text('Select').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsWidgets);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Select'), findsWidgets);
    });

    testWidgets('only one section can select at a time', (tester) async {
      when(storage.loadBills()).thenAnswer((_) async => [_bill('b1')]);
      when(storage.loadReceivables())
          .thenAnswer((_) async => [_receivable('r1')]);
      final (bills, installments) = await build(tester);
      await pumpPage(tester, bills, installments);

      final receivablesSelect = selectButtonNear('Receivables');
      expect(
          tester.widget<TextButton>(receivablesSelect).onPressed, isNotNull);

      await tester.tap(find.text('Select').first); // bills
      await tester.pumpAndSettle();

      // A selection spanning bills and receivables has no single meaning, so
      // the other sections lock rather than starting a second one.
      expect(tester.widget<TextButton>(receivablesSelect).onPressed, isNull);
    });
  });

  group('select all', () {
    testWidgets('covers paid bills in the other card, then clears',
        (tester) async {
      when(storage.loadBills()).thenAnswer((_) async => [
            _bill('b1'),
            _bill('b2', isPaid: true),
          ]);
      final (bills, installments) = await build(tester);
      await pumpPage(tester, bills, installments);

      await tester.tap(find.text('Select').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      // The paid bill lives in the Paid card but is the same selection — that
      // is what makes a batch undo reachable at all.
      expect(find.text('2 selected'), findsWidgets);
      expect(find.text('Pay 1'), findsOneWidget);
      expect(find.text('Undo 1'), findsOneWidget);

      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
    });
  });

  group('settling a batch', () {
    testWidgets('pays every picked bill through the presenter', (tester) async {
      when(storage.loadBills()).thenAnswer((_) async => [
            _bill('b1', amount: 500),
            _bill('b2', amount: 300),
          ]);
      final (bills, installments) = await build(tester);
      await pumpPage(tester, bills, installments);

      await tester.tap(find.text('Select').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Pay 2'));
      await tester.pumpAndSettle();

      expect(find.text('Mark 2 bills paid'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Mark 2 paid'));
      await tester.pumpAndSettle();

      expect(bills.bills.where((b) => b.isPaid).map((b) => b.id),
          unorderedEquals(['b1', 'b2']));
      // And selection mode is over — the bar is gone.
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('funds picked set-asides through the presenter',
        (tester) async {
      when(storage.loadBudgetedExpenses())
          .thenAnswer((_) async => [_setAside('e1'), _setAside('e2')]);
      final (bills, installments) = await build(tester);
      await pumpPage(tester, bills, installments);

      await tester.tap(selectButtonNear('Budgeted Set-Asides'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Fund 2'));
      await tester.pumpAndSettle();

      expect(find.text('Fund 2 set-asides'), findsOneWidget);
      // Neither names a destination, so the shared one must be answered. The
      // second dropdown is "Set aside into" (the first is "Fund from").
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(DropdownButtonFormField<String>),
      ).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spend it (no transfer)').last);
      await tester.pumpAndSettle();
      // The batch bar behind the dialog also reads "Fund 2" — and is disabled
      // while the batch is in flight, which is the point. Scope to the dialog.
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Fund 2'),
      ));
      await tester.pumpAndSettle();

      expect(bills.budgetedExpenses.where((e) => e.isPaid).length, 2);
    });

    testWidgets('cancelling the dialog settles nothing and keeps the selection',
        (tester) async {
      when(storage.loadBills()).thenAnswer((_) async => [_bill('b1')]);
      final (bills, installments) = await build(tester);
      await pumpPage(tester, bills, installments);

      await tester.tap(find.text('Select').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Pay 1'));
      await tester.pumpAndSettle();
      // Scoped to the dialog — the select control has a Cancel of its own, and
      // tapping that one would end the selection rather than the dialog.
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ));
      await tester.pumpAndSettle();

      expect(bills.bills.single.isPaid, isFalse);
      // Still selecting, so a mis-click doesn't cost the whole selection.
      expect(find.text('1 selected'), findsWidgets);
    });
  });
}
