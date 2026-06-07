import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/credit_finance_charge.dart';

void main() {
  group('computeFinanceCharge', () {
    test('applies the monthly rate to the outstanding balance', () {
      expect(computeFinanceCharge(outstanding: 10000, monthlyRate: 0.03),
          closeTo(300, 0.001));
    });

    test('returns 0 when nothing is outstanding', () {
      expect(computeFinanceCharge(outstanding: 0, monthlyRate: 0.03), 0);
    });

    test('returns 0 when no rate is set', () {
      expect(computeFinanceCharge(outstanding: 5000, monthlyRate: 0), 0);
    });

    test('clamps to the BSP 3%/month cap', () {
      // A 5% rate is illegal; charge must not exceed the 3% cap.
      expect(computeFinanceCharge(outstanding: 10000, monthlyRate: 0.05),
          closeTo(300, 0.001));
    });
  });

  group('computeMinimumDue', () {
    test('uses the percentage when above the floor', () {
      // 50000 * 3.57% = 1785, above the 850 floor.
      expect(computeMinimumDue(balance: 50000), closeTo(1785, 0.001));
    });

    test('uses the floor when the percentage is below it', () {
      // 10000 * 3.57% = 357, below 850 → floor wins.
      expect(computeMinimumDue(balance: 10000), 850);
    });

    test('never exceeds the balance', () {
      // Owe only 200 → min due can not be the 850 floor.
      expect(computeMinimumDue(balance: 200), 200);
    });

    test('adds past due on top', () {
      expect(computeMinimumDue(balance: 10000, pastDue: 500), 1350);
    });

    test('zero balance with past due returns the past due', () {
      expect(computeMinimumDue(balance: 0, pastDue: 300), 300);
    });
  });

  group('computeLateFee', () {
    test('caps at the flat fee', () {
      expect(computeLateFee(unpaidMinimumDue: 2000), 850);
    });

    test('is the unpaid minimum when below the flat fee', () {
      expect(computeLateFee(unpaidMinimumDue: 400), 400);
    });

    test('is 0 when nothing is unpaid', () {
      expect(computeLateFee(unpaidMinimumDue: 0), 0);
    });
  });
}
