import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// TODO: Fill in your project credentials before testing sign-in.
// See docs/setup/google_signin_setup.md for step-by-step instructions.
// ---------------------------------------------------------------------------
const _supabaseUrl = 'YOUR_SUPABASE_PROJECT_URL';
const _supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

/// The **Web** OAuth 2.0 client ID from Google Cloud Console.
/// (Not the Android client ID — Supabase needs the Web one to verify ID tokens.)
const _googleWebClientId =
    'YOUR_GOOGLE_WEB_CLIENT_ID.apps.googleusercontent.com';
// ---------------------------------------------------------------------------

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _googleSignIn = GoogleSignIn(serverClientId: _googleWebClientId);

  /// Initialises Supabase. Call once at app startup before any auth checks.
  Future<void> init() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
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
    final googleUser = await _googleSignIn.signIn();
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
    await _googleSignIn.signOut();
    await _client.auth.signOut();
  }
}

class _CancelledByUserException implements Exception {
  const _CancelledByUserException();
  @override
  String toString() => 'Sign-in cancelled by user.';
}
