import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState;

import '../services/auth_service.dart';

class AuthPresenter extends ChangeNotifier {
  final AuthService _auth;

  /// Optional hook for Plan 014 (cloud sync). Fired exactly once on the first
  /// successful sign-in so SyncService can pull the user's cloud data.
  final void Function(String userId)? onFirstSignIn;

  /// Fired when the user signs out so SyncService can be torn down.
  final VoidCallback? onSignOut;

  StreamSubscription<AuthState>? _authSub;
  String? _lastKnownUserId;
  bool _isLoading = false;
  String? _error;

  AuthPresenter(this._auth, {this.onFirstSignIn, this.onSignOut});

  // ── Public state ─────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSignedIn => _auth.isSignedIn;
  String? get userId => _auth.currentUserId;
  String? get userEmail => _auth.currentUserEmail;
  String? get userAvatarUrl => _auth.currentUserAvatarUrl;
  String? get userDisplayName => _auth.currentUserDisplayName;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Call from AppShell.initState (after Supabase.initialize) to silently
  /// restore a cached session and subscribe to future auth changes.
  void init() {
    // Seed from any already-restored session so token-refresh events for the
    // existing user don't look like a new sign-in.
    _lastKnownUserId = _auth.currentUserId;
    _authSub = _auth.authStateChanges.listen((state) {
      final newUserId =
          state.event == AuthChangeEvent.signedOut ? null : _auth.currentUserId;
      if (newUserId != null && newUserId != _lastKnownUserId) {
        _lastKnownUserId = newUserId;
        onFirstSignIn?.call(newUserId);
      } else if (state.event == AuthChangeEvent.signedOut &&
          _lastKnownUserId != null) {
        _lastKnownUserId = null;
        onSignOut?.call();
      }
      notifyListeners();
    });
    notifyListeners(); // reflect any already-cached session immediately
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> signInWithGoogle() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _auth.signInWithGoogle();
      // onFirstSignIn is fired by the auth stream listener in init() when it
      // observes a new userId, so no explicit call needed here.
    } catch (e) {
      _error = _friendlyError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    // onSignOut and notifyListeners are fired by the auth stream listener
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('cancel')) return 'Sign-in cancelled.';
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('connection')) {
      return 'Network error. Check your connection.';
    }
    // Surface raw error in debug builds to help diagnose config issues
    if (kDebugMode) return 'Sign-in failed: $e';
    return 'Sign-in failed. Please try again.';
  }
}
