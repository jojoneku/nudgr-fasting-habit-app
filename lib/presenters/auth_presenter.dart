import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

class AuthPresenter extends ChangeNotifier {
  final AuthService _auth;

  /// Optional hook for Plan 014 (cloud sync). Fired exactly once on the first
  /// successful sign-in so SyncService can pull the user's cloud data.
  final void Function(String userId)? onFirstSignIn;

  StreamSubscription<AuthState>? _authSub;
  bool _isLoading = false;
  String? _error;

  AuthPresenter(this._auth, {this.onFirstSignIn});

  // ── Public state ─────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSignedIn => _auth.isSignedIn;
  String? get userId => _auth.currentUserId;
  String? get userEmail => _auth.currentUserEmail;
  String? get userAvatarUrl => _auth.currentUserAvatarUrl;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Call from AppShell.initState (after Supabase.initialize) to silently
  /// restore a cached session and subscribe to future auth changes.
  void init() {
    _authSub = _auth.authStateChanges.listen((_) => notifyListeners());
    notifyListeners(); // reflect any already-cached session immediately
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> signInWithGoogle() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    final wasSignedIn = isSignedIn;
    try {
      await _auth.signInWithGoogle();
      if (!wasSignedIn && userId != null) {
        onFirstSignIn?.call(userId!);
      }
    } catch (e) {
      _error = _friendlyError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    // authStateChanges stream triggers notifyListeners via _authSub
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
    return 'Sign-in failed. Please try again.';
  }
}
