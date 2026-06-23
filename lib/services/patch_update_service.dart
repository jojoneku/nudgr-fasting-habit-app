import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Thin wrapper around the Shorebird code-push updater.
///
/// Keeps the `shorebird_code_push` dependency at the service boundary so
/// presenters/views stay package-agnostic and the behaviour is mockable.
///
/// Shorebird already downloads and applies Dart-only patches silently on the
/// next launch (see `auto_update` in `shorebird.yaml`). This service exists
/// only to *observe* that state so the UI can nudge the user to reopen the app
/// when a patch has been staged. It is a no-op on builds where the updater is
/// unavailable (debug, web, or a build not made with `shorebird release`).
class PatchUpdateService {
  PatchUpdateService({ShorebirdUpdater? updater})
      : _updater = updater ?? ShorebirdUpdater();

  final ShorebirdUpdater _updater;

  /// Whether the Shorebird updater is active in this build. False in debug,
  /// on the web, and in plain `flutter build` (non-`shorebird release`) APKs.
  bool get isAvailable => _updater.isAvailable;

  /// The patch number currently running, or null if none/unavailable.
  Future<int?> currentPatchNumber() async {
    if (!isAvailable) return null;
    try {
      final patch = await _updater.readCurrentPatch();
      return patch?.number;
    } catch (e) {
      debugPrint('PatchUpdateService: readCurrentPatch error: $e');
      return null;
    }
  }

  /// Checks for a newer patch and, if one exists, downloads it in the
  /// background. Returns true when a patch is staged and a restart is required
  /// for it to take effect; false otherwise (already current, none available,
  /// updater unavailable, or the download failed).
  Future<bool> checkAndStageUpdate() async {
    if (!isAvailable) return false;
    try {
      final status = await _updater.checkForUpdate();
      // A patch was already staged on a previous check.
      if (status == UpdateStatus.restartRequired) return true;
      if (status == UpdateStatus.outdated) {
        await _updater.update();
        // After a successful update() the patch is staged for next launch.
        return true;
      }
      // upToDate or unavailable — nothing to do.
      return false;
    } on UpdateException catch (e) {
      debugPrint('PatchUpdateService: update failed: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('PatchUpdateService: checkAndStageUpdate error: $e');
      return false;
    }
  }
}
