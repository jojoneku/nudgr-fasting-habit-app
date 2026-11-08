import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/account_meter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// The shared account meter (Plan 071 Phase 9): only credit accounts with a
/// limit and goals (or savings) with a target get one.
void main() {
  FinancialAccount account(
    AccountCategory category, {
    double balance = 0,
    double? creditLimit,
    double? goalTarget,
    DateTime? fundedAt,
    DateTime? redeemedAt,
  }) =>
      FinancialAccount(
        id: category.name,
        name: category.name,
        category: category,
        balance: balance,
        colorHex: '#46BD6B',
        icon: category.name,
        creditLimit: creditLimit,
        goalTarget: goalTarget,
        goalFundedAt: fundedAt,
        goalRedeemedAt: redeemedAt,
      );

  group('accountMeterFor', () {
    test('a credit card with a limit shows available of limit', () {
      final meter = accountMeterFor(account(AccountCategory.creditCard,
          balance: 12000, creditLimit: 20000))!;
      expect(meter.kind, AccountMeterKind.credit);
      expect(meter.fraction, closeTo(0.6, 1e-9));
      expect(
          meter.label, '${formatPeso(8000)} available of ${formatPeso(20000)}');
    });

    test('an over-limit card shows a negative available and a full bar', () {
      final meter = accountMeterFor(account(AccountCategory.creditLine,
          balance: 25000, creditLimit: 20000))!;
      expect(meter.fraction, 1.0);
      expect(meter.label, startsWith('−₱5,000.00 available'));
    });

    test('a goal with a target shows the share of the target', () {
      final meter = accountMeterFor(
          account(AccountCategory.goal, balance: 2700, goalTarget: 6000))!;
      expect(meter.kind, AccountMeterKind.goal);
      expect(meter.fraction, closeTo(0.45, 1e-9));
      expect(meter.label, '45% of ${formatPeso(6000)}');
    });

    test('a funded goal stays at 100% after it is spent', () {
      final meter = accountMeterFor(account(AccountCategory.goal,
          balance: 0, goalTarget: 6000, fundedAt: DateTime(2026, 10, 1)))!;
      expect(meter.fraction, 1.0);
    });

    test('a savings account with a target gets a goal meter', () {
      final meter = accountMeterFor(
          account(AccountCategory.savings, balance: 500, goalTarget: 1000))!;
      expect(meter.kind, AccountMeterKind.goal);
      expect(meter.fraction, closeTo(0.5, 1e-9));
    });

    test('no meter on liquid, plain savings, limitless credit or completed',
        () {
      expect(
          accountMeterFor(account(AccountCategory.bank, balance: 900)), isNull);
      expect(
          accountMeterFor(account(AccountCategory.cash, balance: -50)), isNull);
      expect(accountMeterFor(account(AccountCategory.savings, balance: 900)),
          isNull);
      expect(accountMeterFor(account(AccountCategory.creditCard, balance: 900)),
          isNull);
      expect(
        accountMeterFor(account(AccountCategory.goal,
            goalTarget: 6000,
            fundedAt: DateTime(2026, 9, 1),
            redeemedAt: DateTime(2026, 10, 1))),
        isNull,
      );
    });
  });
}
