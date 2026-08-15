import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_month_scope.dart';

import '../mocks.mocks.dart';

/// Regression tests for the Treasury flow/UX audit fixes.
///
/// Each group pins a behaviour that was wrong in a way the user could feel:
/// balances silently drifting, an Undo that only half-worked, a search that
/// couldn't see its own data, or two tabs disagreeing about which month it is.

FinancialAccount _account({
  required String id,
  double balance = 0,
  AccountCategory category = AccountCategory.ewallet,
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
  required String accountId,
  required double amount,
  required TransactionType type,
  String month = '2026-03',
  DateTime? date,
  String? transferGroupId,
}) =>
    TransactionRecord(
      id: id,
      date: date ?? DateTime(2026, 3, 15),
      accountId: accountId,
      categoryId: '',
      amount: amount,
      type: type,
      description: 'Test $id',
      month: month,
      transferGroupId: transferGroupId,
    );

Future<void> _waitForLoad(LedgerPresenter p) async {
  var guard = 0;
  while (p.isLoading && guard++ < 50) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;

  void stubLedgerStorage({List<FinancialAccount>? accounts}) {
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async =>
        accounts ??
        [
          _account(id: 'gcash', balance: 1000),
          _account(id: 'bpi', balance: 5000, category: AccountCategory.bank),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  }

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
  });

  group('deleting a transfer leg', () {
    late LedgerPresenter presenter;

    setUp(() async {
      stubLedgerStorage();
      presenter = LedgerPresenter(storage, stats);
      await _waitForLoad(presenter);
      // A transfer: 300 out of gcash, 300 into bpi, sharing a group id.
      await presenter.addTransaction(_txn(
        id: 'out',
        accountId: 'gcash',
        amount: 300,
        type: TransactionType.outflow,
        transferGroupId: 'g1',
      ));
      await presenter.addTransaction(_txn(
        id: 'in',
        accountId: 'bpi',
        amount: 300,
        type: TransactionType.inflow,
        transferGroupId: 'g1',
      ));
    });

    double balanceOf(String id) =>
        presenter.accounts.firstWhere((a) => a.id == id).balance;

    test('takes BOTH legs, so neither account is left half-adjusted', () async {
      expect(balanceOf('gcash'), 700);
      expect(balanceOf('bpi'), 5300);

      final removed = await presenter.deleteTransactionOrGroup('out');

      expect(removed.map((t) => t.id), containsAll(['out', 'in']));
      expect(presenter.allTransactions, isEmpty);
      expect(balanceOf('gcash'), 1000);
      expect(balanceOf('bpi'), 5000);
    });

    test('restoring the removed set puts both legs and both balances back',
        () async {
      final removed = await presenter.deleteTransactionOrGroup('in');
      await presenter.restoreTransactions(removed);

      expect(presenter.allTransactions.map((t) => t.id),
          containsAll(['out', 'in']));
      expect(balanceOf('gcash'), 700);
      expect(balanceOf('bpi'), 5300);
    });

    test('bulk delete returns the transfer partner the caller never selected',
        () async {
      // Only the outflow leg is selected; the inflow leg must come with it.
      final removed = await presenter.deleteTransactions({'out'});

      expect(removed.map((t) => t.id), containsAll(['out', 'in']));
      expect(balanceOf('gcash'), 1000);
      expect(balanceOf('bpi'), 5000);
    });
  });

  group('cross-month ledger rows', () {
    test('all-months rows span history while month rows stay scoped', () async {
      stubLedgerStorage();
      when(storage.loadTransactions()).thenAnswer((_) async => [
            _txn(
              id: 'march',
              accountId: 'gcash',
              amount: 100,
              type: TransactionType.outflow,
              month: '2026-03',
              date: DateTime(2026, 3, 2),
            ),
            _txn(
              id: 'april',
              accountId: 'gcash',
              amount: 200,
              type: TransactionType.outflow,
              month: '2026-04',
              date: DateTime(2026, 4, 2),
            ),
          ]);
      final presenter = LedgerPresenter(storage, stats);
      await _waitForLoad(presenter);
      presenter.setMonth('2026-03');

      // The month grid sees only March — which is why a search bound to it
      // could never find the April row.
      expect(presenter.ledgerSpreadsheetRows.map((r) => r.txn.id), ['march']);
      expect(
        presenter.ledgerSpreadsheetRowsAllMonths.map((r) => r.txn.id),
        containsAll(['march', 'april']),
      );
    });
  });

  group('quick-add month snap marker', () {
    test('starts unset and is cleared with the commit summary', () async {
      stubLedgerStorage();
      final presenter = LedgerPresenter(storage, stats);
      await _waitForLoad(presenter);

      // Nothing committed yet, so there is no jump to explain — the views read
      // this to decide whether to say "the list moved months".
      expect(presenter.lastCommitSnappedFromMonth, isNull);

      // Clearing the summary must clear the marker too, or the explanation
      // would ride along on the next unrelated commit toast.
      presenter.clearLastCommittedSummary();
      expect(presenter.lastCommitSnappedFromMonth, isNull);
    });
  });

  group('TreasuryMonthScope', () {
    test('a month set on one presenter is adopted by the others', () async {
      stubLedgerStorage();
      when(storage.loadBudgets()).thenAnswer((_) async => []);
      when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
      when(storage.saveBudgets(any)).thenAnswer((_) async {});
      when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => {});

      final scope = TreasuryMonthScope('2026-03');
      final ledger = LedgerPresenter(storage, stats, monthScope: scope);
      final budget = BudgetPresenter(storage, stats, ledger, null, scope);
      await _waitForLoad(ledger);

      expect(ledger.selectedMonth, '2026-03');
      expect(budget.selectedMonth, '2026-03');

      // Paging the Ledger back must not leave Budget describing a different
      // month with nothing on screen saying so.
      ledger.setMonth('2026-01');

      expect(scope.month, '2026-01');
      expect(budget.selectedMonth, '2026-01');

      // ...and the other direction.
      budget.setMonth('2026-05');

      expect(scope.month, '2026-05');
      expect(ledger.selectedMonth, '2026-05');
    });

    test('presenters built without a scope keep their own month', () async {
      stubLedgerStorage();
      final a = LedgerPresenter(storage, stats);
      final b = LedgerPresenter(storage, stats);
      await _waitForLoad(a);
      await _waitForLoad(b);

      a.setMonth('2026-01');

      expect(a.selectedMonth, '2026-01');
      expect(b.selectedMonth, isNot('2026-01'));
    });
  });
}
