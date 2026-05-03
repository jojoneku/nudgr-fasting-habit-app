import 'package:flutter/foundation.dart';
import '../services/update_service.dart';
import '../services/local_storage_service.dart';

class UpdatePresenter extends ChangeNotifier {
  final UpdateService updateService;
  final LocalStorageService storage;
  final String currentVersion;

  UpdateManifest? _latestManifest;
  bool _isChecking = false;
  bool _updateAvailable = false;
  bool _dismissed = false;

  UpdatePresenter({
    required this.updateService,
    required this.storage,
    required this.currentVersion,
  });

  UpdateManifest? get latestManifest => _latestManifest;
  bool get isChecking => _isChecking;
  bool get updateAvailable => _updateAvailable && !_dismissed;
  bool get dismissed => _dismissed;

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

  /// Mark the current update as dismissed (won't prompt again until app restart)
  void dismissUpdate() {
    _dismissed = true;
    notifyListeners();
  }

  /// Reset dismissed state (useful for testing)
  void resetDismissed() {
    _dismissed = false;
    notifyListeners();
  }
}
