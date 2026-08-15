import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../mocks.mocks.dart';

/// Editing a goal or a budget on one page has to show up on the others.
///
/// The presenters each keep their own copy of the treasury data, so a write
/// that only touches its owner leaves every other page rendering pre-edit
/// numbers — with no reload in sight if the other page isn't a sibling tab
/// (the Hub's Finance card, for one, never reloads on its own).
void main() {
  const month = '2026-03';

  FinancialAccount goal({
    required String id,
    String name = 'Emergency Fund',
    double balance = 5000,
    double? goalTarget,
    AccountCategory category = AccountCategory.goal,
  }) =>
      FinancialAccount(
        id: id,
        name: name,
        category: category,
        balance: balance,
        colorHex: '#FFFFFF',
        icon: 'wallet',
        goalTarget: goalTarget,
      );

  late MockStorageService storage;
  late MockStatsPresenter stats;

  /// In-memory storage: writes land where the next read will see them, which is
  /// the whole point — these tests are about one presenter reading another's
  /// persisted state.
  late List<FinancialAccount> accounts;
  late List<Budget> budgets;
  late List<BudgetGroupDef> groups;

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    accounts = [goal(id: 'ef', goalTarget: 20000)];
    budgets = <Budget>[];
    groups = <BudgetGroupDef>[];

    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());

    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.saveAccounts(any)).thenAnswer((inv) async {
      accounts = List<FinancialAccount>.from(
          inv.positionalArguments.first as List<FinancialAccount>);
    });
    when(storage.loadBudgets()).thenAnswer((_) async => budgets);
    when(storage.saveBudgets(any)).thenAnswer((inv) async {
      budgets =
          List<Budget>.from(inv.positionalArguments.first as List<Budget>);
    });
    when(storage.loadBudgetGroups()).thenAnswer((_) async => groups);
    when(storage.saveBudgetGroups(any)).thenAnswer((inv) async {
      groups = List<BudgetGroupDef>.from(
          inv.positionalArguments.first as List<BudgetGroupDef>);
    });
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          FinanceCategory(
            id: 'food',
            name: 'Food',
            type: CategoryType.expense,
            icon: 'tag',
            colorHex: '#FFFFFF',
          ),
        ]);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(storage.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
  });

  /// Builds the mobile wiring: ledger → dashboard → budget, with the dependent
  /// refresh the composition roots install.
  Future<
      ({
        LedgerPresenter ledger,
        TreasuryDashboardPresenter dashboard,
        BudgetPresenter budget,
      })> buildStack({bool wireDependents = true}) async {
    final ledger = LedgerPresenter(storage, stats);
    final dashboard = TreasuryDashboardPresenter(storage, ledger);
    final budget = BudgetPresenter(storage, stats, ledger);
    if (wireDependents) {
      budget.onBudgetsChanged = dashboard.reloadBudgets;
    }
    await dashboard.load();
    await budget.load();
    var guard = 0;
    while (ledger.isLoading && guard++ < 50) {
      await Future<void>.delayed(Duration.zero);
    }
    return (ledger: ledger, dashboard: dashboard, budget: budget);
  }

  group('editing a goal', () {
    test('reaches the ledger and the budget page, not just the dashboard',
        () async {
      final s = await buildStack();

      // The Goals page edits through the dashboard presenter.
      await s.dashboard.updateAccount(
        goal(
            id: 'ef', name: 'Emergency Fund', balance: 5000, goalTarget: 50000),
      );

      expect(s.dashboard.goalAccounts.single.goalTarget, 50000,
          reason: 'the page you edited on');
      expect(s.ledger.accounts.single.goalTarget, 50000,
          reason: 'the ledger holds the authoritative account list');
      expect(s.budget.savingsTargets.single.goalTarget, 50000,
          reason: 'the Budget page lists goals as savings targets');
    });

    test('a renamed goal is renamed everywhere', () async {
      final s = await buildStack();

      await s.dashboard.updateAccount(goal(id: 'ef', name: 'House Fund'));

      expect(s.dashboard.goalAccounts.single.name, 'House Fund');
      expect(s.ledger.accounts.single.name, 'House Fund');
      expect(s.budget.savingsTargets.single.name, 'House Fund');
    });

    test('a newly added goal appears on the other pages', () async {
      final s = await buildStack();

      await s.dashboard
          .addAccount(goal(id: 'car', name: 'Car', goalTarget: 300000));

      expect(s.dashboard.goalAccounts.map((a) => a.id), contains('car'));
      expect(s.ledger.accounts.map((a) => a.id), contains('car'));
      expect(s.budget.savingsTargets.map((a) => a.id), contains('car'));
    });
  });

  group('editing a budget', () {
    test('updates the dashboard totals and its month-end projection', () async {
      final s = await buildStack();
      s.budget.setMonth(month);
      // The dashboard forecasts against the CURRENT real month, so budget in
      // that month to exercise the figures the Hub card reads.
      final live = toMonthKey(DateTime.now());
      s.budget.setMonth(live);

      expect(s.dashboard.totalBudgetAllocated, 0);
      final projectionBefore = s.dashboard.forecastedNetBalance;

      await s.budget.setBudget('food', 4000);

      expect(s.dashboard.totalBudgetAllocated, 4000,
          reason: 'the dashboard keeps its own copy of the budgets');
      expect(s.dashboard.totalBudgetRemaining, 4000);
      // forecastedNetBalance reserves the unspent budget, and the Hub's
      // Finance card renders exactly this number.
      expect(s.dashboard.forecastedNetBalance, projectionBefore - 4000);
    });

    test('removing a budget updates the dashboard too', () async {
      final s = await buildStack();
      s.budget.setMonth(toMonthKey(DateTime.now()));
      await s.budget.setBudget('food', 4000);
      expect(s.dashboard.totalBudgetAllocated, 4000);

      await s.budget.removeBudget('food');

      expect(s.dashboard.totalBudgetAllocated, 0);
    });

    test('a new budget group reaches the dashboard', () async {
      final s = await buildStack();

      await s.budget.addGroup('Sinking Funds');

      expect(s.dashboard.budgetGroups.map((g) => g.name),
          contains('Sinking Funds'));
    });

    test('a renamed group is renamed on the dashboard', () async {
      final s = await buildStack();
      await s.budget.addGroup('Sinking Funds');
      final added =
          s.budget.groups.firstWhere((g) => g.name == 'Sinking Funds');

      await s.budget.renameGroup(added.id, 'Big Purchases');

      expect(s.dashboard.budgetGroups.map((g) => g.name),
          contains('Big Purchases'));
      expect(s.dashboard.budgetGroups.map((g) => g.name),
          isNot(contains('Sinking Funds')));
    });

    test('without the dependent wiring the dashboard goes stale — the bug',
        () async {
      final s = await buildStack(wireDependents: false);
      s.budget.setMonth(toMonthKey(DateTime.now()));

      await s.budget.setBudget('food', 4000);

      // Pins the regression: this is exactly what the user saw before the
      // composition roots started wiring onBudgetsChanged.
      expect(s.dashboard.totalBudgetAllocated, 0);
    });
  });
}
