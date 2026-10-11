import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/dev/preview_seed.dart';
import 'package:intermittent_fasting/views/web/pages/goals/web_goals_page.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:intermittent_fasting/views/web/widgets/web_widgets.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

/// The v2 Goals page (Plan 063, Phase 9) against the preview seed: one card
/// per goal account, the hero carries the presenter's saved total, a goal
/// with nothing in it hands "Set a monthly amount" to the integrator, Add goal
/// and Start again call the presenter through the kit dialogs, and the
/// funding note's links fire their callbacks — at three widths, dark and light.
void main() {
  const widths = [1440.0, 1100.0, 760.0];
  const modes = [true, false];
  String mode(bool dark) => dark ? 'dark' : 'light';

  late LocalStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
    await storage.setUserId(PreviewSeed.userId);
    await PreviewSeed.seedInto(storage);
  });

  /// Builds the seeded presenter on the real clock, as the Dashboard test does.
  Future<TreasuryDashboardPresenter> seeded(WidgetTester tester) async {
    late TreasuryDashboardPresenter dash;
    await tester.runAsync(() async {
      dash = TreasuryDashboardPresenter(storage);
      await dash.load();
    });
    return dash;
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required TreasuryDashboardPresenter presenter,
    double width = 1440,
    bool dark = true,
    VoidCallback? onOpenBudget,
    VoidCallback? onOpenSetup,
    ValueChanged<FinancialAccount>? onSetMonthlyAmount,
  }) async {
    // Tall enough that nothing needs scrolling into view before a tap.
    tester.view.physicalSize = Size(width, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? buildWebDarkTheme() : buildWebLightTheme(),
      home: Scaffold(
        body: WebGoalsPage(
          presenter: presenter,
          onOpenBudget: onOpenBudget ?? () {},
          onOpenSetup: onOpenSetup ?? () {},
          onSetMonthlyAmount: onSetMonthlyAmount ?? (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Every key the page attaches with seeded data.
  const parityKeys = <Key>[
    WebKeys.goalsAddGoal,
    WebKeys.goalsHero,
    WebKeys.goalsGrid,
    WebKeys.goalsSavingsTable,
    WebKeys.goalsFundingNote,
    WebGoalsKeys.openBudget,
    WebGoalsKeys.manageSetup,
    WebGoalsKeys.noteStartAgain,
  ];

  group('parity', () {
    for (final dark in modes) {
      for (final width in widths) {
        testWidgets(
            'header, hero, cards and keys at $width px in ${mode(dark)}',
            (tester) async {
          final dash = await seeded(tester);
          await pumpPage(tester, presenter: dash, width: width, dark: dark);

          expect(find.text('Goals'), findsOneWidget);
          expect(find.text('Add goal'), findsOneWidget);
          for (final key in parityKeys) {
            expect(find.byKey(key), findsOneWidget, reason: '$key');
          }

          // One card per goal account — the seed's 8, none completed yet.
          final goals = dash.activeGoalAccounts;
          final completed = dash.completedGoalAccounts;
          expect(goals, hasLength(8));
          expect(find.byType(WebGoalCard),
              findsNWidgets(goals.length + completed.length));
          for (final a in goals) {
            expect(find.text(a.name), findsOneWidget, reason: a.name);
          }

          // 4 funded, 4 not started: the pill, the dashed card's action and
          // the strip all agree.
          final notStarted = goals.where((a) => a.balance <= 0).length;
          expect(notStarted, 4);
          expect(find.widgetWithText(WebBadge, 'Not started'),
              findsNWidgets(notStarted));
          expect(find.byKey(WebKeys.goalsCardSetMonthly),
              findsNWidgets(notStarted));
          expect(
              find.text('${goals.length - notStarted} funded'), findsOneWidget);

          // Hero total is the presenter's figure, to the centavo.
          expect(find.text('TOTAL SAVED'), findsOneWidget);
          expect(
              find.text(formatPeso(dash.totalSavingsAndGoals)), findsOneWidget);
          expect(
            find.text(
                '${formatPesoSigned(dash.monthSavingsContributions)} this month'
                ' · ${formatPercent(goals.fold(0.0, (s, a) => s + a.balance) / goals.fold(0.0, (s, a) => s + (a.goalTarget ?? 0)))} of all targets'),
            findsOneWidget,
          );

          for (final title in [
            'Savings & investments',
            'How goals are funded',
            'Open the Savings rows in Budget',
            'Manage in Setup ›',
          ]) {
            expect(find.text(title), findsOneWidget, reason: title);
          }
          // Plain savings and investments sit in the table, not the grid.
          for (final a
              in dash.savingsAccounts.where((a) => (a.goalTarget ?? 0) <= 0)) {
            expect(find.text(a.name), findsOneWidget, reason: a.name);
          }
          expect(find.text('Investment'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('set a monthly amount', () {
    testWidgets('hands the not-started goal to the integrator', (tester) async {
      final dash = await seeded(tester);
      final received = <FinancialAccount>[];
      await pumpPage(tester, presenter: dash, onSetMonthlyAmount: received.add);

      await tester.tap(find.byKey(WebKeys.goalsCardSetMonthly).first);
      await tester.pump();

      expect(received, hasLength(1));
      expect(received.single.balance, lessThanOrEqualTo(0));
      expect(dash.activeGoalAccounts.map((a) => a.id),
          contains(received.single.id));
    });
  });

  group('add goal', () {
    testWidgets(
        'opens the dialog and submitting adds the goal via the presenter',
        (tester) async {
      final dash = await seeded(tester);
      await pumpPage(tester, presenter: dash);
      final before = dash.activeGoalAccounts.length;

      await tester.tap(find.byKey(WebKeys.goalsAddGoal));
      await tester.pumpAndSettle();

      expect(find.byKey(WebGoalsKeys.addGoalDialog), findsOneWidget);
      expect(
          find.text(
              'A fund with a target. It is funded through budget set-asides.'),
          findsOneWidget);
      expect(find.text('Stored in'), findsOneWidget);

      // Required fields are enforced before the presenter is touched.
      await tester.tap(find.byKey(WebGoalsKeys.addGoalSubmit));
      await tester.pumpAndSettle();
      expect(find.text('Give the goal a name'), findsOneWidget);
      expect(find.text('Enter a target above ₱0'), findsOneWidget);
      expect(dash.activeGoalAccounts, hasLength(before));

      await tester.enterText(
          find.byKey(WebGoalsKeys.addGoalName), 'Laptop Fund');
      await tester.enterText(find.byKey(WebGoalsKeys.addGoalTarget), '45000');
      await tester.tap(find.byKey(WebGoalsKeys.addGoalSubmit));
      await tester.pumpAndSettle();

      expect(find.byKey(WebGoalsKeys.addGoalDialog), findsNothing);
      final added =
          dash.activeGoalAccounts.where((a) => a.name == 'Laptop Fund').single;
      expect(added.category, AccountCategory.goal);
      expect(added.goalTarget, 45000);
      expect(added.balance, 0);
      expect(added.parentAccountId, isNull);
      // The new goal shows up as a not-started card.
      expect(find.byType(WebGoalCard), findsNWidgets(before + 1));
      expect(find.text('Laptop Fund'), findsOneWidget);
      expect(find.text('Added Laptop Fund'), findsOneWidget);
    });
  });

  group('start again', () {
    testWidgets('card menu shows the confirm with the real copy and restarts',
        (tester) async {
      final dash = await seeded(tester);
      await pumpPage(tester, presenter: dash);
      final goal = dash.activeGoalAccounts.first;

      await tester.tap(find.byKey(WebGoalsKeys.cardMenu).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WebKeys.goalsCardStartAgain));
      await tester.pumpAndSettle();

      expect(find.byKey(WebGoalsKeys.startAgainDialog), findsOneWidget);
      expect(find.text('Start ${goal.name} again'), findsOneWidget);
      expect(
        find.text('Clears the completed stamp and starts tracking toward a new '
            'target. The account and everything in its history stay put.'),
        findsOneWidget,
      );
      // The current target is offered as the starting point.
      expect(find.text(goal.goalTarget!.toStringAsFixed(2)), findsOneWidget);

      await tester.enterText(
          find.byKey(WebGoalsKeys.startAgainTarget), '99000');
      await tester.tap(find.byKey(WebGoalsKeys.startAgainSubmit));
      await tester.pumpAndSettle();

      expect(find.byKey(WebGoalsKeys.startAgainDialog), findsNothing);
      final after = dash.activeGoalAccounts.firstWhere((a) => a.id == goal.id);
      expect(after.goalTarget, 99000);
      expect(after.goalRedeemedAt, isNull);
      expect(
          find.text('${goal.name} is tracking a new target'), findsOneWidget);
    });

    testWidgets('the funding note\'s "Start again…" asks which goal first',
        (tester) async {
      final dash = await seeded(tester);
      await pumpPage(tester, presenter: dash);

      await tester.tap(find.byKey(WebGoalsKeys.noteStartAgain));
      await tester.pumpAndSettle();

      expect(find.byKey(WebGoalsKeys.startAgainDialog), findsOneWidget);
      expect(find.text('Start a goal again'), findsOneWidget);
      expect(find.byKey(WebGoalsKeys.startAgainGoal), findsOneWidget);
      expect(find.byKey(WebGoalsKeys.startAgainTarget), findsOneWidget);
    });
  });

  group('links', () {
    testWidgets('"Open the Savings rows in Budget" fires onOpenBudget',
        (tester) async {
      final dash = await seeded(tester);
      var opened = 0;
      await pumpPage(tester, presenter: dash, onOpenBudget: () => opened++);

      await tester.tap(find.byKey(WebGoalsKeys.openBudget));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('"Manage in Setup ›" fires onOpenSetup', (tester) async {
      final dash = await seeded(tester);
      var opened = 0;
      await pumpPage(tester, presenter: dash, onOpenSetup: () => opened++);

      await tester.tap(find.byKey(WebGoalsKeys.manageSetup));
      await tester.pump();
      expect(opened, 1);
    });
  });

  group('empty state', () {
    testWidgets('offers "Add goal" when there are no goals or savings',
        (tester) async {
      final empty = MockStorageService();
      when(empty.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(empty.loadAccounts()).thenAnswer((_) async => <FinancialAccount>[]);
      when(empty.loadTransactions())
          .thenAnswer((_) async => <TransactionRecord>[]);
      when(empty.loadBills()).thenAnswer((_) async => []);
      when(empty.loadReceivables()).thenAnswer((_) async => []);
      when(empty.loadBudgets()).thenAnswer((_) async => []);
      when(empty.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(empty.loadFinanceCategories()).thenAnswer((_) async => []);
      when(empty.loadBudgetGroups()).thenAnswer((_) async => []);
      when(empty.loadMonthlySummaries())
          .thenAnswer((_) async => <MonthlySummary>[]);
      when(empty.saveMonthlySummaries(any)).thenAnswer((_) async {});
      when(empty.saveAccounts(any)).thenAnswer((_) async {});
      final dash = TreasuryDashboardPresenter(empty);
      await dash.load();

      await pumpPage(tester, presenter: dash);

      expect(find.text('No goals yet'), findsOneWidget);
      expect(find.byKey(WebGoalsKeys.emptyAddGoal), findsOneWidget);
      expect(find.byKey(WebKeys.goalsHero), findsNothing);
      expect(find.byType(WebGoalCard), findsNothing);

      await tester.tap(find.byKey(WebGoalsKeys.emptyAddGoal));
      await tester.pumpAndSettle();
      expect(find.byKey(WebGoalsKeys.addGoalDialog), findsOneWidget);
      // No liquid accounts to store it in, so the field is not offered.
      expect(find.text('Stored in'), findsNothing);
    });
  });
}
