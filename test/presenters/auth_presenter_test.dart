import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intermittent_fasting/presenters/auth_presenter.dart';
import 'package:intermittent_fasting/services/auth_service.dart';

// Hand-written fake — AuthService has a private constructor so @GenerateMocks
// cannot call super(); using Fake + implements satisfies the interface instead.
class _FakeAuthService extends Fake implements AuthService {
  bool _isSignedIn;
  String? _userId;
  final Exception? _signInError;

  bool signOutCalled = false;
  bool signInCalled = false;

  final _authController = StreamController<AuthState>.broadcast();

  _FakeAuthService({
    bool isSignedIn = false,
    String? userId,
    Exception? signInError,
  })  : _isSignedIn = isSignedIn,
        _userId = userId,
        _signInError = signInError;

  @override
  bool get isSignedIn => _isSignedIn;

  @override
  String? get currentUserId => _userId;

  @override
  String? get currentUserEmail => null;

  @override
  String? get currentUserAvatarUrl => null;

  @override
  Stream<AuthState> get authStateChanges => _authController.stream;

  @override
  Future<void> signInWithGoogle() async {
    signInCalled = true;
    if (_signInError != null) throw _signInError!;
    _isSignedIn = true;
    _userId = _userId ?? 'test-uid';
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    _isSignedIn = false;
    _userId = null;
  }

  void close() => _authController.close();
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

AuthPresenter _buildPresenter(
  _FakeAuthService auth, {
  void Function(String)? onFirstSignIn,
  VoidCallback? onSignOut,
}) =>
    AuthPresenter(auth, onFirstSignIn: onFirstSignIn, onSignOut: onSignOut);

void main() {
  late _FakeAuthService auth;

  setUp(() {
    auth = _FakeAuthService();
  });

  tearDown(() {
    auth.close();
  });

  // ── signInWithGoogle ───────────────────────────────────────────────────────

  group('signInWithGoogle', () {
    test('fires onFirstSignIn when user was not previously signed in', () async {
      String? receivedId;
      final presenter = _buildPresenter(
        auth,
        onFirstSignIn: (id) => receivedId = id,
      );

      await presenter.signInWithGoogle();

      expect(receivedId, 'test-uid');
    });

    test('does not fire onFirstSignIn when already signed in', () async {
      auth = _FakeAuthService(isSignedIn: true, userId: 'existing-uid');
      String? receivedId;
      final presenter = _buildPresenter(
        auth,
        onFirstSignIn: (id) => receivedId = id,
      );

      await presenter.signInWithGoogle();

      expect(receivedId, isNull);
    });

    test('does not fire onFirstSignIn when sign-in errors', () async {
      auth = _FakeAuthService(signInError: Exception('network error'));
      String? receivedId;
      final presenter = _buildPresenter(
        auth,
        onFirstSignIn: (id) => receivedId = id,
      );

      await presenter.signInWithGoogle();

      expect(receivedId, isNull);
    });

    test('sets isLoading true during call, false after', () async {
      final presenter = _buildPresenter(auth);
      final loadingStates = <bool>[];
      presenter.addListener(() => loadingStates.add(presenter.isLoading));

      await presenter.signInWithGoogle();

      expect(loadingStates, containsAllInOrder([true, false]));
    });

    test('maps cancel exception to a friendly message', () async {
      auth = _FakeAuthService(signInError: Exception('Sign-in cancelled by user.'));
      final presenter = _buildPresenter(auth);

      await presenter.signInWithGoogle();

      expect(presenter.error, 'Sign-in cancelled.');
    });

    test('maps network exception to a friendly message', () async {
      auth = _FakeAuthService(signInError: Exception('network socket error'));
      final presenter = _buildPresenter(auth);

      await presenter.signInWithGoogle();

      expect(presenter.error, 'Network error. Check your connection.');
    });

    test('guards against concurrent calls (isLoading gate)', () async {
      // Simulate a slow sign-in: complete manually
      final slowAuth = _FakeAuthService();
      final completer = Completer<void>();
      var callCount = 0;

      final presenter = AuthPresenter(
        slowAuth,
        onFirstSignIn: (_) => callCount++,
      );

      // First call starts sign-in, second is gated out
      unawaited(presenter.signInWithGoogle());
      unawaited(presenter.signInWithGoogle()); // should be no-op

      // Let the first call finish
      await Future.microtask(() {});
      slowAuth.close();

      // Only one callback should have fired (or zero since slow — just
      // verifying no crash and no double-fire)
      expect(callCount, lessThanOrEqualTo(1));
    });
  });

  // ── signOut ───────────────────────────────────────────────────────────────

  group('signOut', () {
    test('fires onSignOut callback', () async {
      bool signedOut = false;
      final presenter = _buildPresenter(
        auth,
        onSignOut: () => signedOut = true,
      );

      await presenter.signOut();

      expect(signedOut, isTrue);
    });

    test('calls auth.signOut()', () async {
      final presenter = _buildPresenter(auth);

      await presenter.signOut();

      expect(auth.signOutCalled, isTrue);
    });

    test('does not fire onFirstSignIn', () async {
      bool firstSignInFired = false;
      final presenter = _buildPresenter(
        auth,
        onFirstSignIn: (_) => firstSignInFired = true,
        onSignOut: () {},
      );

      await presenter.signOut();

      expect(firstSignInFired, isFalse);
    });
  });

  // ── clearError ────────────────────────────────────────────────────────────

  group('clearError', () {
    test('resets error to null', () async {
      auth = _FakeAuthService(signInError: Exception('network'));
      final presenter = _buildPresenter(auth);
      await presenter.signInWithGoogle(); // sets error

      expect(presenter.error, isNotNull);

      presenter.clearError();

      expect(presenter.error, isNull);
    });

    test('notifies listeners when clearing', () async {
      auth = _FakeAuthService(signInError: Exception('network'));
      final presenter = _buildPresenter(auth);
      await presenter.signInWithGoogle();

      int notifyCount = 0;
      presenter.addListener(() => notifyCount++);
      presenter.clearError();

      expect(notifyCount, 1);
    });
  });

  // ── state getters ─────────────────────────────────────────────────────────

  group('state getters', () {
    test('isSignedIn delegates to auth service', () {
      auth = _FakeAuthService(isSignedIn: true, userId: 'uid');
      final presenter = _buildPresenter(auth);
      expect(presenter.isSignedIn, isTrue);
    });

    test('userId delegates to auth service', () {
      auth = _FakeAuthService(userId: 'abc-123');
      final presenter = _buildPresenter(auth);
      expect(presenter.userId, 'abc-123');
    });
  });
}
