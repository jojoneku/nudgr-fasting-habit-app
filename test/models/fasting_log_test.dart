import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/fasting_log.dart';

void main() {
  group('FastingLog', () {
    late FastingLog log;

    setUp(() {
      log = FastingLog(
        fastStart: DateTime(2026, 3, 25, 8, 0),
        fastEnd: DateTime(2026, 3, 25, 24, 0),
        fastDuration: 16.0,
        success: true,
        eatingStart: DateTime(2026, 3, 26, 0, 0),
        eatingEnd: DateTime(2026, 3, 26, 8, 0),
        eatingDuration: 8.0,
        note: 'Felt great',
        goalDuration: 16,
      );
    });

    test('fromJson/toJson round-trip preserves all fields', () {
      final restored = FastingLog.fromJson(log.toJson());
      expect(restored.fastStart, log.fastStart);
      expect(restored.fastEnd, log.fastEnd);
      expect(restored.fastDuration, log.fastDuration);
      expect(restored.success, log.success);
      expect(restored.eatingStart, log.eatingStart);
      expect(restored.eatingEnd, log.eatingEnd);
      expect(restored.eatingDuration, log.eatingDuration);
      expect(restored.note, log.note);
      expect(restored.goalDuration, log.goalDuration);
    });

    test('fromJson handles null optional fields', () {
      final minLog = FastingLog(
        fastStart: DateTime(2026, 3, 25, 8, 0),
        fastEnd: DateTime(2026, 3, 25, 24, 0),
        fastDuration: 16.0,
        success: false,
        eatingStart: DateTime(2026, 3, 26, 0, 0),
      );
      final restored = FastingLog.fromJson(minLog.toJson());
      expect(restored.eatingEnd, isNull);
      expect(restored.eatingDuration, isNull);
      expect(restored.note, isNull);
    });

    test('goalDuration defaults to 16 when not provided', () {
      final logNoGoal = FastingLog(
        fastStart: DateTime(2026, 3, 25, 8, 0),
        fastEnd: DateTime(2026, 3, 25, 24, 0),
        fastDuration: 16.0,
        success: true,
        eatingStart: DateTime(2026, 3, 26, 0, 0),
      );
      expect(logNoGoal.goalDuration, 16);
    });

    test('equality holds after round-trip', () {
      final restored = FastingLog.fromJson(log.toJson());
      expect(restored, equals(log));
    });

    test('success=false stored and restored', () {
      final failLog = FastingLog(
        fastStart: DateTime(2026, 3, 25, 8, 0),
        fastEnd: DateTime(2026, 3, 25, 16, 0),
        fastDuration: 8.0,
        success: false,
        eatingStart: DateTime(2026, 3, 25, 16, 0),
        goalDuration: 16,
      );
      final restored = FastingLog.fromJson(failLog.toJson());
      expect(restored.success, false);
      expect(restored.fastDuration, 8.0);
    });
  });
}
