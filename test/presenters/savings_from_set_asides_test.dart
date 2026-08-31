import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 060 — a goal's monthly target lives in one place: the Bills set-aside.
///
/// Two things under test. The Budget page reads the set-aside instead of
/// carrying a second copy of the number; and the forecast stops reserving that
/// money twice.

String get _month => toMonthKey(DateTime.now());

FinancialAccount _goal(String id, {double balance = 0}) => FinancialAccount(
      id: id,
      name: id,
      category: AccountCategory.goal,
      balance: balance,
      colorHex: '#46BD6B',
      icon: 'savings',
    );

Budget _savingsBudget(String accountId, double amount) => Budget(
      id: 'b_$accountId',
      categoryId: accountId,
      month: _month,
      allocatedAmount: amount,
      group: BudgetGroupDef.idSavings,
      budgetType: BudgetType.monthly,
    );

BudgetedExpense _setAside(
  String id, {
  required String destination,
  required double amount,
  bool isRecurring = true,
  bool isPaid = false,
  double spent = 0,
}) =>
    BudgetedExpense(
      id: id,
      name: id,
      budgetedType: SetAsideType.goal,
      month: _month,
      allocatedAmount: amount,
      spentAmount: spent,
      categoryId: 'savings_cat',
      destinationAccountId: destination,
      isPaid: isPaid,
      isRecurring: isRecurring,
    );

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;

  void stub({
    List<Budget> budgets = const [],
    List<FinancialAccount> accounts = const [],
    List<BudgetedExpense> setAsides = const [],
    List<TransactionRecord> transactions = const [],
  }) {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    when(storage.loadBudgets()).thenAnswer((_) async => budgets);
    when(storage.loadBudgetGroups())
        .thenAnswer((_) async => <BudgetGroupDef>[]);
    when(storage.loadFinanceCategories())
        .thenAnswer((_) async => <FinanceCategory>[]);
    when(storage.loadTransactions()).thenAnswer((_) async => transactions);
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => setAsides);
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(storage.saveBudgets(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  }

  group('the savings row reads the set-aside', () {
    test('a recurring set-aside becomes the target', () async {
      stub(
        accounts: [_goal('braces')],
        budgets: [_savingsBudget('braces', 1000)],
        setAsides: [_setAside('sa', destination: 'braces', amount: 3000)],
      );
      final p = BudgetPresenter(storage, stats, null, notifications);
      await p.load();
      p.debugSetSetAsides(
          [_setAside('sa', destination: 'braces', amount: 3000)]);

      expect(p.setAsideTargetFor('braces'), 3000,
          reason: 'the set-aside is the plan, not the stale budget row');
    });

    test('two recurring set-asides on one goal sum', () async {
      stub(accounts: [_goal('braces')]);
      final p = BudgetPresenter(storage, stats, null, notifications);
      await p.load();
      p.debugSetSetAsides([
        _setAside('a', destination: 'braces', amount: 2000),
        _setAside('b', destination: 'braces', amount: 1000),
      ]);

      expect(p.setAsideTargetFor('braces'), 3000,
          reason: 'two set-asides can legitimately fund one goal');
    });

    test('a one-off set-aside does NOT move the target', () async {
      // The case that broke an earlier draft: funding a goal twice in a month
      // when spare money turns up. Counting the extra would make the target
      // chase the actual — 5,000/5,000 instead of 5,000/3,000 — so a generous
      // month would look identical to a bare-minimum one.
      stub(accounts: [_goal('braces')]);
      final p = BudgetPresenter(storage, stats, null, notifications);
      await p.load();
      p.debugSetSetAsides([
        _setAside('planned', destination: 'braces', amount: 3000),
        _setAside('spare',
            destination: 'braces', amount: 2000, isRecurring: false),
      ]);

      expect(p.setAsideTargetFor('braces'), 3000);
    });

    test('no set-aside means no opinion — the row keeps its own amount',
        () async {
      stub(accounts: [_goal('rainy')]);
      final p = BudgetPresenter(storage, stats, null, notifications);
      await p.load();
      p.debugSetSetAsides(const []);

      expect(p.setAsideTargetFor('rainy'), isNull);
    });

    test('a set-aside for another account is ignored', () async {
      stub(accounts: [_goal('braces')]);
      final p = BudgetPresenter(storage, stats, null, notifications);
      await p.load();
      p.debugSetSetAsides([
        _setAside('other', destination: 'emergency', amount: 5000),
      ]);

      expect(p.setAsideTargetFor('braces'), isNull);
    });

    test('a set-aside from another month is ignored', () async {
      stub(accounts: [_goal('braces')]);
      final p = BudgetPresenter(storage, stats, null, notifications);
      await p.load();
      p.debugSetSetAsides([
        BudgetedExpense(
          id: 'old',
          name: 'old',
          budgetedType: SetAsideType.goal,
          month: '2020-01',
          allocatedAmount: 9000,
          spentAmount: 0,
          categoryId: 'savings_cat',
          destinationAccountId: 'braces',
          isRecurring: true,
        ),
      ]);

      expect(p.setAsideTargetFor('braces'), isNull);
    });
  });

  group('the forecast stops reserving the same peso twice', () {
    /// A ₱3,000 savings budget for Braces plus an unfunded ₱3,000 set-aside
    /// into Braces. Before this fix the forecast subtracted both.
    Future<TreasuryDashboardPresenter> dashboard() async {
      final p = TreasuryDashboardPresenter(storage);
      await p.load();
      return p;
    }

    test('an unfunded set-aside and its savings budget overlap', () async {
      stub(
        accounts: [_goal('braces', balance: 0)],
        budgets: [_savingsBudget('braces', 3000)],
        setAsides: [_setAside('sa', destination: 'braces', amount: 3000)],
      );
      final p = await dashboard();

      // The overlap is credited back in full: both terms reserved ₱3,000 for
      // the same intent, so exactly ₱3,000 must come back.
      expect(p.budgetRemainingNetOfObligations, 0,
          reason: 'the savings budget adds no marginal claim over the '
              'set-aside already counted');
    });

    test('a partly funded set-aside only overlaps what is still owed',
        () async {
      stub(
        accounts: [_goal('braces', balance: 0)],
        budgets: [_savingsBudget('braces', 3000)],
        setAsides: [
          _setAside('sa', destination: 'braces', amount: 3000, spent: 1000),
        ],
      );
      final p = await dashboard();

      // ₱2,000 still owed on the set-aside; the budget's ₱3,000 remaining is
      // credited back only to that extent.
      expect(p.budgetRemainingNetOfObligations, 1000);
    });

    test('a savings budget with no set-aside still claims its own', () async {
      stub(
        accounts: [_goal('rainy', balance: 0)],
        budgets: [_savingsBudget('rainy', 2000)],
      );
      final p = await dashboard();

      expect(p.budgetRemainingNetOfObligations, 2000,
          reason: 'nothing else reserved this, so it is a real claim');
    });

    test('a paid set-aside reserves nothing and credits nothing', () async {
      stub(
        accounts: [_goal('braces', balance: 0)],
        budgets: [_savingsBudget('braces', 3000)],
        setAsides: [
          _setAside('sa',
              destination: 'braces', amount: 3000, isPaid: true, spent: 3000),
        ],
      );
      final p = await dashboard();

      expect(p.budgetRemainingNetOfObligations, 3000);
    });
  });
}
