import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

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

  AiCoachPresenter build() => AiCoachPresenter(
        stats: stats,
        fasting: fasting,
        service: service,
      );

  test('successful stream lands as the assistant message', () async {
    when(service.respond(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      isThinking: anyNamed('isThinking'),
    )).thenAnswer((_) => Stream.fromIterable(['Keep ', 'going.']));

    final p = build();
    await p.send('status?');

    expect(p.errorMessage, isNull);
    expect(p.messages.last.text, 'Keep going.');
    p.dispose();
  });

  test('AiCoachException surfaces its specific user message', () async {
    when(service.respond(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      isThinking: anyNamed('isThinking'),
    )).thenAnswer((_) => Stream.error(const AiCoachException(
        'The cloud coach had a hiccup on our end. Try again in a moment.')));

    final p = build();
    await p.send('status?');

    expect(p.errorMessage,
        'The cloud coach had a hiccup on our end. Try again in a moment.');
    // The streaming placeholder must not survive as a phantom reply.
    expect(p.messages.last.text, isEmpty);
    p.dispose();
  });

  test('unknown errors keep the generic message', () async {
    when(service.respond(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      isThinking: anyNamed('isThinking'),
    )).thenAnswer((_) => Stream.error(StateError('boom')));

    final p = build();
    await p.send('status?');

    expect(p.errorMessage, 'Something went wrong. Try again.');
    p.dispose();
  });
}
