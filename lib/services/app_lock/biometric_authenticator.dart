/// Device authentication for the app lock: biometrics, or the device's own
/// screen lock for Forgot PIN.
///
/// This file has no plugin import on purpose. Only the mobile root imports
/// `LocalAuthBiometricAuthenticator`, which keeps `local_auth` out of the web
/// bundle; web passes no authenticator at all.
abstract class BiometricAuthenticator {
  /// True when a biometric is enrolled and usable.
  Future<bool> isAvailable();

  /// True when the device has any screen lock (PIN, pattern, password, or
  /// biometric). Forgot PIN on mobile needs this.
  Future<bool> isDeviceSupported();

  /// Shows the system prompt. [biometricOnly] false also accepts the device
  /// PIN/pattern/password. Returns false on failure or cancel; never throws.
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  });
}
