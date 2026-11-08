import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_bill_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_budgeted_expense_sheet.dart';
import 'package:intermittent_fasting/views/treasury/bills/add_installment_sheet.dart';
import '../../../mocks.mocks.dart';

/// The bill, set-aside and installment forms fold their optional fields under
/// "More options" (Plan 071 Phase 6). The fold stays shut on a new entry and
/// opens on its own when editing a record that has a value inside it.
void main() {
  const month = '2026-03';
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter bills;
  late InstallmentPresenter plans;

  setUp(() async {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'card',
            name: 'BPI Card',
            category: AccountCategory.creditCard,
            balance: 0,
            creditLimit: 50000,
            colorHex: '#FF0000',
            icon: 'card',
          ),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          FinanceCategory(
            id: 'cat-util',
            name: 'Utilities',
            colorHex: '#3366FF',
            icon: 'bolt',
            type: CategoryType.expense,
          ),
        ]);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(stats.stats).thenReturn(UserStats.initial());
    ledger = LedgerPresenter(storage, stats);
    bills = BillsReceivablesPresenter(storage, ledger, stats);
    plans = InstallmentPresenter(storage, ledger, stats);
  });

  /// Sheet field labels render in capitals.
  Finder label(String text) => find.text(text.toUpperCase());

  Future<void> pump(WidgetTester tester, Widget sheet) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await ledger.load();
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(body: sheet),
    ));
    await tester.pumpAndSettle();
  }

  group('bill form', () {
    Bill existing({String? note, String categoryId = ''}) => Bill(
          id: 'meralco',
          name: 'Meralco',
          billType: BillType.utility,
          amount: 2500,
          dueDay: 15,
          month: month,
          categoryId: categoryId,
          paymentNote: note,
        );

    testWidgets('More options stays shut on a new bill', (tester) async {
      await pump(tester, AddBillSheet(presenter: bills));
      expect(find.byKey(AddBillSheetKeys.moreOptions), findsOneWidget);
      expect(label('Payment Note (optional)'), findsNothing);

      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      expect(label('Payment Note (optional)'), findsOneWidget);
    });

    testWidgets('editing a bill with a note opens More options',
        (tester) async {
      await pump(
          tester,
          AddBillSheet(
              presenter: bills, existing: existing(note: 'Auto-debit')));
      expect(label('Payment Note (optional)'), findsOneWidget);
      expect(find.text('Auto-debit'), findsOneWidget);
    });

    testWidgets('editing a bill with a category opens More options',
        (tester) async {
      await pump(
          tester,
          AddBillSheet(
              presenter: bills, existing: existing(categoryId: 'cat-util')));
      expect(label('Category'), findsOneWidget);
      expect(find.text('Utilities'), findsOneWidget);
    });
  });

  group('set-aside form', () {
    BudgetedExpense existing({String? note}) => BudgetedExpense(
          id: 'travel',
          name: 'Travel Fund',
          budgetedType: SetAsideType.savings,
          month: month,
          allocatedAmount: 1000,
          categoryId: '',
          note: note,
        );

    testWidgets('More options stays shut on a new set-aside', (tester) async {
      await pump(tester, AddBudgetedExpenseSheet(presenter: bills));
      expect(
          find.byKey(AddBudgetedExpenseSheetKeys.moreOptions), findsOneWidget);
      expect(label('Note (optional)'), findsNothing);
    });

    testWidgets('editing a set-aside with a note opens More options',
        (tester) async {
      await pump(
          tester,
          AddBudgetedExpenseSheet(
              presenter: bills, existing: existing(note: 'Japan 2027')));
      expect(label('Note (optional)'), findsOneWidget);
      expect(find.text('Japan 2027'), findsOneWidget);
    });
  });

  group('installment form', () {
    Installment existing({String? note}) => Installment(
          id: 'phone',
          name: 'Phone',
          accountId: 'card',
          totalAmount: 12000,
          monthlyAmount: 1000,
          totalMonths: 12,
          startMonth: month,
          note: note,
        );

    testWidgets('More options stays shut on a new plan', (tester) async {
      await pump(tester, AddInstallmentSheet(presenter: plans));
      expect(find.byKey(AddInstallmentSheetKeys.moreOptions), findsOneWidget);
      expect(label('Note (optional)'), findsNothing);
      expect(label('Deferred First Payment (optional)'), findsNothing);
      expect(label('Monthly Interest Rate (optional)'), findsNothing);
    });

    testWidgets('editing a plan with a note opens More options',
        (tester) async {
      await pump(
          tester,
          AddInstallmentSheet(
              presenter: plans, existing: existing(note: '0%')));
      expect(label('Note (optional)'), findsOneWidget);
      expect(label('Deferred First Payment (optional)'), findsOneWidget);
      expect(label('Category (optional)'), findsOneWidget);
    });
  });
}
