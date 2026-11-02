import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/finance/raw_capture.dart';

/// Dart side of the Android notification listener.
///
/// The native `TransactionNotificationListener` filters and queues; this
/// service drains. It exists as an interface so the presenter never checks the
/// platform: web and iOS get [NullCaptureBridge], which answers "no access,
/// nothing queued" and never throws.
abstract class CaptureBridgeService {
  /// Whether this platform can capture notifications at all.
  bool get isSupported;

  /// True when the user has granted notification access to the app.
  Future<bool> isAccessGranted();

  /// Opens the system *Notification access* page.
  Future<void> openAccessSettings();

  /// Asks the system to reconnect the listener (after a battery kill).
  Future<void> requestRebind();

  /// Tells the listener which packages to keep. Everything else is dropped
  /// inside `onNotificationPosted`, before anything is stored. A package in
  /// [titleFilters] is kept only when its title contains one of the words
  /// (Gmail: the sender name), so personal mail never enters the queue.
  Future<void> setAllowlist(
    Set<String> packages, {
    Map<String, List<String>> titleFilters = const {},
  });

  /// Returns the queued captures and clears the queue in one step.
  Future<List<RawCapture>> drainRaw();

  /// Puts captures back when persisting them failed, so nothing is lost.
  Future<void> requeue(List<RawCapture> captures);

  /// Apps seen posting in the last 7 days (label and package only).
  Future<List<RecentApp>> recentApps();

  /// When the listener last connected to the system; null if never.
  Future<DateTime?> lastConnectedAt();
}

/// Android implementation over the `com.nudgr.app/capture` channel.
class MethodChannelCaptureBridge implements CaptureBridgeService {
  static const MethodChannel _channel = MethodChannel('com.nudgr.app/capture');

  const MethodChannelCaptureBridge();

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<T?> _call<T>(String method, [Object? args]) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('CaptureBridge.$method failed: ${e.code} ${e.message}');
      return null;
    }
  }

  @override
  Future<bool> isAccessGranted() async =>
      await _call<bool>('isAccessGranted') ?? false;

  @override
  Future<void> openAccessSettings() => _call<void>('openAccessSettings');

  @override
  Future<void> requestRebind() => _call<void>('requestRebind');

  @override
  Future<void> setAllowlist(
    Set<String> packages, {
    Map<String, List<String>> titleFilters = const {},
  }) =>
      _call<void>('setAllowlist', {
        'packages': packages.toList(),
        'titleFilters': {
          for (final e in titleFilters.entries)
            if (packages.contains(e.key) && e.value.isNotEmpty) e.key: e.value,
        },
      });

  @override
  Future<List<RawCapture>> drainRaw() async {
    final raw = await _call<List<Object?>>('drainRaw');
    if (raw == null) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(RawCapture.fromMap)
        .where((c) => c.packageName.isNotEmpty && c.text.isNotEmpty)
        .toList();
  }

  @override
  Future<void> requeue(List<RawCapture> captures) =>
      _call<void>('requeue', captures.map((c) => c.toMap()).toList());

  @override
  Future<List<RecentApp>> recentApps() async {
    final raw = await _call<List<Object?>>('recentApps');
    if (raw == null) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(RecentApp.fromMap)
        .where((a) => a.packageName.isNotEmpty)
        .toList();
  }

  @override
  Future<DateTime?> lastConnectedAt() async {
    final ms = await _call<int>('lastConnectedAt');
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

/// Web, iOS and tests: capture is not available, nothing is queued.
class NullCaptureBridge implements CaptureBridgeService {
  const NullCaptureBridge();

  @override
  bool get isSupported => false;
  @override
  Future<bool> isAccessGranted() async => false;
  @override
  Future<void> openAccessSettings() async {}
  @override
  Future<void> requestRebind() async {}
  @override
  Future<void> setAllowlist(
    Set<String> packages, {
    Map<String, List<String>> titleFilters = const {},
  }) async {}
  @override
  Future<List<RawCapture>> drainRaw() async => const [];
  @override
  Future<void> requeue(List<RawCapture> captures) async {}
  @override
  Future<List<RecentApp>> recentApps() async => const [];
  @override
  Future<DateTime?> lastConnectedAt() async => null;
}
