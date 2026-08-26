import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../mocks.mocks.dart';

// Savings budgets that were written under an expense group.
//
// The web add-row kept its Savings toggle and the group it persists in two
// separate fields. After one add the group reset to Variable while the toggle
// stayed on Savings, so the next entry was saved with an *account* id under an
// expense group. Nothing could render it: categoriesByGroup finds no category
// for an account id, savingsBudgets skips it for not being in a savings group —
// yet totalAllocated still counted the money. The row simply vanished while the
// header total grew.

String get _month => toMonthKey(DateTime.now());

FinanceCategory _cat(String id, String name) => FinanceCategory(
      id: id,
      name: name,
      type: CategoryType.expense,
      icon: 'receipt',
      colorHex: '#F6685E',
    );

FinancialAccount _savings(String id, String name) => FinancialAccount(
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
  required double amount,
  required String group,
}) =>
    Budget(
      id: id,
      categoryId: categoryId,
      month: _month,
      allocatedAmount: amount,
      group: group,
      budgetType: BudgetType.variable,
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
  }) {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    when(storage.loadBudgets()).thenAnswer((_) async => budgets);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => categories);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(storage.saveBudgets(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  }

  group('orphaned savings budgets are repaired on load', () {
    test('a budget on an account id under an expense group moves to Savings',
        () async {
      stub(
        accounts: [_savings('braces', 'Braces Fund')],
        budgets: [
          _budget(
            id: 'b1',
            categoryId: 'braces', // an ACCOUNT id…
            amount: 3000,
            group: BudgetGroupDef.idVariableOptional, // …under an expense group
          ),
        ],
      );
      final p = build();
      await p.load();

      expect(
        p.savingsBudgets.map((e) => e.account.name),
        ['Braces Fund'],
        reason: 'the row should be visible again',
      );
      expect(p.budgetFor('braces')!.group, BudgetGroupDef.idSavings);
      expect(
        p.categoriesByGroup[BudgetGroupDef.idVariableOptional],
        isEmpty,
        reason: 'and it should leave the expense group it was stranded in',
      );
      // It was always in the total — that was the tell that it existed at all.
      expect(p.totalAllocated, 3000);
      verify(storage.saveBudgets(any)).called(1);
    });

    test('a normal expense budget is left alone', () async {
      stub(
        categories: [_cat('c1', 'Food')],
        accounts: [_savings('braces', 'Braces Fund')],
        budgets: [
          _budget(
            id: 'b1',
            categoryId: 'c1',
            amount: 5000,
            group: BudgetGroupDef.idVariableOptional,
          ),
        ],
      );
      final p = build();
      await p.load();

      expect(p.budgetFor('c1')!.group, BudgetGroupDef.idVariableOptional);
      expect(p.savingsBudgets, isEmpty);
      expect(
        p.categoriesByGroup[BudgetGroupDef.idVariableOptional]!
            .map((c) => c.name),
        ['Food'],
      );
      verifyNever(storage.saveBudgets(any));
    });

    test('a category sharing an id with an account is not dragged across',
        () async {
      // Ids are timestamp+random so this cannot really collide, but the repair
      // should key off "no category owns this id" rather than the id alone.
      stub(
        categories: [_cat('shared', 'Dental')],
        accounts: [_savings('shared', 'Braces Fund')],
        budgets: [
          _budget(
            id: 'b1',
            categoryId: 'shared',
            amount: 1200,
            group: BudgetGroupDef.idNonNegotiables,
          ),
        ],
      );
      final p = build();
      await p.load();

      expect(p.budgetFor('shared')!.group, BudgetGroupDef.idNonNegotiables);
      verifyNever(storage.saveBudgets(any));
    });

    test('an already-correct savings budget is not rewritten', () async {
      stub(
        accounts: [_savings('ef', 'Emergency Fund')],
        budgets: [
          _budget(
            id: 'b1',
            categoryId: 'ef',
            amount: 5000,
            group: BudgetGroupDef.idSavings,
          ),
        ],
      );
      final p = build();
      await p.load();

      expect(p.savingsBudgets.map((e) => e.account.name), ['Emergency Fund']);
      verifyNever(storage.saveBudgets(any));
    });

    test('repeated loads settle — the repair is idempotent', () async {
      final budgets = [
        _budget(
          id: 'b1',
          categoryId: 'braces',
          amount: 3000,
          group: BudgetGroupDef.idVariableOptional,
        ),
      ];
      stub(
        accounts: [_savings('braces', 'Braces Fund')],
        budgets: budgets,
      );
      final p = build();
      await p.load();
      // Second load reads back what the repair persisted.
      when(storage.loadBudgets()).thenAnswer((_) async => p.allBudgets);
      await p.load();

      expect(p.savingsBudgets.length, 1);
      verify(storage.saveBudgets(any)).called(1); // not called again
    });
  });

  group('isSavingsGroup', () {
    test('recognises a user-created savings group, not just the built-in',
        () async {
      stub();
      when(storage.loadBudgetGroups()).thenAnswer((_) async => [
            const BudgetGroupDef(
              id: 'sinking',
              name: 'Sinking Funds',
              isSavings: true,
              isBuiltIn: false,
              sortOrder: 3,
            ),
          ]);
      final p = build();
      await p.load();

      expect(p.isSavingsGroup('sinking'), isTrue);
      expect(p.isSavingsGroup(BudgetGroupDef.idSavings), isTrue);
      expect(p.isSavingsGroup(BudgetGroupDef.idVariableOptional), isFalse);
      expect(p.isSavingsGroup('nonexistent'), isFalse);
    });
  });
}
