import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_setup_view.dart';
import 'package:intermittent_fasting/views/treasury/shared/sheet_fields.dart';
import '../mocks.mocks.dart';

/// Credit billing terms on the mobile account form: the payment-due rule
/// (day of month vs days after statement) and the minimum-payment rule. Exactly
/// one due rule is stored, and the minimum rule is always saved explicitly.
void main() {
  late MockStorageService mockStorage;

  final card = FinancialAccount(
    id: 'cc1',
    name: 'Rewards Card',
    category: AccountCategory.creditCard,
    balance: 12000,
    statementDay: 5,
    paymentDueDay: 25,
    colorHex: '#DC2626',
    icon: 'creditCard',
  );
  final line = FinancialAccount(
    id: 'cl1',
    name: 'Credit Line',
    category: AccountCategory.creditLine,
    balance: 3000,
    statementDay: 20,
    dueDaysAfterStatement: 15,
    colorHex: '#0891B2',
    icon: 'creditLine',
  );

  setUp(() {
    mockStorage = MockStorageService();
    when(mockStorage.loadAccounts()).thenAnswer((_) async => [card, line]);
    when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
    when(mockStorage.loadBills()).thenAnswer((_) async => []);
    when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgets()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(mockStorage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(mockStorage.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(mockStorage.saveAccounts(any)).thenAnswer((_) async {});
  });

  Future<void> pumpForm(WidgetTester tester, FinancialAccount existing) async {
    final presenter = TreasuryDashboardPresenter(mockStorage);
    await presenter.load();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountSetupView(presenter: presenter, existing: existing),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  FinancialAccount lastSaved(String id) {
    final captured = verify(mockStorage.saveAccounts(captureAny)).captured.last
        as List<FinancialAccount>;
    return captured.firstWhere((a) => a.id == id);
  }

  testWidgets('an offset-due account opens in offset mode and keeps its rule',
      (tester) async {
    await pumpForm(tester, line);

    expect(find.text('DUE AFTER'), findsOneWidget);
    expect(find.text('15 days'), findsOneWidget);

    await tapVisible(tester, find.text('Save'));

    final saved = lastSaved('cl1');
    expect(saved.dueDaysAfterStatement, 15);
    expect(saved.paymentDueDay, isNull);
    expect(saved.minimumRule, CreditMinimumRule.payInFull,
        reason: 'the category default is saved explicitly');
    expect(saved.minimumFixedAmount, isNull);
  });

  testWidgets('switching to days-after-statement clears the fixed due day',
      (tester) async {
    await pumpForm(tester, card);

    await tapVisible(tester, find.text('Days after statement'));
    await tapVisible(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('due-days-after')),
        matching: find.byType(DropdownButtonFormField<int?>),
      ),
    );
    await tester.tap(find.text('5 days').last);
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Save'));

    final saved = lastSaved('cc1');
    expect(saved.dueDaysAfterStatement, 5);
    expect(saved.paymentDueDay, isNull);
    expect(saved.minimumRule, CreditMinimumRule.percentOfBalance);
  });

  testWidgets('a fixed minimum requires an amount above zero', (tester) async {
    await pumpForm(tester, card);

    await tapVisible(tester, find.text('Fixed amount'));
    await tapVisible(tester, find.text('Save'));
    expect(find.text('Enter an amount above ₱0'), findsOneWidget);
    verifyNever(mockStorage.saveAccounts(any));

    final amountField = find.descendant(
      of: find.ancestor(
        of: find.text('MINIMUM AMOUNT'),
        matching: find.byType(SheetLabeledField),
      ),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(amountField, '1500');
    await tapVisible(tester, find.text('Save'));

    final saved = lastSaved('cc1');
    expect(saved.minimumRule, CreditMinimumRule.fixedAmount);
    expect(saved.minimumFixedAmount, 1500);
    expect(saved.paymentDueDay, 25);
    expect(saved.dueDaysAfterStatement, isNull);
  });

  testWidgets('a new account\'s minimum rule follows its category until picked',
      (tester) async {
    // Tall surface so the whole new-account form fits without scrolling.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final presenter = TreasuryDashboardPresenter(mockStorage);
    await presenter.load();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountSetupView(
          presenter: presenter,
          initialCategory: AccountCategory.creditCard,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    CreditMinimumRule shownRule() => tester
        .widget<SegmentedButton<CreditMinimumRule>>(
            find.byType(SegmentedButton<CreditMinimumRule>))
        .selected
        .single;

    expect(shownRule(), CreditMinimumRule.percentOfBalance);

    await tapVisible(tester, find.text('Credit Card'));
    await tester.tap(find.text('Credit Line').last);
    await tester.pumpAndSettle();
    expect(shownRule(), CreditMinimumRule.payInFull);

    await tester.enterText(find.byType(TextFormField).first, 'New Line');
    await tapVisible(tester, find.text('Add Account'));

    final captured = verify(mockStorage.saveAccounts(captureAny)).captured.last
        as List<FinancialAccount>;
    final saved = captured.firstWhere((a) => a.name == 'New Line');
    expect(saved.category, AccountCategory.creditLine);
    expect(saved.minimumRule, CreditMinimumRule.payInFull);
  });
}
