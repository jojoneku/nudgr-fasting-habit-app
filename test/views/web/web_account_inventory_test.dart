import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/pages/dashboard/web_account_inventory_dialog.dart';

import '../../mocks.mocks.dart';

/// The "All accounts" inventory — the answer to "is that account filtered out,
/// or actually missing?".
///
/// The dashboard's Accounts section lists only top-level liquid + credit
/// accounts. Everything else (savings, goals, investments, sub-accounts,
/// custodian money, archived) is absent by design, and there was no way to see
/// it.
void main() {
  FinancialAccount account(
    String id,
    String name,
    AccountCategory category, {
    double balance = 100,
    bool isActive = true,
    String? parentAccountId,
  }) =>
      FinancialAccount(
        id: id,
        name: name,
        category: category,
        balance: balance,
        colorHex: '#2E90FA',
        icon: 'wallet',
        isActive: isActive,
        parentAccountId: parentAccountId,
      );

  /// One account of every kind the buckets have to place, plus the two edge
  /// cases (a sub-account and an archived one).
  final everyKind = <FinancialAccount>[
    account('a_bank', 'BPI Personal', AccountCategory.bank),
    account('a_wallet', 'GCash', AccountCategory.ewallet),
    account('a_cash', 'Cash', AccountCategory.cash),
    account('a_cc', 'BPI Credit Card', AccountCategory.creditCard),
    account('a_cl', 'Credit Line', AccountCategory.creditLine),
    account('a_bnpl', 'ShopeePay', AccountCategory.bnpl),
    account('a_savings', 'Savings Braces', AccountCategory.savings),
    account('a_goal', 'Travel Fund', AccountCategory.goal),
    account('a_td', 'Time Deposit', AccountCategory.timeDeposit),
    account('a_invest', 'Pagibig', AccountCategory.investment),
    account('a_custodian', 'Held for Mom', AccountCategory.custodian),
    account('a_pocket', 'Pocket in BPI', AccountCategory.goal,
        parentAccountId: 'a_bank'),
    account('a_archived', 'Old Wallet', AccountCategory.ewallet,
        isActive: false),
  ];

  MockStorageService buildStorage(List<FinancialAccount> accounts) {
    final s = MockStorageService();
    when(s.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(s.loadAccounts()).thenAnswer((_) async => accounts);
    when(s.loadTransactions()).thenAnswer((_) async => <TransactionRecord>[]);
    when(s.loadBills()).thenAnswer((_) async => []);
    when(s.loadReceivables()).thenAnswer((_) async => []);
    when(s.loadBudgets()).thenAnswer((_) async => []);
    when(s.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(s.loadFinanceCategories()).thenAnswer((_) async => []);
    when(s.loadBudgetGroups()).thenAnswer((_) async => []);
    when(s.loadMonthlySummaries()).thenAnswer((_) async => <MonthlySummary>[]);
    when(s.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(s.saveAccounts(any)).thenAnswer((_) async {});
    return s;
  }

  Future<TreasuryDashboardPresenter> load(
      List<FinancialAccount> accounts) async {
    final p = TreasuryDashboardPresenter(buildStorage(accounts));
    await p.load();
    return p;
  }

  group('accountInventory', () {
    test('places every account in exactly one bucket', () async {
      final p = await load(everyKind);
      final groups = p.accountInventory;

      final ids = [
        for (final g in groups)
          for (final a in g.accounts) a.id,
      ];
      // No account listed twice, and none dropped — the property that makes the
      // dialog's counts trustworthy.
      expect(ids.toSet(), hasLength(ids.length), reason: 'no duplicates');
      expect(ids.toSet(), everyKind.map((a) => a.id).toSet());
      expect(p.accountInventoryCount, everyKind.length);
    });

    test('only the liquid and credit buckets are marked as shown', () async {
      final p = await load(everyKind);

      final shown = p.accountInventory.where((g) => g.onDashboard).toList();
      expect(shown.map((g) => g.title),
          containsAll(['Cash & banks', 'Credit & BNPL']));

      // 3 liquid + 3 credit — and the count matches what the header claims.
      expect(p.accountInventoryShownCount, 6);
      expect(
        shown.fold<int>(0, (n, g) => n + g.accounts.length),
        p.accountInventoryShownCount,
      );
    });

    test('the shown buckets are exactly what the Accounts section renders',
        () async {
      final p = await load(everyKind);
      final onDashboard = [
        for (final g in p.accountInventory.where((g) => g.onDashboard))
          for (final a in g.accounts) a.id,
      ];
      // The section builds [...liquidAccounts, ...creditAccounts]; the dialog
      // must not claim an account is a tile when it isn't.
      expect(
        onDashboard,
        [...p.liquidAccounts, ...p.creditAccounts].map((a) => a.id).toList(),
      );
    });

    test('a sub-account is a pocket, not a top-level goal', () async {
      final p = await load(everyKind);
      final pockets = p.accountInventory
          .firstWhere((g) => g.title == 'Pockets inside another account');

      expect(pockets.accounts.map((a) => a.id), ['a_pocket']);
      expect(pockets.onDashboard, isFalse);
      // Its money is inside the parent, so the note must not imply it adds on.
      expect(pockets.surfacedIn, contains('inside the parent'));
    });

    test('archived accounts are listed but flagged as hidden', () async {
      final p = await load(everyKind);
      final archived =
          p.accountInventory.firstWhere((g) => g.title == 'Archived');

      expect(archived.accounts.map((a) => a.id), ['a_archived']);
      expect(archived.onDashboard, isFalse);
    });

    test('empty buckets are dropped', () async {
      final p = await load([
        account('a_cash', 'Cash', AccountCategory.cash),
      ]);

      expect(p.accountInventory.map((g) => g.title), ['Cash & banks']);
      expect(p.accountInventoryCount, 1);
    });

    test('no accounts at all yields no buckets', () async {
      final p = await load([]);
      expect(p.accountInventory, isEmpty);
      expect(p.accountInventoryCount, 0);
      expect(p.accountInventoryShownCount, 0);
    });

    test('bucket totals sum the balances they contain', () async {
      final p = await load([
        account('a_bank', 'BPI', AccountCategory.bank, balance: 1000),
        account('a_cash', 'Cash', AccountCategory.cash, balance: 234.5),
        account('a_cc', 'Card', AccountCategory.creditCard, balance: 800),
      ]);

      final liquid =
          p.accountInventory.firstWhere((g) => g.title == 'Cash & banks');
      expect(liquid.total, 1234.5);
      final credit =
          p.accountInventory.firstWhere((g) => g.title == 'Credit & BNPL');
      expect(credit.total, 800);
    });
  });

  group('WebAccountInventoryDialog', () {
    Future<void> pump(
        WidgetTester tester, TreasuryDashboardPresenter presenter) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildWebDarkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 900,
            child: WebAccountInventoryDialog(presenter: presenter),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('names every account and states the shown count',
        (tester) async {
      final p = await load(everyKind);
      await pump(tester, p);

      expect(find.text('All accounts'), findsOneWidget);
      expect(
        find.text('13 total · 6 shown as tiles on the dashboard'),
        findsOneWidget,
      );

      // A shown account is listed up top...
      expect(find.text('GCash'), findsOneWidget);

      // ...and every filtered-out one is reachable by scrolling. The list is
      // lazily built, so these are off-screen rather than absent.
      for (final name in [
        'Savings Braces',
        'Pagibig',
        'Pocket in BPI',
        'Held for Mom',
        'Old Wallet',
      ]) {
        await tester.scrollUntilVisible(
          find.text(name),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(name), findsOneWidget, reason: name);
      }
    });

    testWidgets('labels the credit bucket as owed, not held', (tester) async {
      final p = await load([
        account('a_cc', 'Card', AccountCategory.creditCard, balance: 800),
      ]);
      await pump(tester, p);

      // The bucket total, and the row itself — a credit row carries the balance
      // OWED, while the dashboard tile for the same card shows its *available*
      // credit. Both places must say which figure this is.
      expect(find.text('owed ${formatPeso(800)}'), findsOneWidget);
      expect(find.text('Credit Card · owed'), findsOneWidget);
    });

    testWidgets('renders an empty treasury without throwing', (tester) async {
      final p = await load([]);
      await pump(tester, p);

      expect(find.text('No accounts yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out in light mode too', (tester) async {
      final p = await load(everyKind);
      await tester.pumpWidget(MaterialApp(
        theme: buildWebLightTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 900,
            child: WebAccountInventoryDialog(presenter: p),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('All accounts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
