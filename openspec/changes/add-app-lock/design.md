## Context

The app has two roots:
- Mobile: `FastingApp` in `lib/views/fasting_app.dart`.
- Web: `TreasuryWebApp` → `TreasuryWebShell` in `lib/views/web/treasury_web_app.dart`.

Both roots keep the user signed in and keep all presenter state in memory. Today, nothing gates access after the device is unlocked.

Facts from the code:
- `MainActivity` already extends `FlutterFragmentActivity`, and `minSdk` is 26. So `local_auth` 3.x works without activity changes.
- The repo has no `ios/` folder. Mobile means Android in this change.
- `cryptography` is already a dependency, for the backup AES-GCM. It has `Pbkdf2`.
- `StorageService` already has device-level, unscoped keys (`kThemeMode`, hero slots, the onboarding gate). These keys survive `detachUser` and `clearUserData`.
- `flutter_secure_storage` is already used for secrets on mobile (`SecureSessionStorage`, `RemoteSecretsService`). On web it is not real protection.
- Cloud sync uses `SyncService` + `SyncQueue` with `SyncDomain`s. Singleton rows such as `user_profile` are last-write-wins JSON blobs. `RealtimeSyncService` subscribes to `postgres_changes` on a `sync:<userId>` channel. DB migrations live in `docs/supabase_migration_0NN_*.sql`, and the user applies them by hand. The latest is 057.
- `main_web.dart` compiles only its transitive imports. Any mobile-only plugin must stay out of the web import graph.
- `FastingApp` pushes `QuestAlarmScreen` on the root navigator for alarms. On that path, the activity can draw over the keyguard (`LockScreenService`).
- On mobile, sign-out wipes local data that is not synced. So "sign out" must never be the mobile Forgot-PIN path.

Threat model: a person who borrows an unlocked laptop or phone and opens the app. The lock is a privacy gate. It is not a defense against a person with developer tools, root access, the device's storage, or the user's Google account.

## Goals / Non-Goals

**Goals:**
- Use one PIN per account, the same on every device. The PIN is required. Biometrics are an optional phone-only shortcut on top of it.
- Use one presenter and one set of lock widgets for both platforms, mounted at each app root.
- Make the lock unbypassable through the UI: no route, dialog, sheet, or focus traversal can reach content while the app is locked.
- Keep the session and state alive behind the lock. Unlock must be instant and must work offline.
- Make the lock timing fully testable with an injected clock (`fake_async`).

**Non-Goals:**
- Web at-rest encryption, server-side PIN checks, offline PIN changes, guest (no-account) locks, WebAuthn, per-page locks, widget or notification redaction, cross-tab lock sync, and iOS. The proposal gives the reasons.

## Decisions

### 1. One `AppLockPresenter`, owned by each app root, mounted with `MaterialApp.builder`
The lock overlay goes in `MaterialApp.builder`, so it sits above the root `Navigator`. Every route, dialog, and bottom sheet is therefore below it. The builder returns a `Stack`:
- the navigator child, wrapped in `ExcludeSemantics` + `IgnorePointer` + `ExcludeFocus` while locked
- the opaque `AppLockScreen` on top when `presenter.isLocked`, or the mandatory `SetPinFlow` when `presenter.pinResetRequired`

- **Mobile:** `_FastingAppState` creates the presenter next to `SettingsPresenter` and passes it to `HomeScreen` for Settings.
- **Web:** `TreasuryWebApp` becomes stateful, creates the presenter, and passes it to `TreasuryWebShell`.
- **Alternative considered:** a lock route pushed on the navigator. It was rejected because dialogs pushed later would stack above it, and the back button or `Navigator.pop` could dismiss it.
- **Consequences of sitting above the Navigator:**
  - The gate has no Overlay or Navigator. So the lock screen and the reset flow use no dialogs, snack bars, or tooltips, and the web Forgot PIN confirmation is inline.
  - A `PopScope` there has no route to register with. Android Back and the predictive back gesture are held instead by `AppLockBackGuard`, a `WidgetsBindingObserver`. The binding asks observers in the order they were added, so the root attaches the guard in `initState`, before `MaterialApp` (and its Navigator observer) exists.
  - An Escape `Shortcuts` override on the cover stops a key-driven pop.
- **Alternative considered:** the Treasury presenter graph (`TreasuryPresenters`). It was rejected because the lock is app-wide, not a Treasury concern.

The presenter's public surface:
- State: `isAvailable` (signed in), `isEnabled`, `isLocked`, `pinResetRequired`, `pinLength`, `lockAfter`, `biometricsEnabled`, `biometricsAvailable`, `cooldownRemaining`, `failedAttempts`, `isSuspended`, `isBusy`, `errorMessage`
- Commands: `enable(pin)`, `disable(pin)`, `changePin(old, new)`, `submitPin(digits)`, `unlockWithBiometrics()`, `forgotPin()`, `lockNow()`, `setLockAfter(d)`, `setBiometricsEnabled(b)`
- Activity hooks: `recordActivity()`, `onBackgrounded()`, `onForegrounded()`
- Exemption hooks: `runExempt<T>(Future<T> Function())` and `suspend(reason)` / `resume(reason)`

All conditionals stay in the presenter, so the lock widgets only render getters.

### 2. Platform behavior through injected collaborators, not `kIsWeb` branches
The presenter takes these collaborators in its constructor:
- `AppLockRemote`: the account PIN in the cloud.
- `PinVerifierCache`: the local copy of the hash.
- `AppLockDeviceStore`: the per-device settings, through `StorageService`.
- `BiometricAuthenticator?`: `null` on web.
- `AppLockPolicy`: the timeout options, the default, and the web sign-out threshold. There are two constants, `AppLockPolicy.mobile` and `AppLockPolicy.web`.
- `DateTime Function() clock`.
- `PrivacyFlagChannel`: a no-op on web.

The mobile root imports `LocalAuthBiometricAuthenticator`. That file is the only importer of `package:local_auth`. The web root never imports it. This keeps `local_auth` out of the web bundle in the same way `main_web.dart` keeps out the other mobile plugins.

### 3. The account PIN lives in its own table, not in a sync domain
New table `app_lock`, shipped as `docs/supabase_migration_058_app_lock.sql`:
- Columns: `user_id uuid primary key references auth.users on delete cascade`, `verifier jsonb` (null means no PIN), `updated_at timestamptz not null default now()`.
- RLS: select, insert, update, and delete only where `auth.uid() = user_id`.
- The table is added to the `supabase_realtime` publication.

`AppLockRemote` (`fetch()`, `put(verifier)`, `delete()`, `changes` stream) talks to this table directly. Writes are **write-through**: the presenter calls `put`/`delete`, waits for success, and only then updates the cache and notifies listeners. That is why PIN changes need a connection.

Turning the lock off writes `verifier = null`. It does not delete the row. Realtime does not deliver a `DELETE` to a filtered subscriber, but it does deliver an `UPDATE`, so other devices hear about the change. A missing row and a null verifier both mean "no PIN".

- **Alternative considered:** a field inside the `user_profile` blob through `SyncDomain.userProfile`. It was rejected for 3 reasons:
  1. The blob is last-write-wins as a whole, so an offline stats edit could overwrite a newer PIN. This is the clobber risk in the 2026-07-04 audit.
  2. The queue would allow offline PIN changes, so devices could disagree.
  3. The PIN hash would mix with data that the backup and export paths copy.
- **Alternative considered:** an edge function that checks the PIN on the server. It was rejected because unlock must work offline, and a server check adds latency to every unlock.

### 4. Local copy and per-device state
- **`PinVerifierCache`** holds the latest fetched verifier:
  - Mobile: `FlutterSecureStorage` with `encryptedSharedPreferences`, like `SecureSessionStorage`.
  - Web: device-level prefs.
  - Key: `app_lock.verifier`.
  - It holds 1 entry for the signed-in user. Sign-out deletes it.
- **`AppLockDeviceStore`** goes through new device-level `StorageService` methods, `loadAppLockDevice` / `saveAppLockDevice`. It is one JSON blob under `kAppLockDevice` with `lockAfterSeconds`, `biometricsEnabled`, `failedAttempts`, `cooldownUntil`, `lastActivityAt`, and `pinResetPending`. Sign-out resets `failedAttempts` and `cooldownUntil`. It keeps `lockAfterSeconds` and `biometricsEnabled`, because they are this device's preferences.
- The verifier record is `{v: 1, algo: 'pbkdf2-sha256', iterations, salt, hash, length}`. It stores the PIN length, so the keypad can auto-submit. The length leaks only 4 vs 6, which is acceptable.

### 5. Refresh rules (how devices follow PIN changes)
The presenter calls `AppLockRemote.fetch()` and replaces the cache in these cases:
- after sign-in
- on `onForegrounded` (mobile)
- on tab show (web)
- on every `changes` event from the realtime subscription

The rules:
- If the fetch fails because the device is offline, the cache stays as it is, and unlock keeps working with the last known PIN.
- A fetched row turns the lock on. A missing row turns it off.
- A refresh never unlocks a locked device. If the PIN changed while the device was locked, the new PIN unlocks it.

### 6. PIN hashing: PBKDF2-HMAC-SHA256 from `cryptography`
- Use a 16-byte random salt from `Random.secure()` and a 256-bit output.
- Store the iteration count with the hash, so a later change re-hashes on the next PIN set.
- Compare in constant time.
- The iteration count is 40 000. On the desktop Dart VM, 50 000 took about 300 ms and 100 000 took 600–700 ms per derive, so 100 000 was too slow for a keypad. On web, `cryptography` derives through WebCrypto, which is much faster.
- On native, the derive runs in a background isolate (`compute`), so the keypad does not freeze. Tests pass `offThread: false`, because `fake_async` cannot wait for an isolate.
- **Alternative considered:** Argon2id. It is stronger, but it is much slower in pure Dart on web, and it gives little gain for a 4–6 digit keyspace (see Risks).

### 7. Lock timing
- **Mobile:** an `AppLifecycleListener` in the root state calls `onBackgrounded()` on `onHide`/`onPause` and `onForegrounded()` on `onShow`/`onResume`. `onForegrounded` locks if `clock() - backgroundedAt >= lockAfter`. "Immediately" is `Duration.zero`. Cold start with a saved session: `init()` sets `isLocked = isEnabled`, using the cached verifier before any network call.
- **Mobile foreground idle is not tracked.** The screen timeout already pauses the app, which takes the background path.
- **Web:** an `AppLockActivityDetector` widget wraps the builder child.
  - It uses a `Listener` with `HitTestBehavior.translucent` for pointer events and a `HardwareKeyboard.instance` handler for keys.
  - Both call `recordActivity()`. This method only stores a timestamp. It does not call `notifyListeners`.
  - A periodic `Timer` (every 15 s, injected for tests) checks `clock() - lastActivity >= lockAfter`.
  - `AppLifecycleListener` maps `visibilitychange`. When the tab shows, the presenter runs the same check, so hidden time counts as idle.
  - `lastActivityAt` is written at most once every 30 s. On cold start, the presenter locks if there is no stored value or if the stored value is older than `lockAfter`.
- **Fresh sign-in starts unlocked.** A Google sign-in in this session proves identity, so the presenter does not lock right after `bindAuth` reports a new sign-in. Session restore at cold start is not a fresh sign-in.
- **How a fresh sign-in is detected:** `AuthPresenter.lastEvent == AuthChangeEvent.signedIn`. Supabase (`gotrue` 2.20) reports a restored session as `initialSession` or `tokenRefreshed`, never as `signedIn`. The web OAuth redirect reports `signedIn`. The auth state seen at `bindAuth` time always counts as a restore. A misread in the safe direction (a sign-in read as a restore) only shows the lock once.

### 8. Exemptions: `runExempt` and `suspend`
- `runExempt(fn)` sets an exempt counter for the duration of `fn`. While the counter is above 0, `onBackgrounded`/`onForegrounded` do nothing. These calls are exempt:
  - the image picker and camera in `food_photo_sheet.dart`, `photo_log_sheet.dart`, and `ai_chat_sheet.dart`
  - the biometric and device-credential prompts (inside the presenter)
- These calls are not exempt, by decision:
  - Google sign-in, because the lock is never on while the user is signed out.
  - Opening a URL or a file (the update APK, links in Settings), because that is leaving the app for another app. The timeout applies as usual.
  - The web file picker, because web locks on idle input, not on background events.
- The pickers reach `runExempt` through `AppLockExemption`, an `InheritedWidget` that `AppLockGate` places above the Navigator. It carries only the exemption function, not the presenter, so views still get presenters by constructor injection (rule 6). The other option was to thread the presenter through about 6 constructors (AppShell → HubScreen → ledger, nutrition, and chat sheets) only for 3 picker calls, and it was rejected. Without a gate above it (tests, previews), `AppLockExemption.run` just runs the action.
- `suspend('alarm')` / `resume('alarm')`: `FastingApp._showAlarm` calls them around the alarm route. While suspended, the overlay does not render, but `isLocked` stays the same.
- **Alternative considered:** a short grace window after resume. It was rejected because it is timing-based and flaky, and the photo picker can stay open for minutes.

### 9. Wrong-PIN throttle (per device)
- After 5 wrong PINs in a row, the cooldown is `30 s × 2^(n−5)`, with a cap of 15 minutes. The count and `cooldownUntil` persist in `AppLockDeviceStore`.
- On web, the 10th wrong PIN in a row runs the web Forgot PIN path: it sets `pinResetPending` and signs out.
- On mobile there is no forced sign-out, because sign-out wipes data that is not synced.
- Biometric failures do not count. The OS throttles them.
- The throttle is per device, not per account. A shared count would need a server, and a borrower can reach only one device at a time.

### 10. Forgot PIN
- **Mobile:** `forgotPin()` calls `authenticate(biometricOnly: false)`, which accepts the device PIN, pattern, or password, inside `runExempt`. On success, it unlocks and pushes `SetPinFlow` in "replace" mode. This mode calls `AppLockRemote.put` without the old PIN, because the device credential proved the owner. If `isDeviceSupported()` is false, the lock screen says "Your phone has no screen lock. Use Forgot PIN on the web app to reset your PIN."
- **Web:** `forgotPin()` sets `pinResetPending = true`, then calls `onForcedSignOut`. After the next fresh sign-in on that device, `pinResetRequired` is true. The gate then shows a mandatory `SetPinFlow` in "replace" mode, with a "Turn off app lock" option, before any content. The Google sign-in proves the owner.
- A borrower who knows only the laptop cannot reset the PIN, because they would need the owner's Google password or phone screen lock.

### 11. Sign-in and sign-out: the lock presenter subscribes to auth
- The root creates the lock presenter before the shell creates the `AuthPresenter`. The shell (web) and `HomeScreen` (mobile) call `appLock.bindAuth(authPresenter)`.
- The lock presenter listens to the auth presenter, following rule 8: the reader subscribes to the owner, and auth does not push into the lock.
- **Signed out → signed in:** fetch the account PIN, start the realtime subscription, and start unlocked.
- **Signed in → signed out:** stop the subscription, delete the cache, and reset the device's wrong-PIN state. Keep the account row. Keep `pinResetPending` if it is set.
- **While signed out:** `isAvailable` is false, so there is no lock and no Security controls. Only the login screen is visible.

### 12. Android app-switcher privacy without `FLAG_SECURE`
- Add a `setRecentsPrivacy(bool)` method on the existing `com.nudgr.app/lockscreen` channel in `MainActivity.kt`. On API 33+ it calls `Activity.setRecentsScreenshotEnabled(!enabled)`. On older APIs it does nothing.
- The presenter calls it whenever `isEnabled` changes and on init.
- **Alternative considered:** `FLAG_SECURE`. It was rejected because it also blocks screenshots and screen recording.

### 13. Lock screen UI
- Use an opaque `scaffoldBackgroundColor` surface. Do not use blur.
- Show the app mark, the title "Enter PIN", and the PIN dots, with a semantic label such as "3 of 6 digits entered".
- Use a 3×4 keypad with 64 px keys in the bottom part of the screen: digits, a biometric key or blank, and backspace.
- Show "Forgot PIN?" as a text button.
- A wrong PIN shows a horizontal shake of 250 ms. The cooldown shows a countdown and a disabled keypad.
- When biometrics are on, the prompt starts automatically when the screen shows. The keypad is visible behind it as the backup.
- Web uses the same widget, centered with a maximum width of 360 px, and it accepts physical digit keys.
- Use theme colors only (`colorScheme.*`, `textTheme.*`).
- `SetPinFlow` (choose 4 or 6 → enter → confirm) reuses the keypad. It shows a spinner while `AppLockRemote` writes, and an error with a retry when it is offline.

### 14. Settings surfaces
- **Mobile:** add a "Security" section in `settings_screen.dart` after "Account".
  - Signed out: "Sign in to use app lock".
  - Signed in: App lock (switch), Lock after (picker), Use biometrics (only when available), Change PIN, and Lock now.
  - A subtitle states "Your PIN works on all your devices."
- **Web:**
  - Narrow layout: a "Security" card on `web_more_page.dart`.
  - Desktop layout: a "Security" button in the sidebar footer (v1 `_SignOutFooter` and v2 `_NavFoot` through `WebShellV2.footerExtra`). It opens the same rows in a dialog. Beside it is a "Lock now" icon button.
- One widget, `AppLockSettingsTiles`, renders the rows on every surface, so the platforms cannot drift.
- Each row reads presenter getters. No logic goes in `build()`.

## Risks / Trade-offs

- **[A 4–6 digit PIN hash is brute-forceable offline]** There are at most 10⁶ combinations. Anyone who can read the device storage or the user's `app_lock` row can crack it in seconds. → Accept this. Only the user's own session can read the row (RLS), and that session can already read all their finance data. The real protection is the per-device UI throttle. The hash only stops the PIN from showing in plain text.
- **[An offline device keeps an old PIN]** After a PIN change, a device that stays offline still accepts the old PIN until it refreshes. → Accept this. It is the cost of offline unlock. It refreshes on the next foreground or tab show with a connection.
- **[Web content stays in memory and in local storage]** A person with developer tools can read everything. → This is a documented non-goal. The 10-wrong-PIN sign-out limits guessing through the UI.
- **[A missed exemption locks the user mid-flow]** → List every current call site in the tasks. Add a code-review note in the presenter doc comment. The failure is annoying but safe.
- **[The biometric prompt pauses the activity on Android]** This can cause a lock → prompt → resume → lock loop. → The prompt always runs inside `runExempt`. A test covers the loop.
- **[A phone with no screen lock and a forgotten PIN]** → The web Forgot PIN path still works, because the PIN is account-level. The mobile lock screen points the user there.
- **[The migration is not applied before the app ships]** `AppLockRemote` calls fail with a missing-table error. → The presenter treats a missing table as "app lock unavailable" and hides the Security controls, so nothing breaks. The PR description lists the migration as a manual step.
- **[Multiple web tabs]** Each tab has its own timer. → This is a non-goal for v1.
- **[PBKDF2 cost on web]** → A task measures it and tunes the count. The count is stored with the hash.

## Migration Plan

1. Apply `docs/supabase_migration_058_app_lock.sql` by hand in the Supabase SQL editor. It creates the table, the RLS policies, and the realtime publication entry.
2. Ship the app. The lock is off for every account until the user sets a PIN. Existing users see only the new Settings section.
3. **Rollback:** revert the app code. The `app_lock` table and the local keys stay unused and harmless. To remove them fully, drop the table.

## Open Questions

- Should there be a "Lock now" keyboard shortcut on web, for example `Ctrl+Shift+L`? The current design has none.
- Should Treasury-only locking on mobile (lock only the Treasury tab) be an option later? It is out of scope now.
