import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';

import '../mocks.mocks.dart';

/// Plan 071 Phase 4: the ledger helpers the mobile list and the web v2 page
/// share — transfer legs, row actions, filter chips, empty text, daily net.
void main() {
  const month = '2026-03';

  FinancialAccount account(String id,
          {AccountCategory category = AccountCategory.ewallet}) =>
      FinancialAccount(
        id: id,
        name: id.toUpperCase(),
        category: category,
        balance: 0,
        colorHex: '#FFFFFF',
        icon: 'wallet',
      );

  TransactionRecord txn(
    String id, {
    String accountId = 'gcash',
    String categoryId = 'food',
    double amount = 100,
    int day = 5,
    TransactionType type = TransactionType.outflow,
    String? transferGroupId,
    String? installmentId,
    bool isInstallment = false,
    bool reimbursable = false,
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
        transferGroupId: transferGroupId,
        installmentId: installmentId,
        isInstallment: isInstallment,
        reimbursable: reimbursable,
      );

  final records = [
    txn('lunch', categoryId: 'food', amount: 100),
    txn('salary',
        type: TransactionType.inflow, categoryId: 'pay', amount: 1000, day: 6),
    txn('card-buy', accountId: 'visa', amount: 900, day: 7),
    txn('move-out', transferGroupId: 'g1', amount: 300, day: 8),
    txn('move-in',
        accountId: 'bpi',
        type: TransactionType.inflow,
        transferGroupId: 'g1',
        amount: 300,
        day: 8),
  ];

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter presenter;

  Future<void> load() async {
    presenter = LedgerPresenter(storage, stats);
    for (var i = 0; i < 40 && presenter.isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    presenter.setMonth(month);
  }

  TransactionRecord byId(String id) =>
      presenter.allTransactions.firstWhere((t) => t.id == id);

  setUp(() async {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          account('gcash'),
          account('bpi', category: AccountCategory.bank),
          account('visa', category: AccountCategory.creditCard),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          FinanceCategory(
            id: 'food',
            name: 'Food',
            type: CategoryType.expense,
            icon: 'food',
            colorHex: '#FF0000',
          ),
        ]);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => records);
    when(stats.stats).thenReturn(UserStats.initial());
    await load();
  });

  group('transferLegsOf', () {
    test('returns both legs from either leg', () {
      for (final id in ['move-out', 'move-in']) {
        final legs = presenter.transferLegsOf(byId(id));
        expect(legs.from?.id, 'move-out');
        expect(legs.from?.accountId, 'gcash');
        expect(legs.to?.id, 'move-in');
        expect(legs.to?.accountId, 'bpi');
      }
    });

    test('is empty for a record outside a transfer', () {
      final legs = presenter.transferLegsOf(byId('lunch'));
      expect(legs.from, isNull);
      expect(legs.to, isNull);
    });
  });

  group('rowActionsFor', () {
    test('expense on a debit account: no split, can mark reimbursable', () {
      final a = presenter.rowActionsFor(byId('lunch'));
      expect(a.canSplit, isFalse);
      expect(a.canMarkReimbursable, isTrue);
      expect(a.reimbursableLabel, 'Mark "I\'ll get this back"');
    });

    test('expense on a credit account: split offered', () {
      final a = presenter.rowActionsFor(byId('card-buy'));
      expect(a.canSplit, isTrue);
      expect(a.splitLabel, 'Split into installments');
      expect(a.canMarkReimbursable, isTrue);
    });

    test('income: neither split nor reimbursable', () {
      final a = presenter.rowActionsFor(byId('salary'));
      expect(a.canSplit, isFalse);
      expect(a.canMarkReimbursable, isFalse);
    });

    test('transfer legs: neither split nor reimbursable', () {
      for (final id in ['move-out', 'move-in']) {
        final a = presenter.rowActionsFor(byId(id));
        expect(a.canSplit, isFalse, reason: id);
        expect(a.canMarkReimbursable, isFalse, reason: id);
      }
    });

    test('installment purchase: edit plan, not reimbursable', () {
      final a = presenter.rowActionsFor(txn('plan',
          accountId: 'visa', installmentId: 'i1', isInstallment: true));
      expect(a.canSplit, isTrue);
      expect(a.splitLabel, 'Edit installment plan');
      expect(a.canMarkReimbursable, isFalse);
    });

    test('installment payment record: no split', () {
      final a = presenter.rowActionsFor(
          txn('payment', accountId: 'visa', installmentId: 'i1'));
      expect(a.canSplit, isFalse);
    });

    test('already reimbursable: label switches to edit', () {
      final a = presenter.rowActionsFor(txn('lent', reimbursable: true));
      expect(a.canMarkReimbursable, isTrue);
      expect(a.reimbursableLabel, 'Edit "I\'ll get this back"');
    });
  });

  group('activeFilterChips', () {
    test('one chip per active filter, removable one by one', () {
      expect(presenter.activeFilterChips, isEmpty);

      presenter.setSelectedDate(DateTime(2026, 3, 5));
      presenter.setOwedFilter(true);
      presenter.toggleAccountFilter('gcash');
      presenter.toggleCategoryFilter('food');
      presenter.toggleCategoryFilter('gone');

      final chips = presenter.activeFilterChips;
      expect(chips.length, presenter.activeFilterCount);
      expect(chips.map((c) => c.label),
          ['Mar 5', 'Owed to you', 'GCASH', 'Food', 'Removed category']);

      presenter.removeFilterChip(
          chips.firstWhere((c) => c.kind == LedgerFilterKind.account));
      expect(presenter.selectedAccountIds, isEmpty);
      expect(presenter.selectedCategoryIds, {'food', 'gone'});
      expect(presenter.owedOnly, isTrue);
      expect(presenter.selectedDate, isNotNull);

      presenter.removeFilterChip(
          chips.firstWhere((c) => c.kind == LedgerFilterKind.day));
      expect(presenter.selectedDate, isNull);
      presenter.removeFilterChip(
          chips.firstWhere((c) => c.kind == LedgerFilterKind.owed));
      expect(presenter.owedOnly, isFalse);
      expect(presenter.activeFilterChips.length, 2);
    });
  });

  group('empty list text', () {
    test('no filters: the month is empty', () {
      expect(presenter.filtersHideEverything, isFalse);
      expect(presenter.emptyListTitle, 'No transactions this month');
    });

    test('filters that hide every row: blames the filters', () {
      presenter.toggleCategoryFilter('nothing-here');
      expect(presenter.filtersHideEverything, isTrue);
      expect(presenter.emptyListTitle, 'No transactions match these filters');
      presenter.clearAllFilters();
      expect(presenter.filtersHideEverything, isFalse);
    });

    test('filters that still match rows: not hiding everything', () {
      presenter.toggleCategoryFilter('food');
      expect(presenter.filtersHideEverything, isFalse);
    });
  });

  test('dailyNetOf: income adds, expense subtracts, a transfer nets to zero',
      () {
    expect(presenter.dailyNetOf([byId('lunch'), byId('salary')]), 1000 - 100.0);
    expect(presenter.dailyNetOf([byId('move-out'), byId('move-in')]), 0);
  });

  test('lookups: accountById, accountIndexOf, categoryById', () {
    expect(presenter.accountById('bpi')?.name, 'BPI');
    expect(presenter.accountById('nope'), isNull);
    expect(presenter.accountIndexOf('visa'), 2);
    expect(presenter.accountIndexOf('nope'), -1);
    expect(presenter.categoryById('food')?.name, 'Food');
    expect(presenter.categoryById(''), isNull);
  });
}
