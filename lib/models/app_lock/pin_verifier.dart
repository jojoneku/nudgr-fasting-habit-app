import 'dart:convert';

/// The stored proof of an app-lock PIN: a salted PBKDF2 hash, never the PIN.
///
/// One verifier belongs to the account (the `app_lock` row) and each device
/// keeps a copy so unlock works offline. [length] is stored so the keypad can
/// auto-submit; it only reveals 4 vs 6 digits. [iterations] travels with the
/// hash so the cost can change later without a migration.
class PinVerifier {
  static const int currentVersion = 1;
  static const String pbkdf2Sha256 = 'pbkdf2-sha256';

  final int version;
  final String algorithm;
  final int iterations;
  final List<int> salt;
  final List<int> hash;
  final int length;

  const PinVerifier({
    this.version = currentVersion,
    this.algorithm = pbkdf2Sha256,
    required this.iterations,
    required this.salt,
    required this.hash,
    required this.length,
  });

  Map<String, dynamic> toJson() => {
        'v': version,
        'algo': algorithm,
        'iterations': iterations,
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
        'length': length,
      };

  /// Returns null for anything that is not a usable verifier, so a malformed
  /// row reads as "no PIN" instead of crashing the lock screen.
  static PinVerifier? tryFromJson(Object? json) {
    if (json is! Map) return null;
    try {
      final iterations = json['iterations'];
      final length = json['length'];
      final salt = json['salt'];
      final hash = json['hash'];
      if (iterations is! int || length is! int) return null;
      if (salt is! String || hash is! String) return null;
      if (length != 4 && length != 6) return null;
      return PinVerifier(
        version: json['v'] as int? ?? currentVersion,
        algorithm: json['algo'] as String? ?? pbkdf2Sha256,
        iterations: iterations,
        salt: base64Decode(salt),
        hash: base64Decode(hash),
        length: length,
      );
    } on FormatException {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  static PinVerifier? tryDecode(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      return tryFromJson(jsonDecode(source));
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PinVerifier &&
      other.version == version &&
      other.algorithm == algorithm &&
      other.iterations == iterations &&
      other.length == length &&
      _sameBytes(other.salt, salt) &&
      _sameBytes(other.hash, hash);

  @override
  int get hashCode =>
      Object.hash(version, algorithm, iterations, length, Object.hashAll(hash));

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
