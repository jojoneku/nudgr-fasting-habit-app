import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/settle_request.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_month_summary.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_receivables_view.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_tab_chips.dart';
import 'package:intermittent_fasting/views/treasury/bills/coming_up_timeline.dart';
import 'package:intermittent_fasting/views/treasury/bills/credit_cards_card.dart';
import 'package:intermittent_fasting/views/treasury/bills/hero_bill_card.dart';
import 'package:intermittent_fasting/views/treasury/bills/obligation_card.dart';
import 'package:intermittent_fasting/views/treasury/shared/settle_sheet.dart';
import '../../../mocks.mocks.dart';

/// The Bills tab after Plan 071 Phase 6: each bill in one tab row (the hero
/// bill is also spotlighted above the tabs), tabs with counts, a Paid tab, batch select inside one tab,
/// no Coming up, the This month summary, and the credit cards card.
/// "Today" is pinned to 10 March 2026.
void main() {
  const month = '2026-03';
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter presenter;
  late InstallmentPresenter installments;

  Bill bill(String id, int dueDay, {bool paid = false}) => Bill(
        id: id,
        name: id,
        billType: BillType.utility,
        amount: 500,
        dueDay: dueDay,
        month: month,
        categoryId: '',
        isPaid: paid,
        paidAmount: paid ? 500 : null,
      );

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'bpi',
            name: 'BPI',
            category: AccountCategory.bank,
            balance: 20000,
            colorHex: '#FFFFFF',
            icon: 'wallet',
          ),
          // No statement day, so no statement bill is generated into the
          // month and the bill list stays exactly the seed below.
          FinancialAccount(
            id: 'card',
            name: 'BPI Card',
            category: AccountCategory.creditCard,
            balance: 4000,
            creditLimit: 10000,
            colorHex: '#FF0000',
            icon: 'card',
          ),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => [
          bill('Hero Bill', 5),
          bill('Soon A', 12),
          bill('Soon B', 15),
          bill('Later A', 25),
          bill('Later B', 28),
          bill('Paid Bill', 3, paid: true),
        ]);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => [
          BudgetedExpense(
            id: 'travel',
            name: 'Travel Fund',
            budgetedType: SetAsideType.savings,
            month: month,
            allocatedAmount: 1000,
            categoryId: '',
          ),
        ]);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadDismissedStatementKeys())
        .thenAnswer((_) async => <String>{});
    when(storage.saveDismissedStatementKeys(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(storage.saveBills(any)).thenAnswer((_) async {});
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    ledger = LedgerPresenter(storage, stats);
    installments = InstallmentPresenter(storage, ledger, stats);
    presenter = BillsReceivablesPresenter(
      storage,
      ledger,
      stats,
      notifications: MockNotificationService(),
      clock: () => DateTime(2026, 3, 10),
    );
  });

  Future<void> pumpView(WidgetTester tester, {bool dark = true}) async {
    await tester.binding.setSurfaceSize(const Size(360, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await ledger.load();
    await tester.pumpWidget(MaterialApp(
      theme: dark ? buildDarkTheme() : buildLightTheme(),
      home: BillsReceivablesView(
        presenter: presenter,
        installmentPresenter: installments,
      ),
    ));
    await tester.pumpAndSettle();
    await presenter.setMonth(month);
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, BillsTab tab) async {
    final chip = find.byKey(BillsTabKeys.chip(tab));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  /// [name] inside a list row (not the hero).
  Finder row(String name) => find.descendant(
        of: find.byType(ObligationCard),
        matching: find.text(name),
      );

  Finder inHero(String name) => find.descendant(
        of: find.byKey(HeroBillCardKeys.card),
        matching: find.text(name),
      );

  testWidgets('a bill appears exactly once besides the hero', (tester) async {
    await pumpView(tester);

    // The hero carries the most imminent bill, and only that one. The bill
    // stays in "Due soon" too, so its row actions are reachable.
    expect(inHero('Hero Bill'), findsOneWidget);
    expect(row('Hero Bill'), findsOneWidget);
    expect(find.text('Hero Bill'), findsNWidgets(2));
    for (final name in ['Soon A', 'Soon B']) {
      expect(inHero(name), findsNothing, reason: name);
    }

    // Every other unpaid bill is one Upcoming row; the paid one is not here.
    for (final name in ['Soon A', 'Soon B', 'Later A', 'Later B']) {
      expect(find.text(name), findsOneWidget, reason: name);
      expect(row(name), findsOneWidget, reason: name);
    }
    expect(find.text('Paid Bill'), findsNothing);
    expect(find.text('Due soon'), findsOneWidget);
    expect(find.text('Later this month'), findsOneWidget);
  });

  testWidgets('each tab count equals the presenter list length',
      (tester) async {
    await pumpView(tester);

    final counts = presenter.tabCounts(installments);
    final expected = {
      BillsTab.upcoming: counts.upcoming,
      BillsTab.setAsides: counts.setAsides,
      BillsTab.receivables: counts.receivables,
      BillsTab.installments: counts.installments,
      BillsTab.paid: counts.paid,
    };
    expect(expected[BillsTab.upcoming],
        presenter.unpaidDueSoon.length + presenter.unpaidLater.length);
    // The hero bill is counted: it is a "Due soon" row too.
    expect(expected[BillsTab.upcoming], 5);
    expect(expected[BillsTab.paid], presenter.paidBills.length);
    for (final entry in expected.entries) {
      expect(
        find.descendant(
          of: find.byKey(BillsTabKeys.chip(entry.key)),
          matching: find.text('${entry.value}'),
        ),
        findsOneWidget,
        reason: '${entry.key} → ${entry.value}',
      );
    }

    // The Upcoming tab shows as many rows as its chip says.
    expect(find.byType(ObligationCard), findsNWidgets(counts.upcoming));
  });

  testWidgets('the Paid tab holds only paid bills', (tester) async {
    await pumpView(tester);
    await openTab(tester, BillsTab.paid);

    expect(row('Paid Bill'), findsOneWidget);
    for (final name in ['Soon A', 'Soon B', 'Later A', 'Later B']) {
      expect(row(name), findsNothing, reason: name);
    }
    expect(find.byType(ObligationCard), findsNWidgets(1));
  });

  testWidgets('Coming up is not on the Bills tab', (tester) async {
    await pumpView(tester);
    expect(find.text('Coming up'), findsNothing);
    expect(find.byType(ComingUpTimeline), findsNothing);
    // The presenter still serves it to the Dashboard and the Hub.
    expect(presenter.comingUpItems(installments), isNotEmpty);
  });

  testWidgets('batch select stays inside one tab', (tester) async {
    await pumpView(tester);

    await tester.longPress(row('Soon A'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 5 selected'), findsOneWidget);

    // Select all picks the tab's rows, the hero bill's row included.
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('5 of 5 selected'), findsOneWidget);

    // The hero and the card Pay stand down during the selection.
    final heroPay = tester.widget<FilledButton>(find.descendant(
      of: find.byKey(HeroBillCardKeys.card),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    ));
    expect(heroPay.onPressed, isNull);
    final cardPay = tester
        .widget<FilledButton>(find.byKey(CreditCardsCardKeys.pay('card')));
    expect(cardPay.onPressed, isNull);

    // Switching tabs ends the selection.
    await openTab(tester, BillsTab.paid);
    expect(find.textContaining('selected'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // A selection on Paid counts Paid rows only.
    await tester.longPress(row('Paid Bill'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 selected'), findsOneWidget);
  });

  testWidgets('This month opens to show the presenter totals', (tester) async {
    await pumpView(tester);
    expect(find.byKey(BillsMonthSummaryKeys.fold), findsOneWidget);
    // Closed by default: only the header line shows.
    expect(find.text(presenter.monthSummaryHeadline), findsOneWidget);
    expect(find.text('Set-asides to fund'), findsNothing);

    await tester.tap(find.text('This month'));
    await tester.pumpAndSettle();

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text(formatPeso(presenter.totalBillsPending)), findsWidgets);
    expect(find.text('Set-asides to fund'), findsOneWidget);
    expect(find.text(formatPeso(presenter.setAsidePendingTotal)), findsWidgets);
    expect(find.byKey(BillsMonthSummaryKeys.byAccount), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
  });

  testWidgets('Pay on the credit cards card opens the card payment',
      (tester) async {
    await pumpView(tester);
    expect(find.byKey(CreditCardsCardKeys.card), findsOneWidget);
    expect(find.text(presenter.creditLinesDescription), findsOneWidget);

    final pay = find.byKey(CreditCardsCardKeys.pay('card'));
    await tester.ensureVisible(pay);
    await tester.pumpAndSettle();
    await tester.tap(pay);
    await tester.pumpAndSettle();

    final sheet = tester.widget<SettleSheet>(find.byType(SettleSheet));
    expect(sheet.kind, SettleKind.cardPayment);
    expect(find.text('Pay BPI Card'), findsOneWidget);
  });

  testWidgets(
      'credit cards card: unbilled installments are not "owed" above the '
      'empty state', (tester) async {
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
    when(storage.loadInstallments()).thenAnswer((_) async => [
          Installment(
            id: 'laptop',
            name: 'Laptop',
            accountId: 'card',
            totalAmount: 12000,
            monthlyAmount: 1000,
            totalMonths: 12,
            startMonth: '2026-04',
          ),
        ]);
    await installments.load();
    await pumpView(tester);

    final line = presenter.creditLinesDescription;
    expect(find.text(line), findsOneWidget);
    expect(line, isNot(contains('Owe ')));
    expect(
        line, contains('${formatPeso(12000)} in installments not yet billed'));
    expect(find.byKey(CreditCardsCardKeys.empty), findsOneWidget);
    expect(find.byKey(CreditCardsCardKeys.pay('card')), findsNothing);
  });

  testWidgets('renders in light mode at 360 dp', (tester) async {
    await pumpView(tester, dark: false);
    for (final tab in BillsTab.values) {
      await openTab(tester, tab);
    }
    expect(tester.takeException(), isNull);
  });
}
