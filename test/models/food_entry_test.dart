import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/estimation_source.dart';
import 'package:intermittent_fasting/models/food_entry.dart';

void main() {
  group('FoodEntry', () {
    late FoodEntry entry;

    setUp(() {
      entry = FoodEntry(
        id: 'test-id',
        name: 'Chicken Breast',
        calories: 165,
        protein: 31.0,
        carbs: 0.0,
        fat: 3.6,
        grams: 100.0,
        estimationSource: EstimationSource.db,
        loggedAt: DateTime(2026, 3, 25, 12, 0),
      );
    });

    test('fromJson/toJson round-trip preserves estimationSource', () {
      final restored = FoodEntry.fromJson(entry.toJson());
      expect(restored.id, entry.id);
      expect(restored.name, entry.name);
      expect(restored.calories, entry.calories);
      expect(restored.protein, entry.protein);
      expect(restored.estimationSource, EstimationSource.db);
      expect(restored.aiEstimated, false);
    });

    test('fromJson handles missing optional macros', () {
      final json = {
        'id': 'x',
        'name': 'Test',
        'calories': 100,
        'loggedAt': DateTime.now().toIso8601String()
      };
      final e = FoodEntry.fromJson(json);
      expect(e.protein, isNull);
      expect(e.carbs, isNull);
      expect(e.fat, isNull);
      expect(e.estimationSource, EstimationSource.db);
      expect(e.aiEstimated, false);
    });

    test('legacy aiEstimated:true maps to aiPerItem source', () {
      final json = {
        'id': 'x',
        'name': 'Test',
        'calories': 100,
        'aiEstimated': true,
        'loggedAt': DateTime.now().toIso8601String()
      };
      final e = FoodEntry.fromJson(json);
      expect(e.estimationSource, EstimationSource.aiPerItem);
      expect(e.aiEstimated, true);
    });

    test('copyWith preserves id and loggedAt', () {
      final updated = entry.copyWith(calories: 200, name: 'Updated');
      expect(updated.id, entry.id);
      expect(updated.loggedAt, entry.loggedAt);
      expect(updated.calories, 200);
      expect(updated.name, 'Updated');
    });

    test('generateId produces unique values', () {
      final ids = List.generate(10, (_) => FoodEntry.generateId());
      expect(ids.toSet().length, ids.length);
    });

    test('needsConfirmation is true for low-confidence AI estimates', () {
      final aiEntry = FoodEntry(
        id: 'ai-1',
        name: 'longganisa',
        calories: 370,
        grams: 100,
        estimationSource: EstimationSource.aiPerItem,
        confidence: 0.4,
        loggedAt: DateTime.now(),
      );
      expect(aiEntry.needsConfirmation, true);
    });

    test('needsConfirmation is false for DB entries', () {
      expect(entry.needsConfirmation, false);
    });
  });
}
