import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/advisor_event.dart';
import 'package:intermittent_fasting/models/advisor_reply.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/widgets/ai_chat_sheet.dart';

import '../../mocks.mocks.dart';
import '../../support/advisor_events.dart';

/// The two affordances that stop a failure costing the user their question:
/// a Retry on the error chip, and an edit button on anything they typed.
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

  void answerWith(Stream<AdvisorEvent> Function() answer) {
    when(cloud.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
      tools: anyNamed('tools'),
    )).thenAnswer((_) => answer());
  }

  Stream<AdvisorEvent> failing(String message, {required bool retryable}) =>
      Stream<AdvisorEvent>.error(
          AiCoachException(message, retryable: retryable));

  AiCoachPresenter openAdvisor() {
    final presenter = AiCoachPresenter(stats: stats, service: cloud);
    presenter.openSession(AiCoachEntryPoint.financeAdvisor);
    return presenter;
  }

  Future<void> pumpChat(WidgetTester tester, AiCoachPresenter presenter) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: AiChatBody(
          presenter: presenter,
          entryPoint: AiCoachEntryPoint.financeAdvisor,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Runs a turn, pumping frames for as long as it takes.
  ///
  /// `await presenter.send(...)` deadlocks here. The retry backoff is a
  /// `Future.delayed`, and under `testWidgets` a pending timer only fires while
  /// the clock is being advanced — so awaiting the turn first means nothing
  /// ever pumps and the timer never comes due. The clock has to move WHILE the
  /// turn is in flight, not before or after it.
  Future<void> runTurn(WidgetTester tester, Future<void> turn) async {
    var done = false;
    final joined = turn.whenComplete(() => done = true);
    // Bounded so a genuine hang fails the test instead of running forever.
    for (var i = 0; i < 200 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(done, isTrue, reason: 'the turn never completed');
    await joined;
    await tester.pumpAndSettle();
  }

  /// Settles a turn the test kicked off by tapping, where there is no future to
  /// join — the presenter owns it.
  Future<void> settleTurn(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  group('retry affordance', () {
    testWidgets('a transient failure offers Retry', (tester) async {
      answerWith(() => failing('The advisor had a hiccup.', retryable: true));
      final presenter = openAdvisor();
      await pumpChat(tester, presenter);

      await runTurn(tester, presenter.send('how much on food?'));

      expect(find.text('The advisor had a hiccup.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      presenter.dispose();
    });

    testWidgets('an expired session offers no Retry', (tester) async {
      // Retrying bad credentials can only fail again, so the button would be a
      // lie about what the user can do next.
      answerWith(() => failing('Your session has expired.', retryable: false));
      final presenter = openAdvisor();
      await pumpChat(tester, presenter);

      await runTurn(tester, presenter.send('how much on food?'));

      expect(find.text('Your session has expired.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      presenter.dispose();
    });

    testWidgets('tapping Retry re-asks and clears the error', (tester) async {
      answerWith(() => failing('hiccup', retryable: true));
      final presenter = openAdvisor();
      await pumpChat(tester, presenter);
      await runTurn(tester, presenter.send('how much on food?'));
      expect(find.text('Retry'), findsOneWidget);

      answerWith(
          () => advisorStreamOf(const AdvisorReply(text: 'About 4,120.')));
      await tester.tap(find.text('Retry'));
      await settleTurn(tester);

      expect(find.text('About 4,120.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      // The question was never retyped, and appears once.
      expect(find.text('how much on food?'), findsOneWidget);
      presenter.dispose();
    });
  });

  group('edit affordance', () {
    testWidgets('a typed question gets an edit button', (tester) async {
      answerWith(
          () => advisorStreamOf(const AdvisorReply(text: 'About 4,120.')));
      final presenter = openAdvisor();
      await pumpChat(tester, presenter);

      await runTurn(tester, presenter.send('how much on food?'));

      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      presenter.dispose();
    });

    testWidgets('the assistant reply gets no edit button', (tester) async {
      answerWith(
          () => advisorStreamOf(const AdvisorReply(text: 'About 4,120.')));
      final presenter = openAdvisor();
      await pumpChat(tester, presenter);
      await runTurn(tester, presenter.send('how much on food?'));

      // Exactly one — the user's turn. Not the reply.
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      presenter.dispose();
    });

    testWidgets('editing replaces the question and the answer', (tester) async {
      answerWith(
          () => advisorStreamOf(const AdvisorReply(text: 'About 4,120.')));
      final presenter = openAdvisor();
      await pumpChat(tester, presenter);
      await runTurn(tester, presenter.send('how much on food?'));

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Edit question'), findsOneWidget);
      // The replacement is spelled out, because it is not undoable.
      expect(find.textContaining('will be replaced'), findsOneWidget);

      answerWith(
          () => advisorStreamOf(const AdvisorReply(text: 'About 1,980.')));
      await tester.enterText(
          find.byType(TextField).last, 'how much on transport?');
      await tester.tap(find.text('Ask again'));
      await settleTurn(tester);

      expect(find.text('how much on transport?'), findsOneWidget);
      expect(find.text('About 1,980.'), findsOneWidget);
      expect(find.text('how much on food?'), findsNothing);
      expect(find.text('About 4,120.'), findsNothing);
      presenter.dispose();
    });

    testWidgets('cancelling changes nothing', (tester) async {
      answerWith(
          () => advisorStreamOf(const AdvisorReply(text: 'About 4,120.')));
      final presenter = openAdvisor();
      await pumpChat(tester, presenter);
      await runTurn(tester, presenter.send('how much on food?'));

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'something else');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('how much on food?'), findsOneWidget);
      expect(find.text('About 4,120.'), findsOneWidget);
      expect(find.text('something else'), findsNothing);
      presenter.dispose();
    });
  });
}
