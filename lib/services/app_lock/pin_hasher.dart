import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../models/app_lock/pin_verifier.dart';

/// Hashes and checks app-lock PINs with PBKDF2-HMAC-SHA256.
///
/// Be honest about what this buys: a 4–6 digit PIN has at most 10⁶ values, so
/// anyone who can read a verifier can brute-force it whatever the KDF cost.
/// The hash only keeps the PIN out of plain text; the real protection is the
/// per-device wrong-PIN throttle in [AppLockPresenter]. That is why the cost
/// is tuned for a snappy unlock rather than maximum stretch.
class PinHasher {
  /// Measured 2026-10-25 on the Dart VM (desktop, JIT, pure-Dart PBKDF2):
  /// 50k ≈ 300 ms, 100k ≈ 600–700 ms, 200k ≈ 1.4 s per derive. 40k keeps an
  /// unlock near 250 ms there; AOT on a phone is in the same range, and web
  /// derives through WebCrypto, which is far faster. Stored per verifier, so
  /// it can rise later without a migration.
  static const int defaultIterations = 40000;
  static const int saltBytes = 16;
  static const int hashBits = 256;

  final int iterations;
  final Random _random;

  /// False runs the derive on the calling isolate (tests under `fake_async`,
  /// where a spawned isolate's reply never arrives).
  final bool offThread;

  PinHasher({
    this.iterations = defaultIterations,
    Random? random,
    this.offThread = true,
  }) : _random = random ?? Random.secure();

  static bool isValidPin(String pin) =>
      (pin.length == 4 || pin.length == 6) &&
      pin.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

  Future<PinVerifier> hash(String pin) async {
    if (!isValidPin(pin)) {
      throw ArgumentError('A PIN is 4 or 6 digits.');
    }
    final salt = List<int>.generate(saltBytes, (_) => _random.nextInt(256));
    return PinVerifier(
      iterations: iterations,
      salt: salt,
      hash: await _derive(pin, salt, iterations, offThread),
      length: pin.length,
    );
  }

  Future<bool> verify(String pin, PinVerifier verifier) async {
    if (verifier.algorithm != PinVerifier.pbkdf2Sha256) return false;
    if (pin.length != verifier.length || !isValidPin(pin)) return false;
    final candidate =
        await _derive(pin, verifier.salt, verifier.iterations, offThread);
    return constantTimeEquals(candidate, verifier.hash);
  }

  /// Off the UI thread on native, where PBKDF2 is pure Dart and would freeze
  /// the keypad. On web `compute` runs inline, but the derive goes through
  /// WebCrypto there and does not block.
  static Future<List<int>> _derive(
          String pin, List<int> salt, int iterations, bool offThread) =>
      offThread
          ? compute(_deriveInIsolate, (pin, salt, iterations))
          : _deriveInIsolate((pin, salt, iterations));

  static Future<List<int>> _deriveInIsolate(
      (String, List<int>, int) args) async {
    final (pin, salt, iterations) = args;
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: hashBits,
    );
    final key = await kdf.deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  /// Compares every byte so the time taken does not reveal where a mismatch is.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
