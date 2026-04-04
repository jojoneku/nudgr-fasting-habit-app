# Plan 013 — Authentication (Google Sign-In via Supabase)

**Status:** DRAFT — Awaiting Approval
**Author:** System Architect
**Date:** 2026-04-02
**Depends on:** none (Plan 014 Supabase Sync depends on this)

---

## Goal

Add Google Sign-In via Supabase Auth so every user has a stable `userId` that scopes their cloud data. The app shows a `LoginView` on first launch and restores the session automatically on subsequent launches. Sign-out is accessible from Settings. On first sign-in, `AuthPresenter` fires a callback that a future `SyncService` (Plan 013) can hook into to pull any existing cloud data for the user.

---

## Affected Files

| File | Action |
|---|---|
| `pubspec.yaml` | Modify — add `supabase_flutter`, `google_sign_in` |
| `lib/services/auth_service.dart` | Create — wraps Supabase Auth + Google Sign-In |
| `lib/presenters/auth_presenter.dart` | Create — state machine for auth flow |
| `lib/views/auth/login_view.dart` | Create — Solo Leveling login screen |
| `lib/views/home_screen.dart` | Modify — add auth gate (session check → LoginView or Hub) |
| `lib/views/settings_screen.dart` | Modify — add sign-out button |

---

## New Dependencies

```yaml
# pubspec.yaml additions
supabase_flutter: ^2.x.x   # Supabase client + Auth + session management
google_sign_in: ^6.x.x     # Google OAuth token for Supabase signInWithIdToken
```

> Platform setup required (see Risks section).

---

## Interface Definitions

### AuthService

```dart
// lib/services/auth_service.dart

class AuthService {
  Future<void> init();                       // restore session on app launch
  Future<void> signInWithGoogle();           // OAuth flow → Supabase signInWithIdToken
  Future<void> signOut();                    // Supabase signOut + clear Google session
  String? get currentUserId;                 // null if not signed in
  bool get isSignedIn;
  Stream<AuthState> get authStateChanges;    // proxies supabase.auth.onAuthStateChange
}
```

### AuthPresenter

```dart
// lib/presenters/auth_presenter.dart

class AuthPresenter extends ChangeNotifier {
  AuthPresenter(AuthService auth, {void Function(String userId)? onFirstSignIn});

  bool get isSignedIn;
  bool get isLoading;
  String? get error;
  String? get userId;

  Future<void> init();                 // called at app startup; restores session
  Future<void> signInWithGoogle();     // delegates to AuthService; fires onFirstSignIn
  Future<void> signOut();              // delegates to AuthService
}
```

`onFirstSignIn` is an optional callback injected at construction time. Plan 013 will inject a `SyncService.pullForUser(userId)` call here. When `null`, the callback is a no-op.

---

## LoginView Spec

**Solo Leveling aesthetic.** Dark background, centered branding, single CTA in the bottom 30%.

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│                                     │
│          [APP LOGO / ICON]          │
│                                     │
│           THE SYSTEM                │  ← AppTextStyles.displayLarge
│        Your wellness RPG            │  ← AppTextStyles.bodyMedium, muted
│                                     │
│                                     │
│                                     │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  G   Continue with Google   │    │  ← full-width, min 52px height
│  └─────────────────────────────┘    │  ← bottom 30% of screen
│                                     │
│  [error snackbar — shown on fail]   │
└─────────────────────────────────────┘
```

States:
- **Idle** — Google Sign-In button visible, enabled.
- **Loading** — Button replaced by `CircularProgressIndicator` (centered in same slot).
- **Error** — Button re-enabled; `ScaffoldMessenger` shows a `SnackBar` with `AuthPresenter.error`.

---

## Implementation Order

1. [ ] Add `supabase_flutter` and `google_sign_in` to `pubspec.yaml`; run `flutter pub get`
2. [ ] Create `AuthService` — `init()`, `signInWithGoogle()`, `signOut()`, getters, stream
3. [ ] Create `AuthPresenter` — wraps `AuthService`, exposes `isLoading`/`error`, calls `onFirstSignIn` callback on first successful sign-in
4. [ ] Create `lib/views/auth/login_view.dart` — Solo Leveling login screen per spec above
5. [ ] Modify `AppShell` in `lib/views/home_screen.dart` — call `authPresenter.init()` in `initState`; wrap body in `ListenableBuilder` to gate on `isSignedIn` (show `LoginView` or `HubScreen`)
6. [ ] Modify `lib/views/settings_screen.dart` — add "Sign Out" `ListTile` in the danger/account section; calls `authPresenter.signOut()`
7. [ ] Perform platform setup (SHA-1 fingerprint, OAuth client IDs — see Risks)
8. [ ] Smoke test: cold launch shows `LoginView` → sign in → Hub → force-kill → relaunch → Hub (session restored)
9. [ ] Smoke test: Settings → Sign Out → `LoginView` shown

---

## RPG Impact

None. Authentication is infrastructure. No XP, stats, streaks, or level changes.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Google Sign-In requires SHA-1 fingerprint registered in Google Cloud Console | Document in a `docs/setup/google_signin_setup.md` checklist; required for both debug and release keystores |
| OAuth client IDs differ per platform (Android, iOS, Web) | Store in `google-services.json` (Android) and `GoogleService-Info.plist` (iOS); never hardcode in Dart |
| Session token expiry mid-session | Supabase auto-refreshes tokens; listen on `authStateChanges` stream and react to `AuthChangeEvent.signedOut` |
| Cold launch while offline | `supabase.auth.currentSession` reads from local cache — session can be restored offline; no network required |
| User signs out with unsynced local data | Plan 013 concern; for now, sign-out proceeds immediately. Plan 013 will add a pre-sign-out sync check |
| First-time user has no Supabase data | `onFirstSignIn` triggers a pull; `SyncService` must handle empty-result gracefully (no-op) |
| User denies Google permission dialog | `signInWithGoogle()` throws; `AuthPresenter` catches and sets `error`; LoginView shows snackbar |
| Multiple rapid taps on Sign-In button | `isLoading` guard in `AuthPresenter.signInWithGoogle()` — ignore calls while already in progress |

---

## Acceptance Criteria

- [ ] Cold launch with no session → `LoginView` is shown
- [ ] Tapping "Continue with Google" triggers OAuth flow and shows loading state
- [ ] Successful sign-in navigates to `HubScreen` without rebuilding the entire widget tree unnecessarily
- [ ] `AuthPresenter.userId` is non-null after sign-in
- [ ] `onFirstSignIn` callback is invoked exactly once on first successful sign-in
- [ ] Force-killing the app and relaunching restores the session — `HubScreen` shown directly
- [ ] Settings screen shows a "Sign Out" option
- [ ] Signing out clears the session and returns the user to `LoginView`
- [ ] Network error or Google permission denial shows an error snackbar on `LoginView`
- [ ] No auth logic exists in any `build()` method — all state delegated to `AuthPresenter`
- [ ] `AuthService` and `AuthPresenter` are constructor-injected; no global locators
