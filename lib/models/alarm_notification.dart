import 'dart:convert';

/// A full-screen, alarm-style notification: the kind that is allowed to wake
/// the screen and draw over the lock screen.
///
/// Only these notifications route to the alarm screen. Everything else opens
/// the app normally, behind the keyguard, so the Hub (and the finance figures
/// on it) is never rendered on a locked device.
class AlarmNotification {
  const AlarmNotification({
    this.questId,
    required this.title,
    required this.body,
  });

  /// Quest this alarm belongs to, or null for a fasting/eating milestone.
  final int? questId;
  final String title;
  final String body;

  /// Payload key flagging a notification as alarm-style. Read from Dart and
  /// from `MainActivity.kt`, which needs the same answer before Flutter starts.
  static const String payloadFlag = 'alarm';

  /// Parses a notification payload into an alarm, or returns null when the
  /// payload is absent, not JSON, or not flagged alarm-style.
  static AlarmNotification? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return null; // non-JSON payload (e.g. the OTA install path)
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded[payloadFlag] != true) return null;
    final id = decoded['id'];
    return AlarmNotification(
      questId: id is int ? id : null,
      title: decoded['title'] as String? ?? 'Reminder',
      body: decoded['body'] as String? ?? '',
    );
  }
}
