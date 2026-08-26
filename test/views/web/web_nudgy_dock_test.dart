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
}
