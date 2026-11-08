import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/views/treasury/budget/budget_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/budget_overview_card.dart';

/// Plan 071 Phase 2: mobile shows budget status in words, from the shared
/// rule, not by color alone.
BudgetSectionRow _row({
  required double allocated,
  required double actual,
  bool isSavings = false,
}) {
  final isOver = !isSavings && allocated > 0 && actual > allocated;
  return BudgetSectionRow(
    targetId: 't',
    name: isSavings ? 'Emergency fund' : 'Groceries',
    colorHex: '#2563EB',
    colorIndex: 0,
    categoryType: CategoryType.expense,
    isSavings: isSavings,
    isGoal: false,
    isIncome: false,
    budgetType: BudgetType.monthly,
    allocated: allocated,
    actual: actual,
    progress: allocated > 0 ? (actual / allocated).clamp(0.0, 1.0) : 0.0,
    isOver: isOver,
    overBy: isOver ? actual - allocated : 0,
    met: isSavings && actual >= allocated,
    transactions: const [],
    status: budgetStatusFor(
      allocated: allocated,
      spent: actual,
      accountBacked: isSavings,
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  group('BudgetCard', () {
    testWidgets('an over row says "Over by ₱X" in words', (tester) async {
      await _pump(tester, BudgetCard(row: _row(allocated: 1000, actual: 2200)));
      expect(find.text('Over by ₱1,200'), findsOneWidget);
    });

    testWidgets('a row past the watch line says "Watch · N%"', (tester) async {
      await _pump(tester, BudgetCard(row: _row(allocated: 1000, actual: 800)));
      expect(find.text('Watch · 80%'), findsOneWidget);
    });

    testWidgets('an on-track row shows no status line', (tester) async {
      await _pump(tester, BudgetCard(row: _row(allocated: 1000, actual: 300)));
      expect(find.text('On track'), findsNothing);
      expect(find.textContaining('Watch'), findsNothing);
    });

    testWidgets('a funded savings row says Funded', (tester) async {
      await _pump(
        tester,
        BudgetCard(row: _row(allocated: 1000, actual: 1000, isSavings: true)),
      );
      expect(find.text('Funded'), findsOneWidget);
    });
  });

  group('BudgetOverviewCard', () {
    final presenter = _FakeDashboard();

    testWidgets('rows carry the shared status label', (tester) async {
      await _pump(tester, BudgetOverviewCard(presenter: presenter));
      expect(find.text('Watch · 82%'), findsOneWidget);
      expect(find.text('Over by ₱1,000'), findsOneWidget);
    });

    testWidgets('lists only the rows the presenter returns', (tester) async {
      await _pump(tester, BudgetOverviewCard(presenter: presenter));
      expect(find.text('Living'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
    });

    testWidgets('"Open budget" calls back, and is hidden without a callback',
        (tester) async {
      var opened = 0;
      await _pump(
        tester,
        BudgetOverviewCard(presenter: presenter, onOpenBudget: () => opened++),
      );
      await tester.tap(find.text('Open budget'));
      expect(opened, 1);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('dashboard.budget.open')))
            .height,
        greaterThanOrEqualTo(44),
      );

      await _pump(tester, BudgetOverviewCard(presenter: presenter));
      expect(find.text('Open budget'), findsNothing);
    });
  });
}

/// Only the two getters the card reads. The generated mocks predate them, and
/// a fake keeps this test from depending on a mocks rebuild.
class _FakeDashboard extends Fake implements TreasuryDashboardPresenter {
  @override
  BudgetHealthRow get budgetHealthExpenseTotal => BudgetHealthRow.of(
        id: 'total',
        name: 'Total',
        allocated: 10000,
        spent: 8200,
        isSavings: false,
      );

  @override
  List<BudgetHealthRow> budgetHealthRows({required bool includeSavings}) => [
        BudgetHealthRow.of(
          id: 'living',
          name: 'Living',
          allocated: 4000,
          spent: 5000,
          isSavings: false,
        ),
      ];
}
