import 'package:flutter/foundation.dart';
import '../services/update_service.dart';
import '../services/patch_update_service.dart';
import '../services/local_storage_service.dart';

class UpdatePresenter extends ChangeNotifier {
  final UpdateService updateService;
  final LocalStorageService storage;
  final String currentVersion;

  /// Optional Shorebird code-push observer. When null (e.g. web), patch
  /// handling is simply disabled and only the full-APK flow runs.
  final PatchUpdateService? patchService;

  UpdateManifest? _latestManifest;
  bool _isChecking = false;
  bool _updateAvailable = false;
  bool _dismissed = false;
  bool _patchReady = false;
  bool _patchDismissed = false;

  UpdatePresenter({
    required this.updateService,
    required this.storage,
    required this.currentVersion,
    this.patchService,
  });

  UpdateManifest? get latestManifest => _latestManifest;
  bool get isChecking => _isChecking;
  bool get updateAvailable => _updateAvailable && !_dismissed;
  bool get dismissed => _dismissed;

  /// True when a Shorebird patch has been downloaded and will apply on the
  /// next app launch — the UI can prompt the user to reopen the app.
  bool get patchReady => _patchReady && !_patchDismissed;

  /// Check for updates and load the latest manifest
  Future<void> checkForUpdates() async {
    _isChecking = true;
    notifyListeners();

    try {
      final manifest = await updateService.fetchLatestManifest();
      _latestManifest = manifest;

      if (manifest != null) {
        _updateAvailable = UpdateService.isUpdateAvailable(
          currentVersion,
          manifest.version,
        );
      }
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  /// Check for a Shorebird code-push patch and stage it in the background.
  /// Safe to call on every build — no-ops when no patch service is wired or
  /// the updater is unavailable (debug/web/non-Shorebird builds).
  Future<void> checkForPatch() async {
    final service = patchService;
    if (service == null || !service.isAvailable) return;
    final ready = await service.checkAndStageUpdate();
    if (ready && !_patchReady) {
      _patchReady = true;
      notifyListeners();
    }
  }

  /// Mark the current update as dismissed (won't prompt again until app restart)
  void dismissUpdate() {
    _dismissed = true;
    notifyListeners();
  }

  /// Dismiss the "patch ready — reopen to apply" nudge for this session.
  void dismissPatch() {
    _patchDismissed = true;
    notifyListeners();
  }

  /// Reset dismissed state (useful for testing)
  void resetDismissed() {
    _dismissed = false;
    notifyListeners();
  }
}
