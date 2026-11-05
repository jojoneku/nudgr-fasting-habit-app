import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_installment_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/installment_review_panel.dart';
import '../../../mocks.mocks.dart';

/// Plan 067 on the mobile sheet: the "Paying for someone" toggle and the
/// review step, in add mode and edit mode.
void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;
  late LedgerPresenter ledger;
  late InstallmentPresenter plans;
  late BillsReceivablesPresenter bills;
  late List<Installment> stored;
  late List<Receivable> receivables;

  // "Madness Limit": statement closes the 15th, payment due the 4th.
  final card = FinancialAccount(
    id: 'bpi',
    name: 'Madness Limit',
    category: AccountCategory.creditCard,
    balance: 0,
    creditLimit: 100000,
    statementDay: 15,
    paymentDueDay: 4,
    colorHex: '#AA0000',
    icon: 'credit_card',
  );

  // Stored before the card had a statement day: purchase month + 3.
  final panasonic = Installment(
    id: 'panasonic',
    name: 'Panasonic Refrigerator',
    accountId: 'bpi',
    totalAmount: 36000,
    monthlyAmount: 3000,
    totalMonths: 12,
    startMonth: '2026-12',
    purchaseDate: DateTime(2026, 9, 25),
    deferralMonths: 3,
  );

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    stored = [];
    receivables = [];
    var accounts = <FinancialAccount>[card];
    var txns = <TransactionRecord>[];
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.saveAccounts(any)).thenAnswer((inv) async {
      accounts = List<FinancialAccount>.from(inv.positionalArguments[0]);
    });
    when(storage.loadTransactions()).thenAnswer((_) async => txns);
    when(storage.saveTransactions(any)).thenAnswer((inv) async {
      txns = List<TransactionRecord>.from(inv.positionalArguments[0]);
    });
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => stored);
    when(storage.saveInstallments(any)).thenAnswer((inv) async {
      stored = List<Installment>.from(inv.positionalArguments[0]);
    });
    when(storage.loadBills()).thenAnswer((_) async => <Bill>[]);
    when(storage.saveBills(any)).thenAnswer((_) async {});
    when(storage.loadReceivables()).thenAnswer((_) async => receivables);
    when(storage.saveReceivables(any)).thenAnswer((inv) async {
      receivables = List<Receivable>.from(inv.positionalArguments[0]);
    });
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadDismissedStatementKeys())
        .thenAnswer((_) async => <String>{});
    when(storage.saveDismissedStatementKeys(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    ledger = LedgerPresenter(storage, stats);
    plans = InstallmentPresenter(storage, ledger, stats);
    bills = BillsReceivablesPresenter(storage, ledger, stats,
        notifications: notifications, installments: plans);
  });

  /// Opens the sheet on a pushed route so its save can pop back.
  Future<void> openSheet(WidgetTester tester, {Installment? existing}) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await ledger.load();
      await plans.load();
      await bills.load();
      if (existing != null) {
        await plans.saveInstallment(existing, isEdit: false);
      }
    });
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              body: AddInstallmentSheet(
                presenter: plans,
                receivables: bills,
                existing: existing,
              ),
            ),
          )),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  const toggle = ValueKey('installment.paidForToggle');
  const person = ValueKey('installment.paidForName');

  testWidgets('add: toggle on, review lists receivables, confirm saves',
      (tester) async {
    await openSheet(tester);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. MacBook Pro, Braces'),
        'Xiaomi Redmi Note 15');
    await tester.enterText(
        find.widgetWithText(TextFormField, '0.00').first, '12000');
    await tester.pumpAndSettle();

    // Off: no person field.
    expect(find.byKey(person), findsNothing);
    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    expect(find.byKey(person), findsOneWidget);

    // The person is required while the toggle is on.
    await tester.tap(find.text('Add Installment'));
    await tester.pumpAndSettle();
    expect(find.text('Who is it for?'), findsOneWidget);
    expect(find.byKey(InstallmentReviewKeys.panel), findsNothing);

    await tester.enterText(find.byKey(person), 'Papa');
    await tester.tap(find.text('Add Installment'));
    await tester.pumpAndSettle();
    expect(find.byKey(InstallmentReviewKeys.panel), findsOneWidget);
    expect(find.text('Receivables from Papa'), findsOneWidget);
    expect(find.text('12 new'), findsOneWidget);
    expect(stored, isEmpty, reason: 'nothing saves before Confirm');

    // Back returns to the form with the input kept.
    await tester.tap(find.byKey(InstallmentReviewKeys.back));
    await tester.pumpAndSettle();
    expect(find.byKey(InstallmentReviewKeys.panel), findsNothing);
    expect(find.text('Papa'), findsWidgets);
    expect(stored, isEmpty);

    await tester.tap(find.text('Add Installment'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InstallmentReviewKeys.confirm));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(stored.single.paidForName, 'Papa');
    expect(receivables.where((r) => r.installmentId == stored.single.id).length,
        12);
  });

  testWidgets('add: toggle off makes no receivables', (tester) async {
    await openSheet(tester);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. MacBook Pro, Braces'),
        'Laptop');
    await tester.enterText(
        find.widgetWithText(TextFormField, '0.00').first, '12000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Installment'));
    await tester.pumpAndSettle();
    expect(find.byKey(InstallmentReviewKeys.panel), findsOneWidget);
    expect(find.textContaining('Receivables'), findsNothing);
    await tester.tap(find.byKey(InstallmentReviewKeys.confirm));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(stored.single.paidForName, isNull);
    expect(receivables, isEmpty);
  });

  testWidgets('edit: the toggle shows the saved person', (tester) async {
    await openSheet(tester,
        existing:
            panasonic.copyWith(paidForName: 'Mama', startMonth: '2027-02'));
    final field = tester.widget<TextFormField>(find.byKey(person));
    expect(field.controller!.text, 'Mama');
  });

  testWidgets('edit: review flags the start month and can take the fix',
      (tester) async {
    await openSheet(tester, existing: panasonic);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text("Stored Dec 2026 · the card's cycle gives Feb 2027"),
        findsOneWidget);
    expect(find.text('Nov 15, 2026'), findsOneWidget);

    await tester.tap(find.byKey(InstallmentReviewKeys.useSuggested));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stored Dec 2026'), findsNothing);
    expect(find.text('Jan 15, 2027'), findsOneWidget);
    expect(find.text('Feb 4, 2027'), findsOneWidget);
    expect(stored.single.startMonth, '2026-12',
        reason: 'the button changes the review only');

    await tester.tap(find.byKey(InstallmentReviewKeys.confirm));
    await tester.pumpAndSettle();
    expect(stored.single.startMonth, '2027-02');
  });

  testWidgets('edit: Back after the fix keeps the stored month on the form',
      (tester) async {
    await openSheet(tester, existing: panasonic);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InstallmentReviewKeys.useSuggested));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InstallmentReviewKeys.back));
    await tester.pumpAndSettle();
    // The form took the month too; nothing is saved.
    expect(find.text('February 2027'), findsOneWidget);
    expect(stored.single.startMonth, '2026-12');
  });
}
