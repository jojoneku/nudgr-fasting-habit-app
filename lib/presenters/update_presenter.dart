import 'package:flutter/foundation.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';

/// OTA update flow (docs/ota_update_spec.md): check → available → in-app
/// download with progress → ready-to-install → package installer.
enum UpdateFlowState {
  idle,
  checking,
  available,
  downloading,
  readyToInstall,
  error,
}

class UpdatePresenter extends ChangeNotifier {
  final UpdateService updateService;
  final LocalStorageService storage;
  final NotificationService? notifications;
  final String currentVersion;

  UpdateManifest? _latestManifest;
  UpdateFlowState _state = UpdateFlowState.idle;
  bool _updateAvailable = false;
  bool _dismissed = false;
  double? _downloadProgress; // 0.0–1.0, null while total size is unknown
  String? _errorMessage;
  String? _apkPath;
  int _lastNotifiedPercent = -1;

  UpdatePresenter({
    required this.updateService,
    required this.storage,
    required this.currentVersion,
    this.notifications,
  });

  UpdateManifest? get latestManifest => _latestManifest;
  UpdateFlowState get state => _state;
  bool get isChecking => _state == UpdateFlowState.checking;
  bool get isDownloading => _state == UpdateFlowState.downloading;
  bool get readyToInstall => _state == UpdateFlowState.readyToInstall;
  bool get updateAvailable => _updateAvailable && !_dismissed;
  bool get dismissed => _dismissed;
  double? get downloadProgress => _downloadProgress;
  String? get errorMessage => _errorMessage;

  /// Whether the update can be downloaded and installed in-app (Android).
  /// When false the UI falls back to opening the release URL in a browser.
  bool get canSelfUpdate => updateService.supportsInAppInstall;

  /// Check for updates and load the latest manifest
  Future<void> checkForUpdates() async {
    // Never clobber an in-flight download / pending install on app resume.
    if (_state == UpdateFlowState.downloading ||
        _state == UpdateFlowState.readyToInstall) {
      return;
    }
    _state = UpdateFlowState.checking;
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

      if (!_updateAvailable) {
        _state = UpdateFlowState.idle;
        return;
      }

      // A previous attempt may have finished the download already (stale
      // versions get cleaned up inside cachedApk).
      if (canSelfUpdate) {
        final cached = await updateService.cachedApk(_latestManifest!);
        if (cached != null) {
          _apkPath = cached.path;
          _state = UpdateFlowState.readyToInstall;
          return;
        }
      }
      _state = UpdateFlowState.available;
    } finally {
      if (_state == UpdateFlowState.checking) _state = UpdateFlowState.idle;
      notifyListeners();
    }
  }

  /// Downloads the APK with live progress, then fires the "ready to install"
  /// notification. No-op unless an update is available (or retrying an error).
  Future<void> downloadUpdate() async {
    final manifest = _latestManifest;
    if (manifest == null || !canSelfUpdate) return;
    if (_state != UpdateFlowState.available &&
        _state != UpdateFlowState.error) {
      return;
    }

    _state = UpdateFlowState.downloading;
    _downloadProgress = null;
    _errorMessage = null;
    _lastNotifiedPercent = -1;
    notifyListeners();

    try {
      final file = await updateService.downloadApk(
        manifest,
        onProgress: _onDownloadProgress,
      );
      _apkPath = file.path;
      _downloadProgress = 1.0;
      _state = UpdateFlowState.readyToInstall;
      notifyListeners();
      await notifications?.showUpdateReadyNotification(
          manifest.version, file.path);
    } catch (e) {
      debugPrint('UpdatePresenter: download failed: $e');
      _errorMessage = 'Download failed. Check your connection and retry.';
      _state = UpdateFlowState.error;
      notifyListeners();
    }
  }

  void _onDownloadProgress(int received, int total) {
    if (total <= 0) return; // no content length — stay indeterminate
    final percent = (received * 100) ~/ total;
    if (percent == _lastNotifiedPercent) return; // throttle to 1% steps
    _lastNotifiedPercent = percent;
    _downloadProgress = received / total;
    notifyListeners();
  }

  /// Opens the Android package installer for the downloaded APK.
  /// Returns null on success, or a user-facing error message.
  Future<String?> installUpdate() async {
    final path = _apkPath;
    if (path == null) return 'No downloaded update found.';
    await notifications?.cancelUpdateReadyNotification();
    return updateService.openApkInstaller(path);
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
