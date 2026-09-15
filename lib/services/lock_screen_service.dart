import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls whether the app's activity may draw over the Android lock screen.
///
/// This used to be a manifest-wide `android:showWhenLocked="true"`, which meant
/// *any* screen — the Hub, with its balances on it — could end up rendered on a
/// locked phone. Now `MainActivity` turns the flags on only for a launch that
/// carries an alarm payload, and [release] turns them back off the moment the
/// alarm screen is dismissed, so the rest of the app stays behind the keyguard.
class LockScreenService {
  LockScreenService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.nudgr.app/lockscreen';

  final MethodChannel _channel;

  /// Lets the activity wake the screen and draw over the keyguard.
  ///
  /// `MainActivity` already does this in `onCreate` for a launch carrying an
  /// alarm payload, which is the path that avoids a lock-screen flash. This is
  /// the backstop for when that native check misses — it depends on an intent
  /// extra key owned by `flutter_local_notifications` — so the alarm still
  /// shows, just a beat later.
  Future<void> acquire() => _invoke('acquire');

  /// Drops the show-when-locked / turn-screen-on flags. Safe to call when they
  /// were never set.
  Future<void> release() => _invoke('release');

  /// Whether the activity is currently allowed over the keyguard — i.e. it was
  /// launched by an alarm. The alarm screen uses this to decide whether
  /// dismissing should hand the user back to the lock screen or to the app.
  Future<bool> isShowingOverLockScreen() async {
    final result = await _invoke('isShowingOverLockScreen');
    return result == true;
  }

  Future<Object?> _invoke(String method) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<Object?>(method);
    } on PlatformException catch (e) {
      debugPrint('LockScreenService: $method failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null; // host without the channel (tests, older build)
    }
  }
}
