import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../mocks.mocks.dart';

// Plan 050 — web dashboard parity getters (totalAssets, monthNetCashFlow,
// savingsRate, currentObligations, projectedSpareThisMonth, canAfford).

FinancialAccount _account({
  required String id,
  AccountCategory category = AccountCategory.ewallet,
  double balance = 0,
}) =>
    FinancialAccount(
      id: id,
      name: id,
      category: category,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

TransactionRecord _txn({
  required String id,
  required double amount,
  required TransactionType type,
}) =>
    TransactionRecord(
      id: id,
      date: DateTime.now(),
      accountId: 'acc1',
      categoryId: 'cat',
      amount: amount,
      type: type,
      description: 'Test',
      month: toMonthKey(DateTime.now()),
    );

void main() {
  late MockStorageService mockStorage;

  setUp(() {
    mockStorage = MockStorageService();
    when(mockStorage.loadAccounts()).thenAnswer((_) async => []);
    when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
    when(mockStorage.loadBills()).thenAnswer((_) async => []);
    when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgets()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
  });

  group('parity getters', () {
    test(
        'totalAssets sums top-level non-liability accounts; netWorth nets debt',
        () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'acc1', balance: 10000),
            _account(id: 'acc2', category: AccountCategory.cash, balance: 2000),
            _account(
                id: 'cc', category: AccountCategory.creditCard, balance: 4000),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      expect(p.totalAssets, 12000);
      expect(p.totalLiabilities, 4000);
      // netWorth == totalAssets - held(0) - liabilities
      expect(p.netWorth, p.totalAssets - p.totalHeldForOthers - 4000);
      expect(p.netWorth, 8000);
      expect(p.currentObligations, 4000); // 0 unpaid bills + 4000 liabilities
    });

    test('monthNetCashFlow and savingsRate compute from this month', () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(id: 't1', amount: 5000, type: TransactionType.inflow),
            _txn(id: 't2', amount: 2000, type: TransactionType.outflow),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      expect(p.monthNetCashFlow, 3000);
      expect(p.savingsRate, closeTo(0.6, 1e-9)); // 3000 / 5000
    });

    test('savingsRate is null when there is no income', () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(id: 't1', amount: 2000, type: TransactionType.outflow),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      expect(p.savingsRate, isNull);
      expect(p.monthNetCashFlow, -2000);
    });
  });

  group('canAfford', () {
    // With no bills/receivables/budgets, projectedSpareThisMonth == liquid cash.
    Future<TreasuryDashboardPresenter> presenterWithCash() async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'acc1', balance: 10000),
            _account(id: 'acc2', category: AccountCategory.cash, balance: 2000),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();
      return p;
    }

    test('yes when amount is well within spare', () async {
      final p = await presenterWithCash(); // spare = 12000
      final v = p.canAfford(5000);
      expect(v.tier, AffordTier.yes); // 5000 <= 12000 * 0.8 (9600)
      expect(v.spareAfter, 7000);
      expect(v.accountShortfall, isNull);
    });

    test('tight when amount is above 80% of spare but still fits', () async {
      final p = await presenterWithCash(); // spare = 12000
      final v = p.canAfford(11000);
      expect(v.tier, AffordTier.tight); // 9600 < 11000 <= 12000
      expect(v.spareAfter, 1000);
    });

    test('no when amount exceeds spare', () async {
      final p = await presenterWithCash(); // spare = 12000
      final v = p.canAfford(13000);
      expect(v.tier, AffordTier.no);
      expect(v.spareAfter, -1000);
    });

    test('no with shortfall when the chosen account cannot cover it', () async {
      final p = await presenterWithCash(); // spare = 12000
      final v = p.canAfford(3000, accountId: 'acc2'); // acc2 has 2000
      expect(v.tier, AffordTier.no);
      expect(v.accountShortfall, 1000);
    });
  });
}
