import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/budget_status.dart';

/// Plan 071 Phase 2: one budget status rule for mobile and web.
void main() {
  group('budgetStatusFor — expense rows', () {
    final cases = <({double spent, BudgetStatus status, String label})>[
      (spent: 0, status: BudgetStatus.onTrack, label: 'On track'),
      (spent: 740, status: BudgetStatus.onTrack, label: 'On track'),
      (spent: 750, status: BudgetStatus.watch, label: 'Watch · 75%'),
      // Exactly at the limit is not "over" — there is nothing to be over by.
      (spent: 1000, status: BudgetStatus.watch, label: 'Watch · 100%'),
      (spent: 2200, status: BudgetStatus.over, label: 'Over by ₱1,200'),
    ];
    for (final c in cases) {
      test('₱${c.spent} of ₱1,000 → ${c.label}', () {
        final s = budgetStatusFor(allocated: 1000, spent: c.spent);
        expect(s.status, c.status);
        expect(s.label, c.label);
      });
    }

    test('spending with no allocation reads "No budget set", not over', () {
      final s = budgetStatusFor(allocated: 0, spent: 300);
      expect(s.status, BudgetStatus.watch);
      expect(s.label, 'No budget set');
    });

    test('nothing allocated and nothing spent is on track', () {
      expect(
          budgetStatusFor(allocated: 0, spent: 0).status, BudgetStatus.onTrack);
    });

    test('the watch boundary is the shared threshold', () {
      expect(kBudgetWatchThreshold, 0.75);
    });
  });

  group('budgetStatusFor — savings rows', () {
    test('never over: funding past the target is Funded', () {
      final s =
          budgetStatusFor(allocated: 1000, spent: 1500, accountBacked: true);
      expect(s.status, BudgetStatus.funded);
      expect(s.label, 'Funded');
    });
    test('below the target is On track, even past the watch line', () {
      final s =
          budgetStatusFor(allocated: 1000, spent: 900, accountBacked: true);
      expect(s.status, BudgetStatus.onTrack);
    });
  });

  group('budgetStatusFor — income rows', () {
    test('received in full reads Received', () {
      final s = budgetStatusFor(allocated: 50000, spent: 50000, isIncome: true);
      expect(s.status, BudgetStatus.funded);
      expect(s.label, 'Received');
    });
    test('partly received says what is still to come', () {
      final s = budgetStatusFor(allocated: 50000, spent: 20000, isIncome: true);
      expect(s.status, BudgetStatus.onTrack);
      expect(s.label, '₱30,000 to come');
    });
  });

  group('budgetGroupUsedLabel', () {
    test('expense group shows percent used', () {
      expect(
        budgetGroupUsedLabel(allocated: 1000, spent: 820, isSavings: false),
        '82% used',
      );
    });
    test('savings group shows percent funded, then Funded', () {
      expect(
        budgetGroupUsedLabel(allocated: 1000, spent: 400, isSavings: true),
        '40% funded',
      );
      expect(
        budgetGroupUsedLabel(allocated: 1000, spent: 1000, isSavings: true),
        'Funded',
      );
    });
    test('empty when nothing is allocated', () {
      expect(
        budgetGroupUsedLabel(allocated: 0, spent: 50, isSavings: false),
        '',
      );
    });
  });
}
