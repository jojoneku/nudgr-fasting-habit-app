import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/treasury_presenters.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../mocks.mocks.dart';

/// An installment hold is what a card's plans will still bill. It is derived
/// from the live plans (owned by InstallmentPresenter) and the payments in the
/// ledger — never stored. These tests pin that every surface reads the live
/// figure, from a cold start on, with no storage round-trip and no explicit
/// refresh call.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('FinancialAccount — hold is not persisted', () {
    final card = FinancialAccount(
      id: 'cc',
      name: 'BPI',
      category: AccountCategory.creditCard,
      balance: 1000,
      creditLimit: 50000,
      unbilledInstallments: 9000,
      colorHex: '#FFFFFF',
      icon: 'card',
    );

    test('toJson leaves the hold out', () {
      expect(card.toJson().containsKey('unbilledInstallments'), isFalse);
    });

    test('fromJson ignores a hold an older build stored', () {
      final json = card.toJson()..['unbilledInstallments'] = 10000;
      expect(FinancialAccount.fromJson(json).unbilledInstallments, 0.0);
    });
  });

  group('FinancialAccount — overpaid card offsets its hold', () {
    FinancialAccount card(double balance, double hold) => FinancialAccount(
          id: 'cc',
          name: 'BPI',
          category: AccountCategory.creditCard,
          balance: balance,
          creditLimit: 50000,
          unbilledInstallments: hold,
          colorHex: '#FFFFFF',
          icon: 'card',
        );

    test('a credit balance smaller than the hold', () {
      final a = card(-2000, 5000);
      expect(a.currentPayable, 0.0);
      expect(a.totalDebt, 3000.0);
      expect(a.availableCredit, 47000.0);
      expect(a.utilization, 3000.0 / 50000.0);
    });

    test('a credit balance larger than the hold floors at zero', () {
      final a = card(-6000, 5000);
      expect(a.totalDebt, 0.0);
      expect(a.availableCredit, 50000.0);
      expect(a.utilization, 0.0);
    });
  });

  group('Installment.holdsByAccount', () {
    Installment plan(String id, String account, double monthly, int months,
            {bool active = true}) =>
        Installment(
          id: id,
          name: id,
          accountId: account,
          totalAmount: monthly * months,
          monthlyAmount: monthly,
          totalMonths: months,
          startMonth: '2026-01',
          isActive: active,
        );

    TransactionRecord pay(String id, String planId, {bool purchase = false}) =>
        TransactionRecord(
          id: id,
          date: DateTime(2026, 1, 15),
          accountId: 'cc',
          categoryId: 'x',
          amount: 1000,
          type: TransactionType.outflow,
          description: id,
          month: '2026-01',
          installmentId: planId,
          isInstallment: purchase,
        );

    test('sums remaining billing per account, skipping inactive plans', () {
      final holds = Installment.holdsByAccount(
        [
          plan('a', 'cc', 1000, 10),
          plan('b', 'cc', 500, 4),
          plan('c', 'other', 2000, 3),
          plan('d', 'cc', 9999, 9, active: false),
        ],
        [
          pay('p1', 'a'),
          pay('p2', 'a'),
          pay('p3', 'b'),
          pay('buy', 'a',
              purchase: true), // the purchase record is not a payment
          pay('p4', 'unknown'),
        ],
      );
      expect(holds, {'cc': 8000.0 + 1500.0, 'other': 6000.0});
    });

    test('includes add-on interest: it is what the plan will still bill', () {
      final monthly = Installment.computeMonthlyAmount(
          principal: 12000, months: 12, monthlyRate: 1);
      final p = Installment(
        id: 'i',
        name: 'Phone',
        accountId: 'cc',
        totalAmount: 12000,
        monthlyAmount: monthly, // 1,000 principal + 120 interest
        totalMonths: 12,
        startMonth: '2026-01',
        interestRate: 1,
      );
      expect(Installment.holdsByAccount([p], const [])['cc'],
          closeTo(12 * 1120.0, 0.001));
    });
  });

  group('graph — holds follow the plan owner', () {
    late MockStorageService storage;
    late MockStatsPresenter stats;
    late List<FinancialAccount> accounts;
    late List<TransactionRecord> txns;
    late List<Installment> plans;

    final thisMonth = toMonthKey(DateTime.now());
    final now = DateTime.now();
    final lastMonth = toMonthKey(DateTime(now.year, now.month - 1));

    setUp(() {
      storage = MockStorageService();
      stats = MockStatsPresenter();

      // Stored the way an older build wrote it: with a hold one write behind
      // (10,000, before the first payment). It must not be trusted.
      final storedJson = FinancialAccount(
        id: 'cc',
        name: 'BPI',
        category: AccountCategory.creditCard,
        balance: 0,
        creditLimit: 50000,
        colorHex: '#FFFFFF',
        icon: 'card',
      ).toJson()
        ..['unbilledInstallments'] = 10000;
      accounts = [
        FinancialAccount.fromJson(storedJson),
        FinancialAccount(
          id: 'bank',
          name: 'Bank',
          category: AccountCategory.bank,
          balance: 100000,
          colorHex: '#FFFFFF',
          icon: 'bank',
        ),
      ];
      plans = [
        Installment(
          id: 'phone',
          name: 'Phone',
          accountId: 'cc',
          totalAmount: 10000,
          monthlyAmount: 1000,
          totalMonths: 10,
          startMonth: lastMonth,
        ),
      ];
      // One month already paid.
      txns = [
        TransactionRecord(
          id: 'pay-1',
          date: DateTime(now.year, now.month - 1, 5),
          accountId: 'bank',
          categoryId: '__installment__',
          amount: 1000,
          type: TransactionType.outflow,
          description: 'Phone — Payment 1/10',
          month: lastMonth,
          installmentId: 'phone',
        ),
      ];

      when(stats.addXp(any)).thenAnswer((_) async {});
      when(stats.stats).thenReturn(UserStats.initial());
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer((_) async => accounts);
      when(storage.saveAccounts(any)).thenAnswer((inv) async {
        accounts = List<FinancialAccount>.from(
            inv.positionalArguments.first as List<FinancialAccount>);
      });
      when(storage.loadTransactions()).thenAnswer((_) async => txns);
      when(storage.saveTransactions(any)).thenAnswer((inv) async {
        txns = List<TransactionRecord>.from(
            inv.positionalArguments.first as List<TransactionRecord>);
      });
      when(storage.loadInstallments()).thenAnswer((_) async => plans);
      when(storage.saveInstallments(any)).thenAnswer((inv) async {
        plans = List<Installment>.from(
            inv.positionalArguments.first as List<Installment>);
      });
      when(storage.loadBudgets()).thenAnswer((_) async => []);
      when(storage.saveBudgets(any)).thenAnswer((_) async {});
      when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
      when(storage.saveBudgetGroups(any)).thenAnswer((_) async {});
      when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
      when(storage.loadBills()).thenAnswer((_) async => []);
      when(storage.saveBills(any)).thenAnswer((_) async {});
      when(storage.loadReceivables()).thenAnswer((_) async => []);
      when(storage.saveReceivables(any)).thenAnswer((_) async {});
      when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(storage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
      when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
      when(storage.saveMonthlySummaries(any)).thenAnswer((_) async {});
      when(storage.loadGroceryCart()).thenAnswer((_) async => []);
      when(storage.loadGroceryPriceMemory()).thenAnswer((_) async => []);
      when(storage.loadGroceryTripHistory()).thenAnswer((_) async => []);
      when(storage.loadGroceryBudget()).thenAnswer((_) async => null);
      when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
      when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
      when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
      when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
      when(storage.loadDismissedStatementKeys())
          .thenAnswer((_) async => <String>{});
      when(storage.saveDismissedStatementKeys(any)).thenAnswer((_) async {});
    });

    Future<TreasuryPresenters> build() async {
      final t = TreasuryPresenters(storage: storage, stats: stats);
      await Future.wait(t.loadAll());
      return t;
    }

    FinancialAccount cardIn(List<FinancialAccount> list) =>
        list.firstWhere((a) => a.id == 'cc');

    void expectHoldEverywhere(TreasuryPresenters t, double hold) {
      expect(cardIn(t.ledger.accounts).unbilledInstallments, hold,
          reason: 'ledger');
      expect(cardIn(t.dashboard.creditAccounts).unbilledInstallments, hold,
          reason: 'dashboard');
      expect(cardIn(t.bills.creditAccounts).unbilledInstallments, hold,
          reason: 'bills');
      expect(cardIn(t.installments.creditAccounts).unbilledInstallments, hold,
          reason: 'installments');
    }

    test('a cold start shows the live hold, not the stored one', () async {
      final t = await build();
      addTearDown(t.dispose);

      // 9 of 10 months left: 9,000 — not the stale 10,000 in storage, and no
      // refreshInstallmentHolds() call needed.
      expectHoldEverywhere(t, 9000);
      expect(t.dashboard.totalCreditOwed, 9000);
      expect(t.dashboard.totalCreditAvailable, 41000);
      expect(t.dashboard.totalLiabilities, 9000);
      // Plans are read only by their owner: once from its constructor and once
      // from loadAll(). The ledger never reads them.
      verify(storage.loadInstallments()).called(2);
    });

    test('a dashboard load that finishes after the ledger keeps the hold',
        () async {
      final t = await build();
      addTearDown(t.dispose);

      // Simulates the startup race where the dashboard's own storage read
      // lands last. Storage has no hold; the ledger's live one must win.
      await t.dashboard.load();
      await t.budget.load();
      await t.history.load();

      expect(cardIn(t.dashboard.creditAccounts).unbilledInstallments, 9000);
      expect(t.dashboard.totalCreditOwed, 9000);
    });

    test('the account form helpers read the live hold', () async {
      final t = await build();
      addTearDown(t.dispose);

      final card = cardIn(accounts); // straight from storage: no hold
      expect(card.unbilledInstallments, 0);
      expect(t.dashboard.accountBalanceFieldValue(card), 9000);
      expect(
        t.dashboard.balanceFromField(AccountCategory.creditCard, 9500,
            accountId: 'cc'),
        500,
      );
      expect(
        t.dashboard
            .accountBalanceHint(AccountCategory.creditCard, accountId: 'cc'),
        contains(formatPeso(9000)),
      );
      expect(
        t.dashboard.accountBalanceError(AccountCategory.creditCard, '8000',
            accountId: 'cc'),
        isNotNull,
      );
    });

    test('marking a payment lowers the hold everywhere', () async {
      final t = await build();
      addTearDown(t.dispose);
      t.installments.setMonth(thisMonth);

      await t.installments.markPaid('phone', fundingAccountId: 'bank');

      expectHoldEverywhere(t, 8000);
      expect(t.dashboard.totalCreditAvailable, 42000);
      // Nothing stored carries a hold.
      for (final a in accounts) {
        expect(a.toJson().containsKey('unbilledInstallments'), isFalse);
      }
    });

    test('undoing a payment raises the hold back', () async {
      final t = await build();
      addTearDown(t.dispose);
      t.installments.setMonth(thisMonth);
      await t.installments.markPaid('phone', fundingAccountId: 'bank');

      await t.installments.markUnpaid('phone');

      expectHoldEverywhere(t, 9000);
    });

    test('a new plan holds credit on every surface at once', () async {
      final t = await build();
      addTearDown(t.dispose);

      await t.installments.addInstallment(Installment(
        id: 'laptop',
        name: 'Laptop',
        accountId: 'cc',
        totalAmount: 20000,
        monthlyAmount: 5000,
        totalMonths: 4,
        startMonth: thisMonth,
      ));

      expectHoldEverywhere(t, 29000);

      await t.installments.deleteInstallment('laptop');

      expectHoldEverywhere(t, 9000);
    });

    test('saving the card from the form keeps the derived hold', () async {
      final t = await build();
      addTearDown(t.dispose);

      // The form builds a fresh account with no hold on it.
      await t.dashboard.updateAccount(
          cardIn(accounts).copyWith(name: 'BPI Gold', creditLimit: 60000));

      expectHoldEverywhere(t, 9000);
      expect(cardIn(t.dashboard.creditAccounts).availableCredit, 51000);
    });
  });
}
