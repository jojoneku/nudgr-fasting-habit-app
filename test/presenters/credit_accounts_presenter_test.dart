import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
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
        description: 'Pay card',
        date: DateTime(2026, 6, 7),
      );
      final cc = ledger.accounts.firstWhere((a) => a.id == 'cc');
      final gcash = ledger.accounts.firstWhere((a) => a.id == 'gcash');
      expect(gcash.balance, 2000); // cash down
      expect(cc.balance, 2000); // debt down
    });
  });

  group('LedgerPresenter — chat description cleaning', () {
    late MockStorageService storage;
    late MockStatsPresenter stats;
    late LedgerPresenter ledger;

    setUp(() {
      storage = MockStorageService();
      stats = MockStatsPresenter();
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts())
          .thenAnswer((_) async => [_bank('gcash', 1000)]);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => [
            FinanceCategory(
              id: 'food',
              name: 'Food',
              type: CategoryType.expense,
              icon: 'tag',
              colorHex: '#FFFFFF',
            ),
          ]);
      when(storage.loadTransactions()).thenAnswer((_) async => []);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
      when(storage.saveTransactions(any)).thenAnswer((_) async {});
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      when(stats.addXp(any)).thenAnswer((_) async {});
      when(stats.stats).thenReturn(UserStats.initial());
      // No AI → fully-resolved input commits straight through _commitParsed.
      ledger = LedgerPresenter(storage, stats);
    });

    test('strips amount + account from the stored description', () async {
      await _waitForLoad(ledger);
      await ledger.sendChatInput('-500 food gcash');
      expect(ledger.allTransactions, hasLength(1));
      final desc = ledger.allTransactions.first.description;
      expect(desc, isNot(contains('500')));
      expect(desc.toLowerCase(), isNot(contains('gcash')));
      expect(desc.toLowerCase(), contains('food'));
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
      when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
      when(storage.saveMonthlySummaries(any)).thenAnswer((_) async {});
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

    test('creditCycleNote warns when a card can never be billed', () async {
      // The generator needs both days. Without them the card still shows a
      // balance (and a due date, if that one is set), so nothing revealed that
      // it would never produce a statement.
      expect(
        presenter.creditCycleNote(_card(id: 'x', paymentDueDay: 15))?.warning,
        isTrue,
      );
      expect(
        presenter.creditCycleNote(_card(id: 'y', statementDay: 5))?.warning,
        isTrue,
      );
    });

    test('creditCycleNote names the close date while the cycle is open',
        () async {
      // A close day that cannot have passed yet, whatever day it runs on.
      final openCycle = _card(
        id: 'z',
        statementDay: 28,
        paymentDueDay: 15,
        balance: 1011.31,
      );
      final note = presenter.creditCycleNote(openCycle);
      if (DateTime.now().day < 28) {
        expect(note, isNotNull);
        expect(note!.warning, isFalse);
        expect(note.label, startsWith('Statement closes '));
      } else {
        // Run on the 28th or later, that cycle has closed.
        expect(note, isNull);
      }
    });

    test('creditCycleNote is silent once the cycle has closed', () async {
      // statementDay 1 has always closed — the statement is a bill by now, so
      // the card has nothing left to explain.
      final closed = _card(id: 'w', statementDay: 1, paymentDueDay: 15);
      expect(presenter.creditCycleNote(closed), isNull);
    });

    test('creditCycleNote ignores non-liability accounts', () async {
      expect(presenter.creditCycleNote(_bank('bpi', 8000)), isNull);
    });
  });

  group('LedgerPresenter.payableAsOf', () {
    /// A card owing [balance] today, with [txns] already recorded against it.
    Future<LedgerPresenter> ledgerWith(
      double balance,
      List<TransactionRecord> txns,
    ) async {
      final storage = MockStorageService();
      final stats = MockStatsPresenter();
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer((_) async => [
            _card(id: 'sp', balance: balance, creditLimit: 75000),
            _bank('gcash', 5000),
          ]);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(storage.loadTransactions()).thenAnswer((_) async => txns);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(stats.stats).thenReturn(UserStats.initial());
      final ledger = LedgerPresenter(storage, stats);
      await _waitForLoad(ledger);
      return ledger;
    }

    /// Peso comparisons tolerate float dust.
    Matcher owes(double amount) => closeTo(amount, 0.001);

    TransactionRecord charge(String id, double amount, DateTime on) =>
        TransactionRecord(
          id: id,
          date: on,
          accountId: 'sp',
          categoryId: '',
          amount: amount,
          type: TransactionType.outflow,
          description: id,
          month: '2026-08',
        );

    test('excludes charges made after the close date', () async {
      // Closed Aug 5 owing 1011.31; 500 more charged Aug 6; the app is not
      // opened (so the statement is not generated) until Aug 8.
      final ledger = await ledgerWith(1511.31, [
        charge('c1', 1011.31, DateTime(2026, 8, 3)),
        charge('c2', 500, DateTime(2026, 8, 6)),
      ]);

      expect(ledger.payableAsOf('sp', DateTime(2026, 8, 5)), owes(1011.31));
      expect(ledger.payableAsOf('sp', DateTime(2026, 8, 8)), owes(1511.31));
    });

    test('counts a charge dated ON the close date', () async {
      // The closing day belongs to the cycle that closes.
      final ledger = await ledgerWith(600, [
        charge('c1', 100, DateTime(2026, 8, 4)),
        charge('c2', 500, DateTime(2026, 8, 5, 21, 30)),
      ]);

      expect(ledger.payableAsOf('sp', DateTime(2026, 8, 5)), owes(600));
    });

    test('a payment after the close date does not shrink the statement',
        () async {
      // Owed 1011.31 at close, paid in full on Aug 10 → balance 0 today, but
      // the closed cycle still billed 1011.31.
      final ledger = await ledgerWith(0, [
        charge('c1', 1011.31, DateTime(2026, 8, 3)),
        TransactionRecord(
          id: 'pay',
          date: DateTime(2026, 8, 10),
          accountId: 'sp',
          categoryId: '',
          amount: 1011.31,
          type: TransactionType.inflow,
          description: 'Pay card',
          month: '2026-08',
        ),
      ]);

      expect(ledger.payableAsOf('sp', DateTime(2026, 8, 5)), owes(1011.31));
      expect(ledger.payableAsOf('sp', DateTime(2026, 8, 31)), 0);
    });

    test('floors at zero for an overpaid card, and ignores other accounts',
        () async {
      final ledger = await ledgerWith(-250, [
        charge('c1', 250, DateTime(2026, 8, 20)),
      ]);

      // Unwinding the post-close charge leaves −500 owed (a credit balance).
      expect(ledger.payableAsOf('sp', DateTime(2026, 8, 5)), 0);
      // A non-liability account has no payable.
      expect(ledger.payableAsOf('gcash', DateTime(2026, 8, 5)), 0);
      expect(ledger.payableAsOf('nope', DateTime(2026, 8, 5)), 0);
    });
  });
}
