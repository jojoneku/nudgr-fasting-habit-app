import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/alarm_notification.dart';

void main() {
  group('AlarmNotification.fromPayload', () {
    test('parses a quest alarm payload', () {
      final payload = jsonEncode({
        'id': 7,
        'title': 'Take meds',
        'body': "It's time for your quest!",
        'alarm': true,
      });
      final alarm = AlarmNotification.fromPayload(payload);
      expect(alarm, isNotNull);
      expect(alarm!.questId, 7);
      expect(alarm.title, 'Take meds');
      expect(alarm.body, "It's time for your quest!");
    });

    test('parses a milestone alarm with no quest id', () {
      final payload = jsonEncode({
        'title': 'You did it! 🏆',
        'body': 'Fasting goal reached.',
        'alarm': true,
      });
      final alarm = AlarmNotification.fromPayload(payload);
      expect(alarm, isNotNull);
      expect(alarm!.questId, isNull);
      expect(alarm.title, 'You did it! 🏆');
    });

    // The whole point of the flag: a reminder without it must open the app
    // normally, behind the keyguard, instead of drawing over the lock screen.
    test('rejects a quest payload that is not flagged alarm-style', () {
      final payload = jsonEncode({'id': 7, 'title': 'Stretch'});
      expect(AlarmNotification.fromPayload(payload), isNull);
    });

    test('rejects an explicitly false flag', () {
      final payload = jsonEncode({'id': 7, 'title': 'Stretch', 'alarm': false});
      expect(AlarmNotification.fromPayload(payload), isNull);
    });

    test('rejects a non-boolean flag rather than coercing it', () {
      final payload = jsonEncode({'id': 7, 'title': 'x', 'alarm': 'true'});
      expect(AlarmNotification.fromPayload(payload), isNull);
    });

    test('survives payloads that are not JSON', () {
      // The OTA "update ready" notification carries a bare file path.
      expect(AlarmNotification.fromPayload('installapk:/data/app.apk'), isNull);
      expect(AlarmNotification.fromPayload('[1,2,3]'), isNull);
      expect(AlarmNotification.fromPayload(''), isNull);
      expect(AlarmNotification.fromPayload(null), isNull);
    });

    test('falls back rather than throwing on a malformed alarm payload', () {
      final alarm =
          AlarmNotification.fromPayload(jsonEncode({'alarm': true, 'id': 'x'}));
      expect(alarm, isNotNull);
      expect(alarm!.questId, isNull, reason: 'non-int id must not be cast');
      expect(alarm.title, 'Reminder');
      expect(alarm.body, isEmpty);
    });
  });
}
