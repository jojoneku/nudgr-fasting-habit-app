import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../models/app_lock/app_lock_device_state.dart';
import '../models/app_lock/app_lock_policy.dart';
import '../models/app_lock/pin_verifier.dart';
import '../services/app_lock/app_lock_remote.dart';
import '../services/app_lock/biometric_authenticator.dart';
import '../services/app_lock/pin_hasher.dart';
import '../services/app_lock/pin_verifier_cache.dart';
import '../services/app_lock/privacy_flag_channel.dart';
import '../services/storage_service.dart';
import 'auth_presenter.dart';

/// What the app lock needs from auth. The lock *reads* auth — it subscribes to
/// the owner (CLAUDE.md rule 8); auth never pushes into the lock.
class AppLockAuth {
  final Listenable listenable;

  /// The signed-in user, or null when signed out.
  final String? Function() userId;

  /// True when the latest auth change was a real sign-in that proved identity
  /// (not a restored session).
  final bool Function() isFreshSignIn;

  final Future<void> Function() signOut;

  const AppLockAuth({
    required this.listenable,
    required this.userId,
    required this.isFreshSignIn,
    required this.signOut,
  });

  factory AppLockAuth.fromPresenter(AuthPresenter auth) => AppLockAuth(
        listenable: auth,
        userId: () => auth.isSignedIn ? auth.userId : null,
        isFreshSignIn: () => auth.lastEvent == AuthChangeEvent.signedIn,
        signOut: auth.signOut,
      );
}

enum ForgotPinOutcome {
  /// Mobile: the device screen lock passed; the set-new-PIN gate is showing.
  resetStarted,

  /// Mobile: the device has no screen lock to prove the owner.
  noDeviceLock,

  /// Mobile: the device screen lock failed or was cancelled.
  cancelled,

  /// Web: signed out; the next sign-in on this device must set a new PIN.
  signedOut,
}

/// The app lock: one PIN per account, a per-device timeout and throttle, and
/// an opaque gate above every route (see openspec/changes/add-app-lock).
///
/// Owned by each app root (`FastingApp`, `TreasuryWebApp`), not by the
/// Treasury graph, because it guards the whole app.
///
/// **Exemptions.** Anything the app itself sends to the background — the photo
/// picker, Google sign-in, a file or URL launch, the biometric prompt — must
/// go through [runExempt], or "Lock after: Immediately" will demand the PIN
/// the moment it returns. A new call site that leaves the app needs the same.
class AppLockPresenter extends ChangeNotifier {
  AppLockPresenter({
    required StorageService storage,
    required PinVerifierCache cache,
    required AppLockRemote remote,
    required AppLockPolicy policy,
    BiometricAuthenticator? biometrics,
    PinHasher? hasher,
    PrivacyFlagChannel? privacy,
    DateTime Function()? clock,
    this.idleCheckInterval = const Duration(seconds: 15),
    this.activityPersistInterval = const Duration(seconds: 30),
  })  : _storage = storage,
        _cache = cache,
        _remote = remote,
        _policy = policy,
        _biometrics = biometrics,
        _hasher = hasher ?? PinHasher(),
        _privacy = privacy ?? PrivacyFlagChannel(),
        _clock = clock ?? DateTime.now;

  final StorageService _storage;
  final PinVerifierCache _cache;
  final AppLockRemote _remote;
  final AppLockPolicy _policy;
  final BiometricAuthenticator? _biometrics;
  final PinHasher _hasher;
  final PrivacyFlagChannel _privacy;
  final DateTime Function() _clock;
  final Duration idleCheckInterval;
  final Duration activityPersistInterval;

  static const String offlineMessage =
      'Connect to the internet to change your PIN.';
  static const String unavailableMessage = 'App lock is not available yet.';
  static const String saveFailedMessage = 'Could not save your PIN. Try again.';
  static const String noDeviceLockMessage =
      'Your phone has no screen lock. Use Forgot PIN on the web app to reset '
      'your PIN.';

  bool _initialized = false;
  bool _disposed = false;
  AppLockDeviceState _device = const AppLockDeviceState();
  PinVerifier? _verifier;
  String? _userId;
  bool _locked = false;
  int _lockGeneration = 0;
  int _autoPromptedGeneration = -1;
  bool _pinResetRequired = false;

  /// Set when the device screen lock proved the owner (mobile Forgot PIN).
  bool _resetAuthorized = false;
  bool _remoteUnavailable = false;
  bool _biometricsAvailable = false;
  bool _biometricInFlight = false;
  bool _verifying = false;
  bool _busy = false;
  String? _error;
  int _wrongPinSignal = 0;
  final Set<String> _suspendReasons = {};
  int _exemptDepth = 0;
  DateTime? _backgroundedAt;
  DateTime? _lastActivity;
  DateTime? _lastActivityPersisted;
  Timer? _idleTimer;
  Timer? _cooldownTicker;
  AppLockAuth? _auth;
  StreamSubscription<void>? _watchSub;

  // ── Public state ─────────────────────────────────────────────────────────

  /// The lock can be offered: a user is signed in and the backend has the
  /// `app_lock` table.
  bool get isAvailable => _userId != null && !_remoteUnavailable;
  bool get isSignedIn => _userId != null;
  bool get isEnabled => _verifier != null;
  bool get isLocked => _locked && isEnabled;
  bool get isSuspended => _suspendReasons.isNotEmpty;

  /// A new account PIN must be set (or the lock turned off) before content.
  bool get pinResetRequired => _pinResetRequired && isSignedIn;

  /// Content is hidden: before init, while locked, or while a PIN reset is
  /// owed. A live alarm suspends the gate.
  bool get isGated =>
      !isSuspended && (!_initialized || isLocked || pinResetRequired);
  bool get showLockScreen =>
      _initialized && !isSuspended && isLocked && !pinResetRequired;
  bool get showPinReset => _initialized && !isSuspended && pinResetRequired;

  int get pinLength => _verifier?.length ?? 6;
  List<Duration> get lockAfterOptions => _policy.lockAfterOptions;
  Duration get lockAfter {
    final seconds = _device.lockAfterSeconds;
    if (seconds == null) return _policy.defaultLockAfter;
    final stored = Duration(seconds: seconds);
    return _policy.lockAfterOptions.contains(stored)
        ? stored
        : _policy.defaultLockAfter;
  }

  /// This build can use biometrics at all (mobile). Hides the row on web.
  bool get supportsBiometrics => _biometrics != null;
  bool get biometricsAvailable => supportsBiometrics && _biometricsAvailable;
  bool get biometricsEnabled =>
      biometricsAvailable && _device.biometricsEnabled;

  /// Mobile: Forgot PIN uses the device screen lock. Web: sign out.
  bool get forgotPinSignsOut => _biometrics == null;

  int get failedAttempts => _device.failedAttempts;
  Duration? get cooldownRemaining {
    final until = _device.cooldownUntil;
    if (until == null) return null;
    final left = until.difference(_clock());
    return left > Duration.zero ? left : null;
  }

  bool get isCoolingDown => cooldownRemaining != null;
  bool get isVerifying => _verifying;

  /// The keypad takes input: not cooling down, not mid-check, not saving.
  bool get keypadEnabled => !isCoolingDown && !_verifying && !_busy;

  /// The line under the lock-screen title: the cooldown countdown wins over
  /// the last error.
  String? get statusMessage => isCoolingDown ? cooldownLabel : _error;
  bool get isBusy => _busy;
  String? get errorMessage => _error;

  /// Increments on every wrong PIN, so the keypad can shake on change.
  int get wrongPinSignal => _wrongPinSignal;

  /// The reset gate may offer "Turn off app lock" without the old PIN.
  bool get canTurnOffWithoutPin => _resetAuthorized || pinResetRequired;

  String labelForLockAfter(Duration d) {
    if (d == Duration.zero) return 'Immediately';
    if (d.inMinutes == 1) return 'After 1 minute';
    if (d.inMinutes == 60) return 'After 1 hour';
    return 'After ${d.inMinutes} minutes';
  }

  String get lockAfterLabel => labelForLockAfter(lockAfter);

  String get cooldownLabel {
    final left = cooldownRemaining;
    if (left == null) return '';
    final m = left.inMinutes;
    final s = (left.inSeconds % 60).toString().padLeft(2, '0');
    return 'Too many tries. Try again in $m:$s';
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// Reads this device's lock state. A cold start with a cached PIN locks
  /// before any content shows (the gate is opaque until this completes).
  Future<void> init() async {
    _device = AppLockDeviceState.decode(await _storage.loadAppLockDevice());
    _verifier = await _cache.read();
    final biometrics = _biometrics;
    if (biometrics != null) {
      _biometricsAvailable = await biometrics.isAvailable();
    }
    final now = _clock();
    if (_verifier != null) {
      if (_policy.lockOnEveryColdStart) {
        _lock(notify: false);
      } else {
        final last = _device.lastActivityAt;
        if (last == null || now.difference(last) >= lockAfter) {
          _lock(notify: false);
        }
      }
    }
    _lastActivity = now;
    _initialized = true;
    if (_policy.tracksIdleInput) {
      _idleTimer = Timer.periodic(idleCheckInterval, (_) => _checkIdle());
    }
    _startCooldownTickerIfNeeded();
    unawaited(_privacy.setRecentsPrivacy(isEnabled));
    _notify();
  }

  /// Subscribes to auth. Call right after the shell's `AuthPresenter.init()`,
  /// so a restored session is already visible.
  void bindAuth(AppLockAuth auth) {
    if (_auth != null) _auth!.listenable.removeListener(_onAuthChanged);
    _auth = auth;
    auth.listenable.addListener(_onAuthChanged);
    _onAuthChanged(initial: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _auth?.listenable.removeListener(_onAuthChanged);
    _idleTimer?.cancel();
    _cooldownTicker?.cancel();
    _watchSub?.cancel();
    super.dispose();
  }

  void _onAuthChanged({bool initial = false}) {
    final auth = _auth;
    if (auth == null) return;
    final uid = auth.userId();
    if (uid == _userId) {
      // No user ever attached, but a copy from a previous session is cached
      // (expired session, signed out elsewhere): drop it so the login screen
      // is not stuck behind a lock nobody can open.
      if (initial && uid == null && _verifier != null) {
        unawaited(_handleSignedOut());
      }
      return;
    }
    final previous = _userId;
    _userId = uid;
    if (uid == null) {
      unawaited(_handleSignedOut());
      return;
    }
    unawaited(_handleSignedIn(uid,
        fresh: !initial && auth.isFreshSignIn(), switched: previous != null));
  }

  Future<void> _handleSignedIn(String uid,
      {required bool fresh, required bool switched}) async {
    if (switched) {
      // Another account replaced this one without a sign-out event: the
      // cached PIN is the previous user's.
      _verifier = null;
      await _cache.write(null);
    }
    if (fresh) {
      // A Google sign-in in this session proved identity: start unlocked.
      _locked = false;
      _lastActivity = _clock();
      if (_device.pinResetPending) _pinResetRequired = true;
    }
    _watchSub?.cancel();
    _watchSub = _remote.watch(uid).listen((_) => unawaited(refresh()));
    _notify();
    await refresh();
  }

  Future<void> _handleSignedOut() async {
    _watchSub?.cancel();
    _watchSub = null;
    _userId = null;
    _verifier = null;
    _locked = false;
    _pinResetRequired = false;
    _resetAuthorized = false;
    _error = null;
    // The account PIN stays on the account; only this device's copy and its
    // throttle go. pinResetPending survives: the web Forgot PIN path sets it
    // right before this sign-out.
    _device = _device.withThrottleReset();
    _cooldownTicker?.cancel();
    _notify();
    await _cache.write(null);
    await _saveDevice();
    unawaited(_privacy.setRecentsPrivacy(false));
  }

  /// Re-reads the account PIN. Offline keeps the cached copy (unlock still
  /// works); a missing row turns the lock off; a refresh never unlocks.
  Future<void> refresh() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      final verifier = await _remote.fetch(uid);
      if (uid != _userId || _disposed) return;
      _remoteUnavailable = false;
      await _applyVerifier(verifier);
    } on AppLockRemoteException catch (e) {
      if (e.kind == AppLockRemoteFailure.unavailable && !_remoteUnavailable) {
        _remoteUnavailable = true;
        _notify();
      }
    }
  }

  Future<void> _applyVerifier(PinVerifier? verifier) async {
    final wasEnabled = isEnabled;
    final changed = verifier != _verifier;
    _verifier = verifier;
    if (verifier == null) {
      _locked = false;
      _pinResetRequired = false;
      _resetAuthorized = false;
      if (_device.pinResetPending) {
        _device = _device.copyWith(pinResetPending: false);
        await _saveDevice();
      }
    } else if (!wasEnabled) {
      // Turned on from another device: start the idle clock now rather than
      // locking at once mid-use.
      _lastActivity = _clock();
    }
    if (changed) await _cache.write(verifier);
    if (wasEnabled != isEnabled) {
      unawaited(_privacy.setRecentsPrivacy(isEnabled));
    }
    _notify();
  }

  // ── Activity & app lifecycle ─────────────────────────────────────────────

  /// Pointer / key input (web). Cheap: stores a timestamp, persists at most
  /// every [activityPersistInterval], never notifies.
  void recordActivity() {
    if (_locked) return;
    final now = _clock();
    _lastActivity = now;
    final persisted = _lastActivityPersisted;
    if (_policy.tracksIdleInput &&
        (persisted == null ||
            now.difference(persisted) >= activityPersistInterval)) {
      _lastActivityPersisted = now;
      _device = _device.copyWith(lastActivityAt: now);
      unawaited(_saveDevice());
    }
  }

  /// The app left the foreground (mobile) or the tab was hidden (web).
  void onBackgrounded() {
    if (_exemptDepth > 0 || !isEnabled) return;
    if (_policy.tracksIdleInput) {
      // Persist so a reload or a closed tab still knows the idle start.
      final last = _lastActivity;
      if (last != null) {
        _device = _device.copyWith(lastActivityAt: last);
        unawaited(_saveDevice());
      }
      return;
    }
    _backgroundedAt ??= _clock();
    // "Immediately": cover the content before the OS snapshots it.
    if (lockAfter == Duration.zero) _lock();
  }

  /// The app returned to the foreground (mobile) or the tab showed (web).
  void onForegrounded() {
    if (_exemptDepth > 0) {
      _backgroundedAt = null;
      return;
    }
    if (_policy.tracksIdleInput) {
      _checkIdle();
    } else {
      final away = _backgroundedAt;
      _backgroundedAt = null;
      if (away != null && _clock().difference(away) >= lockAfter) _lock();
    }
    unawaited(refresh());
  }

  void _checkIdle() {
    if (!isEnabled || _locked || _exemptDepth > 0) return;
    final last = _lastActivity;
    if (last != null && _clock().difference(last) >= lockAfter) _lock();
  }

  /// Runs [action] — something that sends the app to the background on the
  /// user's behalf — without it counting as leaving the app. Nests safely.
  Future<T> runExempt<T>(Future<T> Function() action) async {
    _exemptDepth++;
    try {
      return await action();
    } finally {
      _exemptDepth--;
      _backgroundedAt = null;
      _lastActivity = _clock();
    }
  }

  /// Hides the gate (e.g. 'alarm') without changing the lock state; the lock
  /// shows again once every reason resumes.
  void suspend(String reason) {
    if (_suspendReasons.add(reason)) _notify();
  }

  void resume(String reason) {
    if (_suspendReasons.remove(reason)) _notify();
  }

  // ── Locking & unlocking ──────────────────────────────────────────────────

  void lockNow() {
    if (isEnabled) _lock();
  }

  void _lock({bool notify = true}) {
    if (_locked) return;
    _locked = true;
    _lockGeneration++;
    _error = null;
    if (notify) _notify();
  }

  void _unlock() {
    _locked = false;
    _backgroundedAt = null;
    _lastActivity = _clock();
    _error = null;
    _notify();
  }

  /// Checks a PIN typed on the lock screen.
  Future<void> submitPin(String pin) async {
    if (!isLocked || _verifying || isCoolingDown) return;
    if (await _checkPin(pin)) _unlock();
  }

  /// The lock screen calls this when it shows; prompts once per lock.
  Future<void> maybeAutoPromptBiometrics() async {
    if (!biometricsEnabled || !showLockScreen) return;
    if (_autoPromptedGeneration == _lockGeneration) return;
    _autoPromptedGeneration = _lockGeneration;
    await unlockWithBiometrics();
  }

  Future<void> unlockWithBiometrics() async {
    final biometrics = _biometrics;
    if (biometrics == null || !biometricsEnabled || !isLocked) return;
    if (_biometricInFlight) return;
    _biometricInFlight = true;
    try {
      final ok = await runExempt(() => biometrics.authenticate(
            reason: 'Unlock the app',
            biometricOnly: true,
          ));
      if (ok && isLocked) {
        _device = _device.withThrottleReset();
        await _saveDevice();
        _unlock();
      }
    } finally {
      _biometricInFlight = false;
    }
  }

  /// Verifies [pin] and runs the per-device throttle. Wrong PINs count toward
  /// it wherever they are typed (lock screen, turn off, change PIN).
  Future<bool> _checkPin(String pin) async {
    final verifier = _verifier;
    if (verifier == null || isCoolingDown) return false;
    _verifying = true;
    _error = null;
    _notify();
    final ok = await _hasher.verify(pin, verifier);
    _verifying = false;
    if (ok) {
      _device = _device.withThrottleReset();
      await _saveDevice();
      _notify();
      return true;
    }
    final attempts = _device.failedAttempts + 1;
    final cooldown = AppLockPolicy.cooldownFor(attempts);
    _device = _device.copyWith(
      failedAttempts: attempts,
      cooldownUntil: cooldown == null ? null : _clock().add(cooldown),
    );
    _wrongPinSignal++;
    _error = 'Wrong PIN';
    await _saveDevice();
    _startCooldownTickerIfNeeded();
    _notify();
    final signOutAt = _policy.forcedSignOutAttempts;
    if (signOutAt != null && attempts >= signOutAt) {
      await _signOutForPinReset();
    }
    return false;
  }

  void _startCooldownTickerIfNeeded() {
    _cooldownTicker?.cancel();
    if (!isCoolingDown) return;
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!isCoolingDown) {
        t.cancel();
        _error = null;
      }
      _notify();
    });
  }

  // ── Forgot PIN ───────────────────────────────────────────────────────────

  Future<ForgotPinOutcome> forgotPin() async {
    final biometrics = _biometrics;
    if (biometrics == null) {
      await _signOutForPinReset();
      return ForgotPinOutcome.signedOut;
    }
    if (!await biometrics.isDeviceSupported()) {
      _error = noDeviceLockMessage;
      _notify();
      return ForgotPinOutcome.noDeviceLock;
    }
    final ok = await runExempt(() => biometrics.authenticate(
          reason: 'Confirm it is you to reset your app PIN',
          biometricOnly: false,
        ));
    if (!ok) return ForgotPinOutcome.cancelled;
    _resetAuthorized = true;
    _pinResetRequired = true;
    _device = _device.withThrottleReset();
    await _saveDevice();
    _unlock();
    return ForgotPinOutcome.resetStarted;
  }

  Future<void> _signOutForPinReset() async {
    _device = _device.copyWith(pinResetPending: true);
    await _saveDevice();
    final auth = _auth;
    if (auth != null) await auth.signOut();
  }

  // ── Settings commands ────────────────────────────────────────────────────

  /// Sets a new account PIN. Allowed when the lock is off, or during a reset
  /// (after the device screen lock or a fresh sign-in proved the owner).
  /// Write-through: nothing changes locally unless the account write lands.
  Future<bool> setNewPin(String pin) async {
    if (isEnabled && !canTurnOffWithoutPin) return false;
    if (!PinHasher.isValidPin(pin)) return false;
    return _writeVerifier(() => _hasher.hash(pin));
  }

  /// Changes the account PIN after checking the current one.
  Future<bool> changePin(String currentPin, String newPin) async {
    if (!isEnabled || !PinHasher.isValidPin(newPin)) return false;
    if (!await _checkPin(currentPin)) return false;
    return _writeVerifier(() => _hasher.hash(newPin));
  }

  /// Checks the current PIN without changing anything (the Change PIN flow
  /// asks for it first). Counts toward the throttle.
  Future<bool> verifyCurrentPin(String pin) => _checkPin(pin);

  /// Turns the lock off for the account after checking the current PIN.
  Future<bool> disable(String currentPin) async {
    if (!isEnabled) return true;
    if (!await _checkPin(currentPin)) return false;
    return _writeVerifier(() async => null);
  }

  /// Turns the lock off during a reset, where the old PIN is unknown.
  Future<bool> disableDuringReset() async {
    if (!canTurnOffWithoutPin) return false;
    return _writeVerifier(() async => null);
  }

  Future<bool> _writeVerifier(Future<PinVerifier?> Function() build) async {
    final uid = _userId;
    if (uid == null) return false;
    _busy = true;
    _error = null;
    _notify();
    try {
      final verifier = await build();
      await _remote.put(uid, verifier);
      if (uid != _userId) return false;
      _resetAuthorized = false;
      _pinResetRequired = false;
      _device = _device.withThrottleReset().copyWith(pinResetPending: false);
      await _saveDevice();
      _locked = false;
      _lastActivity = _clock();
      await _applyVerifier(verifier);
      return true;
    } on AppLockRemoteException catch (e) {
      _error = switch (e.kind) {
        AppLockRemoteFailure.offline => offlineMessage,
        AppLockRemoteFailure.unavailable => unavailableMessage,
        AppLockRemoteFailure.other => saveFailedMessage,
      };
      if (e.kind == AppLockRemoteFailure.unavailable) _remoteUnavailable = true;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> setLockAfter(Duration value) async {
    if (!_policy.lockAfterOptions.contains(value)) return;
    _device = _device.copyWith(lockAfterSeconds: value.inSeconds);
    _notify();
    await _saveDevice();
  }

  /// Turning biometrics on asks for one biometric first, so a broken sensor
  /// cannot be switched on and then fail at the lock screen.
  Future<bool> setBiometricsEnabled(bool value) async {
    final biometrics = _biometrics;
    if (biometrics == null) return false;
    if (value) {
      final ok = await runExempt(() => biometrics.authenticate(
            reason: 'Confirm your fingerprint or face',
            biometricOnly: true,
          ));
      if (!ok) return false;
    }
    _device = _device.copyWith(biometricsEnabled: value);
    _notify();
    await _saveDevice();
    return true;
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _saveDevice() => _storage.saveAppLockDevice(_device.encode());

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
