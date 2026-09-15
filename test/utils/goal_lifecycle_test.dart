import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/goal_lifecycle.dart';

FinancialAccount _goal({
  double balance = 0,
  double? target = 6000,
  DateTime? fundedAt,
  DateTime? redeemedAt,
  double? redeemedAmount,
  AccountCategory category = AccountCategory.goal,
}) {
  return FinancialAccount(
    id: 'phone',
    name: 'Phone',
    category: category,
    balance: balance,
    colorHex: '#FFFFFF',
    icon: 'flag',
    goalTarget: target,
    goalFundedAt: fundedAt,
    goalRedeemedAt: redeemedAt,
    goalRedeemedAmount: redeemedAmount,
  );
}

final _now = DateTime(2026, 9, 13);

void main() {
  group('GoalStage', () {
    test('a goal below target is still saving', () {
      expect(_goal(balance: 4000).goalStage, GoalStage.saving);
    });

    test('a stamped goal is funded, and stays funded once spent', () {
      final funded = _goal(balance: 6000, fundedAt: _now);
      expect(funded.goalStage, GoalStage.funded);
      // The purchase drains it. This is the case the whole feature exists for.
      expect(funded.copyWith(balance: 0).goalStage, GoalStage.funded);
    });

    test('a redeemed goal outranks funded', () {
      final done = _goal(balance: 0, fundedAt: _now, redeemedAt: _now);
      expect(done.goalStage, GoalStage.redeemed);
    });

    test('a savings account with a target is not a goal account', () {
      expect(_goal(category: AccountCategory.savings).goalStage,
          GoalStage.notAGoal);
    });

    test('a goal with no usable target is not trackable', () {
      expect(_goal(target: null).goalStage, GoalStage.notAGoal);
      expect(_goal(target: 0).goalStage, GoalStage.notAGoal);
    });
  });

  group('goalProgress', () {
    test('tracks the balance while saving', () {
      expect(_goal(balance: 3000).goalProgress, 0.5);
    });

    test('never exceeds 100% when overfunded', () {
      expect(_goal(balance: 9000).goalProgress, 1.0);
    });

    test('stays at 100% after the goal is spent', () {
      // Before the lifecycle this read 0.0 — a completed goal rendered exactly
      // like one never started.
      final spent = _goal(balance: 0, fundedAt: _now);
      expect(spent.goalProgress, 1.0);
    });
  });

  group('stampIfFunded', () {
    test('stamps when the balance first reaches the target', () {
      final stamped = stampIfFunded(_goal(balance: 6000), _now);
      expect(stamped.goalFundedAt, _now);
      expect(stamped.goalStage, GoalStage.funded);
    });

    test('does not stamp below target', () {
      expect(stampIfFunded(_goal(balance: 5999), _now).goalFundedAt, isNull);
    });

    test('keeps the original date on an already-funded goal', () {
      final first = DateTime(2026, 6, 1);
      final again = stampIfFunded(_goal(balance: 9000, fundedAt: first), _now);
      expect(again.goalFundedAt, first);
    });

    test('never re-stamps a redeemed goal', () {
      final done = _goal(balance: 6000, fundedAt: _now, redeemedAt: _now);
      expect(stampIfFunded(done, _now).goalStage, GoalStage.redeemed);
    });

    test('leaves non-goal accounts alone', () {
      final savings = _goal(balance: 9999, category: AccountCategory.savings);
      expect(stampIfFunded(savings, _now).goalFundedAt, isNull);
    });
  });

  group('reconcileGoalStamps', () {
    final stored = _goal(balance: 6000, fundedAt: _now);

    test('raising the target above the balance un-funds the goal', () {
      // The user re-planned: ₱6,000 was the old definition of done.
      final replanned = stored.copyWith(goalTarget: 10000);
      expect(reconcileGoalStamps(replanned, stored, _now).goalStage,
          GoalStage.saving);
    });

    test('raising the target to something already covered stays funded', () {
      final replanned = stored.copyWith(goalTarget: 5000, balance: 6000);
      expect(reconcileGoalStamps(replanned, stored, _now).goalFundedAt, _now);
    });

    test('lowering the target leaves the stamp alone', () {
      final lowered = stored.copyWith(goalTarget: 3000);
      expect(reconcileGoalStamps(lowered, stored, _now).goalFundedAt, _now);
    });

    test('a drawdown alone never un-funds a goal', () {
      // The case the feature exists for: the target did not move, the money was
      // spent. Without the `previous` comparison this silently un-funded.
      final spent = stored.copyWith(balance: 0);
      expect(
          reconcileGoalStamps(spent, stored, _now).goalStage, GoalStage.funded);
    });

    test('an unrelated edit on a spent goal keeps it funded', () {
      final renamed = stored.copyWith(balance: 0, name: 'Phone (2026)');
      expect(reconcileGoalStamps(renamed, stored, _now).goalStage,
          GoalStage.funded);
    });

    test('a redeemed goal is history and is left untouched', () {
      final done = _goal(balance: 0, fundedAt: _now, redeemedAt: _now);
      expect(
          reconcileGoalStamps(done, done, _now).goalStage, GoalStage.redeemed);
    });

    test('a brand-new account with no previous is left alone', () {
      final fresh = _goal(balance: 0, fundedAt: _now);
      expect(
          reconcileGoalStamps(fresh, null, _now).goalStage, GoalStage.funded);
    });
  });

  group('redeemGoal', () {
    test('records the date and what the goal delivered', () {
      final done = redeemGoal(_goal(balance: 0, fundedAt: _now), _now);
      expect(done.goalStage, GoalStage.redeemed);
      expect(done.goalRedeemedAt, _now);
      expect(done.goalRedeemedAmount, 6000);
    });

    test('accepts an explicit amount when the spend differed', () {
      final done =
          redeemGoal(_goal(balance: 0, fundedAt: _now), _now, amount: 5800);
      expect(done.goalRedeemedAmount, 5800);
    });

    test('a goal still being saved into cannot be redeemed', () {
      final saving = _goal(balance: 3000);
      expect(redeemGoal(saving, _now).goalStage, GoalStage.saving);
    });
  });

  group('restartGoal', () {
    test('clears both stamps and takes the new target', () {
      final done = _goal(
          balance: 0, fundedAt: _now, redeemedAt: _now, redeemedAmount: 6000);
      final again = restartGoal(done, _now, newTarget: 9000);

      expect(again.goalStage, GoalStage.saving);
      expect(again.goalTarget, 9000);
      expect(again.goalFundedAt, isNull);
      expect(again.goalRedeemedAt, isNull);
      expect(again.goalRedeemedAmount, isNull);
      // Same account, so the transaction history survives.
      expect(again.id, done.id);
    });

    test('rejects a non-positive target', () {
      final done = _goal(balance: 0, fundedAt: _now, redeemedAt: _now);
      expect(
          restartGoal(done, _now, newTarget: 0).goalStage, GoalStage.redeemed);
    });
  });

  group('goalLooksSpent', () {
    test('true once a funded goal has been drawn down', () {
      expect(_goal(balance: 0, fundedAt: _now).goalLooksSpent, isTrue);
    });

    test('false while the money is still sitting there', () {
      expect(_goal(balance: 6000, fundedAt: _now).goalLooksSpent, isFalse);
    });

    test('false for a goal that was never funded', () {
      expect(_goal(balance: 0).goalLooksSpent, isFalse);
    });
  });

  group('persistence', () {
    test('the stamps survive a JSON round-trip', () {
      final done = _goal(
        balance: 0,
        fundedAt: DateTime(2026, 8, 1),
        redeemedAt: DateTime(2026, 9, 13),
        redeemedAmount: 6000,
      );
      final back = FinancialAccount.fromJson(done.toJson());

      expect(back.goalFundedAt, DateTime(2026, 8, 1));
      expect(back.goalRedeemedAt, DateTime(2026, 9, 13));
      expect(back.goalRedeemedAmount, 6000);
      expect(back.goalStage, GoalStage.redeemed);
    });

    test('an account saved before the lifecycle shipped loads as saving', () {
      final legacy = {
        'id': 'old',
        'name': 'Old Goal',
        'category': 'goal',
        'balance': 1000.0,
        'colorHex': '#FFFFFF',
        'icon': 'flag',
        'goalTarget': 5000.0,
      };
      final back = FinancialAccount.fromJson(legacy);

      expect(back.goalFundedAt, isNull);
      expect(back.goalStage, GoalStage.saving);
      expect(back.goalProgress, 0.2);
    });
  });
}
