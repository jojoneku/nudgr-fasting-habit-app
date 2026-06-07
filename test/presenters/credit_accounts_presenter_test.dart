import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import '../mocks.mocks.dart';

FinancialAccount _card({
  String id = 'cc',
  String name = 'BPI CC',
  double balance = 0,
  double? creditLimit,
  int? statementDay,
  int? paymentDueDay,
  String? creditBrand,
}) =>
    FinancialAccount(
      id: id,
      name: name,
      category: AccountCategory.creditCard,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'creditCard',
      creditLimit: creditLimit,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      creditBrand: creditBrand,
    );

FinancialAccount _bank(String id, double balance) => FinancialAccount(
      id: id,
      name: id,
      category: AccountCategory.bank,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'bank',
    );

TransactionRecord _txn({
  required String id,
  required String accountId,
  required double amount,
  required TransactionType type,
}) =>
    TransactionRecord(
      id: id,
      date: DateTime(2026, 6, 7),
      accountId: accountId,
      categoryId: '',
      amount: amount,
      type: type,
      description: 'Test',
      month: '2026-06',
    );

Future<void> _waitForLoad(LedgerPresenter p) async {
  while (p.isLoading) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('LedgerPresenter — liability balance sign', () {
    late MockStorageService storage;
    late MockStatsPresenter stats;
    late LedgerPresenter ledger;

    setUp(() {
      storage = MockStorageService();
      stats = MockStatsPresenter();
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer((_) async => [
            _card(id: 'cc', balance: 0, creditLimit: 50000),
            _bank('gcash', 5000),
          ]);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(storage.loadTransactions()).thenAnswer((_) async => []);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
      when(storage.saveTransactions(any)).thenAnswer((_) async {});
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      when(stats.addXp(any)).thenAnswer((_) async {});
      when(stats.stats).thenReturn(UserStats.initial());
      ledger = LedgerPresenter(storage, stats);
    });

    test('spending (outflow) on a credit card increases the owed balance',
        () async {
      await _waitForLoad(ledger);
      await ledger.addTransaction(_txn(
          id: 't1',
          accountId: 'cc',
          amount: 5000,
          type: TransactionType.outflow));
      final cc = ledger.accounts.firstWhere((a) => a.id == 'cc');
      expect(cc.balance, 5000); // debt went up, not down
    });

    test('paying (inflow) a credit card decreases the owed balance', () async {
      await _waitForLoad(ledger);
      await ledger.addTransaction(_txn(
          id: 't1',
          accountId: 'cc',
          amount: 5000,
          type: TransactionType.outflow));
      await ledger.addTransaction(_txn(
          id: 't2',
          accountId: 'cc',
          amount: 2000,
          type: TransactionType.inflow));
      final cc = ledger.accounts.firstWhere((a) => a.id == 'cc');
      expect(cc.balance, 3000);
    });

    test('deleting a credit charge reverses the debt increase', () async {
      await _waitForLoad(ledger);
      await ledger.addTransaction(_txn(
          id: 't1',
          accountId: 'cc',
          amount: 4000,
          type: TransactionType.outflow));
      await ledger.deleteTransaction('t1');
      final cc = ledger.accounts.firstWhere((a) => a.id == 'cc');
      expect(cc.balance, 0);
    });

    test('transfer funder→card lowers cash and lowers the card debt', () async {
      await _waitForLoad(ledger);
      // Start the card with 5000 owed.
      await ledger.addTransaction(_txn(
          id: 't1',
          accountId: 'cc',
          amount: 5000,
          type: TransactionType.outflow));
      await ledger.addTransfer(
        fromAccountId: 'gcash',
        toAccountId: 'cc',
        amount: 3000,
        categoryId: '',
        description: 'Pay card',
        date: DateTime(2026, 6, 7),
      );
      final cc = ledger.accounts.firstWhere((a) => a.id == 'cc');
      final gcash = ledger.accounts.firstWhere((a) => a.id == 'gcash');
      expect(gcash.balance, 2000); // cash down
      expect(cc.balance, 2000); // debt down
    });
  });

  group('TreasuryDashboardPresenter — credit getters', () {
    late MockStorageService storage;
    late TreasuryDashboardPresenter presenter;

    setUp(() {
      storage = MockStorageService();
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer((_) async => [
            _card(id: 'cc1', balance: 12000, creditLimit: 50000),
            _card(id: 'cc2', balance: 3000, creditLimit: 10000),
            _bank('bpi', 8000),
          ]);
      when(storage.loadTransactions()).thenAnswer((_) async => []);
      when(storage.loadBills()).thenAnswer((_) async => []);
      when(storage.loadReceivables()).thenAnswer((_) async => []);
      when(storage.loadBudgets()).thenAnswer((_) async => []);
      when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      presenter = TreasuryDashboardPresenter(storage);
    });

    test('creditAccounts excludes non-liability accounts', () async {
      await presenter.load();
      expect(presenter.creditAccounts.map((a) => a.id),
          containsAll(['cc1', 'cc2']));
      expect(presenter.creditAccounts.any((a) => a.id == 'bpi'), isFalse);
    });

    test('totals sum owed and remaining credit', () async {
      await presenter.load();
      expect(presenter.totalCreditOwed, 15000); // 12000 + 3000
      expect(presenter.totalCreditAvailable, 45000); // 38000 + 7000
    });

    test('creditMinimumDue uses the floor for a small balance', () async {
      await presenter.load();
      final cc2 = presenter.creditAccounts.firstWhere((a) => a.id == 'cc2');
      // 3000 * 3.57% = 107.1 → below the 850 floor.
      expect(presenter.creditMinimumDue(cc2), 850);
    });

    test('creditMinimumDue is null when nothing is owed', () async {
      final paid = _card(id: 'cc3', balance: 0, creditLimit: 10000);
      expect(presenter.creditMinimumDue(paid), isNull);
    });
  });
}
