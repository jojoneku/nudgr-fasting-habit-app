import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_bill_sheet.dart';
import 'package:intermittent_fasting/views/treasury/shared/recurring_scope_field.dart';

import '../../../mocks.mocks.dart';

/// The scope switch is the user-facing half of the recurring-edit fix: without
/// it, carrying an amount forward would be an invisible behaviour change, and a
/// genuinely one-off correction ("they overcharged me in March") would have no
/// way to stay in its month.
void main() {
  const month = '2026-08';
  const nextMonth = '2026-09';

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter presenter;
  late List<Bill> saved;

  Bill rent({
    required String id,
    required String month,
    double amount = 15000,
    bool isRecurring = true,
    String? seriesId,
    bool isPaid = false,
    String? transactionId,
  }) =>
      Bill(
        id: id,
        name: 'Rent',
        billType: BillType.other,
        amount: amount,
        dueDay: 5,
        month: month,
        categoryId: '',
        isRecurring: isRecurring,
        recurrenceType: isRecurring ? RecurrenceType.monthly : null,
        seriesId: seriesId,
        isPaid: isPaid,
        transactionId: transactionId,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = MockStorageService();
    stats = MockStatsPresenter();
    // Injected, not defaulted: `load()` awaits the notification service, and a
    // real one never settles inside a widget test's zone.
    notifications = MockNotificationService();
    saved = <Bill>[];

    when(notifications.cancelBillsReminder()).thenAnswer((_) async {});
    when(notifications.scheduleBillsReminder(any)).thenAnswer((_) async {});
    when(notifications.cancelBillReminder(any)).thenAnswer((_) async {});
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.saveBills(any)).thenAnswer((inv) async {
      saved = List<Bill>.from(inv.positionalArguments.first as List<Bill>);
    });
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());

    ledger = LedgerPresenter(storage, stats);
    presenter = BillsReceivablesPresenter(storage, ledger, stats,
        notifications: notifications);
  });

  /// Pushes the sheet onto a route of its own so saving — which pops — has
  /// something to pop, the way it does in the app.
  Future<void> pumpSheet(
    WidgetTester tester, {
    required List<Bill> existingBills,
    Bill? editing,
  }) async {
    when(storage.loadBills()).thenAnswer((_) async => existingBills);
    await ledger.load();
    await presenter.load();
    await presenter.setMonth(month);
    await tester.binding.setSurfaceSize(const Size(393, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                body: SingleChildScrollView(
                  child: AddBillSheet(presenter: presenter, existing: editing),
                ),
              ),
            )),
            child: const Text('open sheet'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
  }

  Bill savedBillIn(String month) => saved.firstWhere((b) => b.month == month);

  testWidgets('offers the choice, defaulting to carrying the edit forward',
      (tester) async {
    final aug = rent(id: 'aug', month: month, seriesId: 's1');
    await pumpSheet(
      tester,
      existingBills: [aug, rent(id: 'sep', month: nextMonth, seriesId: 's1')],
      editing: aug,
    );

    expect(find.byType(RecurringScopeField), findsOneWidget);
    expect(find.text('Apply to future months'), findsOneWidget);
    expect(find.text('The next month will use this amount too'), findsOneWidget,
        reason: 'the switch has to name its blast radius, not just exist');
  });

  testWidgets('saving with the switch on rewrites the month ahead',
      (tester) async {
    final aug = rent(id: 'aug', month: month, seriesId: 's1');
    await pumpSheet(
      tester,
      existingBills: [aug, rent(id: 'sep', month: nextMonth, seriesId: 's1')],
      editing: aug,
    );

    await tester.enterText(find.byType(TextFormField).at(1), '18000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedBillIn(month).amount, 18000);
    expect(savedBillIn(nextMonth).amount, 18000);
  });

  testWidgets('switching it off keeps the edit in its own month',
      (tester) async {
    final aug = rent(id: 'aug', month: month, seriesId: 's1');
    await pumpSheet(
      tester,
      existingBills: [aug, rent(id: 'sep', month: nextMonth, seriesId: 's1')],
      editing: aug,
    );

    await tester.enterText(find.byType(TextFormField).at(1), '18000');
    await tester.tap(find.descendant(
      of: find.byType(RecurringScopeField),
      matching: find.byType(Switch),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Only August 2026 changes'), findsOneWidget,
        reason: 'the subtitle names the month so the choice reads concretely');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedBillIn(month).amount, 18000);
    expect(savedBillIn(nextMonth).amount, 15000);
  });

  testWidgets('stays hidden when there is no later month to reach',
      (tester) async {
    final aug = rent(id: 'aug', month: month, seriesId: 's1');
    await pumpSheet(tester, existingBills: [aug], editing: aug);

    expect(find.byType(RecurringScopeField), findsNothing,
        reason: 'a choice between two identical outcomes is just clutter');
  });

  testWidgets('stays hidden when the only month ahead is already paid',
      (tester) async {
    final aug = rent(id: 'aug', month: month, seriesId: 's1');
    await pumpSheet(
      tester,
      existingBills: [
        aug,
        rent(
          id: 'sep',
          month: nextMonth,
          seriesId: 's1',
          isPaid: true,
          transactionId: 'txn-1',
        ),
      ],
      editing: aug,
    );

    expect(find.byType(RecurringScopeField), findsNothing);
  });

  testWidgets('warns that dropping recurrence removes the months ahead',
      (tester) async {
    final aug = rent(id: 'aug', month: month, seriesId: 's1');
    await pumpSheet(
      tester,
      existingBills: [aug, rent(id: 'sep', month: nextMonth, seriesId: 's1')],
      editing: aug,
    );

    await tester.tap(find.text('Recurring'));
    await tester.pumpAndSettle();

    // Still offered — the months ahead exist only because it used to recur —
    // but now opt-in, and labelled as the removal it actually is.
    expect(find.text('Also drop future months'), findsOneWidget);
    expect(find.text('The months already generated ahead stay'), findsOneWidget,
        reason: 'a destructive switch must not come pre-armed');
  });

  testWidgets('a new recurring bill can seed the months already opened',
      (tester) async {
    // September exists because the user paged forward once; the seeding pass
    // skips a month that already holds anything.
    await pumpSheet(
      tester,
      existingBills: [rent(id: 'sep-other', month: nextMonth)],
    );

    await tester.enterText(find.byType(TextFormField).first, 'Gym');
    await tester.enterText(find.byType(TextFormField).at(1), '1200');
    await tester.tap(find.text('Recurring'));
    await tester.pumpAndSettle();

    expect(find.byType(RecurringScopeField), findsOneWidget);

    await tester.tap(find.text('Save bill'));
    await tester.pumpAndSettle();

    expect(
      saved.where((b) => b.name == 'Gym').map((b) => b.month),
      containsAll([month, nextMonth]),
    );
  });
}
