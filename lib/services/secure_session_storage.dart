import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase session (access + refresh token) in the platform
/// keystore instead of plaintext `SharedPreferences`.
///
/// supabase_flutter's default [LocalStorage] writes the serialised session to
/// SharedPreferences, which on Android is a world-readable-by-root XML file in
/// the app sandbox. That put a live, replayable access token AND a long-lived
/// refresh token on disk in the clear — while this app already took the
/// trouble to put a far less sensitive HuggingFace read token in
/// `flutter_secure_storage` (see [RemoteSecretsService]). This closes that
/// inversion. Flagged in the 2026-07-04 audit.
///
/// Mobile only. `flutter_secure_storage` on web is a thin wrapper over browser
/// storage with no real key protection, so the web build keeps the SDK default
/// — see `docs/data_security_spec.md` §Phase 1, which scopes web out of
/// at-rest encryption for the same reason.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  /// Where the session lives now.
  static const sessionKey = 'supabase.session.v1';

  /// Plaintext keys to migrate off and then delete.
  ///
  /// Matched by shape rather than hardcoded, because the SDK derives its key
  /// from the project URL (`sb-<ref>-auth-token`) and has changed the scheme
  /// between versions. Guessing one literal key and getting it wrong would
  /// fail silently in the worst way: every user signed out on upgrade, and the
  /// plaintext token left behind anyway.
  static bool _looksLikeSupabaseSessionKey(String key) {
    final k = key.toLowerCase();
    return (k.contains('supabase') && k.contains('session')) ||
        k.contains('auth-token') ||
        k.startsWith('sb-');
  }

  final FlutterSecureStorage _secureStorage;

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  @override
  Future<void> initialize() async {
    await _migrateFromPlaintext();
  }

  /// Moves any session the SDK previously wrote in the clear into secure
  /// storage, then deletes the plaintext copy.
  ///
  /// Order matters and is the whole point: write the secure copy FIRST and
  /// only delete the plaintext one once that write succeeded. Deleting first
  /// would sign out every existing user the moment the keystore hiccupped.
  ///
  /// The delete runs even when there was nothing to migrate (a session already
  /// in secure storage, say), because leaving the old plaintext value on disk
  /// is the exact problem this class exists to fix.
  Future<void> _migrateFromPlaintext() async {
    try {
      final prefs = await _prefs();
      final stale =
          prefs.getKeys().where(_looksLikeSupabaseSessionKey).toList();
      if (stale.isEmpty) return;

      final alreadySecure = await _read();
      if (alreadySecure == null || alreadySecure.isEmpty) {
        for (final key in stale) {
          final value = prefs.get(key);
          if (value is! String || value.isEmpty) continue;
          await _secureStorage.write(key: sessionKey, value: value);
          debugPrint('SecureSessionStorage: migrated session out of $key');
          break;
        }
      }

      for (final key in stale) {
        await prefs.remove(key);
      }
      debugPrint(
          'SecureSessionStorage: cleared ${stale.length} plaintext key(s)');
    } catch (e) {
      // Never block startup on this. A failed migration costs one sign-in;
      // throwing here would cost the app its launch.
      debugPrint('SecureSessionStorage: migration failed: $e');
    }
  }

  Future<String?> _read() async {
    try {
      return await _secureStorage.read(key: sessionKey);
    } catch (e) {
      // A keystore that cannot be read is treated as "no session": the user
      // signs in with Google again. Deliberately NOT falling back to
      // SharedPreferences — a fallback that writes the token in the clear
      // whenever the keystore is unhappy is the same bug with extra steps.
      debugPrint('SecureSessionStorage: read failed: $e');
      return null;
    }
  }

  @override
  Future<String?> accessToken() => _read();

  @override
  Future<bool> hasAccessToken() async {
    final value = await _read();
    return value != null && value.isNotEmpty;
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _secureStorage.write(
        key: sessionKey,
        value: persistSessionString,
      );
    } catch (e) {
      debugPrint('SecureSessionStorage: persist failed: $e');
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _secureStorage.delete(key: sessionKey);
    } catch (e) {
      debugPrint('SecureSessionStorage: delete failed: $e');
    }
    // Belt and suspenders on sign-out: if a plaintext key ever reappears
    // (a downgrade, a partial migration), sign-out clears it too.
    try {
      final prefs = await _prefs();
      // .toList() so the iteration does not read from the same collection
      // remove() is mutating.
      final stale =
          prefs.getKeys().where(_looksLikeSupabaseSessionKey).toList();
      for (final key in stale) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('SecureSessionStorage: plaintext cleanup failed: $e');
    }
  }
}
