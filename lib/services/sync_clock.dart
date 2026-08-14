import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks how far this device's clock sits from the server's, so edit times
/// from different devices can be compared on a common scale.
///
/// Last-write-wins needs to order *edits*, and an edit time can only ever be
/// measured on the device that made it — the edit may happen offline, hours
/// before any server sees it. So no server-side trigger can normalise it; the
/// device has to. A browser running four minutes fast would otherwise stamp its
/// edits four minutes into the future and out-rank a phone's genuinely newer
/// ones, which is exactly how a corrected balance reverts.
///
/// The offset is learned for free from a push: the server stamps `updated_at`
/// with its own `now()` and returns it, and the gap between that and this
/// device's clock at request time is the offset. See
/// `docs/sync_conflict_resolution_spec.md` Phase 5.
class SyncClock {
  static const String _prefsPrefix = 'u/';
  static const String _prefsSuffix = '/sync_clock_offset_ms';

  /// Offsets beyond this are treated as garbage rather than skew — a wildly
  /// wrong reading (a device booted with no RTC, a proxy serving a cached
  /// response) must not be allowed to reorder every future edit.
  static const Duration maxPlausibleOffset = Duration(days: 2);

  final String _userId;
  Duration _offset = Duration.zero;

  SyncClock(this._userId);

  /// server ≈ device + [offset].
  Duration get offset => _offset;

  String get _key => '$_prefsPrefix$_userId$_prefsSuffix';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_key);
    if (ms != null) _offset = Duration(milliseconds: ms);
  }

  /// Converts a device-clock instant into the server's frame — used when
  /// writing `client_edited_at`, so every device's edit times are comparable.
  DateTime toServerFrame(DateTime deviceTime) =>
      deviceTime.toUtc().add(_offset);

  /// Converts a server-frame instant back into this device's frame, for
  /// comparison against the queue's (device-frame) watermarks.
  DateTime toDeviceFrame(DateTime serverTime) =>
      serverTime.toUtc().subtract(_offset);

  /// Records a server timestamp observed at [deviceNow], updating the offset.
  ///
  /// [serverTime] is read from a row the server just stamped. Network latency
  /// biases this by up to one round trip, which is irrelevant next to the
  /// minutes-to-hours skew it exists to correct.
  Future<void> observeServerTime(
      DateTime serverTime, DateTime deviceNow) async {
    final observed = serverTime.toUtc().difference(deviceNow.toUtc());
    if (observed.abs() > maxPlausibleOffset) {
      debugPrint(
          'SyncClock: ignoring implausible offset ${observed.inSeconds}s');
      return;
    }
    if ((observed - _offset).abs() < const Duration(seconds: 1)) return;
    _offset = observed;
    debugPrint('SyncClock: server clock offset now ${observed.inSeconds}s');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, observed.inMilliseconds);
  }

  @visibleForTesting
  void setOffsetForTest(Duration offset) => _offset = offset;
}
