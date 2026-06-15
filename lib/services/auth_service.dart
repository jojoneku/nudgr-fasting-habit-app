import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  GoogleSignIn? _googleSignIn;

  /// True once [init] has run [Supabase.initialize]. Until then, reading
  /// `Supabase.instance` throws, so all getters below short-circuit to safe
  /// defaults. This lets the web companion's local preview-seed mode render the
  /// signed-in UI without ever initialising Supabase. (Plan 052)
  bool _initialized = false;

  /// Initialises Supabase. Call once at app startup before any auth checks.
  /// Reads credentials from .env — never hardcoded in source.
  Future<void> init() async {
    final url = dotenv.env['SUPABASE_URL'] ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];

    // Throw (not `assert`) — asserts are stripped in release, so a misconfigured
    // deploy would otherwise initialise Supabase with empty strings and fail
    // opaquely on the first request. Fail loudly at startup instead. (Plan 052 S6)
    if (url.isEmpty || anonKey.isEmpty) {
      throw StateError(
        'Supabase credentials missing from .env '
        '(SUPABASE_URL and SUPABASE_ANON_KEY are required).',
      );
    }

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
    _initialized = true;
  }

  SupabaseClient get _client => Supabase.instance.client;

  // ── Getters ──────────────────────────────────────────────────────────────

  bool get isSignedIn => _initialized && _client.auth.currentUser != null;
  String? get currentUserId =>
      _initialized ? _client.auth.currentUser?.id : null;
  String? get currentUserEmail =>
      _initialized ? _client.auth.currentUser?.email : null;
  String? get currentUserAvatarUrl => _initialized
      ? (_client.auth.currentUser?.userMetadata?['avatar_url'] as String?)
      : null;
  String? get currentUserDisplayName => _initialized
      ? (_client.auth.currentUser?.userMetadata?['full_name'] as String? ??
          _client.auth.currentUser?.userMetadata?['name'] as String?)
      : null;

  /// Current Supabase access token. Refreshed automatically by the SDK.
  String? get currentAccessToken =>
      _initialized ? _client.auth.currentSession?.accessToken : null;

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
    if (_initialized) await _client.auth.signOut();
  }
}

class _CancelledByUserException implements Exception {
  const _CancelledByUserException();
  @override
  String toString() => 'Sign-in cancelled by user.';
}
