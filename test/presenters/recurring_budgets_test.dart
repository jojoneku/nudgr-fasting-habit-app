import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 059 — a budget line set once keeps applying every month, until changed.
///
/// The rules under test, all of which are easy to get subtly wrong:
///   * a month with rows of its own is authoritative and never re-derived
///   * carry-forward only ever goes forward, never backfills history
///   * an edit is the new going rate: this month and later, never earlier
///   * deleting ends the series, so the line does not come back
///   * the "already materialised" and "not yet" paths must agree

Budget _budget(
  String categoryId,
  String month,
  double amount, {
  String? id,
  String? seriesId,
  bool isRecurring = true,
}) =>
    Budget(
      id: id ?? 'b_${categoryId}_$month',
      categoryId: categoryId,
      month: month,
      allocatedAmount: amount,
      group: BudgetGroupDef.idVariableOptional,
      budgetType: BudgetType.monthly,
      seriesId: seriesId ?? 'series_$categoryId',
      isRecurring: isRecurring,
    );

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;

  void stub({List<Budget> budgets = const []}) {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    when(storage.loadBudgets()).thenAnswer((_) async => budgets);
    when(storage.loadBudgetGroups())
        .thenAnswer((_) async => <BudgetGroupDef>[]);
    when(storage.loadFinanceCategories())
        .thenAnswer((_) async => <FinanceCategory>[]);
    when(storage.loadTransactions())
        .thenAnswer((_) async => <TransactionRecord>[]);
    when(storage.loadAccounts()).thenAnswer((_) async => <FinancialAccount>[]);
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(storage.saveBudgets(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  }

  Future<BudgetPresenter> presenterOn(String month) async {
    final p = BudgetPresenter(storage, stats, null, notifications);
    await p.load();
    p.setMonth(month);
    // setMonth fires carry-forward without awaiting so the tab switch stays
    // instant; let it settle before asserting.
    await Future.delayed(const Duration(milliseconds: 20));
    return p;
  }

  List<Budget> monthRows(BudgetPresenter p, String month) =>
      p.allBudgets.where((b) => b.month == month).toList();

  group('carry forward', () {
    test('an empty month is populated from the most recent earlier month',
        () async {
      stub(budgets: [
        _budget('food', '2026-08', 8000),
        _budget('fuel', '2026-08', 3000),
      ]);
      final p = await presenterOn('2026-09');

      final sept = monthRows(p, '2026-09');
      expect(sept, hasLength(2));
      expect(
        sept.map((b) => b.allocatedAmount).toList()..sort(),
        [3000, 8000],
      );
      expect(p.carriedFrom, '2026-08');
    });

    test('carried rows get their own ids but keep the series', () async {
      stub(budgets: [_budget('food', '2026-08', 8000)]);
      final p = await presenterOn('2026-09');

      final aug = monthRows(p, '2026-08').single;
      final sept = monthRows(p, '2026-09').single;
      expect(sept.id, isNot(aug.id),
          reason: 'two months are two rows, not one record in both');
      expect(sept.seriesId, aug.seriesId);
    });

    test('a month with rows of its own is never re-derived', () async {
      stub(budgets: [
        _budget('food', '2026-08', 8000),
        _budget('food', '2026-09', 5000, id: 'kept'),
      ]);
      final p = await presenterOn('2026-09');

      final sept = monthRows(p, '2026-09');
      expect(sept, hasLength(1));
      expect(sept.single.allocatedAmount, 5000,
          reason: 'modified means authoritative');
      expect(p.carriedFrom, isNull);
    });

    test('history is never backfilled', () async {
      stub(budgets: [_budget('food', '2026-08', 8000)]);
      final p = await presenterOn('2026-07');

      expect(monthRows(p, '2026-07'), isEmpty,
          reason: 'a past month with no budget had no budget');
      expect(p.carriedFrom, isNull);
    });

    test('a non-recurring row is left behind', () async {
      stub(budgets: [
        _budget('food', '2026-08', 8000),
        _budget('gift', '2026-08', 1500, isRecurring: false),
      ]);
      final p = await presenterOn('2026-09');

      final sept = monthRows(p, '2026-09');
      expect(sept, hasLength(1));
      expect(sept.single.categoryId, 'food');
    });

    test('it skips a gap month and carries from the latest with data',
        () async {
      stub(budgets: [
        _budget('food', '2026-06', 6000),
        _budget('food', '2026-08', 8000),
      ]);
      final p = await presenterOn('2026-09');

      expect(monthRows(p, '2026-09').single.allocatedAmount, 8000);
      expect(p.carriedFrom, '2026-08');
    });

    test('nothing at all stays nothing', () async {
      stub();
      final p = await presenterOn('2026-09');
      expect(p.allBudgets, isEmpty);
      expect(p.carriedFrom, isNull);
    });
  });

  group('editing is the new going rate', () {
    test('an edit reaches later months of the series', () async {
      stub(budgets: [
        _budget('food', '2026-09', 8000),
        _budget('food', '2026-10', 8000),
        _budget('food', '2026-11', 8000),
      ]);
      final p = await presenterOn('2026-09');

      await p.setBudget('food', 9000);

      expect(monthRows(p, '2026-09').single.allocatedAmount, 9000);
      expect(monthRows(p, '2026-10').single.allocatedAmount, 9000);
      expect(monthRows(p, '2026-11').single.allocatedAmount, 9000);
    });

    test('an edit never rewrites an earlier month', () async {
      stub(budgets: [
        _budget('food', '2026-08', 8000),
        _budget('food', '2026-09', 8000),
      ]);
      final p = await presenterOn('2026-09');

      await p.setBudget('food', 9000);

      expect(monthRows(p, '2026-08').single.allocatedAmount, 8000,
          reason: 'August is history');
    });

    test('a different series is untouched', () async {
      stub(budgets: [
        _budget('food', '2026-09', 8000),
        _budget('fuel', '2026-09', 3000),
        _budget('fuel', '2026-10', 3000),
      ]);
      final p = await presenterOn('2026-09');

      await p.setBudget('food', 9000);

      expect(monthRows(p, '2026-10').single.allocatedAmount, 3000);
    });

    test('materialised and not-yet-materialised months agree', () async {
      // The property that matters: October must read 9000 whether it already
      // existed when the edit happened or is carried afterwards.
      stub(budgets: [_budget('food', '2026-09', 8000)]);
      final p = await presenterOn('2026-09');
      await p.setBudget('food', 9000);

      p.setMonth('2026-10');
      await Future.delayed(const Duration(milliseconds: 20));

      expect(monthRows(p, '2026-10').single.allocatedAmount, 9000);
    });

    test('a brand-new row starts its own series and recurs', () async {
      stub();
      final p = await presenterOn('2026-09');

      await p.setBudget('food', 8000);

      final row = monthRows(p, '2026-09').single;
      expect(row.isRecurring, isTrue, reason: 'recurring is the default');
      expect(row.seriesId, isNotNull);
    });
  });

  group('deleting ends the series', () {
    test('later months go with it', () async {
      stub(budgets: [
        _budget('food', '2026-09', 8000),
        _budget('food', '2026-10', 8000),
      ]);
      final p = await presenterOn('2026-09');

      await p.removeBudget('food');

      expect(monthRows(p, '2026-09'), isEmpty);
      expect(monthRows(p, '2026-10'), isEmpty);
    });

    test('earlier months keep their history but stop recurring', () async {
      stub(budgets: [
        _budget('food', '2026-08', 8000),
        _budget('food', '2026-09', 8000),
      ]);
      final p = await presenterOn('2026-09');

      await p.removeBudget('food');

      final aug = monthRows(p, '2026-08').single;
      expect(aug.allocatedAmount, 8000, reason: 'August did have this budget');
      expect(aug.isRecurring, isFalse);
    });

    test('an ended series never re-materialises', () async {
      // The reason delete-ends-series needs no "deliberately emptied" marker.
      stub(budgets: [
        _budget('food', '2026-08', 8000),
        _budget('food', '2026-09', 8000),
      ]);
      final p = await presenterOn('2026-09');
      await p.removeBudget('food');

      p.setMonth('2026-10');
      await Future.delayed(const Duration(milliseconds: 20));

      expect(monthRows(p, '2026-10'), isEmpty);
    });

    test('a sibling line is unaffected', () async {
      stub(budgets: [
        _budget('food', '2026-09', 8000),
        _budget('fuel', '2026-09', 3000),
      ]);
      final p = await presenterOn('2026-09');

      await p.removeBudget('food');

      expect(monthRows(p, '2026-09').single.categoryId, 'fuel');
    });
  });

  group('just this month', () {
    test('switching off detaches the row from its series', () async {
      stub(budgets: [_budget('food', '2026-09', 8000)]);
      final p = await presenterOn('2026-09');

      await p.setBudgetRecurring('food', false);

      final row = monthRows(p, '2026-09').single;
      expect(row.isRecurring, isFalse);
      expect(row.seriesId, isNull,
          reason: 'a one-off still holding a series would be swept up by a '
              'later "and future" edit of its old siblings');
    });

    test('a one-off does not carry forward', () async {
      stub(budgets: [_budget('food', '2026-09', 8000)]);
      final p = await presenterOn('2026-09');
      await p.setBudgetRecurring('food', false);

      p.setMonth('2026-10');
      await Future.delayed(const Duration(milliseconds: 20));

      expect(monthRows(p, '2026-10'), isEmpty);
    });

    test('switching back on restores a series', () async {
      stub(budgets: [
        _budget('food', '2026-09', 8000, seriesId: null, isRecurring: false),
      ]);
      final p = await presenterOn('2026-09');

      await p.setBudgetRecurring('food', true);

      final row = monthRows(p, '2026-09').single;
      expect(row.isRecurring, isTrue);
      expect(row.seriesId, isNotNull);
    });
  });

  group('rows written before this feature', () {
    test('load as one-offs rather than starting to propagate', () {
      // No seriesId, no isRecurring in the stored JSON — a budget set months
      // ago must not retroactively start filling future months unasked.
      final legacy = Budget.fromJson({
        'id': 'old',
        'categoryId': 'food',
        'month': '2026-08',
        'allocatedAmount': 8000.0,
        'group': BudgetGroupDef.idVariableOptional,
        'budgetType': 'monthly',
      });

      expect(legacy.seriesId, isNull);
      expect(legacy.isRecurring, isFalse);
    });

    test('round-trip preserves the new fields', () {
      final b = _budget('food', '2026-09', 8000);
      final back = Budget.fromJson(b.toJson());
      expect(back.seriesId, b.seriesId);
      expect(back.isRecurring, isTrue);
    });
  });
}
