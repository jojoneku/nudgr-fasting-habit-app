import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';

import '../mocks.mocks.dart';

/// The getters behind the redesigned Ledger "Filter & sort" sheet: the sort
/// choice, the row summaries, the grouped account and category pickers and
/// the live results label.
void main() {
  const month = '2026-03';

  FinancialAccount account(
    String id,
    String name,
    AccountCategory category, {
    bool isActive = true,
  }) =>
      FinancialAccount(
        id: id,
        name: name,
        category: category,
        balance: 1000,
        colorHex: '#3366FF',
        icon: 'wallet',
        isActive: isActive,
      );

  FinanceCategory category(String id, String name, CategoryType type) =>
      FinanceCategory(
        id: id,
        name: name,
        type: type,
        icon: id,
        colorHex: '#FF8800',
      );

  TransactionRecord txn(
    String id,
    String accountId,
    String categoryId, {
    double amount = 100,
    int day = 5,
    String? transferGroupId,
  }) =>
      TransactionRecord(
        id: id,
        date: DateTime(2026, 3, day),
        accountId: accountId,
        categoryId: categoryId,
        amount: amount,
        type: TransactionType.outflow,
        description: id,
        month: month,
        transferGroupId: transferGroupId,
      );

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter presenter;

  setUp(() async {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          account('gcash', 'GCash', AccountCategory.ewallet),
          account('bpi', 'BPI', AccountCategory.bank),
          account('card', 'Visa', AccountCategory.creditCard),
          account('trip', 'Trip fund', AccountCategory.goal),
          account('old', 'Old wallet', AccountCategory.ewallet,
              isActive: false),
          account('gone', 'Closed bank', AccountCategory.bank, isActive: false),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          category('food', 'Food', CategoryType.expense),
          category('transport', 'Transport', CategoryType.expense),
          category('rent', 'Rent', CategoryType.expense),
          category('salary', 'Salary', CategoryType.income),
          category('move', 'Transfer', CategoryType.transfer),
        ]);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => [
          txn('t1', 'gcash', 'food', amount: 100, day: 5),
          txn('t2', 'gcash', 'food', amount: 250, day: 6),
          txn('t3', 'bpi', 'transport', amount: 500, day: 15),
          txn('t4', 'old', 'food', amount: 50, day: 20),
          // A transfer leg is not spending in its stamped category.
          txn('t5', 'bpi', 'rent', amount: 900, day: 21, transferGroupId: 'g'),
        ]);
    when(stats.stats).thenReturn(UserStats.initial());
    presenter = LedgerPresenter(storage, stats);
    for (var i = 0; i < 40 && presenter.isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    presenter.setMonth(month);
  });

  group('sort choice', () {
    test('each option round-trips through the sort field and direction', () {
      for (final o in LedgerSortOption.values) {
        presenter.setSortOption(o);
        expect(presenter.sortOption, o);
      }
      presenter.setSortOption(LedgerSortOption.largest);
      expect(presenter.sortField, LedgerSortField.amount);
      expect(presenter.sortDescending, isTrue);
    });
  });

  group('row summaries', () {
    test('nothing picked reads All', () {
      expect(presenter.accountFilterSummary, 'All accounts');
      expect(presenter.categoryFilterSummary, 'All categories');
      expect(presenter.dayFilterLabel, 'Any day');
      expect(presenter.monthFilterLabel, 'March 2026');
    });

    test('one or two picks are named, more are counted', () {
      presenter.toggleAccountFilter('gcash');
      expect(presenter.accountFilterSummary, 'GCash');
      presenter.toggleAccountFilter('bpi');
      expect(presenter.accountFilterSummary, 'GCash, BPI');
      presenter.toggleAccountFilter('card');
      expect(presenter.accountFilterSummary, '3 accounts');
    });

    test('a pick that no longer exists still reads, so it can be cleared', () {
      presenter.toggleCategoryFilter('deleted');
      expect(presenter.categoryFilterSummary, 'Removed category');
      presenter.clearCategoryFilters();
      expect(presenter.hasCategoryFilter, isFalse);
    });

    test('day label follows the picked day', () {
      presenter.setSelectedDate(DateTime(2026, 3, 6));
      expect(presenter.dayFilterLabel, 'Mar 6');
      expect(presenter.hasDayFilter, isTrue);
    });
  });

  group('account picker groups', () {
    test('accounts are grouped by kind; archived only when used or picked', () {
      final groups = presenter.accountFilterGroups;
      expect(groups.map((g) => g.title),
          ['Cash & bank', 'Savings & goals', 'Credit', 'Archived']);
      expect(groups[0].options.map((o) => o.label), ['GCash', 'BPI']);
      expect(groups[1].options.single.label, 'Trip fund');
      expect(groups[2].options.single.label, 'Visa');
      // "Old wallet" has a record this month; "Closed bank" has none.
      expect(groups[3].options.single.label, 'Old wallet');
    });

    test('options carry this month\'s count and the picked state', () {
      presenter.toggleAccountFilter('gcash');
      final cash = presenter.accountFilterGroups.first.options;
      expect(cash[0].detail, '2 this month');
      expect(cash[0].selected, isTrue);
      expect(cash[1].detail, '2 this month');
      expect(cash[1].selected, isFalse);
    });

    test('a picked archived account stays listed even with no records', () {
      presenter.toggleAccountFilter('gone');
      final archived = presenter.accountFilterGroups.last;
      expect(archived.options.map((o) => o.label),
          containsAll(['Old wallet', 'Closed bank']));
    });
  });

  group('category picker groups', () {
    test('used this month comes first, busiest first; transfer types hidden',
        () {
      final groups = presenter.categoryFilterGroups('');
      expect(
          groups.map((g) => g.title), ['Used this month', 'Expense', 'Income']);
      expect(groups[0].options.map((o) => o.label), ['Food', 'Transport']);
      expect(groups[0].options.first.detail, '3 this month');
      // Rent only appears on a transfer leg, so it is not "used".
      expect(groups[1].options.map((o) => o.label), ['Rent']);
      expect(groups[2].options.map((o) => o.label), ['Salary']);
      final all = [for (final g in groups) ...g.options.map((o) => o.label)];
      expect(all, isNot(contains('Transfer')));
    });

    test('search narrows by name, case-insensitive, and drops empty groups',
        () {
      final groups = presenter.categoryFilterGroups('TRANS');
      expect(groups.map((g) => g.title), ['Used this month']);
      expect(groups.single.options.single.label, 'Transport');
      expect(presenter.categoryFilterGroups('zzz'), isEmpty);
    });

    test('search box only shows for long lists', () {
      expect(presenter.categoryFilterNeedsSearch, isFalse);
    });
  });

  group('results and reset', () {
    test('the results label counts what the list will show', () {
      expect(presenter.showResultsLabel, 'Show 5 transactions');
      presenter.toggleCategoryFilter('transport');
      expect(presenter.showResultsLabel, 'Show 1 transaction');
      presenter.toggleAccountFilter('gcash');
      expect(presenter.showResultsLabel, 'No transactions match');
    });

    test('Reset clears every filter and the order', () {
      expect(presenter.canResetFilters, isFalse);
      presenter.toggleAccountFilter('gcash');
      presenter.setSortOption(LedgerSortOption.smallest);
      expect(presenter.canResetFilters, isTrue);

      presenter.resetFiltersAndSort();
      expect(presenter.activeFilterCount, 0);
      expect(presenter.sortOption, LedgerSortOption.newest);
      expect(presenter.canResetFilters, isFalse);
    });
  });
}
