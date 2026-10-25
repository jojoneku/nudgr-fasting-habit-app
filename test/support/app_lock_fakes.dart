import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/app_lock/pin_verifier.dart';
import 'package:intermittent_fasting/presenters/app_lock_presenter.dart';
import 'package:intermittent_fasting/services/app_lock/app_lock_remote.dart';
import 'package:intermittent_fasting/services/app_lock/biometric_authenticator.dart';
import 'package:intermittent_fasting/services/app_lock/pin_verifier_cache.dart';
import 'package:intermittent_fasting/services/app_lock/privacy_flag_channel.dart';
import 'package:intermittent_fasting/services/storage_service.dart';

/// Only the app-lock storage members are real; anything else is a test bug.
class FakeLockStorage implements StorageService {
  String? device;
  String? verifier;

  @override
  Future<String?> loadAppLockDevice() async => device;

  @override
  Future<void> saveAppLockDevice(String json) async => device = json;

  @override
  Future<String?> loadAppLockVerifier() async => verifier;

  @override
  Future<void> saveAppLockVerifier(String? json) async => verifier = json;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeLockStorage: ${invocation.memberName}');
}

class FakeVerifierCache implements PinVerifierCache {
  PinVerifier? value;
  int writes = 0;

  @override
  Future<PinVerifier?> read() async => value;

  @override
  Future<void> write(PinVerifier? verifier) async {
    writes++;
    value = verifier;
  }
}

/// The account rows, keyed by user id, plus a switchable failure.
class FakeLockRemote implements AppLockRemote {
  final Map<String, PinVerifier?> rows = {};
  AppLockRemoteFailure? failWith;
  int fetches = 0;
  final Map<String, StreamController<void>> _doorbells = {};

  @override
  Future<PinVerifier?> fetch(String userId) async {
    fetches++;
    final failure = failWith;
    if (failure != null) throw AppLockRemoteException(failure);
    return rows[userId];
  }

  @override
  Future<void> put(String userId, PinVerifier? verifier) async {
    final failure = failWith;
    if (failure != null) throw AppLockRemoteException(failure);
    rows[userId] = verifier;
  }

  @override
  Stream<void> watch(String userId) =>
      (_doorbells[userId] ??= StreamController<void>.broadcast()).stream;

  /// Another device changed the row.
  void ring(String userId) => _doorbells[userId]?.add(null);
}

class FakeBiometrics implements BiometricAuthenticator {
  bool available = true;
  bool deviceSupported = true;
  bool result = true;
  final List<bool> calls = []; // biometricOnly per call

  /// Lets a test observe the presenter while the prompt is "open".
  Future<void> Function()? whilePrompting;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    calls.add(biometricOnly);
    await whilePrompting?.call();
    return result;
  }
}

class FakePrivacy extends PrivacyFlagChannel {
  final List<bool> calls = [];

  @override
  Future<void> setRecentsPrivacy(bool enabled) async => calls.add(enabled);
}

/// A stand-in for AuthPresenter.
class FakeLockAuth extends ChangeNotifier {
  String? userId;
  bool fresh = false;
  int signOuts = 0;

  AppLockAuth get asLockAuth => AppLockAuth(
        listenable: this,
        userId: () => userId,
        isFreshSignIn: () => fresh,
        signOut: () async {
          signOuts++;
          signOutNow();
        },
      );

  /// A real Google sign-in.
  void signIn(String id) {
    userId = id;
    fresh = true;
    notifyListeners();
  }

  /// A session restored from storage.
  void restore(String id) {
    userId = id;
    fresh = false;
    notifyListeners();
  }

  void signOutNow() {
    userId = null;
    fresh = false;
    notifyListeners();
  }
}
