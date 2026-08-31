import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// A savings budget is a target; a set-aside is the transfer that fills it.
/// Setting one without the other leaves a fund planned but never funded — the
/// Budget page shows a goal and Bills has nothing to mark paid. The budget
/// sheet now offers the missing half at save time; this covers what it creates.

String get _month => toMonthKey(DateTime.now());

FinancialAccount _account(String id, AccountCategory category) =>
    FinancialAccount(
      id: id,
      name: 'Fund $id',
      category: category,
      balance: 0,
      colorHex: '#46BD6B',
      icon: 'savings',
    );

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;
  late MockBillsReceivablesPresenter bills;

  void stub({List<FinancialAccount> accounts = const []}) {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    bills = MockBillsReceivablesPresenter();
    when(storage.loadBudgets()).thenAnswer((_) async => <Budget>[]);
    when(storage.loadBudgetGroups())
        .thenAnswer((_) async => <BudgetGroupDef>[]);
    when(storage.loadFinanceCategories())
        .thenAnswer((_) async => <FinanceCategory>[]);
    when(storage.loadTransactions())
        .thenAnswer((_) async => <TransactionRecord>[]);
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.loadBudgetedExpenses())
        .thenAnswer((_) async => <BudgetedExpense>[]);
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(storage.saveBudgets(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    when(bills.addBudgetedExpense(any,
            applyToFuture: anyNamed('applyToFuture')))
        .thenAnswer((_) async {});
  }

  Future<BudgetPresenter> presenter() async {
    final p = BudgetPresenter(storage, stats, null, notifications, null, bills);
    await p.load();
    return p;
  }

  BudgetedExpense captureCreated() => verify(bills.addBudgetedExpense(
        captureAny,
        applyToFuture: anyNamed('applyToFuture'),
      )).captured.single as BudgetedExpense;

  group('creating the set-aside behind a savings budget', () {
    test('writes it through the owner, aimed at the budgeted account',
        () async {
      stub(accounts: [_account('braces', AccountCategory.goal)]);
      final p = await presenter();

      await p.createRecurringSetAsideFor('braces', 3000);

      final created = captureCreated();
      expect(created.destinationAccountId, 'braces',
          reason: 'the set-aside has to land in the fund it was offered for');
      expect(created.allocatedAmount, 3000);
      expect(created.name, 'Fund braces');
      expect(created.month, _month);
    });

    test('recurs monthly, so next month still derives a target', () async {
      // A one-off would fund this month and leave the row deriving its target
      // from nothing in October — setAsideTargetFor ignores non-recurring rows
      // by design.
      stub(accounts: [_account('braces', AccountCategory.goal)]);
      final p = await presenter();

      await p.createRecurringSetAsideFor('braces', 3000);

      final created = captureCreated();
      expect(created.isRecurring, isTrue);
      expect(created.recurrenceType, RecurrenceType.monthly);
    });

    test('carries no category — a set-aside is a transfer, not spending',
        () async {
      stub(accounts: [_account('braces', AccountCategory.goal)]);
      final p = await presenter();

      await p.createRecurringSetAsideFor('braces', 3000);

      expect(captureCreated().categoryId, isEmpty,
          reason: 'a category here would let the transfer eat an expense '
              'budget it never spent from');
    });

    test('names no funding account — the mark-paid sheet asks for it',
        () async {
      stub(accounts: [_account('braces', AccountCategory.goal)]);
      final p = await presenter();

      await p.createRecurringSetAsideFor('braces', 3000);

      expect(captureCreated().accountId, isNull,
          reason: 'guessing a source now is a worse answer than asking at '
              'funding time, when the user knows which account has the money');
    });

    test('a goal account produces a goal set-aside', () async {
      stub(accounts: [_account('braces', AccountCategory.goal)]);
      final p = await presenter();

      await p.createRecurringSetAsideFor('braces', 3000);

      expect(captureCreated().budgetedType, SetAsideType.goal);
    });

    test('a savings account produces a savings set-aside', () async {
      stub(accounts: [_account('emergency', AccountCategory.savings)]);
      final p = await presenter();

      await p.createRecurringSetAsideFor('emergency', 2500);

      expect(captureCreated().budgetedType, SetAsideType.savings);
    });

    test('an unknown account creates nothing', () async {
      stub(accounts: [_account('braces', AccountCategory.goal)]);
      final p = await presenter();

      await p.createRecurringSetAsideFor('ghost', 3000);

      verifyNever(bills.addBudgetedExpense(any,
          applyToFuture: anyNamed('applyToFuture')));
    });

    test('what it creates is what the row then derives its target from',
        () async {
      // The offer and the note are complements: after accepting, the fund is no
      // longer "no opinion" — it reads its target off the new set-aside, at the
      // amount just budgeted.
      stub(accounts: [_account('braces', AccountCategory.goal)]);
      final p = await presenter();
      expect(p.setAsideTargetFor('braces'), isNull);

      await p.createRecurringSetAsideFor('braces', 3000);
      p.debugSetSetAsides([captureCreated()]);

      expect(p.setAsideTargetFor('braces'), 3000);
      expect(p.setAsideSourcesFor('braces'), hasLength(1));
    });
  });
}
