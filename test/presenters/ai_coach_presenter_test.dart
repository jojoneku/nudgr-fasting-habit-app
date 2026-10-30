import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_reply.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/services/image_compressor.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';
import '../support/advisor_events.dart';

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
      route: anyNamed('route'),
    )).thenAnswer((inv) {
      captured = inv.namedArguments[#context] as AiCoachContext;
      return advisorStreamOf(
          const AdvisorReply(text: 'Looks like an internet bill.'));
    });

    final p = AiCoachPresenter(
      stats: stats,
      fasting: fasting,
      service: service,
      imageCompressor: _PassthroughCompressor(),
    );
    p.openSession(AiCoachEntryPoint.financeAdvisor);
    await p.send('what is this?', images: [
      Uint8List.fromList([1, 2, 3, 4])
    ]);

    expect(captured, isNotNull);
    expect(captured!.images, hasLength(1));
    expect(captured!.imageMimeType, 'image/jpeg');
    // The attached image is shown on the user's message bubble.
    expect(p.messages[p.messages.length - 2].images, hasLength(1));
    expect(p.messages.last.text, 'Looks like an internet bill.');
    p.dispose();
  });

  test('new chat starts empty; reopening a chat restores its messages',
      () async {
    when(service.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
      route: anyNamed('route'),
    )).thenAnswer((_) => advisorStreamOf(const AdvisorReply(text: 'reply')));

    final p =
        AiCoachPresenter(stats: stats, fasting: fasting, service: service);
    p.openSession(AiCoachEntryPoint.financeAdvisor);
    await p.send('first chat message');
    final firstId = p.currentConversationId;
    expect(firstId, isNotNull);

    p.startNewConversation();
    expect(p.messages, isEmpty);
    expect(p.currentConversationId, isNot(firstId));

    await p.send('second chat message');
    // Reopen the first chat — its messages come back.
    p.openConversation(firstId!);
    expect(p.currentConversationId, firstId);
    expect(p.messages.any((m) => m.text == 'first chat message'), isTrue);
    expect(p.messages.any((m) => m.text == 'second chat message'), isFalse);
    p.dispose();
  });

  test('conversations cap at 10; older chats fold into an archive', () async {
    when(service.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
      route: anyNamed('route'),
    )).thenAnswer((_) => advisorStreamOf(const AdvisorReply(text: 'ok')));

    final p =
        AiCoachPresenter(stats: stats, fasting: fasting, service: service);
    p.openSession(AiCoachEntryPoint.financeAdvisor);
    for (var i = 0; i < 12; i++) {
      await p.send('chat $i');
      if (i < 11) p.startNewConversation();
    }

    final active = p.conversations.where((c) => !c.isArchive).toList();
    expect(active.length, 10);
    expect(p.conversations.any((c) => c.isArchive), isTrue);
    p.dispose();
  });

  test('send with only a photo (no caption) still asks the model', () async {
    when(service.adviseFinance(
      messages: anyNamed('messages'),
      context: anyNamed('context'),
      profile: anyNamed('profile'),
      historical: anyNamed('historical'),
      route: anyNamed('route'),
    )).thenAnswer(
        (_) => advisorStreamOf(const AdvisorReply(text: 'A receipt.')));

    final p = AiCoachPresenter(
      stats: stats,
      fasting: fasting,
      service: service,
      imageCompressor: _PassthroughCompressor(),
    );
    p.openSession(AiCoachEntryPoint.financeAdvisor);
    await p.send('', images: [
      Uint8List.fromList([9, 9, 9])
    ]);

    // Empty caption is replaced with a default prompt so the turn isn't blank.
    final userMsg = p.messages[p.messages.length - 2];
    expect(userMsg.text, isNotEmpty);
    expect(userMsg.images, hasLength(1));
    expect(p.messages.last.text, 'A receipt.');
    p.dispose();
  });

  group('staged attachments', () {
    Uint8List img(int b) => Uint8List.fromList([b, b, b]);

    AiCoachPresenter advisor({Duration? retryHorizon}) {
      final p = AiCoachPresenter(
        stats: stats,
        fasting: fasting,
        service: service,
        imageCompressor: _PassthroughCompressor(),
        // Zero surfaces the first failure instead of retrying it, so the
        // manual retry is what runs the second attempt.
        retryHorizon: retryHorizon ?? AiCoachPresenter.defaultRetryHorizon,
      );
      p.openSession(AiCoachEntryPoint.financeAdvisor);
      return p;
    }

    test('adds several images in order and removes one by index', () {
      final p = advisor();
      expect(p.addAttachments([img(1), img(2), img(3)]), 0);
      expect(p.pendingImages.map((i) => i.first), [1, 2, 3]);

      p.removeAttachment(1);
      expect(p.pendingImages.map((i) => i.first), [1, 3]);
      expect(p.remainingAttachmentSlots, AiCoachPresenter.maxAttachments - 2);

      // A stale index (a double tap on a remove button) is ignored.
      p.removeAttachment(5);
      expect(p.pendingImages, hasLength(2));
      p.dispose();
    });

    test('stops at the cap and reports how many were left out', () {
      final p = advisor();
      const cap = AiCoachPresenter.maxAttachments;
      final dropped =
          p.addAttachments([for (var i = 0; i < cap + 2; i++) img(i)]);

      expect(dropped, 2);
      expect(p.pendingImages, hasLength(cap));
      expect(p.canAddAttachment, isFalse);
      expect(p.addAttachments([img(99)]), 1);
      expect(p.attachmentLimitMessage, contains('$cap'));
      p.dispose();
    });

    test('ignores empty byte arrays', () {
      final p = advisor();
      expect(p.addAttachments([Uint8List(0), img(1)]), 0);
      expect(p.pendingImages, hasLength(1));
      p.dispose();
    });

    test('sendWithAttachments sends every staged image and unstages them',
        () async {
      AiCoachContext? captured;
      when(service.adviseFinance(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
        route: anyNamed('route'),
      )).thenAnswer((inv) {
        captured = inv.namedArguments[#context] as AiCoachContext;
        return advisorStreamOf(const AdvisorReply(text: 'Two bills.'));
      });

      final p = advisor();
      p.addAttachments([img(1), img(2)]);
      await p.sendWithAttachments('');

      expect(captured!.images.map((i) => i.first), [1, 2]);
      expect(captured!.imageMimeType, 'image/jpeg');
      expect(p.pendingImages, isEmpty);
      final userMsg = p.messages[p.messages.length - 2];
      expect(userMsg.images, hasLength(2));
      // An uncaptioned multi-image turn still asks something sensible.
      expect(userMsg.text, 'What do you make of these?');
      p.dispose();
    });

    test('retry resends the failed turn with all of its images', () async {
      var calls = 0;
      final seen = <int>[];
      when(service.adviseFinance(
        messages: anyNamed('messages'),
        context: anyNamed('context'),
        profile: anyNamed('profile'),
        historical: anyNamed('historical'),
        route: anyNamed('route'),
      )).thenAnswer((inv) {
        seen.add(
            (inv.namedArguments[#context] as AiCoachContext).images.length);
        calls++;
        if (calls == 1) {
          return Stream.error(
              const AiCoachException('Dropped.', retryable: true));
        }
        return advisorStreamOf(const AdvisorReply(text: 'ok'));
      });

      final p = advisor(retryHorizon: Duration.zero);
      p.addAttachments([img(1), img(2), img(3)]);
      await p.sendWithAttachments('compare these');
      expect(p.canRetryLastTurn, isTrue);
      await p.retryLastTurn();

      expect(seen, [3, 3]);
      p.dispose();
    });
  });
}
