import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/services/cloud_ai_coach_service.dart';

/// The `x-amz-content-sha256` header the advisor sends.
///
/// The advisor is reached through CloudFront, which SigV4-signs to the Lambda
/// behind it but cannot sign the body — so the client supplies the body's hash
/// and Lambda validates it. Get it wrong and every request is rejected at the
/// edge with a 403 that looks nothing like a hashing problem, which is why the
/// expected digests below are pinned rather than recomputed by the test.
void main() {
  test('matches the digest AWS computes for the same body', () {
    // Cross-checked against `printf '%s' '{}' | sha256sum`.
    expect(CloudAiCoachService.payloadHash('{}'),
        '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a');
    // And the empty body, which is what a GET/preflight would carry.
    expect(CloudAiCoachService.payloadHash(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });

  test('is lowercase hex, 64 chars', () {
    final h = CloudAiCoachService.payloadHash('{"op":"adviseFinance"}');
    expect(h, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('hashes the exact string, not a re-serialised copy', () {
    // These are the same JSON document and different bytes. The header must
    // describe the bytes on the wire, so they must NOT hash alike.
    expect(CloudAiCoachService.payloadHash('{"a":1}'),
        isNot(CloudAiCoachService.payloadHash('{"a": 1}')));
  });

  test('handles multi-byte characters the advisor actually sends', () {
    // A peso sign is three bytes in UTF-8, an em dash three more. Hashing
    // UTF-16 code units, or latin1, gives a different digest and a 403 nobody
    // could explain. Digest computed independently with `sha256sum`.
    expect(
      CloudAiCoachService.payloadHash('{"text":"₱40,000 — the DP"}'),
      'a8efbcbc42499be94682594b35f0bb084f89b0c6089db31109275154c1b68e58',
    );
  });
}
