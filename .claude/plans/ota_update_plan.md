# OTA Self-Update — Implementation Plan

## Goal
Deliver a zero-USB update flow: new APK built → pushed to Supabase Storage → app detects it on
resume → prompts user → downloads with progress → local notification fires → two taps to install.
Keeps the `releases` bucket at a permanent 2-file footprint (idempotent upsert).

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `pubspec.yaml` | Modify — add `dio`, `open_file_plus`, `package_info_plus` | — |
| `android/app/src/main/AndroidManifest.xml` | Modify — add `REQUEST_INSTALL_PACKAGES`, `FileProvider` | Android |
| `android/app/src/main/res/xml/file_paths.xml` | **Create** — FileProvider paths config | Android |
| `lib/models/app_release.dart` | **Create** | Model |
| `lib/services/storage_service.dart` | Modify — 2 new keys + 2 abstract methods | Service |
| `lib/services/local_storage_service.dart` | Modify — implement 2 new methods | Service |
| `lib/services/notification_service.dart` | Modify — new channel + `showUpdateReadyNotification()` + tap routing | Service |
| `lib/presenters/update_presenter.dart` | **Create** | Presenter |
| `lib/views/widgets/update_bottom_sheet.dart` | **Create** | View |
| `lib/views/widgets/update_banner.dart` | **Create** | View |
| `lib/views/home_screen.dart` (`AppShell`) | Modify — wire presenter, trigger check on resume, show banner | View |

---

## Interface Definitions

### Model — `lib/models/app_release.dart`
```dart
class AppRelease {
  final String version;       // "1.4.2"
  final int buildNumber;      // monotonically increasing — sole comparator
  final String apkUrl;        // always the fixed Supabase public URL
  final String releaseNotes;
  final DateTime releasedAt;

  factory AppRelease.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

### StorageService — new surface
```dart
// Two new key constants (abstract class static fields)
static const String keyDismissedBuildNumber = 'ota_dismissed_build_number';
static const String keyLastUpdateCheckAt    = 'ota_last_check_at';
static const String keyCachedApkBuildNumber = 'ota_cached_apk_build_number'; // persists path for notification tap

// Two new abstract methods
Future<void> saveOtaPrefs({int? dismissedBuild, String? lastCheckAt, int? cachedApkBuild});
Future<Map<String, dynamic>> loadOtaPrefs();
// Returns: { 'dismissedBuild': int?, 'lastCheckAt': String?, 'cachedApkBuild': int? }
```

### NotificationService — new surface
```dart
static const String channelIdUpdate = 'update_channel';
static const String channelNameUpdate = 'App Updates';

// Call after download completes. apkPath stored as payload for tap routing.
Future<void> showUpdateReadyNotification(String version, String apkPath) async;

// Tap handler payload routing — in onDidReceiveNotificationResponse:
// if payload starts with 'install_apk:' → OpenFile.open(path)
```

### UpdatePresenter — public API
```dart
enum UpdateState { idle, checking, available, downloading, readyToInstall, error }

class UpdatePresenter extends ChangeNotifier {
  // Constructor injection
  UpdatePresenter({
    required StorageService storage,
    required NotificationService notifications,
  });

  // Observables
  UpdateState get state;
  AppRelease? get availableRelease;
  double get downloadProgress;   // 0.0–1.0
  String? get errorMessage;
  bool get bannerDismissedForSession;

  // Actions
  Future<void> checkForUpdate();    // throttled to once/24h; no-op if offline
  Future<void> downloadUpdate();    // dio download → readyToInstall + notification
  Future<void> installUpdate();     // OpenFile.open(cachedApkPath)
  void dismissUpdate({bool permanent = false}); // permanent → persists build number
  void dismissBanner();             // session-only banner hide
}
```

---

## Implementation Order

### Step 1 — Android plumbing
- [ ] Add `REQUEST_INSTALL_PACKAGES` + `WRITE_EXTERNAL_STORAGE` (maxSdk 28) to `AndroidManifest.xml`
- [ ] Add `FileProvider` `<provider>` block to `AndroidManifest.xml` (authority: `${applicationId}.fileprovider`)
- [ ] Create `android/app/src/main/res/xml/file_paths.xml` with `<external-files-path name="updates" path="updates/"/>`

### Step 2 — pubspec dependencies
- [ ] Add `dio: ^5.x` (download with progress stream)
- [ ] Add `open_file_plus: ^3.x` (triggers package installer)
- [ ] Add `package_info_plus: ^8.x` (reads current `buildNumber`)
  - `path_provider: ^2.1.0` already present — no change needed

### Step 3 — Model
- [ ] Create `lib/models/app_release.dart` — immutable, `fromJson`/`toJson`, no logic

### Step 4 — StorageService
- [ ] Add 3 key constants to abstract class
- [ ] Add `saveOtaPrefs` / `loadOtaPrefs` abstract methods
- [ ] Implement both methods in `LocalStorageService` using `SharedPreferences` (`setInt`/`setString`)

### Step 5 — NotificationService
- [ ] Add `channelIdUpdate` / `channelNameUpdate` constants
- [ ] Register `update_channel` in `init()` alongside existing channels
- [ ] Add `showUpdateReadyNotification(String version, String apkPath)`:
  - Payload: `'install_apk:<apkPath>'`
  - Priority: high, no ongoing
- [ ] Extend `onDidReceiveNotificationResponse` to route `install_apk:` payloads →
  `OpenFile.open(path)` (handles tap when app is foregrounded from notification)
- [ ] Extend `notificationTapBackground` similarly for background taps

### Step 6 — UpdatePresenter
- [ ] Inject `StorageService` + `NotificationService` (constructor injection, matches project pattern)
- [ ] `checkForUpdate()`:
  1. Load `loadOtaPrefs()` → check `lastCheckAt` (skip if < 24h ago)
  2. `PackageInfo.fromPlatform()` → get current `buildNumber`
  3. `dio.get(kUpdateManifestUrl)` → parse `AppRelease.fromJson()`
  4. Compare `release.buildNumber > currentBuildNumber` — if not newer, set `idle`, return
  5. Check `dismissedBuild == release.buildNumber` — if dismissed, return
  6. Clean stale APK files in `updates/` dir (any file not matching current `release.buildNumber`)
  7. Check if `app-release-<buildNumber>.apk` already cached → set `readyToInstall` directly
  8. Otherwise set `available` → `notifyListeners()`
  9. Persist `lastCheckAt` = now
  10. Catch all errors → silent fail (no UI, just `idle`)
- [ ] `downloadUpdate()`:
  1. Set `downloading` → `notifyListeners()`
  2. `dio.download(url, savePath, onReceiveProgress: ...)` → update `_downloadProgress` each tick
  3. On complete: `saveOtaPrefs(cachedApkBuild: buildNumber)` → `showUpdateReadyNotification()`
  4. Set `readyToInstall` → `notifyListeners()`
  5. On error: delete partial file → set `error` with message → `notifyListeners()`
- [ ] `installUpdate()`: `OpenFile.open(cachedApkPath)` — OS handles the rest
- [ ] `dismissUpdate({bool permanent})`: session flag or persist `dismissedBuild`; set `idle`
- [ ] `dismissBanner()`: `_bannerDismissedForSession = true; notifyListeners()`

### Step 7 — UpdateBottomSheet widget
- [ ] `lib/views/widgets/update_bottom_sheet.dart` — stateless, takes `UpdatePresenter`
- [ ] `ListenableBuilder` on presenter — renders two sub-states:
  - `available`: version badge, release notes, "DOWNLOAD UPDATE" button + "Later" + checkbox
  - `downloading`: `LinearProgressIndicator` + "Downloading… N%" text (no cancel button)
- [ ] `showModalBottomSheet` called from `AppShell` (not self-launched from widget)
- [ ] "Don't show for this version" `Checkbox` → calls `dismissUpdate(permanent: true)` + `Navigator.pop`
- [ ] "Later" → `dismissUpdate()` (session) + `Navigator.pop`
- [ ] RPG framing: title = "NEW SYSTEM PATCH DETECTED", subtitle = "v{version}"

### Step 8 — UpdateBanner widget
- [ ] `lib/views/widgets/update_banner.dart` — slim top banner, 48 px tall
- [ ] Shown only when `state == readyToInstall && !bannerDismissedForSession`
- [ ] "Install now" taps `presenter.installUpdate()`
- [ ] X dismisses via `presenter.dismissBanner()`
- [ ] Entrance: 200 ms `AnimatedSlide` + `AnimatedOpacity` from top

### Step 9 — Wire into AppShell (home_screen.dart)
- [ ] Declare `late final UpdatePresenter _updatePresenter` in `_AppShellState`
- [ ] Instantiate in `initState` with `_storage` + `NotificationService()`
- [ ] In `addPostFrameCallback`: call `_updatePresenter.checkForUpdate()` after auth init
- [ ] In `didChangeAppLifecycleState(resumed)`: call `_updatePresenter.checkForUpdate()`
- [ ] In `dispose`: call `_updatePresenter.dispose()`
- [ ] In `build`: wrap `Scaffold.body` in a `ListenableBuilder` on `_updatePresenter`:
  - If `state == available && !isDismissed`: call `showModalBottomSheet(UpdateBottomSheet)` as
    a post-frame callback (avoid calling during build)
  - If `state == readyToInstall && !bannerDismissedForSession`: render `UpdateBanner` above
    the current screen via `Column([UpdateBanner(), Expanded(child: screens[_selectedIndex])])`
  - Error state: `ScaffoldMessenger.of(context).showSnackBar(...)` as post-frame callback

### Step 10 — Supabase setup (manual, one-time)
- [ ] Create `releases` bucket in Supabase dashboard — Public read, requires auth for write
- [ ] Upload initial `manifest.json` to `releases/manifest.json`
- [ ] Upload initial APK as `releases/app-release.apk`
- [ ] Add `UPDATE_MANIFEST_URL` to `.env` and CI secrets
- [ ] Document upload script (upsert pattern) in `docs/ota_update_spec.md`

---

## Build & Release Workflow (after implementation)
Every new build:
1. `flutter build apk --release --dart-define=...`
2. Edit `manifest.json` with new `version`, `build_number`, `released_at`
3. `supabase storage upload releases/manifest.json --upsert`
4. `supabase storage upload releases/app-release.apk --upsert`

Storage stays at exactly 2 files forever.

---

## RPG Impact
None — this feature has no XP, level, or streak effects.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Android 8+ "Install unknown apps" prompt surprises user | Expected OS behavior — no special handling needed. User enables once, remembered by OS. |
| Notification tap when app is fully closed | `notificationTapBackground` must call `OpenFile.open()`. APK path must be stored in storage (not just memory) via `keyCachedApkBuildNumber`. |
| Download fires twice (double-resume) | `checkForUpdate()` guards with `state != idle` check at entry point. |
| Supabase URL contains sensitive project ref | URL is public (public bucket) — safe in `.env`, but keep out of source. |
| `getExternalStorageDirectory()` returns null on some devices | Fallback to `getApplicationDocumentsDirectory()` + `updates/` subdirectory. |
| dio `CancelToken` not implemented | Download is not cancellable per spec — acceptable for v1. |
| `open_file_plus` not available on iOS | This feature is Android-only; guard all `installUpdate()` logic with `Platform.isAndroid`. |

---

## Acceptance Criteria
- [ ] `checkForUpdate()` compares manifest `build_number` vs `PackageInfo.buildNumber`
- [ ] No prompt shown if manifest build ≤ current build, version dismissed, or checked < 24h ago
- [ ] Bottom sheet appears automatically on `available` state; does not show during `build()`
- [ ] `LinearProgressIndicator` updates live during download (not just on complete)
- [ ] Local notification fires on download complete even if app is backgrounded
- [ ] Notification tap opens the Android package installer (APK path routed via payload)
- [ ] "Don't show for this version" persists across app restarts for the same build number
- [ ] Stale cached APKs from prior attempts are cleaned up on next `checkForUpdate()`
- [ ] No exception thrown when offline — `idle` state, no UI
- [ ] `UPDATE_MANIFEST_URL` not hardcoded in Dart source

---
*Awaiting approval before any code is written.*
