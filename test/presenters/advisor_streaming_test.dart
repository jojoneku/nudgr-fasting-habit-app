import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_chat_message.dart';
import 'package:intermittent_fasting/models/advisor_event.dart';
import 'package:intermittent_fasting/models/advisor_reply.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';
import '../support/advisor_events.dart';

/// How a streamed advisor turn ends, from the presenter's side.
///
/// Three outcomes, and the difference between them is what the user sees: a
/// finished answer, a half-written one that says so, or a failure before any
/// prose arrived. Getting the middle case wrong is the expensive one — a
/// partial reply presented as complete is indistinguishable from the advisor
/// simply giving a short answer.
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

  void stub(Stream<AdvisorEvent> Function() answer) {
    when(service.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
      tools: anyNamed('tools'),
    )).thenAnswer((_) => answer());
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

  String lastAssistantText(AiCoachPresenter p) =>
      p.messages.lastWhere((m) => m.role != AiChatRole.user).text;

  test('a completed turn renders the whole reply and no error', () async {
    stub(() => advisorStreamOf(
        const AdvisorReply(text: 'Cut delivery first, then groceries.')));
    final p = build();

    await p.send('what should i cut?');

    expect(lastAssistantText(p), 'Cut delivery first, then groceries.');
    expect(p.errorMessage, isNull);
    p.dispose();
  });

  test('deltas accumulate — the reply is not just its last chunk', () async {
    // advisorStreamOf splits the prose into several deltas, so a presenter that
    // overwrote instead of appending would end up with only the tail.
    const whole = 'You are at 4,120 of a 6,000 budget with nine days left.';
    stub(() => advisorStreamOf(const AdvisorReply(text: whole)));
    final p = build();

    await p.send('how am i doing?');

    expect(lastAssistantText(p), whole);
    p.dispose();
  });

  test('a stream cut off mid-answer keeps the prose and says it is unfinished',
      () async {
    stub(() => advisorStreamCutOff('Start by looking at your delivery spend, '
        'which is running at'));
    final p = build();

    await p.send('what should i cut?');

    // The prose that arrived is real work — it stays.
    expect(lastAssistantText(p), contains('delivery spend'));
    // But the user is told it did not finish, so a half-answer cannot pass for
    // a complete one.
    expect(p.errorMessage, isNotNull);
    expect(p.errorMessage, contains('cut off'));
    p.dispose();
  });

  test('an in-band error frame keeps the prose and surfaces the reason',
      () async {
    stub(() => advisorStreamErroring(
        'Looking at your budget now, ', 'Bedrock fell over.'));
    final p = build();

    await p.send('what should i cut?');

    expect(lastAssistantText(p), contains('Looking at your budget'));
    expect(p.errorMessage, 'Bedrock fell over.');
    p.dispose();
  });

  test('a failure before any prose reports the failure, not an empty answer',
      () async {
    stub(() => Stream<AdvisorEvent>.error(
        const AiCoachException('Advisor unreachable. Check your connection.')));
    final p = build();

    await p.send('what should i cut?');

    expect(lastAssistantText(p), isEmpty);
    expect(p.errorMessage, contains('unreachable'));
    p.dispose();
  });

  test('a turn that never terminates does not become a short answer', () async {
    // The single most important case: `start` and nothing else. Text is empty
    // either way, so only errorMessage distinguishes "failed" from "the advisor
    // had nothing to say".
    stub(() => advisorStreamCutOff(''));
    final p = build();

    await p.send('anything?');

    expect(p.errorMessage, isNotNull);
    p.dispose();
  });
}
