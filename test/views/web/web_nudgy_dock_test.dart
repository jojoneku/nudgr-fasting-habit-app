import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/widgets/web_nudgy_dock.dart';
import 'package:intermittent_fasting/views/web/widgets/web_shell.dart';
import 'package:intermittent_fasting/views/widgets/ai_chat_sheet.dart';

import '../../mocks.mocks.dart';

/// Nudgy's web dock, and the presenter arrangement that lets the advisor run on
/// a platform with no fasting or nutrition presenter.
///
/// Nudgy is a launcher plus a panel sharing a [NudgyController]: the launcher
/// floats over the content bottom-right, the panel is a column in the shell's
/// row. They used to be one widget that collapsed to a 56px rail holding one
/// unlabelled icon — which is why it was reported as unreachable by someone who
/// had it on screen the whole time.
void main() {
  late MockStatsPresenter stats;
  late MockAiCoachService cloud;

  setUp(() {
    stats = MockStatsPresenter();
    cloud = MockAiCoachService();
    when(stats.stats).thenReturn(UserStats.initial());
    when(cloud.isAvailable).thenReturn(true);
    when(cloud.tier).thenReturn(AiCoachTier.cloud);
    when(cloud.downloadProgress).thenReturn(null);
  });

  /// The web composition: no `fasting`, no `nutrition`. Constructing either on
  /// web would init NotificationService or the sqflite food DB.
  AiCoachPresenter buildWebAdvisor({AiCoachService? service}) =>
      AiCoachPresenter(
        stats: stats,
        service: service ?? cloud,
      );

  Widget wrap(Widget child) => MaterialApp(
        theme: buildWebDarkTheme(),
        home: Scaffold(body: Row(children: [child])),
      );

  /// Both halves, as the shell mounts them.
  Widget wrapDock(NudgyController c) => MaterialApp(
        theme: buildWebDarkTheme(),
        home: Scaffold(
          body: Row(children: [
            Expanded(child: NudgyLauncher(controller: c)),
            NudgyPanel(controller: c),
          ]),
        ),
      );

  group('advisor without fasting or nutrition', () {
    test('builds and reports the cloud tier as available', () {
      final p = buildWebAdvisor();
      expect(p.isModelAvailable, isTrue);
      p.dispose();
    });

    test(
        'opening the advisor session does not throw without a fasting '
        'presenter', () {
      final p = buildWebAdvisor();
      p.openSession(AiCoachEntryPoint.financeAdvisor);
      expect(p.entryPoint, AiCoachEntryPoint.financeAdvisor);
      p.dispose();
    });

    test('sending a turn assembles a context with no fast in progress',
        () async {
      // The advisor entry point routes to adviseFinance, not respond.
      when(cloud.adviseFinance(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
      )).thenAnswer((_) => Stream.fromIterable(['Looks fine.']));

      final p = buildWebAdvisor();
      p.openSession(AiCoachEntryPoint.financeAdvisor);
      await p.send('how am I doing?');

      final captured = verify(cloud.adviseFinance(
        messages: anyNamed('messages'),
        context: captureAnyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
      )).captured.single as AiCoachContext;

      // The absent fasting presenter reports "not fasting" rather than
      // inventing a fast or throwing.
      expect(captured.isFasting, isFalse);
      expect(captured.elapsedFastMinutes, isNull);
      expect(captured.fastingGoalHours, isNull);
      expect(p.errorMessage, isNull);
      p.dispose();
    });
  });

  group('Nudgy dock', () {
    testWidgets(
        'starts closed: the launcher is offered, the panel takes no '
        'width', (tester) async {
      final p = buildWebAdvisor();
      final c = NudgyController(p);
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      // Labelled, so it reads as a thing you can use.
      expect(find.text('Ask Nudgy'), findsOneWidget);
      expect(find.text('Nudgy'), findsNothing);
      expect(tester.getSize(find.byType(NudgyPanel)).width, 0);
      c.dispose();
      p.dispose();
    });

    testWidgets('the launcher opens the panel and the advisor session',
        (tester) async {
      final p = buildWebAdvisor();
      final c = NudgyController(p);
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ask Nudgy'));
      await tester.pumpAndSettle();

      expect(find.text('Nudgy'), findsOneWidget);
      expect(find.byType(AiChatBody), findsOneWidget);
      expect(p.entryPoint, AiCoachEntryPoint.financeAdvisor);
      expect(
          tester.getSize(find.byType(NudgyPanel)).width, NudgyPanel.openWidth);
      c.dispose();
      p.dispose();
    });

    testWidgets('the session is opened once, not on every open',
        (tester) async {
      final p = buildWebAdvisor();
      final c = NudgyController(p);
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      c.open();
      await tester.pumpAndSettle();
      final firstMessages = p.messages.length;
      c.close();
      await tester.pumpAndSettle();
      c.open();
      await tester.pumpAndSettle();

      // Re-opening must not restart the conversation the user was having.
      expect(p.messages.length, firstMessages);
      c.dispose();
      p.dispose();
    });

    testWidgets('closes from the header, and the launcher comes back',
        (tester) async {
      final p = buildWebAdvisor();
      final c = NudgyController(p);
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask Nudgy'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(find.text('Nudgy'), findsNothing);
      expect(tester.getSize(find.byType(NudgyPanel)).width, 0);
      expect(find.text('Ask Nudgy'), findsOneWidget);
      c.dispose();
      p.dispose();
    });

    testWidgets('offers no on-device download when the cloud tier is down',
        (tester) async {
      // Web has no on-device tier, so an unavailable model must not present a
      // download button the platform cannot honour.
      final down = MockAiCoachService();
      when(down.isAvailable).thenReturn(false);
      when(down.tier).thenReturn(AiCoachTier.cloud);
      when(down.downloadProgress).thenReturn(null);

      final p = buildWebAdvisor(service: down);
      final c = NudgyController(p);
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask Nudgy'));
      await tester.pumpAndSettle();

      expect(find.text('Nudgy is unavailable'), findsOneWidget);
      expect(find.textContaining('Download'), findsNothing);
      c.dispose();
      p.dispose();
    });
  });

  group('conversation round-trip in the dock', () {
    testWidgets('typing and sending renders the assistant reply',
        (tester) async {
      when(cloud.adviseFinance(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
      )).thenAnswer(
          (_) => Stream.fromIterable(['You are ', 'running a deficit.']));

      final p = buildWebAdvisor();
      final c = NudgyController(p);
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask Nudgy'));
      await tester.pumpAndSettle();

      // Composer is live once a tier is available.
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(find.text('Coach not ready…'), findsNothing);

      await tester.enterText(field, 'how am I doing?');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Icon).last);
      await tester.pumpAndSettle();

      // Both sides of the exchange render in the dock.
      expect(find.textContaining('how am I doing?'), findsOneWidget);
      expect(find.textContaining('running a deficit.'), findsOneWidget);
      expect(p.errorMessage, isNull);
      p.dispose();
    });
  });

  group('AiChatSheet still wraps the shared body on mobile', () {
    testWidgets('shows the drag handle and keeps the entry label',
        (tester) async {
      final p = buildWebAdvisor();
      await tester.pumpWidget(MaterialApp(
        theme: buildWebDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AiChatSheet.show(
                context,
                presenter: p,
                entryPoint: AiCoachEntryPoint.financeAdvisor,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The sheet is a container around the same body the web dock uses...
      expect(find.byType(AiChatBody), findsOneWidget);
      // ...and unlike the dock it keeps the sheet affordances and the label.
      expect(find.text('Nudgy'), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      p.dispose();
    });
  });

  group('WebShell dock', () {
    testWidgets('mounts the dock alongside the body', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildWebDarkTheme(),
        home: WebShell(
          destinations: const [
            WebDestination(icon: Icons.dashboard_outlined, label: 'Dashboard'),
          ],
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          body: const Center(child: Text('page body')),
          dock: const SizedBox(width: 56, child: Text('dock')),
        ),
      ));
      await tester.pumpAndSettle();

      // Both visible at once — the dock does not replace the page.
      expect(find.text('page body'), findsOneWidget);
      expect(find.text('dock'), findsOneWidget);
    });

    testWidgets('omits the dock region when none is given', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildWebDarkTheme(),
        home: WebShell(
          destinations: const [
            WebDestination(icon: Icons.dashboard_outlined, label: 'Dashboard'),
          ],
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          body: const Center(child: Text('page body')),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('page body'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Nudgy dock resize', () {
    /// A window wide enough that the 480px page minimum is never the binding
    /// constraint, so these tests exercise the controller's own limits.
    Future<void> wide(WidgetTester tester) async {
      tester.view.physicalSize = const Size(2400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('dragging the left edge left widens the panel', (tester) async {
      await wide(tester);
      final p = buildWebAdvisor();
      final c = NudgyController(p);
      c.open();
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(NudgyPanel)).width,
          NudgyController.defaultWidth);

      // Grab the strip on the panel's own left edge.
      final panel = tester.getRect(find.byType(NudgyPanel));
      final grip = Offset(panel.left + 4, panel.center.dy);
      await tester.dragFrom(grip, const Offset(-200, 0));
      await tester.pumpAndSettle();

      // Within a touch slop of the drag distance: the recognizer eats the
      // first ~20px breaking slop, which is deliberate — a resize that jumps
      // to catch up on acceptance is worse than a small dead zone.
      expect(c.width, closeTo(NudgyController.defaultWidth + 200, 24));
      expect(tester.getSize(find.byType(NudgyPanel)).width, c.width);
      c.dispose();
      p.dispose();
    });

    testWidgets('dragging right narrows it, but never past the minimum',
        (tester) async {
      await wide(tester);
      final p = buildWebAdvisor();
      final c = NudgyController(p);
      c.open();
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      final panel = tester.getRect(find.byType(NudgyPanel));
      await tester.dragFrom(
          Offset(panel.left + 4, panel.center.dy), const Offset(600, 0));
      await tester.pumpAndSettle();

      // A handle must not be able to drag the panel into a width its own
      // controls cannot render.
      expect(c.width, NudgyController.minWidth);
      c.dispose();
      p.dispose();
    });

    testWidgets('a narrow window caps the drag so the page keeps its column',
        (tester) async {
      // 1200 wide: rail (248) + page floor (480) leaves the panel at most 472.
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final p = buildWebAdvisor();
      final c = NudgyController(p);
      c.open();
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      final panel = tester.getRect(find.byType(NudgyPanel));
      await tester.dragFrom(
          Offset(panel.left + 4, panel.center.dy), const Offset(-800, 0));
      await tester.pumpAndSettle();

      expect(c.width, lessThanOrEqualTo(472));
      expect(c.width, greaterThan(NudgyController.defaultWidth));
      c.dispose();
      p.dispose();
    });

    testWidgets('double-tapping the handle restores the default width',
        (tester) async {
      await wide(tester);
      final p = buildWebAdvisor();
      final c = NudgyController(p);
      c.open();
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      final before = tester.getRect(find.byType(NudgyPanel));
      await tester.dragFrom(
          Offset(before.left + 4, before.center.dy), const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(c.width, isNot(NudgyController.defaultWidth));

      // Re-find the edge: widening moved it left, so the old grip point now
      // sits inside the conversation rather than on the handle.
      final widened = tester.getRect(find.byType(NudgyPanel));
      final grip = Offset(widened.left + 4, widened.center.dy);

      final first = await tester.startGesture(grip);
      await first.up();
      await tester.pump(const Duration(milliseconds: 80));
      final second = await tester.startGesture(grip);
      await second.up();
      await tester.pumpAndSettle();

      expect(c.width, NudgyController.defaultWidth);
      c.dispose();
      p.dispose();
    });

    testWidgets('a double-click with mouse jitter still resets',
        (tester) async {
      await wide(tester);
      final p = buildWebAdvisor();
      final c = NudgyController(p);
      c.open();
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      final before = tester.getRect(find.byType(NudgyPanel));
      await tester.dragFrom(
          Offset(before.left + 4, before.center.dy), const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(c.width, isNot(NudgyController.defaultWidth));

      final widened = tester.getRect(find.byType(NudgyPanel));
      final grip = Offset(widened.left + 4, widened.center.dy);

      // The real failure this guards: a mouse reports a pixel or two between
      // press and release, which was enough for the drag recognizer to claim
      // the arena and defeat GestureDetector's onDoubleTap. Zero-movement
      // synthetic taps passed while a browser never reset once.
      for (var i = 0; i < 2; i++) {
        final g = await tester.startGesture(grip);
        await g.moveBy(const Offset(2, -1));
        await g.up();
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();

      expect(c.width, NudgyController.defaultWidth);
      c.dispose();
      p.dispose();
    });

    testWidgets('two real drags in quick succession do not read as a reset',
        (tester) async {
      await wide(tester);
      final p = buildWebAdvisor();
      final c = NudgyController(p);
      c.open();
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      for (var i = 0; i < 2; i++) {
        final edge = tester.getRect(find.byType(NudgyPanel));
        await tester.dragFrom(
            Offset(edge.left + 4, edge.center.dy), const Offset(-60, 0));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();

      // Deliberate resizes must not be undone by having been quick: the
      // click detector excludes them by distance travelled.
      expect(c.width, greaterThan(NudgyController.defaultWidth));
      c.dispose();
      p.dispose();
    });

    testWidgets('the width survives a reopen', (tester) async {
      await wide(tester);
      final p = buildWebAdvisor();
      final c = NudgyController(p);
      c.open();
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      final panel = tester.getRect(find.byType(NudgyPanel));
      await tester.dragFrom(
          Offset(panel.left + 4, panel.center.dy), const Offset(-120, 0));
      await tester.pumpAndSettle();
      final widened = c.width;

      c.close();
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(NudgyPanel)).width, 0);

      c.open();
      await tester.pumpAndSettle();
      // Collapsing is not a reset: the user chose this width.
      expect(tester.getSize(find.byType(NudgyPanel)).width, widened);
      c.dispose();
      p.dispose();
    });

    testWidgets('a stored width is restored on construction', (tester) async {
      await wide(tester);
      final storage = MockStorageService();
      when(storage.loadNudgyPanelWidth()).thenAnswer((_) async => 620);

      final p = buildWebAdvisor();
      final c = NudgyController(p, storage: storage);
      c.open();
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      expect(c.width, 620);
      expect(tester.getSize(find.byType(NudgyPanel)).width, 620);
      c.dispose();
      p.dispose();
    });

    testWidgets('a stored width beyond the maximum is clamped, not trusted',
        (tester) async {
      await wide(tester);
      final storage = MockStorageService();
      when(storage.loadNudgyPanelWidth()).thenAnswer((_) async => 99999);

      final p = buildWebAdvisor();
      final c = NudgyController(p, storage: storage);
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      expect(c.width, NudgyController.maxWidth);
      c.dispose();
      p.dispose();
    });

    testWidgets('releasing the drag persists the width exactly once',
        (tester) async {
      await wide(tester);
      final storage = MockStorageService();
      when(storage.loadNudgyPanelWidth()).thenAnswer((_) async => null);
      when(storage.saveNudgyPanelWidth(any)).thenAnswer((_) async {});

      final p = buildWebAdvisor();
      final c = NudgyController(p, storage: storage);
      c.open();
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      final panel = tester.getRect(find.byType(NudgyPanel));
      await tester.dragFrom(
          Offset(panel.left + 4, panel.center.dy), const Offset(-150, 0));
      await tester.pumpAndSettle();

      // Once on release, not once per drag frame — a single gesture would
      // otherwise put hundreds of writes through SharedPreferences.
      verify(storage.saveNudgyPanelWidth(c.width)).called(1);
      c.dispose();
      p.dispose();
    });

    testWidgets('the handle does not steal taps from the chat body',
        (tester) async {
      await wide(tester);
      final p = buildWebAdvisor();
      final c = NudgyController(p);
      c.open();
      await tester.pumpWidget(wrapDock(c));
      await tester.pumpAndSettle();

      // The collapse control sits at the panel's far right, well clear of the
      // 10px grip — a resize strip that covered it would trap the user open.
      await tester.tap(find.byTooltip('Collapse Nudgy'));
      await tester.pumpAndSettle();

      expect(c.isOpen, isFalse);
      c.dispose();
      p.dispose();
    });
  });
}
