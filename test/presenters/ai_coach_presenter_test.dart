import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/services/image_compressor.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Skips the platform-channel compress so the send path is unit-testable.
class _PassthroughCompressor implements ImageCompressor {
  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async => bytes;
  @override
  Future<Uint8List> makeThumbnail(Uint8List bytes) async => bytes;
}

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

  test('an attached photo reaches adviseFinance on the context', () async {
    AiCoachContext? captured;
    when(service.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
    )).thenAnswer((inv) {
      captured = inv.namedArguments[#context] as AiCoachContext;
      return Stream.fromIterable(['Looks like an internet bill.']);
    });

    final p = AiCoachPresenter(
      stats: stats,
      fasting: fasting,
      service: service,
      imageCompressor: _PassthroughCompressor(),
    );
    p.openSession(AiCoachEntryPoint.financeAdvisor);
    await p.send('what is this?', image: Uint8List.fromList([1, 2, 3, 4]));

    expect(captured, isNotNull);
    expect(captured!.imageBytes, isNotNull);
    expect(captured!.imageMimeType, 'image/jpeg');
    // The attached image is shown on the user's message bubble.
    expect(p.messages[p.messages.length - 2].imageBytes, isNotNull);
    expect(p.messages.last.text, 'Looks like an internet bill.');
    p.dispose();
  });

  test('send with only a photo (no caption) still asks the model', () async {
    when(service.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
    )).thenAnswer((_) => Stream.fromIterable(['A receipt.']));

    final p = AiCoachPresenter(
      stats: stats,
      fasting: fasting,
      service: service,
      imageCompressor: _PassthroughCompressor(),
    );
    p.openSession(AiCoachEntryPoint.financeAdvisor);
    await p.send('', image: Uint8List.fromList([9, 9, 9]));

    // Empty caption is replaced with a default prompt so the turn isn't blank.
    final userMsg = p.messages[p.messages.length - 2];
    expect(userMsg.text, isNotEmpty);
    expect(userMsg.imageBytes, isNotNull);
    expect(p.messages.last.text, 'A receipt.');
    p.dispose();
  });
}
