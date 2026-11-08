import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// The Trends summaries the mobile spending card switch and the web Trends
/// card both read (Plan 071 Phase 10b), so neither computes them in a view.
void main() {
  group('NetWorthTrendSummary', () {
    NetWorthTrendSummary of(List<double> values, {double current = 0}) =>
        NetWorthTrendSummary(
          points: [
            for (var i = 0; i < values.length; i++)
              (label: 'M$i', month: '2026-0${i + 1}', value: values[i]),
          ],
          current: current,
        );

    test('a rising series: change, labels and positions', () {
      final s = of([40000, 50000, 45000], current: 45000);

      expect(s.hasChart, isTrue);
      expect(s.values, [40000, 50000, 45000]);
      expect(s.labels, ['M0', 'M1', 'M2']);
      expect(s.change, 5000);
      expect(s.isUp, isTrue);
      expect(s.changeTone, StatementTone.good);
      expect(s.changeLabel, '↑ ${formatPesoCompact(5000)} (3 mo)');
      expect(s.startLabel, formatPesoCompact(40000));
      expect(s.currentCompactLabel, formatPesoCompact(45000));
      expect(s.currentLabel, formatPeso(45000));
      expect(s.normalizedValues, [0.0, 1.0, 0.5]);
    });

    test('a falling series reads down and bad', () {
      final s = of([50000, 38000]);

      expect(s.isUp, isFalse);
      expect(s.changeTone, StatementTone.bad);
      expect(s.changeLabel, '↓ ${formatPesoCompact(12000)} (2 mo)');
    });

    test('a flat series sits mid-height', () {
      expect(of([100, 100, 100]).normalizedValues, [0.5, 0.5, 0.5]);
    });

    test('a negative net worth reads −₱, not ₱-', () {
      final s = of([-20000, -12500], current: -12500);

      expect(s.currentCompactLabel, '−${formatPesoCompact(12500)}');
      expect(s.currentCompactLabel, '−₱12.5k');
      expect(s.startLabel, '−₱20k');
      expect(s.currentLabel, '−${formatPeso(12500)}');
      expect(s.changeLabel, '↑ ${formatPesoCompact(7500)} (2 mo)');
    });

    test('a positive series fills to the bottom, unchanged', () {
      final s = of([40000, 50000, 45000]);

      expect(s.normalizedValues, [0.0, 1.0, 0.5]);
      expect(s.normalizedBaseline, 0.0);
    });

    test('a series crossing zero fills to the zero line', () {
      final s = of([-10000, 30000]);

      expect(s.normalizedValues, [0.0, 1.0]);
      expect(s.normalizedBaseline, closeTo(0.25, 1e-9));
    });

    test('an all-negative series hangs below zero at the top', () {
      final s = of([-20000, -10000]);

      // Range widens to 0: −20k at the bottom, −10k halfway, zero on top.
      expect(s.normalizedValues, [0.0, 0.5]);
      expect(s.normalizedBaseline, 1.0);
    });

    test('flat or all-zero series paint without NaN', () {
      for (final vs in [
        [0.0, 0.0, 0.0],
        [100.0, 100.0],
        [-100.0, -100.0],
      ]) {
        final s = of(vs);
        expect(s.normalizedValues.any((v) => v.isNaN), isFalse, reason: '$vs');
        expect(s.normalizedBaseline.isNaN, isFalse, reason: '$vs');
        expect(s.normalizedBaseline, inInclusiveRange(0.0, 1.0));
      }
      expect(of([0, 0]).normalizedValues, [0.5, 0.5]);
      expect(of([-100, -100]).normalizedValues, [0.0, 0.0]);
      expect(of([-100, -100]).normalizedBaseline, 1.0);
    });

    test('one point: no chart, no change', () {
      final s = of([50000], current: 50000);

      expect(s.hasChart, isFalse);
      expect(s.change, 0);
      expect(s.changeLabel, '—');
      expect(s.startLabel, '—');
      expect(s.emptyText, isNotEmpty);
    });
  });

  group('IncomeExpenseTrendSummary', () {
    IncomeExpenseTrendSummary of(List<(double, double)> months) =>
        IncomeExpenseTrendSummary(months: [
          for (var i = 0; i < months.length; i++)
            (
              month: '2026-0${i + 1}',
              label: 'M$i',
              income: months[i].$1,
              expense: months[i].$2,
            ),
        ]);

    test('bar heights are shares of the tallest bar', () {
      final s = of([(20000, 10000), (30000, 40000)]);

      expect(s.hasChart, isTrue);
      expect(s.labels, ['M0', 'M1']);
      expect(s.maxValue, 40000);
      expect(s.incomeFractions, [0.5, 0.75]);
      expect(s.expenseFractions, [0.25, 1.0]);
    });

    test('averages and a positive net', () {
      final s = of([(20000, 10000), (30000, 20000)]);

      expect(s.avgIncome, 25000);
      expect(s.avgExpense, 15000);
      expect(s.avgIncomeLabel, formatPesoCompact(25000));
      expect(s.avgExpenseLabel, formatPesoCompact(15000));
      expect(s.avgNetLabel, '+${formatPesoCompact(10000)}');
      expect(s.avgNetTone, StatementTone.good);
    });

    test('a negative net carries a minus and reads bad', () {
      final s = of([(10000, 12000), (10000, 14000)]);

      expect(s.avgNetLabel, '−${formatPesoCompact(3000)}');
      expect(s.avgNetTone, StatementTone.bad);
    });

    test('no spend or income: zero heights, no division by zero', () {
      final s = of([(0, 0), (0, 0)]);

      expect(s.incomeFractions, [0.0, 0.0]);
      expect(s.expenseFractions, [0.0, 0.0]);
    });

    test('one month: no chart', () {
      final s = of([(10000, 5000)]);

      expect(s.hasChart, isFalse);
      expect(s.emptyText, isNotEmpty);
    });

    IncomeExpenseTrendSummary withLive(
      List<(double, double)> closed,
      (double, double) live,
    ) =>
        IncomeExpenseTrendSummary(
          months: [
            for (var i = 0; i < closed.length; i++)
              (
                month: '2026-0${i + 1}',
                label: 'M$i',
                income: closed[i].$1,
                expense: closed[i].$2,
              ),
            (month: '2026-11', label: 'Nov', income: live.$1, expense: live.$2),
          ],
          currentMonth: '2026-11',
        );

    test('averages cover closed months only; the live month stays charted', () {
      // Five closed months at ₱50k in; two days into November, ₱0 so far.
      final s = withLive(
        [for (var i = 0; i < 5; i++) (50000, 30000)],
        (0, 1000),
      );

      expect(s.months, hasLength(6));
      expect(s.labels.last, 'Nov');
      expect(s.closedMonths, hasLength(5));
      expect(s.avgIncome, 50000);
      expect(s.avgExpense, 30000);
      expect(s.avgIncomeLabel, formatPesoCompact(50000));
      expect(s.avgNetLabel, '+${formatPesoCompact(20000)}');
      // The live month still sets the bar heights.
      expect(s.expenseFractions.last, closeTo(1000 / 50000, 1e-9));
    });

    test('no closed month: the averages read "—"', () {
      final s = withLive([], (8000, 3000));

      expect(s.hasAverages, isFalse);
      expect(s.avgIncomeLabel, '—');
      expect(s.avgExpenseLabel, '—');
      expect(s.avgNetLabel, '—');
      expect(s.avgNetTone, StatementTone.neutral);
    });
  });

  group('formatPesoCompactMinus', () {
    test('typographic minus before the peso sign', () {
      expect(formatPesoCompactMinus(-12500), '−₱12.5k');
      expect(formatPesoCompactMinus(-2000000), '−₱2M');
      expect(formatPesoCompactMinus(-500), '−${formatPeso(500)}');
      expect(formatPesoCompactMinus(45000), '₱45k');
      expect(formatPesoCompactMinus(-1e-12), formatPeso(0));
    });
  });

  test('only the spending view has a full history', () {
    expect(DashboardTrend.spending.hasFullHistory, isTrue);
    expect(DashboardTrend.netWorth.hasFullHistory, isFalse);
    expect(DashboardTrend.incomeExpenses.hasFullHistory, isFalse);
    expect(DashboardTrend.incomeExpenses.semanticLabel, 'Income vs expenses');
  });
}
