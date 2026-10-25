import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/app_lock/app_lock_device_state.dart';
import 'package:intermittent_fasting/services/app_lock/app_lock_remote.dart';
import 'package:intermittent_fasting/services/app_lock/pin_hasher.dart';
import 'package:intermittent_fasting/services/app_lock/pin_verifier_cache.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late LocalStorageService storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
  });

  group('app lock device state (device-level)', () {
    test('round-trips and is absent by default', () async {
      expect(await storage.loadAppLockDevice(), isNull);
      const state = AppLockDeviceState(lockAfterSeconds: 300);
      await storage.saveAppLockDevice(state.encode());
      final back = AppLockDeviceState.decode(await storage.loadAppLockDevice());
      expect(back.lockAfterSeconds, 300);
    });

    test('survives a user switch and clearUserData', () async {
      await storage.setUserId('user-1');
      await storage.saveAppLockDevice(
          const AppLockDeviceState(failedAttempts: 2).encode());
      storage.detachUser();
      await storage.setUserId('user-2');
      await storage.clearUserData();
      final back = AppLockDeviceState.decode(await storage.loadAppLockDevice());
      expect(back.failedAttempts, 2);
    });
  });

  group('StoragePinVerifierCache (web)', () {
    test('writes, reads, and deletes the copy', () async {
      final cache = StoragePinVerifierCache(storage);
      expect(await cache.read(), isNull);
      final verifier =
          await PinHasher(iterations: 200, offThread: false).hash('1234');
      await cache.write(verifier);
      expect(await cache.read(), verifier);
      await cache.write(null);
      expect(await cache.read(), isNull);
      expect(await storage.loadAppLockVerifier(), isNull);
    });
  });

  group('SupabaseAppLockRemote.classify', () {
    test('a missing table means the feature is unavailable', () {
      expect(
        SupabaseAppLockRemote.classify(
            const PostgrestException(message: 'nope', code: '42P01')),
        AppLockRemoteFailure.unavailable,
      );
      expect(
        SupabaseAppLockRemote.classify(
            const PostgrestException(message: 'nope', code: 'PGRST205')),
        AppLockRemoteFailure.unavailable,
      );
    });

    test('timeouts and socket errors mean offline', () {
      expect(SupabaseAppLockRemote.classify(TimeoutException('slow')),
          AppLockRemoteFailure.offline);
      expect(
        SupabaseAppLockRemote.classify(
            Exception('ClientException with SocketException: Failed host '
                'lookup')),
        AppLockRemoteFailure.offline,
      );
    });

    test('anything else is other', () {
      expect(
        SupabaseAppLockRemote.classify(
            const PostgrestException(message: 'denied', code: '42501')),
        AppLockRemoteFailure.other,
      );
      expect(SupabaseAppLockRemote.classify(StateError('x')),
          AppLockRemoteFailure.other);
    });
  });
}
