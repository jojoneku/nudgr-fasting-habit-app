import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';

import '../mocks.mocks.dart';

/// Covers the multi-select filters + sort added to the Ledger "Filter & sort"
/// sheet (LedgerSortField, toggle*/setSort, sortedTransactions).
void main() {
  const month = '2026-03';

  FinancialAccount account(String id) => FinancialAccount(
        id: id,
        name: id,
        category: AccountCategory.ewallet,
        balance: 0,
        colorHex: '#FFFFFF',
        icon: 'wallet',
      );

  TransactionRecord txn({
    required String id,
    required String accountId,
    required String categoryId,
    required double amount,
    required int day,
    TransactionType type = TransactionType.outflow,
  }) =>
      TransactionRecord(
        id: id,
        date: DateTime(2026, 3, day),
        accountId: accountId,
        categoryId: categoryId,
        amount: amount,
        type: type,
        description: id,
        month: month,
      );

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter presenter;

  Future<void> waitForLoad() async {
    for (var i = 0; i < 40 && presenter.isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    presenter.setMonth(month);
  }

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts())
        .thenAnswer((_) async => [account('gcash'), account('bpi')]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => [
          txn(
              id: 't1',
              accountId: 'gcash',
              categoryId: 'food',
              amount: 100,
              day: 5),
          txn(
              id: 't2',
              accountId: 'bpi',
              categoryId: 'transport',
              amount: 500,
              day: 15),
          txn(
              id: 't3',
              accountId: 'gcash',
              categoryId: 'transport',
              amount: 300,
              day: 10,
              type: TransactionType.inflow),
          txn(
              id: 't4',
              accountId: 'bpi',
              categoryId: 'food',
              amount: 50,
              day: 20),
        ]);
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    presenter = LedgerPresenter(storage, stats);
  });

  List<String> ids(List<TransactionRecord> t) => t.map((e) => e.id).toList();

  test('multi-account filter unions the selected accounts', () async {
    await waitForLoad();
    presenter.toggleAccountFilter('gcash');
    expect(ids(presenter.sortedTransactions).toSet(), {'t1', 't3'});

    presenter.toggleAccountFilter('bpi');
    expect(ids(presenter.sortedTransactions).toSet(), {'t1', 't2', 't3', 't4'});
    expect(presenter.activeFilterCount, 2);

    presenter.toggleAccountFilter('gcash'); // deselect gcash
    expect(ids(presenter.sortedTransactions).toSet(), {'t2', 't4'});
  });

  test('multi-category filter unions the selected categories', () async {
    await waitForLoad();
    presenter.toggleCategoryFilter('food');
    expect(ids(presenter.sortedTransactions).toSet(), {'t1', 't4'});
    presenter.toggleCategoryFilter('transport');
    expect(ids(presenter.sortedTransactions).toSet(), {'t1', 't2', 't3', 't4'});
  });

  test('sort by amount, both directions', () async {
    await waitForLoad();
    presenter.setSort(LedgerSortField.amount, descending: true);
    expect(ids(presenter.sortedTransactions), ['t2', 't3', 't1', 't4']);

    presenter.setSort(LedgerSortField.amount, descending: false);
    expect(ids(presenter.sortedTransactions), ['t4', 't1', 't3', 't2']);
  });

  test('sort by date, both directions', () async {
    await waitForLoad();
    presenter.setSort(LedgerSortField.date, descending: true);
    expect(ids(presenter.sortedTransactions), ['t4', 't2', 't3', 't1']);

    presenter.setSort(LedgerSortField.date, descending: false);
    expect(ids(presenter.sortedTransactions), ['t1', 't3', 't2', 't4']);
  });

  test('clearAllFilters resets filters, keeps sort; back-compat getters',
      () async {
    await waitForLoad();
    presenter.setAccount('gcash'); // single setter → set of one
    expect(presenter.selectedAccountId, 'gcash');
    expect(presenter.selectedAccountIds, {'gcash'});

    presenter.toggleAccountFilter('bpi'); // now two → single getter null
    expect(presenter.selectedAccountId, isNull);

    presenter.setSort(LedgerSortField.amount, descending: false);
    presenter.clearAllFilters();
    expect(presenter.activeFilterCount, 0);
    expect(presenter.selectedAccountIds, isEmpty);
    // sort preserved
    expect(presenter.sortField, LedgerSortField.amount);
    expect(presenter.sortDescending, isFalse);
  });
}
