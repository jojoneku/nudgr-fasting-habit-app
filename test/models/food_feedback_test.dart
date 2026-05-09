import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/food_feedback.dart';

void main() {
  group('FoodFeedback', () {
    test('round-trips through JSON', () {
      final original = FoodFeedback(
        id: 'fb1',
        timestamp: DateTime.utc(2026, 5, 9, 14, 30),
        kind: FoodFeedbackKind.userDislike,
        userQuery: 'Red Rice 50g',
        pickedName: 'Sapin-Sapin (Layered Rice Cake)',
        pickedDbId: '27063',
        estimationSource: 'db',
        confidence: 0.65,
        swappedToName: null,
      );

      final restored = FoodFeedback.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.timestamp, original.timestamp);
      expect(restored.kind, FoodFeedbackKind.userDislike);
      expect(restored.userQuery, original.userQuery);
      expect(restored.pickedName, original.pickedName);
      expect(restored.pickedDbId, original.pickedDbId);
      expect(restored.estimationSource, original.estimationSource);
      expect(restored.confidence, original.confidence);
    });

    test('preserves swap target', () {
      final original = FoodFeedback(
        id: 'fb2',
        timestamp: DateTime.utc(2026, 5, 9),
        kind: FoodFeedbackKind.swap,
        userQuery: 'red rice',
        pickedName: 'Sapin-Sapin',
        estimationSource: 'db',
        swappedToName: 'Red Rice, Cooked',
      );
      final restored = FoodFeedback.fromJson(original.toJson());
      expect(restored.kind, FoodFeedbackKind.swap);
      expect(restored.swappedToName, 'Red Rice, Cooked');
    });

    test('falls back to fallbackMiss for unknown kind in legacy JSON', () {
      final json = {
        'id': 'fb3',
        'timestamp': '2026-05-09T00:00:00.000Z',
        'kind': 'someFutureKind',
        'userQuery': 'q',
        'pickedName': 'p',
        'estimationSource': 'db',
      };
      expect(FoodFeedback.fromJson(json).kind, FoodFeedbackKind.fallbackMiss);
    });

    test('generateId produces unique-ish ids', () {
      final ids = {for (var i = 0; i < 100; i++) FoodFeedback.generateId()};
      expect(ids.length, greaterThan(95));
    });
  });
}
