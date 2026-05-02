# OTA Self-Update Spec

## Overview
Allows the app to discover, download, and install new APK builds without USB sideloading.
A version manifest JSON file lives in Supabase Storage. On app foreground (or once per day),
the app fetches the manifest, compares versions, and if newer: shows a prompt, downloads the
APK with progress, then fires a local notification — "Download complete — Install update" —
that opens the Android package installer. Distribution is entirely outside the Play Store.

## User Story
As a developer/user of the sideloaded build, I want the app to notify me when a new version
is available and let me install it in two taps, so I never have to connect a USB cable again.

## Data Model
```dart
// lib/models/app_release.dart
class AppRelease {
  final String version;       // semver: "1.4.2"
  final int buildNumber;      // monotonically increasing integer
  final String apkUrl;        // Supabase Storage public URL
  final String releaseNotes;  // plain text, shown in the prompt
  final DateTime releasedAt;

  const AppRelease({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    required this.releasedAt,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
        version: json['version'] as String,
        buildNumber: json['build_number'] as int,
        apkUrl: json['apk_url'] as String,
        releaseNotes: json['release_notes'] as String? ?? '',
        releasedAt: DateTime.parse(json['released_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'build_number': buildNumber,
        'apk_url': apkUrl,
        'release_notes': releaseNotes,
        'released_at': releasedAt.toIso8601String(),
      };
}

// Supabase Storage manifest path: releases/manifest.json
// Shape of manifest.json:
// {
//   "version": "1.4.2",
//   "build_number": 42,
//   "apk_url": "https://<project>.supabase.co/storage/v1/object/public/releases/the-system-1.4.2.apk",
//   "release_notes": "Fixed fasting timer drift. New quest board UI.",
//   "released_at": "2026-05-01T10:00:00Z"
// }
```

## Presenter API
```dart
// lib/presenters/update_presenter.dart
enum UpdateState { idle, checking, available, downloading, readyToInstall, error }

class UpdatePresenter extends ChangeNotifier {
  UpdateState get state => _state;
  AppRelease? get availableRelease => _availableRelease;
  double get downloadProgress => _downloadProgress;   // 0.0–1.0
  String? get errorMessage => _errorMessage;
  bool get isDismissed => _isDismissed;

  /// Called on app resume / first launch. No-ops if checked within last 24 h.
  Future<void> checkForUpdate() async { ... }

  /// User confirmed download. Streams progress → state = readyToInstall when done.
  Future<void> downloadUpdate() async { ... }

  /// Opens Android package installer for the cached APK.
  Future<void> installUpdate() async { ... }

  /// Stores dismissed build number so we don't re-prompt for the same version.
  void dismissUpdate() { ... }
}
```

## UI Requirements

### Update Prompt Bottom Sheet
- Triggered automatically when `state == UpdateState.available` and not dismissed.
- **Header:** "System Update Available" (RPG flavor: "NEW SYSTEM PATCH DETECTED")
- **Body:** version badge (`v1.4.2`), release notes text, released date.
- **Primary CTA (bottom 30%):** "Download Update" — full-width, 56 px tall.
- **Secondary:** "Later" text button — dismisses for this session only.
- **"Don't show for this version"** checkbox — persists dismissal to storage.
- Entrance animation: slide up 300 ms ease-out from bottom edge.

### Download Progress State (replaces CTA)
- `LinearProgressIndicator` filling the button area (0–100%).
- Text: "Downloading… 42%" centered over bar.
- Not cancellable once started (keep it simple).

### Download Complete Notification
- Channel: `update_channel` (separate from fasting/quest channels).
- Title: "System Patch Ready"
- Body: "The System v1.4.2 — tap to install"
- Tap action: opens `InstallUpdateActivity` intent (triggers package installer).
- Shown even if app is backgrounded or closed.

### In-App Ready-to-Install Banner (when app is foregrounded after download)
- Persistent banner at top of `HomeScreen` (below AppBar, above main content).
- Text: "Update downloaded — Install now"
- Tap: calls `presenter.installUpdate()`.
- Dismiss X button: hides banner for the session (does not delete APK).

### States
| State | UI |
|---|---|
| `idle` | Nothing shown |
| `checking` | Invisible (background only) |
| `available` | Bottom sheet modal |
| `downloading` | Progress in bottom sheet |
| `readyToInstall` | Notification + in-app banner |
| `error` | Snackbar: "Update check failed — try again later" |

### Micro-animations
- Bottom sheet entrance: 300 ms slide-up.
- Progress bar fill: animated, continuous.
- Banner entrance: 200 ms fade-in + 8 px slide-down.

## RPG Mechanics
Not applicable — this is infrastructure. No XP, no level-up, no streak.

## Storage
New `StorageService` keys (via `StorageService` abstract + `LocalStorageService` impl):

| Key constant | Value | Purpose |
|---|---|---|
| `keyDismissedBuildNumber` | `int` | Last build number the user dismissed |
| `keyLastUpdateCheckAt` | `String` (ISO-8601) | Throttle checks to once per 24 h |

```dart
static const String keyDismissedBuildNumber = 'ota_dismissed_build_number';
static const String keyLastUpdateCheckAt    = 'ota_last_check_at';
```

Downloaded APK is saved to `getExternalStorageDirectory()/updates/app-release-<buildNumber>.apk`
(e.g. `app-release-42.apk`). Keyed by build number so the app can detect a stale cached
download from a previous update attempt. Any file in `updates/` whose build number does not
match the manifest's current `build_number` is deleted on next `checkForUpdate()` call.
On successful installation the file is deleted immediately.

## Android Setup Required
```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="28" />

<!-- FileProvider for sharing APK URI on Android 7+ -->
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
  <meta-data
      android:name="android.support.FILE_PROVIDER_PATHS"
      android:resource="@xml/file_paths" />
</provider>
```

```xml
<!-- android/app/src/main/res/xml/file_paths.xml -->
<paths>
  <external-files-path name="updates" path="updates/" />
</paths>
```

New Flutter packages:
- `dio` — HTTP download with progress stream.
- `open_file_plus` — cross-platform file opener (triggers package installer on Android).
- `package_info_plus` — already likely present; reads current `buildNumber`.
- `path_provider` — already likely present; resolves external storage path.

## Supabase Setup Required
1. Create Storage bucket `releases` (public read, authenticated write).
2. Upload `manifest.json` to `releases/manifest.json` as part of the build/release workflow.
3. Upload APK to `releases/app-release.apk` — **always the same fixed filename, upserted each
   release** (Supabase `upsert: true`). This keeps storage at a flat 2-file footprint forever:
   `manifest.json` + `app-release.apk`. No per-version file accumulation.
4. Manifest URL pattern: `https://<project-ref>.supabase.co/storage/v1/object/public/releases/manifest.json`
5. APK URL pattern: `https://<project-ref>.supabase.co/storage/v1/object/public/releases/app-release.apk`
   (this fixed URL is embedded in `manifest.json` as `apk_url` — it never changes between releases)

The manifest URL is stored as an env var / compile-time constant:
```dart
// lib/utils/app_constants.dart
const String kUpdateManifestUrl = String.fromEnvironment('UPDATE_MANIFEST_URL');
```

> **Storage idempotency:** Because the APK path is always `releases/app-release.apk`, every
> new release simply overwrites the previous one. Storage usage stays constant (~50–80 MB max).
> The `build_number` in the manifest is the sole source of truth for "is this newer?"

## Edge Cases
- **No internet:** `checkForUpdate` catches `SocketException`; silently fails, no UI shown.
- **Same or lower build number:** No prompt shown; manifest fetch is a no-op.
- **User dismissed this version:** `dismissedBuildNumber == release.buildNumber` → skip prompt.
- **Download interrupted mid-way:** `dio` throws; state → `error`; partial file deleted; snackbar shown.
- **APK already cached (app restarted after download):** On launch, check if cached APK exists for current `availableRelease`; skip download, go straight to `readyToInstall`.
- **Install rejected by user in OS dialog:** No action needed; banner remains; user can tap again.
- **Android 8+ install from unknown sources:** OS prompts user to enable "Install unknown apps" for this app on first install attempt — this is expected behavior, not an error.
- **Supabase bucket unavailable / 404:** Treat as no update; log error silently.

## Acceptance Criteria
- [ ] `checkForUpdate()` fetches manifest and compares `buildNumber` against `package_info_plus` current build.
- [ ] Update prompt bottom sheet appears automatically when a newer build is detected and not dismissed.
- [ ] "Download Update" triggers `dio` download with live `LinearProgressIndicator` (0–100%).
- [ ] On download complete, a local notification fires even if app is backgrounded.
- [ ] Tapping the notification (or in-app banner) opens the Android package installer for the cached APK.
- [ ] "Don't show for this version" checkbox persists dismissal; same version never re-prompts.
- [ ] `checkForUpdate()` is throttled to once per 24 hours via `keyLastUpdateCheckAt`.
- [ ] Partial/failed downloads clean up the temp file and show an error snackbar.
- [ ] No crash or UI shown when device is offline.
- [ ] `UPDATE_MANIFEST_URL` is read from environment (not hardcoded in source).
