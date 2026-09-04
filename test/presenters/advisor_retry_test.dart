import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_event.dart';
import 'package:intermittent_fasting/models/advisor_reply.dart';
import 'package:intermittent_fasting/models/ai_chat_message.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';
import '../support/advisor_events.dart';

/// Auto-retry, manual retry, and editing a question already asked.
///
/// The behaviour being protected: a fault that had nothing to do with the
/// user's question should not cost them their question. Every test here would
/// have passed before by simply showing an error, which is the point — the
/// assertions are about what the user does NOT have to do.
void main() {
  late MockStatsPresenter stats;
  late MockFastingPresenter fasting;
  late MockAiCoachService service;

  setUp(() {
    stats = MockStatsPresenter();
    fasting = MockFastingPresenter();
    service = MockAiCoachService();
    when(stats.stats).thenReturn(UserStats.initial());
    when(fasting.isFasting).thenReturn(false);
    when(fasting.fastingGoalHours).thenReturn(16);
    when(service.isAvailable).thenReturn(true);
    when(service.tier).thenReturn(AiCoachTier.cloud);
  });

  /// Answers each successive call from [script], repeating the last entry.
  /// Returns a counter of how many calls were actually made.
  List<int> script(List<Stream<AdvisorEvent> Function()> answers) {
    final calls = [0];
    when(service.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
      tools: anyNamed('tools'),
    )).thenAnswer((_) {
      final i = calls[0];
      calls[0]++;
      return answers[i < answers.length ? i : answers.length - 1]();
    });
    return calls;
  }

  AiCoachPresenter build() {
    final p = AiCoachPresenter(
      stats: stats,
      fasting: fasting,
      service: service,
    );
    p.openSession(AiCoachEntryPoint.financeAdvisor);
    return p;
  }

  Stream<AdvisorEvent> failing(String message, {required bool retryable}) =>
      Stream<AdvisorEvent>.error(
          AiCoachException(message, retryable: retryable));

  String lastAssistantText(AiCoachPresenter p) =>
      p.messages.lastWhere((m) => m.role != AiChatRole.user).text;

  List<String> userTexts(AiCoachPresenter p) => p.messages
      .where((m) => m.role == AiChatRole.user)
      .map((m) => m.text)
      .toList();

  group('automatic retry', () {
    test('a transient failure then success shows only the answer', () async {
      final calls = script([
        () => failing('Advisor unreachable.', retryable: true),
        () => advisorStreamOf(const AdvisorReply(text: 'Cut delivery first.')),
      ]);
      final p = build();

      await p.send('what should i cut?');

      expect(calls[0], 2, reason: 'should have retried once');
      expect(lastAssistantText(p), 'Cut delivery first.');
      // The user never learns the first attempt happened.
      expect(p.errorMessage, isNull);
      p.dispose();
    });

    test('it recovers on the third attempt too', () async {
      final calls = script([
        () => failing('boom', retryable: true),
        () => failing('boom', retryable: true),
        () => advisorStreamOf(const AdvisorReply(text: 'Third time.')),
      ]);
      final p = build();

      await p.send('anything?');

      expect(calls[0], 3);
      expect(lastAssistantText(p), 'Third time.');
      expect(p.errorMessage, isNull);
      p.dispose();
    });

    test('a retry does not append to the abandoned half-answer', () async {
      // The bug this guards: attempt one writes prose, attempt two appends to
      // it, and the user reads two beginnings stitched together.
      final calls = script([
        () => advisorStreamErroring('Looking at your budget, I see ', 'died'),
        () => advisorStreamOf(
            const AdvisorReply(text: 'Your food spend is the problem.')),
      ]);
      final p = build();

      await p.send('how am i doing?');

      expect(calls[0], 2);
      expect(lastAssistantText(p), 'Your food spend is the problem.');
      expect(lastAssistantText(p), isNot(contains('Looking at your budget')));
      p.dispose();
    });

    test('it gives up after maxAdvisorAttempts and says so once', () async {
      final calls = script([() => failing('still down', retryable: true)]);
      final p = build();

      await p.send('what should i cut?');

      expect(calls[0], AiCoachPresenter.maxAdvisorAttempts);
      expect(p.errorMessage, 'still down');
      expect(p.canRetryLastTurn, isTrue,
          reason: 'a transient failure stays retryable by hand');
      p.dispose();
    });
  });

  group('what must NOT be retried', () {
    test('an expired session fails on the first attempt', () async {
      final calls = script([
        () => failing('Your session has expired. Sign in again.',
            retryable: false),
      ]);
      final p = build();

      await p.send('what should i cut?');

      // Retrying bad credentials three times just delays the real message.
      expect(calls[0], 1);
      expect(p.errorMessage, contains('session has expired'));
      expect(p.canRetryLastTurn, isFalse,
          reason: 'a retry button here could only fail again');
      p.dispose();
    });

    test('a spent daily cap fails on the first attempt', () async {
      final calls = script([
        () => failing('The advisor hit its daily limit.', retryable: false),
      ]);
      final p = build();

      await p.send('what should i cut?');

      // Three attempts would spend three units discovering there are none.
      expect(calls[0], 1);
      expect(p.canRetryLastTurn, isFalse);
      p.dispose();
    });
  });

  group('manual retry', () {
    test('replays the question without the user retyping it', () async {
      final calls = script([() => failing('down', retryable: true)]);
      final p = build();
      await p.send('how much on food this month?');
      expect(p.canRetryLastTurn, isTrue);

      script([
        () => advisorStreamOf(const AdvisorReply(text: '4,120 so far.')),
      ]);
      await p.retryLastTurn();

      expect(lastAssistantText(p), '4,120 so far.');
      expect(p.errorMessage, isNull);
      // The question appears once, not twice.
      expect(userTexts(p), ['how much on food this month?']);
      expect(calls[0], AiCoachPresenter.maxAdvisorAttempts);
      p.dispose();
    });

    test('is refused when the failure was not retryable', () async {
      script([() => failing('signed out', retryable: false)]);
      final p = build();
      await p.send('anything?');

      final before = p.messages.length;
      await p.retryLastTurn();

      expect(p.messages.length, before, reason: 'nothing should have happened');
      expect(p.errorMessage, 'signed out');
      p.dispose();
    });

    test('is a no-op when the last turn succeeded', () async {
      script([() => advisorStreamOf(const AdvisorReply(text: 'All good.'))]);
      final p = build();
      await p.send('anything?');

      expect(p.canRetryLastTurn, isFalse);
      await p.retryLastTurn();
      expect(userTexts(p), ['anything?']);
      p.dispose();
    });
  });

  group('editing a question already asked', () {
    test('replaces the question and answers the new one', () async {
      script([() => advisorStreamOf(const AdvisorReply(text: 'About 4,120.'))]);
      final p = build();
      await p.send('how much on food?');
      final promptId =
          p.messages.firstWhere((m) => m.role == AiChatRole.user).id;

      script([
        () => advisorStreamOf(const AdvisorReply(text: 'About 1,980.')),
      ]);
      final ok = await p.editAndResend(promptId, 'how much on transport?');

      expect(ok, isTrue);
      expect(userTexts(p), ['how much on transport?']);
      // The old answer went with the old question — leaving it would put a
      // reply above a prompt it does not match.
      expect(lastAssistantText(p), 'About 1,980.');
      expect(p.messages.where((m) => m.text == 'About 4,120.'), isEmpty);
      p.dispose();
    });

    test('drops everything after the edited message, not just its answer',
        () async {
      script([() => advisorStreamOf(const AdvisorReply(text: 'A1'))]);
      final p = build();
      await p.send('q1');
      final firstId =
          p.messages.firstWhere((m) => m.role == AiChatRole.user).id;
      await p.send('q2');

      script([() => advisorStreamOf(const AdvisorReply(text: 'new A1'))]);
      await p.editAndResend(firstId, 'q1 edited');

      expect(userTexts(p), ['q1 edited']);
      expect(p.messages.any((m) => m.text == 'q2'), isFalse);
      p.dispose();
    });

    test('refuses an unknown id, empty text, and an unchanged edit', () async {
      script([() => advisorStreamOf(const AdvisorReply(text: 'A'))]);
      final p = build();
      await p.send('q');
      final id = p.messages.firstWhere((m) => m.role == AiChatRole.user).id;

      expect(await p.editAndResend('nope', 'x'), isFalse);
      expect(await p.editAndResend(id, '   '), isFalse);
      expect(await p.editAndResend(id, 'q'), isFalse,
          reason: 'an unchanged edit should not re-spend a turn');
      expect(userTexts(p), ['q']);
      p.dispose();
    });

    test('a tool-result turn is not editable', () async {
      final p = build();
      // Wears AiChatRole.user, but nobody typed it.
      final toolTurn = AiChatMessage.toolResults([
        const {'type': 'tool_result', 'tool_use_id': 't1'}
      ]);
      expect(p.canEdit(toolTurn), isFalse);
      p.dispose();
    });

    test('a typed prompt is editable', () async {
      final p = build();
      expect(p.canEdit(AiChatMessage.user('how much on food?')), isTrue);
      p.dispose();
    });
  });
}
