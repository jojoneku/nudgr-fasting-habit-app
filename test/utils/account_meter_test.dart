import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/account_meter.dart';

/// [goalMeterFraction] (Plan 071 Phase 9): the bar behind the mobile
/// GoalProgressCard and the web WebGoalCard.
void main() {
  FinancialAccount account(
    AccountCategory category, {
    double balance = 0,
    double? goalTarget,
    DateTime? fundedAt,
  }) =>
      FinancialAccount(
        id: category.name,
        name: category.name,
        category: category,
        balance: balance,
        colorHex: '#46BD6B',
        icon: category.name,
        goalTarget: goalTarget,
        goalFundedAt: fundedAt,
      );

  group('goalMeterFraction', () {
    test('a goal being saved into is its balance share', () {
      expect(
          goalMeterFraction(
              account(AccountCategory.goal, balance: 2700, goalTarget: 6000)),
          closeTo(0.45, 1e-9));
    });

    test('a reached goal stays full after it is spent', () {
      expect(
          goalMeterFraction(account(AccountCategory.goal,
              goalTarget: 6000, fundedAt: DateTime(2026, 9, 1))),
          1.0);
    });

    test('a savings account with a target is the plain balance share', () {
      expect(
          goalMeterFraction(account(AccountCategory.savings,
              balance: 25000, goalTarget: 100000)),
          closeTo(0.25, 1e-9));
      expect(
          goalMeterFraction(account(AccountCategory.savings,
              balance: 150000, goalTarget: 100000)),
          1.0);
    });

    test('no target means an empty bar', () {
      expect(
          goalMeterFraction(account(AccountCategory.savings, balance: 900)), 0);
    });
  });
}
