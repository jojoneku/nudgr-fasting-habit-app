import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  GoogleSignIn? _googleSignIn;

  /// Initialises Supabase. Call once at app startup before any auth checks.
  /// Reads credentials from .env — never hardcoded in source.
  Future<void> init() async {
    final url = dotenv.env['SUPABASE_URL'] ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];

    assert(url.isNotEmpty, 'SUPABASE_URL missing from .env');
    assert(anonKey.isNotEmpty, 'SUPABASE_ANON_KEY missing from .env');

    // On web we use Supabase's OAuth redirect flow instead of the native
    // google_sign_in ID-token flow, so the GoogleSignIn client is never built
    // (Plan 042).
    if (!kIsWeb) {
      _googleSignIn = GoogleSignIn(serverClientId: webClientId);
    }

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
  String? get currentUserDisplayName =>
      _client.auth.currentUser?.userMetadata?['full_name'] as String? ??
      _client.auth.currentUser?.userMetadata?['name'] as String?;

  /// Current Supabase access token. Refreshed automatically by the SDK.
  String? get currentAccessToken => _client.auth.currentSession?.accessToken;

  /// Emits on every auth state change (sign-in, sign-out, token refresh).
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> signInWithGoogle() async {
    // Web: full-page redirect OAuth. supabase_flutter persists the session in
    // localStorage and parses the callback itself; `authStateChanges` fires
    // after the round-trip. An optional WEB_REDIRECT_URL override lets the
    // deployed site point back at its own origin; locally it defaults to the
    // current page (e.g. http://localhost:<port>).
    if (kIsWeb) {
      final redirect = dotenv.env['WEB_REDIRECT_URL'];
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: (redirect != null && redirect.isNotEmpty) ? redirect : null,
      );
      return;
    }

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
