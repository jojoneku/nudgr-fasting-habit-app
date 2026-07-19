import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../mocks.mocks.dart';

// Nudgr budget-cards redesign — pace getters + ordered budgetSections view-model.

String get _nowMonth => toMonthKey(DateTime.now());

FinanceCategory _cat(String id, String name) => FinanceCategory(
      id: id,
      name: name,
      type: CategoryType.expense,
      icon: 'receipt',
      colorHex: '#F6685E',
    );

FinancialAccount _savingsAccount(String id, String name) => FinancialAccount(
      id: id,
      name: name,
      category: AccountCategory.savings,
      balance: 0,
      colorHex: '#46BD6B',
      icon: 'savings',
    );

Budget _budget({
  required String id,
  required String categoryId,
  required String month,
  required double amount,
  required String group,
}) =>
    Budget(
      id: id,
      categoryId: categoryId,
      month: month,
      allocatedAmount: amount,
      group: group,
      budgetType: BudgetType.monthly,
    );

TransactionRecord _outflow({
  required String id,
  required String categoryId,
  required double amount,
  required String month,
}) =>
    TransactionRecord(
      id: id,
      date: DateTime.parse('$month-15'),
      accountId: 'acc1',
      categoryId: categoryId,
      amount: amount,
      type: TransactionType.outflow,
      description: 'Test spend',
      month: month,
    );

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;

  BudgetPresenter build() =>
      BudgetPresenter(storage, stats, null, notifications);

  void stub({
    List<Budget> budgets = const [],
    List<FinanceCategory> categories = const [],
    List<FinancialAccount> accounts = const [],
    List<TransactionRecord> transactions = const [],
  }) {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    when(storage.loadBudgets()).thenAnswer((_) async => budgets);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => categories);
    when(storage.loadTransactions()).thenAnswer((_) async => transactions);
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(storage.saveBudgets(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  }

  group('pace getters', () {
    test('current month is flagged and reads as ahead with no spend', () async {
      stub();
      final p = build();
      await p.load();
      p.setMonth(_nowMonth);
      expect(p.isCurrentMonth, isTrue);
      expect(p.monthElapsedFraction, greaterThan(0.0));
      expect(p.monthElapsedFraction, lessThanOrEqualTo(1.0));
      expect(p.isAheadOfPace, isTrue); // 0% spent is always ahead
    });

    test('past month is fully elapsed and not current', () async {
      stub();
      final p = build();
      await p.load();
      p.setMonth(previousMonth(_nowMonth));
      expect(p.isCurrentMonth, isFalse);
      expect(p.monthElapsedFraction, 1.0);
    });

    test('future month has zero elapsed and is not current', () async {
      stub();
      final p = build();
      await p.load();
      p.setMonth(nextMonth(_nowMonth));
      expect(p.isCurrentMonth, isFalse);
      expect(p.monthElapsedFraction, 0.0);
    });

    test('over-spending past the elapsed pace reads as behind', () async {
      final month = previousMonth(_nowMonth); // fully elapsed → tolerance 1.02
      stub(
        categories: [_cat('c1', 'Food')],
        budgets: [
          _budget(
              id: 'b1',
              categoryId: 'c1',
              month: month,
              amount: 100,
              group: BudgetGroupDef.idLivingExpense),
        ],
        transactions: [
          _outflow(id: 't1', categoryId: 'c1', amount: 150, month: month),
        ],
      );
      final p = build();
      await p.load();
      p.setMonth(month);
      expect(p.percentUsed, greaterThan(1.0));
      expect(p.isAheadOfPace, isFalse);
    });
  });

  group('budgetSections ordering', () {
    test('sections follow Living → Savings → Variable → Essentials and '
        'omit empty groups', () async {
      final month = _nowMonth;
      stub(
        categories: [
          _cat('living', 'Rent'),
          _cat('variable', 'Dining'),
          // no non-negotiables budget → that group must be omitted
        ],
        accounts: [_savingsAccount('sav1', 'Emergency Fund')],
        budgets: [
          _budget(
              id: 'b_var',
              categoryId: 'variable',
              month: month,
              amount: 2000,
              group: BudgetGroupDef.idVariableOptional),
          _budget(
              id: 'b_sav',
              categoryId: 'sav1',
              month: month,
              amount: 5000,
              group: BudgetGroupDef.idSavings),
          _budget(
              id: 'b_liv',
              categoryId: 'living',
              month: month,
              amount: 10000,
              group: BudgetGroupDef.idLivingExpense),
        ],
      );
      final p = build();
      await p.load();
      p.setMonth(month);

      final sections = p.budgetSections;
      expect(sections.map((s) => s.groupId).toList(), [
        BudgetGroupDef.idLivingExpense,
        BudgetGroupDef.idSavings,
        BudgetGroupDef.idVariableOptional,
      ]);
      // Savings interleaved (not forced last) and Non-Negotiables omitted.
      final savings = sections.firstWhere((s) => s.isSavings);
      expect(savings.rows.single.isSavings, isTrue);
      expect(savings.rows.single.targetId, 'sav1');
    });

    test('an over-budget expense row exposes overBy and isOver', () async {
      final month = _nowMonth;
      stub(
        categories: [_cat('c1', 'Groceries')],
        budgets: [
          _budget(
              id: 'b1',
              categoryId: 'c1',
              month: month,
              amount: 8000,
              group: BudgetGroupDef.idLivingExpense),
        ],
        transactions: [
          _outflow(id: 't1', categoryId: 'c1', amount: 8700, month: month),
        ],
      );
      final p = build();
      await p.load();
      p.setMonth(month);

      final row = p.budgetSections.single.rows.single;
      expect(row.isOver, isTrue);
      expect(row.overBy, closeTo(700, 1e-9));
      expect(row.progress, 1.0); // clamped
    });
  });
}
