import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  GoogleSignIn? _googleSignIn;

  /// Initialises Supabase. Call once at app startup before any auth checks.
  /// Reads credentials from .env — never hardcoded in source.
  Future<void> init() async {
    final url = dotenv.env['SUPABASE_URL'] ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];

    assert(url.isNotEmpty, 'SUPABASE_URL missing from .env');
    assert(anonKey.isNotEmpty, 'SUPABASE_ANON_KEY missing from .env');

    _googleSignIn = GoogleSignIn(serverClientId: webClientId);

    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      debug: kDebugMode,
    );
  }

  SupabaseClient get _client => Supabase.instance.client;

  // ── Getters ──────────────────────────────────────────────────────────────

  bool get isSignedIn => _client.auth.currentUser != null;
  String? get currentUserId => _client.auth.currentUser?.id;
  String? get currentUserEmail => _client.auth.currentUser?.email;
  String? get currentUserAvatarUrl =>
      _client.auth.currentUser?.userMetadata?['avatar_url'] as String?;

  /// Emits on every auth state change (sign-in, sign-out, token refresh).
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> signInWithGoogle() async {
    final googleSignIn = _googleSignIn;
    if (googleSignIn == null) throw Exception('AuthService not initialized.');

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) throw const _CancelledByUserException();

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw Exception('Google Sign-In: no ID token received.');
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
  }

  Future<void> signOut() async {
    await _googleSignIn?.signOut();
    await _client.auth.signOut();
  }
}

class _CancelledByUserException implements Exception {
  const _CancelledByUserException();
  @override
  String toString() => 'Sign-in cancelled by user.';
}
