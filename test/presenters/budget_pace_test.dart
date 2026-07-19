import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../mocks.mocks.dart';

/// Covers the additive pace / safe-to-spend getters added for the Nudgr budget
/// hero. Uses month arithmetic that is deterministic for past/future months.
void main() {
  final currentMonth = toMonthKey(DateTime.now());
  const pastMonth = '2020-01';
  const futureMonth = '2999-01';

  Budget budget(String month, double alloc) => Budget(
        id: 'b-$month',
        categoryId: 'c1',
        month: month,
        allocatedAmount: alloc,
        group: 'essentials',
        budgetType: BudgetType.monthly,
      );

  Future<BudgetPresenter> build() async {
    final storage = MockStorageService();
    final stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadBudgets()).thenAnswer((_) async => [
          budget(currentMonth, 30000),
          budget(pastMonth, 10000),
        ]);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    final presenter = BudgetPresenter(storage, stats);
    await presenter.load();
    return presenter;
  }

  test('current month: pace + safe-to-spend are live', () async {
    final p = await build();
    expect(p.isCurrentMonth, isTrue);
    expect(p.totalAllocated, 30000);
    // No spending yet → ahead of pace, and elapsed fraction is within (0, 1].
    expect(p.isAheadOfPace, isTrue);
    expect(p.monthElapsedFraction, greaterThan(0));
    expect(p.monthElapsedFraction, lessThanOrEqualTo(1.0));
    expect(p.daysLeftInSelectedMonth, greaterThanOrEqualTo(0));
    // Remaining (30000) spread over the days left, or the raw remaining on the
    // last day.
    final days = p.daysLeftInSelectedMonth;
    final expected = days > 0 ? 30000 / days : 30000;
    expect(p.safeToSpendPerDay, closeTo(expected, 0.001));
  });

  test('past month: fully elapsed, no days left', () async {
    final p = await build();
    p.setMonth(pastMonth);
    expect(p.isCurrentMonth, isFalse);
    expect(p.monthElapsedFraction, 1.0);
    expect(p.daysLeftInSelectedMonth, 0);
    expect(p.totalAllocated, 10000);
    // Days left == 0 → falls back to the raw remaining (10000, nothing spent).
    expect(p.safeToSpendPerDay, 10000);
  });

  test('future month: nothing elapsed', () async {
    final p = await build();
    p.setMonth(futureMonth);
    expect(p.isCurrentMonth, isFalse);
    expect(p.monthElapsedFraction, 0.0);
    expect(p.isAheadOfPace, isTrue);
  });
}
