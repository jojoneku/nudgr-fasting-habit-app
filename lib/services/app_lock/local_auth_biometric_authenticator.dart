import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'biometric_authenticator.dart';

/// [BiometricAuthenticator] over `local_auth`. Mobile only — see the note on
/// [BiometricAuthenticator] about keeping this import out of the web build.
class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (e) {
      debugPrint('LocalAuthBiometricAuthenticator: isAvailable failed: $e');
      return false;
    }
  }

  @override
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      debugPrint('LocalAuthBiometricAuthenticator: isDeviceSupported: $e');
      return false;
    }
  }

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: biometricOnly,
        // A confirm tap after face unlock is friction on a lock screen the
        // user opened on purpose.
        sensitiveTransaction: false,
      );
    } catch (e) {
      // Lockout, no hardware, cancelled by the system: all read as "not
      // unlocked", and the PIN keypad stays available.
      debugPrint('LocalAuthBiometricAuthenticator: authenticate failed: $e');
      return false;
    }
  }
}
