import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/widgets/web_advisor_panel.dart';
import 'package:intermittent_fasting/views/web/widgets/web_shell.dart';
import 'package:intermittent_fasting/views/widgets/ai_chat_sheet.dart';

import '../../mocks.mocks.dart';

/// The web Money Mentor dock, and the presenter arrangement that lets the
/// advisor run on a platform with no fasting or nutrition presenter.
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

  group('WebAdvisorPanel', () {
    testWidgets('starts collapsed to a rail', (tester) async {
      final p = buildWebAdvisor();
      await tester.pumpWidget(wrap(WebAdvisorPanel(presenter: p)));
      await tester.pumpAndSettle();

      expect(find.text('Money Mentor'), findsNothing);
      expect(
        tester.getSize(find.byType(WebAdvisorPanel)).width,
        WebAdvisorPanel.railWidth,
      );
      p.dispose();
    });

    testWidgets('expands on tap and opens the advisor session', (tester) async {
      final p = buildWebAdvisor();
      await tester.pumpWidget(wrap(WebAdvisorPanel(presenter: p)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.savings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Money Mentor'), findsOneWidget);
      expect(find.byType(AiChatBody), findsOneWidget);
      expect(p.entryPoint, AiCoachEntryPoint.financeAdvisor);
      expect(
        tester.getSize(find.byType(WebAdvisorPanel)).width,
        WebAdvisorPanel.expandedWidth,
      );
      p.dispose();
    });

    testWidgets('collapses again from the header', (tester) async {
      final p = buildWebAdvisor();
      await tester.pumpWidget(wrap(WebAdvisorPanel(presenter: p)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.savings_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(find.text('Money Mentor'), findsNothing);
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
      await tester.pumpWidget(wrap(WebAdvisorPanel(presenter: p)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.savings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Money Mentor is unavailable'), findsOneWidget);
      expect(find.textContaining('Download'), findsNothing);
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
