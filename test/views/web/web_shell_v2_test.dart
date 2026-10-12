import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/presenters/auth_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/services/auth_service.dart';
import 'package:intermittent_fasting/views/web/design/web_breakpoints.dart';
import 'package:intermittent_fasting/views/web/design/web_dest.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/pages/more/web_more_page.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:intermittent_fasting/views/web/widgets/web_shell_v2.dart';

import '../../mocks.mocks.dart';

/// The Treasury web v2 shell (Plan 063, Phase 1): the grouped nav rail, the
/// account row, the right rail vs the dock, and the destination ↔ mobile tab
/// mapping that lets the narrow layout keep Cart while the desktop drops it.
void main() {
  const email = 'eljon@example.com';

  Future<void> pumpShell(
    WidgetTester tester, {
    double width = 1440,
    WebDest selected = WebDest.dashboard,
    ValueChanged<WebDest>? onSelect,
    VoidCallback? onSignOut,
    int billsDueCount = 0,
    Widget? rightRail,
    Widget? dock,
    String? displayName,
    bool dark = true,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? buildWebDarkTheme() : buildWebLightTheme(),
      home: WebShellV2(
        selected: selected,
        onSelect: onSelect ?? (_) {},
        billsDueCount: billsDueCount,
        email: email,
        displayName: displayName,
        onSignOut: onSignOut ?? () {},
        isDark: dark,
        onToggleTheme: () {},
        rightRail: rightRail,
        dock: dock,
        child: const Center(child: Text('page body')),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('WebDest', () {
    test('maps every destination to its mobile tab, Setup to More (7)', () {
      expect(WebDest.dashboard.mobileTabIndex, 0);
      expect(WebDest.ledger.mobileTabIndex, 1);
      expect(WebDest.bills.mobileTabIndex, 2);
      expect(WebDest.budget.mobileTabIndex, 3);
      expect(WebDest.history.mobileTabIndex, 4);
      expect(WebDest.goals.mobileTabIndex, 6);
      expect(WebDest.setup.mobileTabIndex, 7);
    });

    test('Cart (5) has no desktop destination', () {
      expect(WebDest.fromMobileTabIndex(5), isNull);
    });

    test('round-trips every destination through its mobile index', () {
      for (final d in WebDest.values) {
        expect(WebDest.fromMobileTabIndex(d.mobileTabIndex), d);
      }
    });

    test('groups: Overview, Money ×3, Plan, Review; Setup in none', () {
      expect(WebDest.inGroup(WebNavGroup.overview), [WebDest.dashboard]);
      expect(WebDest.inGroup(WebNavGroup.money),
          [WebDest.ledger, WebDest.bills, WebDest.budget]);
      expect(WebDest.inGroup(WebNavGroup.plan), [WebDest.goals]);
      expect(WebDest.inGroup(WebNavGroup.review), [WebDest.history]);
      expect(WebDest.setup.group, isNull);
    });
  });

  group('WebShellV2 nav rail', () {
    for (final dark in [true, false]) {
      testWidgets(
          'lists the 7 destinations under 4 groups, with no Cart '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        await pumpShell(tester, dark: dark);

        for (final d in WebDest.values) {
          expect(find.text(d.label), findsOneWidget, reason: d.label);
        }
        expect(find.text('Cart'), findsNothing);
        for (final g in WebNavGroup.values) {
          expect(find.text(g.label.toUpperCase()), findsOneWidget,
              reason: g.label);
        }
        expect(find.text('Treasury'), findsOneWidget);
        expect(find.text('page body'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the rail is 232 wide and carries no top bar title',
        (tester) async {
      await pumpShell(tester, selected: WebDest.ledger);
      // One "Ledger": the nav item. The shell prints no page title of its own.
      expect(find.text('Ledger'), findsOneWidget);
      final rail = tester.getRect(find.byKey(WebKeys.navLedger));
      expect(rail.right, lessThanOrEqualTo(WebShellV2.navWidth));
    });

    testWidgets('selecting a destination fires onSelect', (tester) async {
      WebDest? picked;
      await pumpShell(tester, onSelect: (d) => picked = d);

      await tester.tap(find.byKey(WebKeys.navLedger));
      expect(picked, WebDest.ledger);
      await tester.tap(find.byKey(WebKeys.navSetup));
      expect(picked, WebDest.setup);
    });

    testWidgets('the Bills pill shows the due count and hides at zero',
        (tester) async {
      await pumpShell(tester, billsDueCount: 3);
      expect(find.byKey(WebKeys.navBillsDuePill), findsOneWidget);
      expect(find.text('3 due'), findsOneWidget);

      await pumpShell(tester, billsDueCount: 0);
      expect(find.byKey(WebKeys.navBillsDuePill), findsNothing);
      expect(find.textContaining('due'), findsNothing);
    });

    testWidgets('the sync row is hidden without a sync presenter',
        (tester) async {
      await pumpShell(tester);
      expect(find.byKey(WebKeys.navSyncStatus), findsNothing);
      expect(find.byKey(WebKeys.navThemeToggle), findsOneWidget);
    });

    testWidgets('the theme toggle names the mode it switches to',
        (tester) async {
      await pumpShell(tester, dark: true);
      expect(find.byTooltip('Switch to light mode'), findsOneWidget);
      await pumpShell(tester, dark: false);
      expect(find.byTooltip('Switch to dark mode'), findsOneWidget);
    });
  });

  group('WebShellV2 account row', () {
    testWidgets('shows the email local part when there is no display name',
        (tester) async {
      await pumpShell(tester);
      expect(find.text('eljon'), findsOneWidget);
      expect(find.text('E'), findsOneWidget); // avatar initial
      // The full email is in the menu, not on the rail.
      expect(find.text(email), findsNothing);
    });

    testWidgets('prefers the display name', (tester) async {
      await pumpShell(tester, displayName: 'Eljon B.');
      expect(find.text('Eljon B.'), findsOneWidget);
      expect(find.text('eljon'), findsNothing);
    });

    testWidgets('the menu shows the full email and Sign out fires the callback',
        (tester) async {
      var signedOut = 0;
      await pumpShell(tester, onSignOut: () => signedOut++);

      await tester.tap(find.byKey(WebKeys.navAccountMenu));
      await tester.pumpAndSettle();

      expect(find.text(email), findsOneWidget);
      expect(find.byKey(WebKeys.navSignOut), findsOneWidget);

      await tester.tap(find.byKey(WebKeys.navSignOut));
      await tester.pumpAndSettle();
      expect(signedOut, 1);
    });
  });

  group('WebShellV2 right rail vs dock', () {
    const rail = SizedBox(width: 200, child: Text('rail'));
    const dock = SizedBox(width: 56, child: Text('dock'));

    testWidgets('the right rail scales with the window, 340–440 px',
        (tester) async {
      expect(WebShellV2.railWidthFor(1280), WebShellV2.minRailWidth);
      expect(WebShellV2.railWidthFor(1600), closeTo(384, 0.01));
      expect(WebShellV2.railWidthFor(2560), WebShellV2.maxRailWidth);

      for (final w in [WebBreakpoints.rightRail, 1600.0, 2560.0]) {
        await pumpShell(tester, width: w, rightRail: rail, dock: dock);
        expect(find.text('rail'), findsOneWidget);
        expect(find.text('dock'), findsNothing);
        // The rail column, padding included, is railWidthFor(window) wide.
        final railRect = tester.getRect(find.text('rail'));
        final window = tester.getRect(find.byType(WebShellV2));
        expect(window.right - railRect.left,
            closeTo(WebShellV2.railWidthFor(w), 0.01),
            reason: 'at $w px');
      }
    });

    testWidgets('beside the rail the page fills the width — no dead strip',
        (tester) async {
      const w = 1848.0; // the owner's window
      await pumpShell(tester, width: w, rightRail: rail, dock: dock);
      final body = tester.getRect(find.text('page body'));
      final railLeft = w - WebShellV2.railWidthFor(w);
      // The page column runs nav edge + 40 → rail edge − 24; its centred
      // body sits at that column's midpoint, not at a 1200 px cap's.
      final columnMid = ((WebShellV2.navWidth + 40) + (railLeft - 24)) / 2;
      expect(body.center.dx, closeTo(columnMid, 1));
    });

    testWidgets('at 1100 the rail folds away and the dock is used',
        (tester) async {
      await pumpShell(tester, width: 1100, rightRail: rail, dock: dock);
      expect(find.text('rail'), findsNothing);
      expect(find.text('dock'), findsOneWidget);
    });

    testWidgets('with no right rail the dock is used at any width',
        (tester) async {
      await pumpShell(tester, width: 1600, dock: dock);
      expect(find.text('dock'), findsOneWidget);
    });

    testWidgets('past the content cap the page centres in the free width',
        (tester) async {
      const w = 2600.0;
      await pumpShell(tester, width: w);
      final body = tester.getRect(find.text('page body'));
      // 2600 − 232 nav = 2368 free > the 1600 cap, so the capped column is
      // centred in the free width.
      const freeMid = WebShellV2.navWidth + (w - WebShellV2.navWidth) / 2;
      expect(body.center.dx, closeTo(freeMid, 1));
      expect(WebBreakpoints.contentV2, 1600);
    });
  });

  group('WebMorePage (narrow layout)', () {
    testWidgets('offers Setup & Accounts', (tester) async {
      final stats = MockStatsPresenter();
      when(stats.stats).thenReturn(UserStats.initial());
      final cloud = MockAiCoachService();
      when(cloud.isAvailable).thenReturn(true);
      when(cloud.tier).thenReturn(AiCoachTier.cloud);
      final advisor = AiCoachPresenter(stats: stats, service: cloud);
      final auth = AuthPresenter(_FakeAuthService());
      final ledger = LedgerPresenter(MockStorageService(), stats);

      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildWebDarkTheme(),
        home: WebMorePage(
          authPresenter: auth,
          advisorPresenter: advisor,
          dashPresenter: MockTreasuryDashboardPresenter(),
          ledgerPresenter: ledger,
          isDark: true,
          onToggleTheme: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(WebKeys.moreSetup), findsOneWidget);
      expect(find.text('Setup & Accounts'), findsOneWidget);
      // The rest of the tab is unchanged.
      expect(find.text('Open Nudgy'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text(email), findsOneWidget);

      advisor.dispose();
      auth.dispose();
      ledger.dispose();
    });
  });
}

class _FakeAuthService extends Fake implements AuthService {
  @override
  bool get isSignedIn => true;
  @override
  String? get currentUserId => 'u1';
  @override
  String? get currentUserEmail => 'eljon@example.com';
  @override
  String? get currentUserDisplayName => null;
  @override
  String? get currentUserAvatarUrl => null;
}
