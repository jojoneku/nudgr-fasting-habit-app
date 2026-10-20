import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_chat_message.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/services/cloud_ai_coach_service.dart';

/// What `adviseFinance` sends for the images attached to a turn.
///
/// The backend reads `images: [{base64, mime_type}]`. A Lambda deployed before
/// multi-image send reads only `image_base64` + `mime_type`, and the app can
/// reach users before that deploy does — so the single field must still carry
/// the first image, or the photo silently vanishes for them.
void main() {
  Map<String, Object?> payloadFor(List<Uint8List> images) =>
      CloudAiCoachService.advisorPayload(
        messages: [AiChatMessage.user('what are these?', images: images)],
        context: AiCoachContext(
          entryPoint: AiCoachEntryPoint.financeAdvisor,
          images: images,
          imageMimeType: images.isEmpty ? null : 'image/jpeg',
        ),
      );

  final a = Uint8List.fromList([1, 2, 3]);
  final b = Uint8List.fromList([4, 5, 6]);
  final c = Uint8List.fromList([7, 8, 9]);

  test('carries every attached image, in order, as its own entry', () {
    final payload = payloadFor([a, b, c]);
    final images = payload['images']! as List;

    expect(images, hasLength(3));
    expect([for (final i in images) (i as Map)['base64']],
        [base64Encode(a), base64Encode(b), base64Encode(c)]);
    expect([for (final i in images) (i as Map)['mime_type']],
        everyElement('image/jpeg'));
  });

  test('mirrors the first image into the single field an older Lambda reads',
      () {
    final payload = payloadFor([a, b]);

    expect(payload['image_base64'], base64Encode(a));
    expect(payload['mime_type'], 'image/jpeg');
  });

  test('a turn without images sends no image fields at all', () {
    final payload = payloadFor(const []);

    expect(payload.containsKey('images'), isFalse);
    expect(payload.containsKey('image_base64'), isFalse);
    expect(payload.containsKey('mime_type'), isFalse);
  });

  test('images are never replayed into the message history', () {
    final payload = payloadFor([a, b]);
    final messages = payload['messages']! as List;

    expect(jsonEncode(messages), isNot(contains(base64Encode(a))));
  });

  test('the request size guard trips past the Lambda limit, not before', () {
    final atLimit = 'x' * CloudAiCoachService.maxAdvisorRequestBytes;
    expect(CloudAiCoachService.exceedsAdvisorRequestLimit(atLimit), isFalse);
    expect(
        CloudAiCoachService.exceedsAdvisorRequestLimit('${atLimit}x'), isTrue);
    // Counted in UTF-8 bytes: a peso sign is three of them.
    final pesos = '₱' * (CloudAiCoachService.maxAdvisorRequestBytes ~/ 3 + 1);
    expect(CloudAiCoachService.exceedsAdvisorRequestLimit(pesos), isTrue);
  });
}
