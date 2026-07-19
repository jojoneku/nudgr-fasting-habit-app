import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';

MonthlySummary summary({required double inflow, required double net}) =>
    MonthlySummary(
      month: '2026-05',
      totalInflow: inflow,
      totalOutflow: inflow - net,
      totalBills: 0,
      totalBillsPaid: 0,
      billCount: 0,
      billsPaidCount: 0,
      totalReceivables: 0,
      totalReceived: 0,
      receivableCount: 0,
      netSavings: net,
      endingCash: 0,
      accountSnapshots: const {},
      categorySpend: const {},
    );

void main() {
  test('savingsRate is net savings over income', () {
    expect(
        summary(inflow: 70000, net: 31580).savingsRate, closeTo(0.451, 0.001));
  });

  test('savingsRate is null when there is no income', () {
    expect(summary(inflow: 0, net: 0).savingsRate, isNull);
  });

  test('savingsRate can be negative when overspending', () {
    expect(
        summary(inflow: 10000, net: -2000).savingsRate, closeTo(-0.2, 0.001));
  });
}
