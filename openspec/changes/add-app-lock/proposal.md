## Why

Other people sometimes use the owner's laptop and phone. The Treasury web app and the mobile app stay signed in, so balances, transactions, and health data are open to anyone who sits down at the device. Banking apps such as GCash solve this with an account PIN (MPIN) and optional biometrics over an app that stays signed in and loaded. This app needs the same gate. It also needs one PIN for the whole account, so that the user does not have to remember a different PIN for each device.

## What Changes

- Add an **app lock**: an opaque lock screen that covers the whole app until the user unlocks it. The session and all loaded data stay in memory behind it. Nothing signs out and nothing reloads on unlock.
- **One PIN per account.** The PIN (4 or 6 digits) belongs to the account. It is the same on the phone and on the web. The user sets it once, and it applies on every device where they sign in. The PIN is the required credential, because the web supports only a PIN.
- **The account stores only a salted PBKDF2 hash** of the PIN, in a new user-scoped Supabase table, `app_lock`. Each device keeps a local copy of the hash, so unlock works offline.
- **Biometrics on the phone, with the PIN as the backup.** On the phone, the user can turn on fingerprint or face unlock. When it is on, the lock screen asks for the biometric first. The PIN always works as the backup. The web has no biometric option.
- **On/off is account-level.** Setting the PIN turns the lock on for all devices of the account. Turning it off (with the PIN) turns it off everywhere.
- **Per-device settings**: "Lock after" and "Use biometrics" stay on each device. A laptop and a phone need different timeouts, and biometrics belong to one phone.
- **Auto-lock triggers**:
  - Mobile: the app returns to the foreground after it was in the background for the chosen time (Immediately, 1, 5, or 15 minutes). A cold start always locks.
  - Web: no pointer or keyboard input for the chosen time (1, 5, 15, 30, or 60 minutes). This includes time the tab is hidden. A reload locks if the idle time already passed.
- **Manual lock**: a "Lock now" action on both platforms.
- **Wrong-PIN throttle**: an escalating cooldown after 5 wrong PINs, counted on each device. On the web, 10 wrong PINs sign the user out.
- **Forgot PIN**:
  - Mobile: unlock with the device screen lock, then set a new PIN for the account.
  - Web: sign out, sign in again with Google, then set a new PIN for the account.
- **The app lock needs a signed-in account.** The PIN lives on the account. A mobile user who has not signed in sees "Sign in to use app lock".
- **Sign-out keeps the PIN on the account.** It deletes only the local copy on that device. When the user signs in again, the lock is on with the same PIN.
- **App-switcher privacy (Android)**: hide the app preview in the recent-apps screen while the lock is on. Screenshots stay allowed.
- **Settings**: a new "Security" section in mobile Settings and on the web "More" page.
- **The fasting alarm still shows** over the Android lock screen. The app lock never covers a live alarm.

## Capabilities

### New Capabilities
- `app-lock`: The lock gate. It covers the account PIN and how it syncs, biometric unlock on mobile, idle and background auto-lock, the wrong-PIN throttle, Forgot PIN, app-switcher privacy, per-device settings, the alarm exemption, and sign-in/sign-out behavior. It applies to the mobile app and the Treasury web app.

### Modified Capabilities
- None. The only existing spec is `hub`, and its requirements do not change.

## Non-goals

- **Encryption at rest on web.** The lock covers the screen. It does not stop a person with browser developer tools from reading local storage. `docs/data_security_spec.md` already scopes web out of at-rest encryption.
- **Server-side PIN checks.** The device checks the PIN against its local copy of the hash. There is no edge function and no server rate limit.
- **Changing the PIN while offline.** Set, change, and turn-off need a connection, so that devices do not disagree about the PIN.
- **App lock without an account** (a local-only PIN for guest users on mobile).
- **WebAuthn or Windows Hello on web.** Without a server check, these only prove presence, so the PIN is enough for this threat model.
- **Per-page passwords** in the style of Webflow. The lock covers the whole app.
- **Home-screen widgets and notification content.** These live outside the app process. `docs/data_security_spec.md` Phase 4 tracks them.
- **Lock state shared across browser tabs.** Each tab locks and unlocks on its own.
- **Remote lock or remote wipe.**
- **iOS.** The repo has no iOS target today.

## Impact

- **New code**:
  - `lib/presenters/app_lock_presenter.dart`
  - `lib/services/app_lock/`: PIN hashing, the local verifier cache, the cloud `AppLockRemote`, the biometric authenticator interface and the `local_auth` implementation, and the privacy-flag channel
  - `lib/views/app_lock/`: lock screen, PIN pad, set-PIN flow, activity detector
- **Modified code**:
  - `lib/views/fasting_app.dart` and `lib/views/web/treasury_web_app.dart`: root overlay through `MaterialApp.builder`
  - `lib/views/settings_screen.dart` and `lib/views/web/pages/more/web_more_page.dart`: Security section
  - `lib/services/storage_service.dart` and `local_storage_service.dart`: device-level lock settings
  - Callers that open external activities (photo picker, Google sign-in, file open, URL launch), which get a lock exemption
- **Backend**: a new table `app_lock` (`user_id` primary key, `verifier` jsonb, `updated_at`) with user-scoped RLS, added to the realtime publication. It ships as the manual migration `docs/supabase_migration_058_app_lock.sql`. It does not use the generic `SyncQueue` and adds no `SyncDomain`.
- **Dependencies**: add `local_auth` (mobile only; `main_web.dart` must not import it). `cryptography` is already present and supplies PBKDF2.
- **Android**:
  - `USE_BIOMETRIC` permission
  - A `MainActivity.kt` method-channel call for `setRecentsScreenshotEnabled(false)` (API 33+)
  - `MainActivity` already extends `FlutterFragmentActivity`, and `minSdk` is 26, so `local_auth` 3.x works
