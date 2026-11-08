import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';

import '../mocks.mocks.dart';

/// Plan 071 Phase 10a: one ledger search for the phone and web v2 — query,
/// scope, matching rules, results order, empty text and the clear action.
void main() {
  // The month opens on the pinned clock: March 2026.
  final now = DateTime(2026, 3, 20, 12);

  FinancialAccount account(String id, String name) => FinancialAccount(
        id: id,
        name: name,
        category: AccountCategory.ewallet,
        balance: 0,
        colorHex: '#FFFFFF',
        icon: 'wallet',
      );

  FinanceCategory category(String id, String name, CategoryType type) =>
      FinanceCategory(
        id: id,
        name: name,
        type: type,
        icon: 'tag',
        colorHex: '#FF0000',
      );

  TransactionRecord txn(
    String id,
    DateTime date, {
    required String description,
    String? note,
    String accountId = 'gcash',
    String categoryId = 'food',
    double amount = 100,
    TransactionType type = TransactionType.outflow,
  }) =>
      TransactionRecord(
        id: id,
        date: date,
        accountId: accountId,
        categoryId: categoryId,
        amount: amount,
        type: type,
        description: description,
        note: note,
        month: '${date.year}-${date.month.toString().padLeft(2, '0')}',
      );

  final records = [
    txn('lunch', DateTime(2026, 3, 5),
        description: 'Jollibee lunch', note: 'with Ana', amount: 245.5),
    txn('salary-mar', DateTime(2026, 3, 6),
        description: 'Salary',
        accountId: 'bpi',
        categoryId: 'pay',
        type: TransactionType.inflow,
        amount: 50000),
    txn('groceries', DateTime(2026, 3, 8),
        description: 'SM Supermarket', amount: 1000),
    txn('salary-feb', DateTime(2026, 2, 6),
        description: 'Salary',
        accountId: 'bpi',
        categoryId: 'pay',
        type: TransactionType.inflow,
        amount: 50000),
    txn('netflix', DateTime(2025, 12, 10),
        description: 'NETFLIX', categoryId: 'subs', amount: 549),
  ];

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter presenter;

  setUp(() async {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          account('gcash', 'GCash'),
          account('bpi', 'BPI Savings'),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          category('food', 'Food', CategoryType.expense),
          category('subs', 'Subscriptions', CategoryType.expense),
          category('pay', 'Payroll', CategoryType.income),
        ]);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => records);
    when(stats.stats).thenReturn(UserStats.initial());

    presenter = LedgerPresenter(storage, stats, clock: () => now);
    for (var i = 0; i < 40 && presenter.isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });

  List<String> ids(Iterable<TransactionRecord> txns) =>
      txns.map((t) => t.id).toList();

  List<String> listedIds() =>
      ids(presenter.groupedTransactions.values.expand((l) => l));

  test('no search: nothing is searched and the list is the month', () {
    expect(presenter.selectedMonth, '2026-03');
    expect(presenter.isSearching, isFalse);
    expect(presenter.searchQuery, '');
    expect(presenter.searchAllMonths, isFalse);
    expect(presenter.searchResults, isEmpty);
    expect(presenter.searchSummary, '');
    expect(listedIds().toSet(), {'lunch', 'salary-mar', 'groceries'});
  });

  test('this month: case-insensitive, other months stay out', () {
    presenter.setSearch('  SALARY ');
    expect(presenter.isSearching, isTrue);
    expect(presenter.searchQuery, 'SALARY');
    expect(presenter.searchSpansAllMonths, isFalse);
    expect(ids(presenter.searchResults), ['salary-mar']);
    expect(listedIds(), ['salary-mar']);
    expect(presenter.searchSummary, '1 match');
  });

  test('all months: every month, newest first', () {
    presenter.setSearch('salary', allMonths: true);
    expect(presenter.searchAllMonths, isTrue);
    expect(presenter.searchSpansAllMonths, isTrue);
    expect(ids(presenter.searchResults), ['salary-mar', 'salary-feb']);
    expect(listedIds(), ['salary-mar', 'salary-feb']);
    expect(presenter.searchSummary, '2 matches');
  });

  test('switching scope keeps the query', () {
    presenter.setSearch('netflix');
    expect(presenter.searchResults, isEmpty);
    presenter.setSearchAllMonths(true);
    expect(presenter.searchQuery, 'netflix');
    expect(ids(presenter.searchResults), ['netflix']);
    presenter.setSearchAllMonths(false);
    expect(presenter.searchResults, isEmpty);
  });

  test('matches note, category name and account name', () {
    presenter.setSearch('ana');
    expect(ids(presenter.searchResults), ['lunch']);
    presenter.setSearch('food');
    expect(ids(presenter.searchResults), ['groceries', 'lunch']);
    presenter.setSearch('bpi sav');
    expect(ids(presenter.searchResults), ['salary-mar']);
    presenter.setSearch('payroll', allMonths: true);
    expect(ids(presenter.searchResults), ['salary-mar', 'salary-feb']);
  });

  test('amount match: exact, grouped, with ₱, and as part of the amount', () {
    presenter.setSearch('1000');
    expect(ids(presenter.searchResults), ['groceries']);
    presenter.setSearch('1,000');
    expect(ids(presenter.searchResults), ['groceries']);
    presenter.setSearch('₱245.5');
    expect(ids(presenter.searchResults), ['lunch']);
    presenter.setSearch('245');
    expect(ids(presenter.searchResults), ['lunch']);
    presenter.setSearch('549', allMonths: true);
    expect(ids(presenter.searchResults), ['netflix']);
  });

  test('matchesSearch and recordMatchesQuery use the same rule', () {
    final lunch = records.first;
    expect(presenter.matchesSearch(lunch), isTrue); // no search: all match
    presenter.setSearch('JOLLIBEE');
    expect(presenter.matchesSearch(lunch), isTrue);
    expect(presenter.matchesSearch(records[1]), isFalse);
    expect(presenter.recordMatchesQuery(lunch, '245.50'), isTrue);
    expect(presenter.recordMatchesQuery(records[1], 'jollibee'), isFalse);
    expect(presenter.recordMatchesQuery(records[1], '  '), isTrue);
  });

  test('clear ends the search, keeps the scope, restores the month list', () {
    presenter.setSearch('salary', allMonths: true);
    presenter.clearSearch();
    expect(presenter.isSearching, isFalse);
    expect(presenter.searchQuery, '');
    expect(presenter.searchAllMonths, isTrue);
    expect(presenter.searchSpansAllMonths, isFalse);
    expect(presenter.searchResults, isEmpty);
    expect(listedIds().toSet(), {'lunch', 'salary-mar', 'groceries'});

    // A blank query is a clear too.
    presenter.setSearch('salary');
    presenter.setSearch('   ');
    expect(presenter.isSearching, isFalse);
  });

  test('notifies once per change, and not for the same search', () {
    var calls = 0;
    presenter.addListener(() => calls++);
    presenter.setSearch('salary');
    presenter.setSearch('salary ');
    presenter.setSearch('salary', allMonths: false);
    expect(calls, 1);
    presenter.setSearchAllMonths(true);
    expect(calls, 2);
  });

  test('a search keeps the web grid row caches', () {
    final before = presenter.ledgerSpreadsheetRowsAllMonths;
    presenter.setSearch('salary', allMonths: true);
    expect(identical(presenter.ledgerSpreadsheetRowsAllMonths, before), isTrue);
  });

  group('empty list', () {
    test('a search with no match names the query and offers Clear search', () {
      presenter.setSearch('netflix');
      expect(presenter.searchHidesEverything, isTrue);
      expect(presenter.emptyListReason, LedgerEmptyReason.search);
      expect(presenter.emptyListTitle, 'No transactions match "netflix"');
      expect(presenter.emptyListBody, contains('Try All months'));
      expect(presenter.emptyListActionLabel, 'Clear search');

      presenter.clearEmptyListCause();
      expect(presenter.isSearching, isFalse);
      expect(listedIds(), isNotEmpty);
    });

    test('an all-months search has no "Try All months" line', () {
      presenter.setSearch('nothing like this', allMonths: true);
      expect(presenter.emptyListTitle,
          'No transactions match "nothing like this"');
      expect(presenter.emptyListBody, isNull);
    });

    test('search plus filters: the search is named first', () {
      presenter.toggleCategoryFilter('food');
      presenter.setSearch('salary');
      expect(presenter.filtersHideEverything, isTrue);
      expect(presenter.emptyListReason, LedgerEmptyReason.search);

      presenter.clearEmptyListCause();
      expect(presenter.isSearching, isFalse);
      expect(presenter.selectedCategoryIds, {'food'});
      expect(listedIds().toSet(), {'lunch', 'groceries'});
    });

    test('filters alone keep their own text and action', () {
      presenter.toggleCategoryFilter('subs');
      expect(presenter.emptyListReason, LedgerEmptyReason.filters);
      expect(presenter.emptyListTitle, 'No transactions match these filters');
      expect(presenter.emptyListActionLabel, 'Clear filters');
      expect(presenter.emptyListBody, isNull);
      presenter.clearEmptyListCause();
      expect(presenter.activeFilterCount, 0);
    });
  });

  group('dates', () {
    test(
        'day headers: Today, Yesterday, the day, and the year when it '
        'differs', () {
      expect(presenter.dateGroupLabel(DateTime(2026, 3, 20, 8)), 'Today');
      expect(presenter.dateGroupLabel(DateTime(2026, 3, 19)), 'Yesterday');
      expect(presenter.dateGroupLabel(DateTime(2026, 2, 6)),
          DateFormat('EEEE, MMMM d').format(DateTime(2026, 2, 6)));
      expect(presenter.dateGroupLabel(DateTime(2025, 12, 10)),
          DateFormat('EEEE, MMMM d, y').format(DateTime(2025, 12, 10)));
    });

    test('a row prints its date only in an all-months amount-sorted list', () {
      final netflix = records.last;
      expect(presenter.searchRowDateLabel(netflix), isNull);
      presenter.setSearch('netflix', allMonths: true);
      expect(presenter.searchRowDateLabel(netflix), isNull);
      presenter.setSort(LedgerSortField.amount, descending: true);
      expect(presenter.searchRowDateLabel(netflix), 'Dec 10, 2025');
      expect(ids(presenter.sortedTransactions), ['netflix']);
    });
  });
}
