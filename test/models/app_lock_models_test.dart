import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/app_lock/app_lock_device_state.dart';
import 'package:intermittent_fasting/models/app_lock/app_lock_policy.dart';
import 'package:intermittent_fasting/models/app_lock/pin_verifier.dart';

void main() {
  group('PinVerifier', () {
    const verifier = PinVerifier(
      iterations: 1000,
      salt: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
      hash: [9, 8, 7, 6],
      length: 6,
    );

    test('round-trips through JSON and the encoded string', () {
      expect(PinVerifier.tryFromJson(verifier.toJson()), verifier);
      expect(PinVerifier.tryDecode(verifier.encode()), verifier);
    });

    test('reads malformed input as no verifier', () {
      expect(PinVerifier.tryFromJson(null), isNull);
      expect(PinVerifier.tryFromJson('nope'), isNull);
      expect(PinVerifier.tryFromJson({'iterations': 1000}), isNull);
      expect(
          PinVerifier.tryFromJson({...verifier.toJson(), 'length': 5}), isNull);
      expect(PinVerifier.tryFromJson({...verifier.toJson(), 'salt': '%%%'}),
          isNull);
      expect(PinVerifier.tryDecode('{not json'), isNull);
      expect(PinVerifier.tryDecode(null), isNull);
    });
  });

  group('AppLockDeviceState', () {
    test('round-trips every field', () {
      final state = AppLockDeviceState(
        lockAfterSeconds: 300,
        biometricsEnabled: true,
        failedAttempts: 6,
        cooldownUntil: DateTime(2026, 10, 25, 9, 30),
        lastActivityAt: DateTime(2026, 10, 25, 9, 0),
        pinResetPending: true,
      );
      final back = AppLockDeviceState.decode(state.encode());
      expect(back.lockAfterSeconds, 300);
      expect(back.biometricsEnabled, isTrue);
      expect(back.failedAttempts, 6);
      expect(back.cooldownUntil, DateTime(2026, 10, 25, 9, 30));
      expect(back.lastActivityAt, DateTime(2026, 10, 25, 9, 0));
      expect(back.pinResetPending, isTrue);
    });

    test('missing or broken blobs fall back to defaults', () {
      for (final source in [null, '', '{', '[]', '{"failedAttempts":"x"}']) {
        final state = AppLockDeviceState.decode(source);
        expect(state.failedAttempts, 0, reason: 'source: $source');
        expect(state.lockAfterSeconds, isNull);
        expect(state.pinResetPending, isFalse);
      }
    });

    test('withThrottleReset clears the count and cooldown only', () {
      final state = AppLockDeviceState(
        lockAfterSeconds: 60,
        failedAttempts: 7,
        cooldownUntil: DateTime(2026),
        pinResetPending: true,
      ).withThrottleReset();
      expect(state.failedAttempts, 0);
      expect(state.cooldownUntil, isNull);
      expect(state.lockAfterSeconds, 60);
      expect(state.pinResetPending, isTrue);
    });
  });

  group('AppLockPolicy.cooldownFor', () {
    test('no cooldown before 5 wrong PINs', () {
      for (var i = 0; i < 5; i++) {
        expect(AppLockPolicy.cooldownFor(i), isNull);
      }
    });

    test('30 s at 5, doubling, capped at 15 min', () {
      expect(AppLockPolicy.cooldownFor(5), const Duration(seconds: 30));
      expect(AppLockPolicy.cooldownFor(6), const Duration(minutes: 1));
      expect(AppLockPolicy.cooldownFor(7), const Duration(minutes: 2));
      expect(AppLockPolicy.cooldownFor(9), const Duration(minutes: 8));
      expect(AppLockPolicy.cooldownFor(10), const Duration(minutes: 15));
      expect(AppLockPolicy.cooldownFor(40), const Duration(minutes: 15));
    });
  });
}
