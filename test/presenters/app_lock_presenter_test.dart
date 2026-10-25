import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/app_lock/app_lock_device_state.dart';
import 'package:intermittent_fasting/models/app_lock/app_lock_policy.dart';
import 'package:intermittent_fasting/models/app_lock/pin_verifier.dart';
import 'package:intermittent_fasting/presenters/app_lock_presenter.dart';
import 'package:intermittent_fasting/services/app_lock/app_lock_remote.dart';
import 'package:intermittent_fasting/services/app_lock/pin_hasher.dart';

import '../support/app_lock_fakes.dart';

const _pin = '482916';
const _user = 'user-1';

void main() {
  late FakeLockStorage storage;
  late FakeVerifierCache cache;
  late FakeLockRemote remote;
  late FakeBiometrics biometrics;
  late FakePrivacy privacy;
  late FakeLockAuth auth;
  late DateTime now;
  final hasher = PinHasher(iterations: 500, offThread: false);
  late PinVerifier verifier;

  setUpAll(() async {
    verifier = await hasher.hash(_pin);
  });

  setUp(() {
    storage = FakeLockStorage();
    cache = FakeVerifierCache();
    remote = FakeLockRemote();
    biometrics = FakeBiometrics();
    privacy = FakePrivacy();
    auth = FakeLockAuth();
    now = DateTime(2026, 10, 25, 9);
  });

  AppLockPresenter build({bool web = false, bool withBiometrics = true}) =>
      AppLockPresenter(
        storage: storage,
        cache: cache,
        remote: remote,
        policy: web ? AppLockPolicy.web : AppLockPolicy.mobile,
        biometrics: web || !withBiometrics ? null : biometrics,
        hasher: hasher,
        privacy: privacy,
        clock: () => now,
      );

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// An account that already has a PIN, signed in on this device before.
  Future<AppLockPresenter> lockedMobile() async {
    remote.rows[_user] = verifier;
    cache.value = verifier;
    final p = build();
    await p.init();
    auth.restore(_user);
    p.bindAuth(auth.asLockAuth);
    await settle();
    return p;
  }

  group('cold start', () {
    test('gated until init finishes', () {
      final p = build();
      expect(p.isGated, isTrue);
      expect(p.showLockScreen, isFalse);
    });

    test('mobile with a cached PIN locks before auth attaches', () async {
      cache.value = verifier;
      final p = build();
      await p.init();
      expect(p.isLocked, isTrue);
      expect(p.showLockScreen, isTrue);
      expect(privacy.calls.last, isTrue);
    });

    test('no cached PIN means no lock', () async {
      final p = build();
      await p.init();
      expect(p.isEnabled, isFalse);
      expect(p.isGated, isFalse);
    });

    test('a restored session keeps the cold-start lock', () async {
      final p = await lockedMobile();
      expect(p.isLocked, isTrue);
      expect(remote.fetches, greaterThan(0));
    });

    test('web reload locks only when the idle time already passed', () async {
      cache.value = verifier;
      storage.device = AppLockDeviceState(
        lastActivityAt: now.subtract(const Duration(seconds: 30)),
      ).encode();
      final early = build(web: true);
      await early.init();
      expect(early.isLocked, isFalse);
      early.dispose();

      storage.device = AppLockDeviceState(
        lastActivityAt: now.subtract(const Duration(minutes: 10)),
      ).encode();
      final late = build(web: true);
      await late.init();
      expect(late.isLocked, isTrue);
      late.dispose();
    });

    test('a stale cached PIN with nobody signed in is dropped', () async {
      cache.value = verifier;
      final p = build();
      await p.init();
      p.bindAuth(auth.asLockAuth); // auth restored no session
      await settle();
      expect(p.isLocked, isFalse);
      expect(cache.value, isNull);
    });
  });

  group('sign-in and sign-out', () {
    test('a fresh sign-in fetches the account PIN and starts unlocked',
        () async {
      remote.rows[_user] = verifier;
      final p = build();
      await p.init();
      p.bindAuth(auth.asLockAuth);
      auth.signIn(_user);
      await settle();
      expect(p.isEnabled, isTrue);
      expect(p.isLocked, isFalse);
      expect(cache.value, verifier);
    });

    test('sign-out deletes the device copy but keeps the account PIN',
        () async {
      final p = await lockedMobile();
      auth.signOutNow();
      await settle();
      expect(p.isEnabled, isFalse);
      expect(p.isLocked, isFalse);
      expect(cache.value, isNull);
      expect(remote.rows[_user], verifier);

      auth.signIn(_user);
      await settle();
      expect(p.isEnabled, isTrue, reason: 'same PIN after signing in again');
    });

    test('a second account without a PIN sees no lock', () async {
      final p = await lockedMobile();
      auth.signOutNow();
      await settle();
      auth.signIn('user-2');
      await settle();
      expect(p.isEnabled, isFalse);
      expect(cache.value, isNull);
    });

    test('sign-out resets the throttle and keeps device preferences', () async {
      storage.device = const AppLockDeviceState(
        lockAfterSeconds: 300,
        failedAttempts: 3,
      ).encode();
      final p = await lockedMobile();
      auth.signOutNow();
      await settle();
      final saved = AppLockDeviceState.decode(storage.device);
      expect(saved.failedAttempts, 0);
      expect(saved.lockAfterSeconds, 300);
      expect(p.lockAfter, const Duration(minutes: 5));
    });
  });

  group('refresh', () {
    test('offline keeps the cached PIN, so unlock still works', () async {
      final p = await lockedMobile();
      remote.failWith = AppLockRemoteFailure.offline;
      await p.refresh();
      expect(p.isEnabled, isTrue);
      await p.submitPin(_pin);
      expect(p.isLocked, isFalse);
    });

    test('a removed account PIN turns the lock off here', () async {
      final p = await lockedMobile();
      remote.rows[_user] = null;
      remote.ring(_user);
      await settle();
      expect(p.isEnabled, isFalse);
      expect(p.isLocked, isFalse);
      expect(cache.value, isNull);
    });

    test('a changed PIN replaces the copy but never unlocks', () async {
      final p = await lockedMobile();
      final newer = await hasher.hash('1234');
      remote.rows[_user] = newer;
      remote.ring(_user);
      await settle();
      expect(p.isLocked, isTrue);
      expect(cache.value, newer);
      await p.submitPin(_pin);
      expect(p.isLocked, isTrue, reason: 'the old PIN no longer works');
      await p.submitPin('1234');
      expect(p.isLocked, isFalse);
    });

    test('a missing table hides the lock settings', () async {
      final p = build();
      await p.init();
      remote.failWith = AppLockRemoteFailure.unavailable;
      p.bindAuth(auth.asLockAuth);
      auth.signIn(_user);
      await settle();
      expect(p.isSignedIn, isTrue);
      expect(p.isAvailable, isFalse);
    });
  });

  group('setting and changing the PIN', () {
    Future<AppLockPresenter> signedInWithoutPin({bool web = false}) async {
      final p = build(web: web);
      await p.init();
      p.bindAuth(auth.asLockAuth);
      auth.signIn(_user);
      await settle();
      return p;
    }

    test('setNewPin writes the account first, then this device', () async {
      final p = await signedInWithoutPin();
      expect(await p.setNewPin('1234'), isTrue);
      expect(remote.rows[_user], isNotNull);
      expect(cache.value, remote.rows[_user]);
      expect(p.isEnabled, isTrue);
      expect(p.isLocked, isFalse);
      expect(p.pinLength, 4);
      expect(privacy.calls.last, isTrue);
    });

    test('offline setNewPin changes nothing and says why', () async {
      final p = await signedInWithoutPin();
      remote.failWith = AppLockRemoteFailure.offline;
      expect(await p.setNewPin('1234'), isFalse);
      expect(p.isEnabled, isFalse);
      expect(cache.value, isNull);
      expect(p.errorMessage, AppLockPresenter.offlineMessage);
    });

    test('setNewPin is refused while a PIN exists', () async {
      final p = await lockedMobile();
      await p.submitPin(_pin);
      expect(await p.setNewPin('1234'), isFalse);
      expect(remote.rows[_user], verifier);
    });

    test('disable needs the current PIN and turns it off for the account',
        () async {
      final p = await lockedMobile();
      await p.submitPin(_pin);
      expect(await p.disable('000000'), isFalse);
      expect(p.failedAttempts, 1);
      expect(remote.rows[_user], verifier);
      expect(await p.disable(_pin), isTrue);
      expect(remote.rows.containsKey(_user), isTrue);
      expect(remote.rows[_user], isNull);
      expect(p.isEnabled, isFalse);
      expect(privacy.calls.last, isFalse);
    });

    test('changePin checks the old PIN, then replaces it', () async {
      final p = await lockedMobile();
      await p.submitPin(_pin);
      expect(await p.changePin('000000', '1234'), isFalse);
      expect(await p.changePin(_pin, '1234'), isTrue);
      expect(await hasher.verify('1234', remote.rows[_user]!), isTrue);
    });

    test('no PIN appears in anything stored', () async {
      final p = await signedInWithoutPin(web: true);
      await p.setNewPin('482916');
      expect(cache.value!.encode(), isNot(contains('482916')));
      expect(remote.rows[_user]!.encode(), isNot(contains('482916')));
      expect(storage.device ?? '', isNot(contains('482916')));
    });
  });

  group('unlock and throttle', () {
    test('the correct PIN unlocks; a wrong one says so', () async {
      final p = await lockedMobile();
      await p.submitPin('000000');
      expect(p.isLocked, isTrue);
      expect(p.errorMessage, 'Wrong PIN');
      expect(p.wrongPinSignal, 1);
      await p.submitPin(_pin);
      expect(p.isLocked, isFalse);
      expect(p.failedAttempts, 0);
    });

    test('5 wrong PINs start a 30 s cooldown that survives a restart',
        () async {
      final p = await lockedMobile();
      for (var i = 0; i < 5; i++) {
        await p.submitPin('000000');
      }
      expect(p.isCoolingDown, isTrue);
      expect(p.cooldownRemaining, const Duration(seconds: 30));
      await p.submitPin(_pin);
      expect(p.isLocked, isTrue, reason: 'blocked during the cooldown');
      p.dispose();

      final restarted = build();
      await restarted.init();
      expect(restarted.isCoolingDown, isTrue);
      now = now.add(const Duration(seconds: 31));
      expect(restarted.isCoolingDown, isFalse);
      await restarted.submitPin(_pin);
      expect(restarted.isLocked, isFalse);
      restarted.dispose();
    });

    test('web signs out at the 10th wrong PIN and owes a new PIN', () async {
      remote.rows[_user] = verifier;
      cache.value = verifier;
      final p = build(web: true);
      await p.init();
      auth.restore(_user);
      p.bindAuth(auth.asLockAuth);
      await settle();
      expect(p.isLocked, isTrue);
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(minutes: 16)); // past any cooldown
        await p.submitPin('000000');
        await settle();
      }
      expect(auth.signOuts, 1);
      expect(p.isSignedIn, isFalse);
      expect(remote.rows[_user], verifier, reason: 'the account keeps it');

      auth.signIn(_user);
      await settle();
      expect(p.pinResetRequired, isTrue);
      expect(p.showPinReset, isTrue);
      expect(await p.setNewPin('1234'), isTrue);
      expect(p.pinResetRequired, isFalse);
      expect(
          AppLockDeviceState.decode(storage.device).pinResetPending, isFalse);
    });

    test('mobile never signs out on wrong PINs', () async {
      final p = await lockedMobile();
      for (var i = 0; i < 12; i++) {
        now = now.add(const Duration(minutes: 16));
        await p.submitPin('000000');
      }
      expect(auth.signOuts, 0);
      expect(p.isSignedIn, isTrue);
    });
  });

  group('mobile background timing', () {
    Future<AppLockPresenter> unlocked() async {
      final p = await lockedMobile();
      await p.submitPin(_pin);
      return p;
    }

    test('returning before the timeout stays unlocked', () async {
      final p = await unlocked();
      await p.setLockAfter(const Duration(minutes: 5));
      p.onBackgrounded();
      now = now.add(const Duration(minutes: 2));
      p.onForegrounded();
      expect(p.isLocked, isFalse);
    });

    test('returning after the timeout locks', () async {
      final p = await unlocked();
      p.onBackgrounded();
      now = now.add(const Duration(minutes: 3));
      p.onForegrounded();
      expect(p.isLocked, isTrue);
    });

    test('Immediately locks as the app leaves', () async {
      final p = await unlocked();
      await p.setLockAfter(Duration.zero);
      p.onBackgrounded();
      expect(p.isLocked, isTrue);
    });

    test('an exempt trip to the photo picker never locks', () async {
      final p = await unlocked();
      await p.setLockAfter(Duration.zero);
      await p.runExempt(() async {
        p.onBackgrounded();
        now = now.add(const Duration(minutes: 10));
        p.onForegrounded();
      });
      expect(p.isLocked, isFalse);
    });

    test('lockNow locks at once', () async {
      final p = await unlocked();
      p.lockNow();
      expect(p.isLocked, isTrue);
    });
  });

  group('web idle timing', () {
    test('locks after the idle time, including hidden-tab time', () {
      fakeAsync((async) {
        remote.rows[_user] = verifier;
        cache.value = verifier;
        storage.device = AppLockDeviceState(lastActivityAt: now).encode();
        final p = AppLockPresenter(
          storage: storage,
          cache: cache,
          remote: remote,
          policy: AppLockPolicy.web,
          hasher: hasher,
          privacy: privacy,
          clock: () => now,
          idleCheckInterval: const Duration(seconds: 15),
        );
        p.init();
        async.flushMicrotasks();
        expect(p.isLocked, isFalse);

        // Activity keeps it open.
        now = now.add(const Duration(minutes: 4));
        p.recordActivity();
        now = now.add(const Duration(minutes: 4));
        async.elapse(const Duration(seconds: 15));
        expect(p.isLocked, isFalse);

        // 5 idle minutes lock it on the next check.
        now = now.add(const Duration(minutes: 1, seconds: 1));
        async.elapse(const Duration(seconds: 15));
        expect(p.isLocked, isTrue);
        p.dispose();
      });
    });

    test('a hidden tab past the timeout locks on show', () async {
      remote.rows[_user] = verifier;
      cache.value = verifier;
      storage.device = AppLockDeviceState(lastActivityAt: now).encode();
      final p = build(web: true);
      await p.init();
      await p.setLockAfter(const Duration(minutes: 15));
      p.onBackgrounded();
      now = now.add(const Duration(minutes: 20));
      p.onForegrounded();
      expect(p.isLocked, isTrue);
      p.dispose();
    });

    test('activity persists at most every 30 s', () async {
      final p = build(web: true);
      await p.init();
      p.recordActivity();
      final first = storage.device;
      now = now.add(const Duration(seconds: 10));
      p.recordActivity();
      expect(storage.device, first);
      now = now.add(const Duration(seconds: 25));
      p.recordActivity();
      expect(storage.device, isNot(first));
      p.dispose();
    });
  });

  group('suspend (alarm)', () {
    test('hides the lock screen without unlocking', () async {
      final p = await lockedMobile();
      p.suspend('alarm');
      expect(p.showLockScreen, isFalse);
      expect(p.isGated, isFalse);
      expect(p.isLocked, isTrue);
      p.resume('alarm');
      expect(p.showLockScreen, isTrue);
    });

    test('a lock that falls due during the alarm shows after it', () async {
      final p = await lockedMobile();
      await p.submitPin(_pin);
      p.suspend('alarm');
      p.lockNow();
      expect(p.showLockScreen, isFalse);
      p.resume('alarm');
      expect(p.showLockScreen, isTrue);
    });
  });

  group('biometrics', () {
    Future<AppLockPresenter> withBiometricsOn() async {
      storage.device =
          const AppLockDeviceState(biometricsEnabled: true).encode();
      return lockedMobile();
    }

    test('auto-prompts once per lock and unlocks', () async {
      final p = await withBiometricsOn();
      await p.maybeAutoPromptBiometrics();
      expect(biometrics.calls, [true]);
      expect(p.isLocked, isFalse);
      p.lockNow();
      await p.maybeAutoPromptBiometrics();
      await p.maybeAutoPromptBiometrics();
      expect(biometrics.calls, hasLength(2));
    });

    test('a cancelled prompt leaves the PIN as the backup', () async {
      final p = await withBiometricsOn();
      biometrics.result = false;
      await p.unlockWithBiometrics();
      expect(p.isLocked, isTrue);
      expect(p.failedAttempts, 0, reason: 'biometric misses do not count');
      await p.submitPin(_pin);
      expect(p.isLocked, isFalse);
    });

    test('the prompt pausing the app does not loop into a new lock', () async {
      final p = await withBiometricsOn();
      await p.setLockAfter(Duration.zero);
      biometrics.whilePrompting = () async {
        p.onBackgrounded();
        now = now.add(const Duration(seconds: 5));
        p.onForegrounded();
      };
      await p.unlockWithBiometrics();
      expect(p.isLocked, isFalse);
      expect(biometrics.calls, hasLength(1));
    });

    test('hidden when no biometric is enrolled', () async {
      biometrics.available = false;
      final p = await lockedMobile();
      expect(p.supportsBiometrics, isTrue);
      expect(p.biometricsAvailable, isFalse);
      expect(p.biometricsEnabled, isFalse);
    });

    test('turning it on needs one successful biometric', () async {
      final p = await lockedMobile();
      await p.submitPin(_pin);
      biometrics.result = false;
      expect(await p.setBiometricsEnabled(true), isFalse);
      expect(p.biometricsEnabled, isFalse);
      biometrics.result = true;
      expect(await p.setBiometricsEnabled(true), isTrue);
      expect(p.biometricsEnabled, isTrue);
    });

    test('web has no biometric option', () async {
      final p = build(web: true);
      await p.init();
      expect(p.supportsBiometrics, isFalse);
      expect(p.forgotPinSignsOut, isTrue);
      p.dispose();
    });
  });

  group('forgot PIN on mobile', () {
    test('the device screen lock unlocks and owes a new PIN', () async {
      final p = await lockedMobile();
      expect(await p.forgotPin(), ForgotPinOutcome.resetStarted);
      expect(biometrics.calls.last, isFalse, reason: 'device credential ok');
      expect(p.isLocked, isFalse);
      expect(p.showPinReset, isTrue);
      expect(await p.setNewPin('1234'), isTrue);
      expect(p.showPinReset, isFalse);
      expect(await hasher.verify('1234', remote.rows[_user]!), isTrue);
    });

    test('the reset can turn the lock off instead', () async {
      final p = await lockedMobile();
      await p.forgotPin();
      expect(await p.disableDuringReset(), isTrue);
      expect(remote.rows[_user], isNull);
      expect(p.isEnabled, isFalse);
    });

    test('no device screen lock explains the web path', () async {
      biometrics.deviceSupported = false;
      final p = await lockedMobile();
      expect(await p.forgotPin(), ForgotPinOutcome.noDeviceLock);
      expect(p.errorMessage, AppLockPresenter.noDeviceLockMessage);
      expect(p.isLocked, isTrue);
    });

    test('a failed device check changes nothing', () async {
      final p = await lockedMobile();
      biometrics.result = false;
      expect(await p.forgotPin(), ForgotPinOutcome.cancelled);
      expect(p.isLocked, isTrue);
      expect(p.showPinReset, isFalse);
      expect(await p.disableDuringReset(), isFalse);
    });
  });
}
