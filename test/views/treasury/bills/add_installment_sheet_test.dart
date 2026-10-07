import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_installment_sheet.dart';
import '../../../mocks.mocks.dart';

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter ledger;
  late InstallmentPresenter presenter;
  late List<Installment> stored;

  // Closes the 20th, due 15 days later.
  final maya = FinancialAccount(
    id: 'maya',
    name: 'Maya Credit',
    category: AccountCategory.creditLine,
    balance: 0,
    creditLimit: 50000,
    statementDay: 20,
    dueDaysAfterStatement: 15,
    colorHex: '#00C853',
    icon: 'card',
  );

  Installment existingPlan({double interestRate = 0}) => Installment(
        id: 'phone',
        name: 'Phone',
        accountId: 'maya',
        totalAmount: 12000,
        monthlyAmount: 1000,
        totalMonths: 12,
        // Bought Oct 19 → Oct 20 statement, due Nov 4.
        startMonth: '2026-11',
        purchaseDate: DateTime(2026, 10, 19),
        interestRate: interestRate,
        categoryId: 'tech',
      );

  setUp(() async {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    stored = [];
    var accounts = <FinancialAccount>[maya];
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
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadInstallments()).thenAnswer((_) async => stored);
    when(storage.saveInstallments(any)).thenAnswer((inv) async {
      stored = List<Installment>.from(inv.positionalArguments[0]);
    });
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    ledger = LedgerPresenter(storage, stats);
    presenter = InstallmentPresenter(storage, ledger, stats);
  });

  /// Opens the sheet on a pushed route so its Save can pop back.
  Future<void> openSheet(WidgetTester tester, Installment existing) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await ledger.load();
      await presenter.saveInstallment(existing, isEdit: false);
    });
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              body: AddInstallmentSheet(
                presenter: presenter,
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

  Finder customRateField() => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Custom %',
      );

  String customRateText(WidgetTester tester) =>
      tester.widget<TextField>(customRateField()).controller!.text;

  testWidgets('editing the deferral recomputes and saves the start month',
      (tester) async {
    await openSheet(tester, existingPlan());
    expect(find.text('November 2026'), findsOneWidget);

    await tester.tap(find.text('2mo'));
    await tester.pumpAndSettle();
    // The hint and the stepper agree on the month that will be saved.
    expect(find.textContaining('Due in Jan 2027'), findsOneWidget);
    expect(find.text('January 2027'), findsOneWidget);

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(stored.single.startMonth, '2027-01');
    expect(stored.single.deferralMonths, 2);
    expect(stored.single.categoryId, 'tech');
  });

  testWidgets('a start month set with the stepper sticks', (tester) async {
    await openSheet(tester, existingPlan());

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('December 2026'), findsOneWidget);

    await tester.tap(find.text('1mo'));
    await tester.pumpAndSettle();
    expect(find.text('December 2026'), findsOneWidget);
  });

  testWidgets('custom interest field shows a saved custom rate',
      (tester) async {
    await openSheet(tester, existingPlan(interestRate: 1.25));
    expect(customRateText(tester), '1.25');

    // Choosing a preset chip clears what the custom field showed.
    await tester.tap(find.text('1%'));
    await tester.pumpAndSettle();
    expect(customRateText(tester), '');
  });

  testWidgets('backspacing a custom rate onto a preset keeps the text',
      (tester) async {
    await openSheet(tester, existingPlan());

    await tester.enterText(customRateField(), '2.5');
    await tester.pump();
    await tester.enterText(customRateField(), '2.');
    await tester.pump();
    // "2." parses as the 2% preset, but the field must not clear mid-typing.
    expect(customRateText(tester), '2.');
  });

  testWidgets('interest preview follows a typed-over monthly payment',
      (tester) async {
    await openSheet(tester, existingPlan(interestRate: 1));
    // Monthly ₱1,000 × 12 = ₱12,000: no interest beyond the principal.
    expect(find.textContaining('Total payable: ₱12,000.00'), findsOneWidget);

    final monthly = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '1000.00');
    await tester.enterText(monthly, '1200');
    await tester.pump();
    expect(find.textContaining('Total payable: ₱14,400.00'), findsOneWidget);
    expect(find.textContaining('Interest: ₱2,400.00 (1%/mo)'), findsOneWidget);
  });
}
