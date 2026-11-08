import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/account_archive_copy.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/goal_copy.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/goals_savings_screen.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_setup_view.dart';

import '../../../mocks.mocks.dart';

/// Plan 071 Phase 9 — mobile Setup and Goals: the goals hero reads the
/// presenter's goal figures, Start again shows on active goals, the funding
/// note links to Budget, and the account form offers Archive only for goals.
void main() {
  final month = toMonthKey(DateTime.now());

  FinancialAccount acct(
    String id,
    AccountCategory category, {
    double balance = 0,
    double? goalTarget,
    DateTime? fundedAt,
    DateTime? redeemedAt,
    String? parentId,
  }) =>
      FinancialAccount(
        id: id,
        name: id,
        category: category,
        balance: balance,
        colorHex: '#46BD6B',
        icon: category.name,
        goalTarget: goalTarget,
        goalFundedAt: fundedAt,
        goalRedeemedAt: redeemedAt,
        parentAccountId: parentId,
      );

  final bank = acct('bpi', AccountCategory.bank, balance: 50000);
  final phone = acct('phone', AccountCategory.goal,
      balance: 2700, goalTarget: 6000); // started
  final trip =
      acct('trip', AccountCategory.goal, goalTarget: 20000); // not started
  final bike = acct('bike', AccountCategory.goal,
      balance: 5000,
      goalTarget: 5000,
      fundedAt: DateTime(2026, 10, 1)); // reached
  final house = acct('house', AccountCategory.savings,
      balance: 25000, goalTarget: 100000); // savings with a target
  final emergency = acct('emergency', AccountCategory.savings, balance: 10000);
  final done = acct('done', AccountCategory.goal,
      goalTarget: 3000,
      fundedAt: DateTime(2026, 9, 1),
      redeemedAt: DateTime(2026, 10, 2)); // completed
  final invest = acct('invest', AccountCategory.investment, balance: 7000);
  final pocketInvest = acct('pocketInvest', AccountCategory.investment,
      balance: 1000, parentId: 'bpi');

  BudgetedExpense setAside(String id, double allocated, double spent) =>
      BudgetedExpense(
        id: id,
        name: id,
        budgetedType: SetAsideType.goal,
        month: month,
        allocatedAmount: allocated,
        spentAmount: spent,
        categoryId: '',
      );

  late MockStorageService storage;

  setUp(() {
    storage = MockStorageService();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          bank,
          phone,
          trip,
          bike,
          house,
          emergency,
          done,
          invest,
          pocketInvest,
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgets()).thenAnswer((_) async => []);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => [
          setAside('s1', 2000, 500),
          setAside('s2', 3000, 3000),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
  });

  Future<TreasuryDashboardPresenter> loaded() async {
    final p = TreasuryDashboardPresenter(storage);
    await p.load();
    return p;
  }

  group('goal figures on the presenter', () {
    test('match what the web _GoalsFigures used to compute', () async {
      final p = await loaded();
      expect(p.activeGoalAccounts.map((a) => a.id),
          ['phone', 'trip', 'bike', 'house']);
      expect(p.goalsActiveCount, 4);
      expect(p.goalsActiveFunded, 3);
      expect(
          p.startedGoalAccounts.map((a) => a.id), ['phone', 'bike', 'house']);
      expect(p.goalsNotStartedCount, 1);
      expect(p.notStartedGoalAccounts.single.id, 'trip');
      expect(p.goalSetAsidesThisMonth, 5000);
      expect(p.goalSetAsidesFundedThisMonth, 3500);
      expect(p.goalsSavedTowardTargets, 2700 + 5000 + 25000);
      expect(p.goalsTotalTarget, 6000 + 20000 + 5000 + 100000);
      expect(p.goalsShareOfTargets, closeTo(32700 / 131000, 1e-9));
      expect(p.plainSavingsAccounts.map((a) => a.id), ['emergency']);
      expect(p.activeInvestmentAccounts.map((a) => a.id),
          ['invest', 'pocketInvest']);
      expect(p.hasGoalsOrSavings, isTrue);
      // Completed first, then live goal accounts; a savings account with a
      // target has no lifecycle to restart.
      expect(p.restartableGoalAccounts.map((a) => a.id),
          ['done', 'phone', 'trip', 'bike']);
    });

    test('Archive and Start again are goal-only rules', () {
      expect(TreasuryDashboardPresenter.canArchiveAccount(phone), isTrue);
      expect(TreasuryDashboardPresenter.canArchiveAccount(done), isTrue);
      expect(TreasuryDashboardPresenter.canArchiveAccount(house), isFalse);
      expect(TreasuryDashboardPresenter.canArchiveAccount(bank), isFalse);
      expect(TreasuryDashboardPresenter.canStartAgain(trip), isTrue);
      expect(TreasuryDashboardPresenter.canStartAgain(house), isFalse);
    });
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    TreasuryDashboardPresenter p, {
    bool dark = true,
    VoidCallback? onOpenBudget,
  }) async {
    tester.view.physicalSize = const Size(360, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? buildDarkTheme() : buildLightTheme(),
      // The test font draws every glyph a full em wide; at this scale a 360 dp
      // width check means what it would with the real proportional font (the
      // same trick as the web Goals test).
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(0.55)),
        child: child!,
      ),
      home: GoalsSavingsScreen(presenter: p, onOpenBudget: onOpenBudget),
    ));
    await tester.pumpAndSettle();
  }

  Finder inCell(String key, String text) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.text(text),
      );

  group('Goals screen', () {
    for (final dark in [true, false]) {
      testWidgets(
          'hero shows the presenter figures at 360 dp '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        final p = await loaded();
        await pumpScreen(tester, p, dark: dark);

        expect(find.text(formatPeso(p.totalSavingsAndGoals)), findsOneWidget);
        expect(inCell('goals.hero.active', '${p.goalsActiveFunded} funded'),
            findsOneWidget);
        expect(inCell('goals.hero.active', 'of ${p.goalsActiveCount} goals'),
            findsOneWidget);
        expect(inCell('goals.hero.notStarted', '${p.goalsNotStartedCount}'),
            findsOneWidget);
        expect(
            inCell(
                'goals.hero.setAsides', formatPeso(p.goalSetAsidesThisMonth)),
            findsOneWidget);
        expect(
            inCell('goals.hero.setAsides',
                '${formatPeso(p.goalSetAsidesFundedThisMonth)} funded so far'),
            findsOneWidget);

        // The Add Goal button reads its text color from the theme.
        final fab = tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton));
        final cs = Theme.of(tester.element(find.byType(GoalsSavingsScreen)))
            .colorScheme;
        expect(fab.foregroundColor, cs.onPrimary);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Start again shows on active goals, not on savings',
        (tester) async {
      final p = await loaded();
      await pumpScreen(tester, p);

      // phone, trip and bike are goal accounts; house is savings with a
      // target and has nothing to restart.
      expect(find.byTooltip('Start again'), findsNWidgets(3));

      await tester.tap(find.byTooltip('Start again').first);
      await tester.pumpAndSettle();
      expect(find.text('Start phone again'), findsOneWidget);
      expect(find.text('NEW TARGET'), findsOneWidget);
    });

    testWidgets('restarting an active goal saves the new target',
        (tester) async {
      final p = await loaded();
      await pumpScreen(tester, p);

      await tester.tap(find.byTooltip('Start again').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '8000');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Start again').last);
      await tester.pumpAndSettle();

      final saved = verify(storage.saveAccounts(captureAny)).captured.last
          as List<FinancialAccount>;
      expect(saved.firstWhere((a) => a.id == 'phone').goalTarget, 8000);
      expect(find.text('Start phone again'), findsNothing);
    });

    testWidgets('funding note opens Budget and offers Start again for any goal',
        (tester) async {
      final p = await loaded();
      var opened = 0;
      await pumpScreen(tester, p, onOpenBudget: () => opened++);

      expect(find.text('How goals are funded'), findsOneWidget);
      expect(find.text(kGoalsFundingNote), findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('goals.fundingNote.openBudget')));
      await tester.pump();
      expect(opened, 1);

      await tester
          .tap(find.byKey(const ValueKey('goals.fundingNote.startAgain')));
      await tester.pumpAndSettle();
      expect(find.text('Start a goal again'), findsOneWidget);
      // Completed goals come first in the picker.
      expect(
          find.byKey(const ValueKey('goals.startAgain.goal')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('goals.startAgain.goal')),
              matching: find.text('done')),
          findsOneWidget);
    });

    testWidgets('with no Budget callback the note stays, the link goes',
        (tester) async {
      final p = await loaded();
      await pumpScreen(tester, p);

      expect(find.text(kGoalsFundingNote), findsOneWidget);
      expect(find.byKey(const ValueKey('goals.fundingNote.openBudget')),
          findsNothing);
    });
  });

  group('account form Archive', () {
    Future<TreasuryDashboardPresenter> pumpForm(
        WidgetTester tester, FinancialAccount existing) async {
      final p = await loaded();
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountSetupView(presenter: p, existing: existing),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return p;
    }

    const archive = ValueKey('accountSetup.archive');

    testWidgets('shows only for goal accounts', (tester) async {
      await pumpForm(tester, bank);
      expect(find.byKey(archive), findsNothing);

      await pumpForm(tester, house);
      expect(find.byKey(archive), findsNothing);

      await pumpForm(tester, phone);
      expect(find.byKey(archive), findsOneWidget);
    });

    testWidgets('confirms, then archives through the presenter',
        (tester) async {
      await pumpForm(tester, phone);
      await tester.ensureVisible(find.byKey(archive));
      await tester.tap(find.byKey(archive));
      await tester.pumpAndSettle();

      expect(find.text(accountArchiveTitle(phone)), findsOneWidget);
      expect(find.text(accountArchiveMessage(phone)), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();

      final saved = verify(storage.saveAccounts(captureAny)).captured.last
          as List<FinancialAccount>;
      expect(saved.firstWhere((a) => a.id == 'phone').isActive, isFalse);
    });
  });
}
