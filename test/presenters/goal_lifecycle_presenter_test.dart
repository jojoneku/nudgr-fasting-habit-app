import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../mocks.mocks.dart';

/// End-to-end goal lifecycle through the presenters (docs/goal_lifecycle_spec.md).
///
/// The worked example throughout is the one that exposed the problem: fund
/// ₱6,000 for a phone over three months, buy the phone, and check that the app
/// still knows you did it.

FinancialAccount _account(
  String id, {
  required AccountCategory category,
  double balance = 0,
  double? goalTarget,
}) =>
    FinancialAccount(
      id: id,
      name: id,
      category: category,
      balance: balance,
      colorHex: '#46BD6B',
      icon: 'savings',
      goalTarget: goalTarget,
    );

Future<void> _waitForLoad(LedgerPresenter ledger) async {
  while (ledger.isLoading) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          _account('bpi', category: AccountCategory.bank, balance: 50000),
          _account('phone', category: AccountCategory.goal, goalTarget: 6000),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.saveBills(any)).thenAnswer((_) async {});
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(storage.saveInstallments(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  });

  Future<LedgerPresenter> buildLedger() async {
    final ledger = LedgerPresenter(storage, stats);
    await _waitForLoad(ledger);
    return ledger;
  }

  FinancialAccount goalIn(LedgerPresenter ledger) =>
      ledger.accounts.firstWhere((a) => a.id == 'phone');

  /// One month's contribution into the goal, as the two-legged transfer the
  /// funding sheet actually books.
  Future<void> fund(LedgerPresenter ledger, double amount, int month) {
    return ledger.addTransfer(
      fromAccountId: 'bpi',
      toAccountId: 'phone',
      amount: amount,
      description: 'Phone fund',
      date: DateTime(2026, month, 1),
    );
  }

  /// Buying the thing: money leaves the goal account for good.
  Future<void> spendGoal(LedgerPresenter ledger, double amount) {
    return ledger.addTransaction(TransactionRecord(
      id: 'buy',
      date: DateTime(2026, 9, 20),
      accountId: 'phone',
      categoryId: '',
      amount: amount,
      type: TransactionType.outflow,
      description: 'Phone',
      month: toMonthKey(DateTime(2026, 9, 20)),
    ));
  }

  group('funding', () {
    test('a goal is still saving while short of the target', () async {
      final ledger = await buildLedger();
      await fund(ledger, 2000, 7);
      await fund(ledger, 2000, 8);

      expect(goalIn(ledger).balance, 4000);
      expect(goalIn(ledger).goalStage, GoalStage.saving);
      expect(goalIn(ledger).goalProgress, closeTo(0.666, 0.01));
    });

    test('reaching the target stamps it funded', () async {
      final ledger = await buildLedger();
      await fund(ledger, 2000, 7);
      await fund(ledger, 2000, 8);
      await fund(ledger, 2000, 9);

      final goal = goalIn(ledger);
      expect(goal.balance, 6000);
      expect(goal.goalStage, GoalStage.funded);
      expect(goal.goalFundedAt, isNotNull);
      expect(goal.goalProgress, 1.0);
    });

    test('spending the goal keeps it funded at 100%', () async {
      final ledger = await buildLedger();
      await fund(ledger, 6000, 7);
      expect(goalIn(ledger).goalStage, GoalStage.funded);

      await spendGoal(ledger, 6000);

      final goal = goalIn(ledger);
      expect(goal.balance, 0);
      // The whole point: before the lifecycle this read `saving` at 0%,
      // indistinguishable from a goal never started.
      expect(goal.goalStage, GoalStage.funded);
      expect(goal.goalProgress, 1.0);
      expect(goal.goalLooksSpent, isTrue);
    });

    test('the funded date is not overwritten by later contributions', () async {
      final ledger = await buildLedger();
      await fund(ledger, 6000, 7);
      final first = goalIn(ledger).goalFundedAt;

      await fund(ledger, 1000, 8);
      expect(goalIn(ledger).goalFundedAt, first);
    });
  });

  group('redemption', () {
    test('markGoalRedeemed records what the goal delivered', () async {
      final ledger = await buildLedger();
      await fund(ledger, 6000, 7);
      await ledger.markGoalRedeemed('phone');

      final goal = goalIn(ledger);
      expect(goal.goalStage, GoalStage.redeemed);
      expect(goal.goalRedeemedAt, isNotNull);
      expect(goal.goalRedeemedAmount, 6000);
    });

    test('a goal still being saved into cannot be redeemed', () async {
      final ledger = await buildLedger();
      await fund(ledger, 3000, 7);
      await ledger.markGoalRedeemed('phone');

      expect(goalIn(ledger).goalStage, GoalStage.saving);
    });

    test('restarting clears both stamps and takes a new target', () async {
      final ledger = await buildLedger();
      await fund(ledger, 6000, 7);
      await ledger.markGoalRedeemed('phone');
      await ledger.restartGoalAccount('phone', newTarget: 9000);

      final goal = goalIn(ledger);
      expect(goal.goalStage, GoalStage.saving);
      expect(goal.goalTarget, 9000);
      expect(goal.goalRedeemedAt, isNull);
    });
  });

  group('XP', () {
    test('funding a goal pays out once, not on every later contribution',
        () async {
      final ledger = await buildLedger();
      await fund(ledger, 6000, 7);
      verify(stats.addXp(50)).called(1);

      // Topping it up further is not a second achievement.
      await fund(ledger, 1000, 8);
      verifyNever(stats.addXp(50));
    });

    test('no payout while the goal is still short', () async {
      final ledger = await buildLedger();
      await fund(ledger, 5999, 7);
      verifyNever(stats.addXp(50));
    });

    test('spending and re-funding a restarted goal earns it again', () async {
      final ledger = await buildLedger();
      await fund(ledger, 6000, 7);
      verify(stats.addXp(50)).called(1);

      await ledger.markGoalRedeemed('phone');
      await spendGoal(ledger, 6000);
      await ledger.restartGoalAccount('phone', newTarget: 9000);
      await fund(ledger, 9000, 10);

      // A second goal reached, not the same one re-counted.
      verify(stats.addXp(50)).called(1);
    });
  });

  group('archiving', () {
    test('a completed goal can be filed away without deleting anything',
        () async {
      final ledger = await buildLedger();
      await fund(ledger, 6000, 7);
      await ledger.markGoalRedeemed('phone');

      // `isActive: false` is the app's existing "Archived — hidden everywhere
      // until reactivated" state, which every account picker already filters.
      final archived = goalIn(ledger).copyWith(isActive: false);
      await ledger.saveAccount(archived);

      expect(goalIn(ledger).isActive, isFalse);
      // Still present, so its transactions keep their account reference.
      expect(ledger.accounts.any((a) => a.id == 'phone'), isTrue);
      expect(goalIn(ledger).goalStage, GoalStage.redeemed);
    });
  });

  group('re-planning the target', () {
    test('raising it above the balance un-funds the goal', () async {
      final ledger = await buildLedger();
      await fund(ledger, 6000, 7);
      expect(goalIn(ledger).goalStage, GoalStage.funded);

      await ledger.saveAccount(goalIn(ledger).copyWith(goalTarget: 10000));
      expect(goalIn(ledger).goalStage, GoalStage.saving);
    });

    test('an unrelated edit after spending keeps the goal funded', () async {
      final ledger = await buildLedger();
      await fund(ledger, 6000, 7);
      await spendGoal(ledger, 6000);

      // Renaming a spent goal must not un-fund it. The target did not move.
      await ledger.saveAccount(goalIn(ledger).copyWith(name: 'Phone (2026)'));
      expect(goalIn(ledger).goalStage, GoalStage.funded);
    });
  });

  group('recurring set-aside', () {
    /// A ₱2,000/month recurring set-aside pointed at the phone goal.
    BudgetedExpense setAside(String month) => BudgetedExpense(
          id: 'sa_$month',
          name: 'Phone fund',
          budgetedType: SetAsideType.goal,
          month: month,
          allocatedAmount: 2000,
          categoryId: '',
          accountId: 'bpi',
          destinationAccountId: 'phone',
          isRecurring: true,
          seriesId: 'phone_series',
        );

    test('stops once the goal is funded, and stays stopped after it is spent',
        () async {
      final prev = toMonthKey(DateTime(2026, 8, 1));
      when(storage.loadBudgetedExpenses())
          .thenAnswer((_) async => [setAside(prev)]);
      // Funded, then drained by the purchase. Before the fix `_goalIsFunded`
      // tested the live balance, so ₱0 read as "not funded" and the ₱2,000/month
      // set-aside quietly resumed for a phone already bought.
      when(storage.loadAccounts()).thenAnswer((_) async => [
            _account('bpi', category: AccountCategory.bank, balance: 50000),
            FinancialAccount(
              id: 'phone',
              name: 'phone',
              category: AccountCategory.goal,
              balance: 0,
              colorHex: '#46BD6B',
              icon: 'savings',
              goalTarget: 6000,
              goalFundedAt: DateTime(2026, 9, 1),
            ),
          ]);

      final ledger = await buildLedger();
      final bills = BillsReceivablesPresenter(storage, ledger, stats);
      // The constructor kicks off load() asynchronously and it reassigns
      // _allExpenses wholesale; awaiting it first stops that overwriting the
      // rows setMonth is about to generate.
      await bills.load();
      await bills.setMonth(toMonthKey(DateTime(2026, 9, 1)));

      final generated = bills.budgetedExpenses
          .where((e) => e.destinationAccountId == 'phone');
      expect(generated, isEmpty);
    });

    test('keeps running while the goal is still short', () async {
      final prev = toMonthKey(DateTime(2026, 8, 1));
      when(storage.loadBudgetedExpenses())
          .thenAnswer((_) async => [setAside(prev)]);
      when(storage.loadAccounts()).thenAnswer((_) async => [
            _account('bpi', category: AccountCategory.bank, balance: 50000),
            _account('phone',
                category: AccountCategory.goal,
                balance: 4000,
                goalTarget: 6000),
          ]);

      final ledger = await buildLedger();
      final bills = BillsReceivablesPresenter(storage, ledger, stats);
      // The constructor kicks off load() asynchronously and it reassigns
      // _allExpenses wholesale; awaiting it first stops that overwriting the
      // rows setMonth is about to generate.
      await bills.load();
      await bills.setMonth(toMonthKey(DateTime(2026, 9, 1)));

      final generated = bills.budgetedExpenses
          .where((e) => e.destinationAccountId == 'phone');
      expect(generated, isNotEmpty);
    });
  });
}
