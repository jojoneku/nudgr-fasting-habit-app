## 1. Backend

- [ ] 1.1 Write `docs/supabase_migration_058_app_lock.sql`. It creates the `app_lock` table (`user_id` primary key referencing `auth.users` on delete cascade, `verifier jsonb not null`, `updated_at timestamptz not null default now()`), enables RLS with select/insert/update/delete policies on `auth.uid() = user_id`, and adds the table to `supabase_realtime`. Verify by applying it to a Supabase branch: a second user cannot read the first user's row. **Status:** Written. Not yet applied to any Supabase project, so the RLS check is still open.

## 2. Storage and crypto foundation

- [x] 2.1 Add `kAppLockDevice` (device-level, unscoped) and `loadAppLockDevice`/`saveAppLockDevice` to `StorageService` and `LocalStorageService`. Confirm that `clearUserData` and `detachUser` do not remove it. Verify with a unit test.
- [x] 2.2 Add an immutable `AppLockDeviceState` model with `fromJson`/`toJson`. Fields: lockAfterSeconds, biometricsEnabled, failedAttempts, cooldownUntil, lastActivityAt, pinResetPending. Verify with a round-trip test that includes missing fields.
- [x] 2.3 Add a `PinHasher` (PBKDF2-HMAC-SHA256 from `cryptography`, 16-byte `Random.secure()` salt, constant-time compare) and an immutable `PinVerifier` model (`v`, algo, iterations, salt, hash, length, with `fromJson`/`toJson`). Verify with tests: hash and verify, wrong PIN fails, and no JSON output contains the PIN.
- [x] 2.4 Add the abstract `PinVerifierCache` with `SecurePinVerifierCache` (`FlutterSecureStorage`, `encryptedSharedPreferences`) and `PrefsPinVerifierCache` (web). Verify with tests that use fakes.
- [x] 2.5 Add the abstract `AppLockRemote` (`fetch`, `put`, `delete`, `changes` stream) and `SupabaseAppLockRemote`. A missing-table error maps to an "unavailable" result. Verify with unit tests that use a fake client: offline, missing table, and success.
- [ ] 2.6 Measure one PIN verify at 100 000 iterations in a web release build and on an Android release build. Set the iteration constant so it takes 150–300 ms on both, and record the numbers in the `PinHasher` doc comment. **Status:** Measured on the desktop Dart VM only (50k ≈ 300 ms, 100k ≈ 650 ms) and set to 40 000. Not yet measured on a web or Android release build.

## 3. Platform collaborators

- [ ] 3.1 Add the `BiometricAuthenticator` interface (`isAvailable`, `isDeviceSupported`, `authenticate({biometricOnly})`) and `LocalAuthBiometricAuthenticator`. Make sure only the mobile root imports the implementation. Verify that `flutter build web -t lib/main_web.dart` output has no `local_auth` reference.
- [x] 3.2 Add `local_auth` (3.x) to `pubspec.yaml`, add `USE_BIOMETRIC` to `AndroidManifest.xml`, and run `flutter pub get`. Verify with `flutter analyze`.
- [ ] 3.3 Add `setRecentsPrivacy(bool)` to the `com.nudgr.app/lockscreen` channel in `MainActivity.kt` (API 33+ `setRecentsScreenshotEnabled`, no-op on older versions). Add `PrivacyFlagChannel` in Dart, with a no-op on web and a safe `MissingPluginException` path. Verify with a manual smoke test on a device: the recent-apps card is blank when enabled. **Status:** Code done. Device smoke test still open.
- [x] 3.4 Add `AppLockPolicy` with `mobile` (Immediately/1/5/15 min, default 1 min, no forced sign-out) and `web` (1/5/15/30/60 min, default 5 min, Forgot-PIN sign-out at 10 wrong PINs).

## 4. AppLockPresenter

- [x] 4.1 Create `AppLockPresenter` with constructor injection (remote, cache, device store, biometrics?, policy, clock, privacy channel). Implement `init()`: cold start with a cached verifier locks on mobile, and on web only when the idle time has passed. Verify with `fake_async` tests.
- [x] 4.2 Implement `bindAuth(AuthPresenter)` and the sign-in/sign-out transitions. Sign-in fetches, subscribes, and starts unlocked. Sign-out unsubscribes, deletes the cache, and resets the wrong-PIN state. Unsubscribe in `dispose`. Verify with unit tests: sign out and sign in again restores the lock, and a second account with no row sees no lock.
- [x] 4.3 Implement the refresh rules: fetch on foreground, tab show, and realtime event; offline keeps the cache; a missing row turns the lock off; a refresh never unlocks. Verify with unit tests.
- [x] 4.4 Implement `enable(pin)`, `disable(pin)`, and `changePin(old, new)` as write-through (remote first, then cache, then notify). Show the offline error and keep the state on failure. Disable and change must verify the current PIN and count toward the throttle. Verify with unit tests.
- [x] 4.5 Implement `submitPin` and the per-device throttle (5 → 30 s, doubled, 15 min cap, persisted). Implement the web 10th-wrong-PIN path (set `pinResetPending`, then `onForcedSignOut`). Verify with `fake_async` tests that include a restart during a cooldown.
- [x] 4.6 Implement `onBackgrounded`/`onForegrounded` (mobile) and `recordActivity` plus the periodic idle check and the throttled `lastActivityAt` persist (web). Verify with `fake_async` tests for before and after the timeout, a hidden tab, and a reload.
- [x] 4.7 Implement `runExempt` (nesting-safe counter) and `suspend`/`resume(reason)`. Verify with tests: an exempt background does not lock, the biometric prompt does not loop, and a lock during an alarm suspend renders after resume.
- [x] 4.8 Implement `unlockWithBiometrics` (inside `runExempt`, failures not counted, success resets the count) and `forgotPin()`. On mobile, this is the device credential, then `SetPinFlow` in replace mode, with a no-screen-lock message. On web, this is `pinResetPending` + sign-out, then `pinResetRequired` after the next fresh sign-in. Verify with unit tests that use a fake authenticator.
- [x] 4.9 Call `PrivacyFlagChannel.setRecentsPrivacy(isEnabled)` on init and whenever the enabled state changes. Verify with a unit test that uses a fake channel.

## 5. Lock UI widgets

- [x] 5.1 Build a shared `PinPad` widget: 3×4 grid with 64 px keys, PIN dots with the "n of m digits entered" semantics, a 250 ms wrong-PIN shake, a disabled state with a countdown, an optional biometric key, and theme colors only. Verify with a widget test for taps, semantics, and the disabled state.
- [x] 5.2 Build `AppLockScreen` (opaque, centered with a 360 px maximum width on wide layouts, keypad in the bottom area on mobile, "Forgot PIN?", auto-start of the biometric prompt with the keypad as backup). Add physical-keyboard digit and Backspace input. Verify with widget tests in dark and light themes.
- [x] 5.3 Build `SetPinFlow` with "new" and "replace" modes (choose 4 or 6 → enter → confirm → mismatch error), a spinner during the remote write, and an offline error with retry. In mandatory-reset mode, add a "Turn off app lock" option. Verify with a widget test.
- [x] 5.4 Build `AppLockGate` for `MaterialApp.builder`. It is a `Stack` of the child (with `IgnorePointer` + `ExcludeSemantics` + `ExcludeFocus` while gated) and either `AppLockScreen` (locked, not suspended) or the mandatory `SetPinFlow` (`pinResetRequired`). Verify with a widget test: an open dialog is covered, taps and focus do not reach it, and the dialog state survives unlock.
- [x] 5.5 Build `AppLockActivityDetector` (`Listener` translucent plus a `HardwareKeyboard` handler that calls `recordActivity`). Verify with a widget test that pointer and key events update the activity time.

## 6. Wire into the app roots

- [ ] 6.1 Mobile: in `_FastingAppState`, create the presenter (mobile policy, `LocalAuthBiometricAuthenticator`, `SecurePinVerifierCache`, `SupabaseAppLockRemote`), add an `AppLifecycleListener`, set `MaterialApp.builder: AppLockGate`, and pass the presenter to `HomeScreen`. Verify with a manual smoke test on a device: cold start locks, and a return after the timeout locks. **Status:** Code done. Device smoke test still open.
- [ ] 6.2 Mobile alarm: wrap `_showAlarm`'s push with `suspend('alarm')`/`resume('alarm')`. Verify with a manual smoke test: an alarm fires on the locked app, the alarm screen works, and the lock shows after dismiss. **Status:** Code done. Device smoke test still open.
- [ ] 6.3 Mobile auth: call `appLock.bindAuth(authPresenter)` where `HomeScreen` holds the `AuthPresenter`. Verify with a manual smoke test: sign out and sign in again, and the lock is back with the same PIN. **Status:** Code done. Device smoke test still open.
- [ ] 6.4 Web: make `TreasuryWebApp` stateful, create the presenter (web policy, no biometrics, `PrefsPinVerifierCache`, `SupabaseAppLockRemote`), and wrap the builder child with `AppLockActivityDetector` + `AppLockGate`. Pass the presenter to `TreasuryWebShell`, which calls `bindAuth` and sets `onForcedSignOut` to `authPresenter.signOut`. Verify with a manual smoke test on localhost:8090: idle, hidden tab, and reload behavior. **Status:** Code done. Browser smoke test still open.
- [x] 6.5 Wrap every in-app external activity in `appLock.runExempt` and inject the presenter where needed: **Status:** Scope changed: the 3 mobile image pickers are exempt through AppLockExemption. Sign-in, URL, and file launches are not exempt by decision (design.md decision 8). The device smoke test is still open.
  - image picker in `lib/views/nutrition/food_photo_sheet.dart` and `lib/views/treasury/shared/photo_log_sheet.dart`
  - Google sign-in callers (`login_view.dart`, `web_login_view.dart`, `onboarding_flow.dart`)
  - `open_filex`/`url_launcher` in `settings_screen.dart` and `onboarding_presenter.dart`
  - the file drop and picker in `web_receipt_drop.dart`

  Verify with a manual smoke test on mobile with "Immediately": pick a photo, and no lock appears.

## 7. Settings surfaces

- [x] 7.1 Mobile: add a "Security" section in `settings_screen.dart` after "Account". Signed out: "Sign in to use app lock". Signed in: App lock switch (on → `SetPinFlow`, off → PIN check), Lock after picker, Use biometrics (only when available), Change PIN, and Lock now, with the subtitle "Your PIN works on all your devices." Keep all values from presenter getters. Verify with a widget test.
- [x] 7.2 Web: add a "Security" card on `web_more_page.dart` with the same rows minus biometrics, and a "Lock now" icon button in the sidebar footer next to sign-out. Verify with a widget test and a manual smoke test.

## 8. Verify and document

- [ ] 8.1 Run `dart format`, `flutter analyze`, and `flutter test`. All must be clean.
- [ ] 8.2 Cross-device pass: set the PIN on the phone and confirm that the web locks with it. Change the PIN on the web and confirm that the phone takes the new PIN after a refresh. Turn the lock off on one device and confirm that it is off on the other.
- [ ] 8.3 Run the full manual pass on an Android release build. Cover: cold start, background timeout, biometrics first with the PIN as backup, a cancelled biometric prompt, offline unlock, an offline PIN-change error, the wrong-PIN cooldown across a restart, Forgot PIN with the device credential, an alarm while locked, a hidden recent-apps preview, and no lock after the photo picker.
- [ ] 8.4 Run the full manual pass on the web release build. Cover: idle lock, hidden-tab lock, reload before and after the timeout, physical-keyboard PIN entry, 10 wrong PINs → sign-out → mandatory new PIN after sign-in, Forgot PIN, and dark and light themes.
- [ ] 8.5 Update `docs/data_security_spec.md` with a short "App lock" note: what it protects and what it does not (no web encryption, brute-forceable hash, widgets and notifications out of scope). In the PR description, list migration 058 as a manual step.
