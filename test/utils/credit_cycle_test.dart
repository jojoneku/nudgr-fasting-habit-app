import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/credit_cycle.dart';

void main() {
  group('creditDueDate', () {
    test('fixed day after the close is due the same month', () {
      expect(creditDueDate(DateTime(2026, 9, 1), dueDay: 15),
          DateTime(2026, 9, 15));
    });

    test('fixed day on/before the close rolls to next month', () {
      expect(creditDueDate(DateTime(2026, 9, 20), dueDay: 5),
          DateTime(2026, 10, 5));
      expect(creditDueDate(DateTime(2026, 9, 20), dueDay: 20),
          DateTime(2026, 10, 20));
    });

    test('days-after counts real days across month lengths', () {
      // Sep has 30 days, Oct has 31: the offset lands on different days.
      expect(creditDueDate(DateTime(2026, 9, 20), daysAfter: 15),
          DateTime(2026, 10, 5));
      expect(creditDueDate(DateTime(2026, 10, 20), daysAfter: 15),
          DateTime(2026, 11, 4));
      expect(creditDueDate(DateTime(2026, 12, 20), daysAfter: 15),
          DateTime(2027, 1, 4));
    });

    test('days-after wins over a fixed day', () {
      expect(creditDueDate(DateTime(2026, 9, 20), dueDay: 5, daysAfter: 20),
          DateTime(2026, 10, 10));
    });
  });

  group('creditCycleContaining — Maya: closes 20th, due 15 days after', () {
    CreditCycle cycleOf(DateTime d) =>
        creditCycleContaining(d, statementDay: 20, daysAfter: 15);

    test('a draw on Sep 21 rides the Oct 20 statement, due Nov 4', () {
      final c = cycleOf(DateTime(2026, 9, 21));
      expect(c.start, DateTime(2026, 9, 21));
      expect(c.close, DateTime(2026, 10, 20));
      expect(c.due, DateTime(2026, 11, 4));
      expect(c.dueMonthKey, '2026-11');
    });

    test('a charge ON the close day stays on that statement', () {
      final c = cycleOf(DateTime(2026, 9, 20, 23, 59));
      expect(c.close, DateTime(2026, 9, 20));
      expect(c.due, DateTime(2026, 10, 5));
      expect(c.contains(DateTime(2026, 9, 20, 23, 59)), isTrue);
      expect(c.contains(DateTime(2026, 9, 21)), isFalse);
    });

    test('December charges after the close roll into January', () {
      final c = cycleOf(DateTime(2026, 12, 25));
      expect(c.close, DateTime(2027, 1, 20));
      expect(c.due, DateTime(2027, 2, 4));
    });
  });

  test('user example: closes the 15th — Sep 16 lands on Oct 15', () {
    final c = creditCycleContaining(DateTime(2026, 9, 16),
        statementDay: 15, dueDay: 5);
    expect(c.close, DateTime(2026, 10, 15));
    expect(c.due, DateTime(2026, 11, 5));
  });

  test('statement day is clamped to 28 so February still closes', () {
    final c = creditCycleClosingIn(2026, 2, statementDay: 31, dueDay: 10);
    expect(c.close, DateTime(2026, 2, 28));
    expect(c.start, DateTime(2026, 1, 29));
    expect(c.due, DateTime(2026, 3, 10));
  });

  group('account extension', () {
    FinancialAccount acct({int? stmt, int? due, int? after}) =>
        FinancialAccount(
          id: 'a',
          name: 'a',
          category: AccountCategory.creditLine,
          balance: 0,
          colorHex: '#FFFFFF',
          icon: 'x',
          statementDay: stmt,
          paymentDueDay: due,
          dueDaysAfterStatement: after,
        );

    test('offset-only account has a billing cycle', () {
      final a = acct(stmt: 20, after: 15);
      expect(a.hasBillingCycle, isTrue);
      expect(a.cycleClosingIn(2026, 10)!.due, DateTime(2026, 11, 4));
    });

    test('no due rule means no cycle', () {
      final a = acct(stmt: 20);
      expect(a.hasBillingCycle, isFalse);
      expect(a.cycleContaining(DateTime(2026, 9, 21)), isNull);
    });
  });

  group('minimum rule defaults and JSON', () {
    FinancialAccount of(AccountCategory c) => FinancialAccount(
        id: 'a',
        name: 'a',
        category: c,
        balance: 0,
        colorHex: '#FFFFFF',
        icon: 'x');

    test('card revolves, line and BNPL pay in full', () {
      expect(of(AccountCategory.creditCard).effectiveMinimumRule,
          CreditMinimumRule.percentOfBalance);
      expect(of(AccountCategory.creditLine).effectiveMinimumRule,
          CreditMinimumRule.payInFull);
      expect(of(AccountCategory.bnpl).effectiveMinimumRule,
          CreditMinimumRule.payInFull);
    });

    test('new fields round-trip, and old JSON still loads', () {
      final a = FinancialAccount(
        id: 'a',
        name: 'a',
        category: AccountCategory.creditLine,
        balance: 1,
        colorHex: '#FFFFFF',
        icon: 'x',
        statementDay: 20,
        dueDaysAfterStatement: 15,
        minimumRule: CreditMinimumRule.fixedAmount,
        minimumFixedAmount: 1200,
      );
      final back = FinancialAccount.fromJson(a.toJson());
      expect(back.dueDaysAfterStatement, 15);
      expect(back.minimumRule, CreditMinimumRule.fixedAmount);
      expect(back.minimumFixedAmount, 1200);

      final legacy = a.toJson()
        ..remove('dueDaysAfterStatement')
        ..remove('minimumRule')
        ..remove('minimumFixedAmount');
      final old = FinancialAccount.fromJson(legacy);
      expect(old.dueDaysAfterStatement, isNull);
      expect(old.minimumRule, isNull);
    });

    test('copyWith can clear the offset and rule back to null', () {
      final a = of(AccountCategory.creditLine).copyWith(
          dueDaysAfterStatement: 15,
          minimumRule: CreditMinimumRule.fixedAmount);
      final cleared =
          a.copyWith(dueDaysAfterStatement: null, minimumRule: null);
      expect(cleared.dueDaysAfterStatement, isNull);
      expect(cleared.minimumRule, isNull);
    });
  });
}
