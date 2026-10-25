import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/app_lock/pin_verifier.dart';
import '../storage_service.dart';

/// This device's copy of the account's PIN verifier, so unlock works offline.
///
/// It holds one entry, for the signed-in user. Sign-out deletes it, so a second
/// account on a shared laptop never inherits the first user's lock.
abstract class PinVerifierCache {
  Future<PinVerifier?> read();

  /// Null deletes the copy.
  Future<void> write(PinVerifier? verifier);
}

/// Mobile: the platform keystore, like [SecureSessionStorage].
class SecurePinVerifierCache implements PinVerifierCache {
  SecurePinVerifierCache({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const String key = 'app_lock.verifier';

  final FlutterSecureStorage _secureStorage;

  @override
  Future<PinVerifier?> read() async {
    try {
      return PinVerifier.tryDecode(await _secureStorage.read(key: key));
    } catch (e) {
      // A keystore hiccup must not crash the lock screen. Reading as "no
      // copy" is safe: the presenter re-fetches the account row when online.
      debugPrint('SecurePinVerifierCache: read failed: $e');
      return null;
    }
  }

  @override
  Future<void> write(PinVerifier? verifier) async {
    if (verifier == null) {
      await _secureStorage.delete(key: key);
    } else {
      await _secureStorage.write(key: key, value: verifier.encode());
    }
  }
}

/// Web: device-level prefs through [StorageService]. Browser storage gives no
/// key protection, which the change's non-goals accept — the hash is not the
/// real protection anyway.
class StoragePinVerifierCache implements PinVerifierCache {
  StoragePinVerifierCache(this._storage);

  final StorageService _storage;

  @override
  Future<PinVerifier?> read() async =>
      PinVerifier.tryDecode(await _storage.loadAppLockVerifier());

  @override
  Future<void> write(PinVerifier? verifier) =>
      _storage.saveAppLockVerifier(verifier?.encode());
}
