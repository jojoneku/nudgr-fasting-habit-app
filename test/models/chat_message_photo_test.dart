import 'package:flutter_test/flutter_test.dart';

import 'package:intermittent_fasting/models/chat_message.dart';
import 'package:intermittent_fasting/models/estimation_source.dart';
import 'package:intermittent_fasting/models/food_entry.dart';
import 'package:intermittent_fasting/models/meal_slot.dart';

void main() {
  group('ChatMessage.photoThumbnailPath', () {
    ChatMessage build({String? thumb}) => ChatMessage(
          id: 'm1',
          rawText: 'Photo meal',
          timestamp: DateTime.parse('2026-06-04T12:00:00.000'),
          kind: ChatMessageKind.food,
          foodItems: const [
            ChatFoodItem(
              entryId: 'e1',
              name: 'Chicken adobo',
              calories: 320,
              grams: 180,
              estimationSource: EstimationSource.photoAi,
              confidence: 0.85,
            ),
          ],
          mealSlot: MealSlot.meal,
          photoThumbnailPath: thumb,
        );

    test('isPhoto reflects the thumbnail path', () {
      expect(build(thumb: 'food_photos/m1.jpg').isPhoto, isTrue);
      expect(build().isPhoto, isFalse);
    });

    test('round-trips through json when present', () {
      final json = build(thumb: 'food_photos/m1.jpg').toJson();
      expect(json['photoThumbnailPath'], 'food_photos/m1.jpg');
      final restored = ChatMessage.fromJson(json);
      expect(restored.photoThumbnailPath, 'food_photos/m1.jpg');
      expect(restored.isPhoto, isTrue);
      expect(
          restored.foodItems.single.estimationSource, EstimationSource.photoAi);
    });

    test('omits the key entirely when absent (text/exercise rows)', () {
      final json = build().toJson();
      expect(json.containsKey('photoThumbnailPath'), isFalse);
      expect(ChatMessage.fromJson(json).photoThumbnailPath, isNull);
    });

    test('copyWithFoodItems preserves the thumbnail path', () {
      final msg = build(thumb: 'food_photos/m1.jpg');
      final copy = msg.copyWithFoodItems(msg.foodItems);
      expect(copy.photoThumbnailPath, 'food_photos/m1.jpg');
    });
  });

  group('EstimationSource.photoAi', () {
    test('is an untrusted estimate with a Photo badge', () {
      expect(EstimationSource.photoAi.isTrusted, isFalse);
      expect(EstimationSource.photoAi.showBadge, isTrue);
      expect(EstimationSource.photoAi.badge, 'Photo');
    });

    test('round-trips through json', () {
      expect(EstimationSource.fromJson('photoAi'), EstimationSource.photoAi);
      expect(EstimationSource.photoAi.name, 'photoAi');
    });
  });

  group('FoodEntry with photoAi source', () {
    test('serialises and restores the photoAi source', () {
      final entry = FoodEntry(
        id: 'e1',
        name: 'Chicken adobo',
        calories: 320,
        grams: 180,
        estimationSource: EstimationSource.photoAi,
        confidence: 0.85,
        loggedAt: DateTime.parse('2026-06-04T12:00:00.000'),
      );
      final restored = FoodEntry.fromJson(entry.toJson());
      expect(restored.estimationSource, EstimationSource.photoAi);
      expect(restored.aiEstimated, isTrue);
    });
  });
}
