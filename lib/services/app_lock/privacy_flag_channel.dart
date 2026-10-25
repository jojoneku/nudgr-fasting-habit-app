import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../lock_screen_service.dart';

/// Hides the app's preview in the Android recent-apps screen while the app
/// lock is on (API 33+ `setRecentsScreenshotEnabled(false)`).
///
/// Deliberately not `FLAG_SECURE`: that would also block screenshots and screen
/// recording of the user's own data. Rides the existing lock-screen channel in
/// `MainActivity`. A no-op on web, on older Android, and in tests.
class PrivacyFlagChannel {
  PrivacyFlagChannel({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel(LockScreenService.channelName);

  final MethodChannel _channel;

  Future<void> setRecentsPrivacy(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('setRecentsPrivacy', enabled);
    } on PlatformException catch (e) {
      debugPrint('PrivacyFlagChannel: setRecentsPrivacy failed: ${e.message}');
    } on MissingPluginException {
      // host without the channel (tests, older build)
    }
  }
}
