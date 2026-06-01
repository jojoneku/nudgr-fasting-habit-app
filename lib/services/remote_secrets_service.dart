import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fetches secrets that must not be bundled into the APK (e.g. HuggingFace
/// tokens for gated model downloads) from a Supabase Edge Function.
///
/// The token is cached in flutter_secure_storage (encrypted at rest) after
/// the first successful fetch so already-installed models keep working
/// offline. Each download attempt tries a fresh fetch first and falls back
/// to the cache if offline / unauthenticated.
class RemoteSecretsService {
  static const _hfTokenCacheKey = 'remote_secrets.hf_token';
  static const _hfTokenFunctionName = 'get-hf-token';

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Returns the HuggingFace token, or null if unavailable.
  /// Tries the Edge Function first; falls back to cached value on failure.
  Future<String?> getHuggingFaceToken() async {
    final fresh = await _fetchHuggingFaceToken();
    if (fresh != null && fresh.isNotEmpty) {
      await _cacheHuggingFaceToken(fresh);
      return fresh;
    }
    return _readCachedHuggingFaceToken();
  }

  Future<String?> _fetchHuggingFaceToken() async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return null;
    try {
      final res = await client.functions.invoke(_hfTokenFunctionName);
      final data = res.data;
      if (data is Map && data['token'] is String) {
        return data['token'] as String;
      }
      debugPrint(
          'RemoteSecretsService: unexpected response shape: ${res.data}');
      return null;
    } catch (e) {
      debugPrint('RemoteSecretsService: edge function failed: $e');
      return null;
    }
  }

  Future<String?> _readCachedHuggingFaceToken() async {
    try {
      final cached = await _secureStorage.read(key: _hfTokenCacheKey);
      return (cached != null && cached.isNotEmpty) ? cached : null;
    } catch (e) {
      debugPrint('RemoteSecretsService: secure read failed: $e');
      return null;
    }
  }

  Future<void> _cacheHuggingFaceToken(String token) async {
    try {
      await _secureStorage.write(key: _hfTokenCacheKey, value: token);
    } catch (e) {
      debugPrint('RemoteSecretsService: secure write failed: $e');
    }
  }
}
