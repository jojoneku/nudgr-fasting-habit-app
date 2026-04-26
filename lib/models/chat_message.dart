import 'dart:math';

import 'exercise_entry.dart';
import 'food_entry.dart';
import 'meal_slot.dart';

enum ChatMessageKind { food, exercise }

/// A snapshot of one food item as it appears in the chat feed.
/// Stores its own copy of nutritional data so edits don't require a join.
class ChatFoodItem {
  final String entryId; // mirrors the FoodEntry.id in DailyNutritionLog
  final String name;
  final int calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? grams;
  final String? amountText; // original user input e.g. "100g rice", "2 jumbo hotdog"
  final bool isEstimated;

  const ChatFoodItem({
    required this.entryId,
    required this.name,
    required this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.grams,
    this.amountText,
    this.isEstimated = false,
  });

  factory ChatFoodItem.fromFoodEntry(FoodEntry e, {String? amountText}) =>
      ChatFoodItem(
        entryId: e.id,
        name: e.name,
        calories: e.calories,
        protein: e.protein,
        carbs: e.carbs,
        fat: e.fat,
        grams: e.grams,
        amountText: amountText,
        isEstimated: e.aiEstimated,
      );

  factory ChatFoodItem.fromJson(Map<String, dynamic> json) => ChatFoodItem(
        entryId: json['entryId'] as String,
        name: json['name'] as String,
        calories: json['calories'] as int,
        protein: (json['protein'] as num?)?.toDouble(),
        carbs: (json['carbs'] as num?)?.toDouble(),
        fat: (json['fat'] as num?)?.toDouble(),
        grams: (json['grams'] as num?)?.toDouble(),
        amountText: json['amountText'] as String?,
        isEstimated: json['isEstimated'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'name': name,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'grams': grams,
        'amountText': amountText,
        'isEstimated': isEstimated,
      };

  ChatFoodItem copyWith({
    String? name,
    int? calories,
    double? protein,
    double? carbs,
    double? fat,
    double? grams,
    String? amountText,
    bool? isEstimated,
  }) =>
      ChatFoodItem(
        entryId: entryId,
        name: name ?? this.name,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
        grams: grams ?? this.grams,
        amountText: amountText ?? this.amountText,
        isEstimated: isEstimated ?? this.isEstimated,
      );
}

/// One user submission in the chat feed — either a food log or an exercise log.
class ChatMessage {
  final String id;
  final String rawText;
  final DateTime timestamp;
  final ChatMessageKind kind;

  // food
  final List<ChatFoodItem> foodItems;
  final MealSlot mealSlot;

  // exercise
  final ExerciseEntry? exerciseEntry;

  const ChatMessage({
    required this.id,
    required this.rawText,
    required this.timestamp,
    required this.kind,
    this.foodItems = const [],
    this.mealSlot = MealSlot.meal,
    this.exerciseEntry,
  });

  static String generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] == 'exercise'
        ? ChatMessageKind.exercise
        : ChatMessageKind.food;
    return ChatMessage(
      id: json['id'] as String,
      rawText: json['rawText'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      kind: kind,
      foodItems: kind == ChatMessageKind.food
          ? (json['foodItems'] as List? ?? [])
              .map((e) => ChatFoodItem.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      mealSlot:
          MealSlot.fromJson((json['mealSlot'] as String?) ?? MealSlot.meal.name),
      exerciseEntry: json['exerciseEntry'] != null
          ? ExerciseEntry.fromJson(
              json['exerciseEntry'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'rawText': rawText,
        'timestamp': timestamp.toIso8601String(),
        'kind': kind.name,
        'foodItems': foodItems.map((f) => f.toJson()).toList(),
        'mealSlot': mealSlot.jsonKey,
        'exerciseEntry': exerciseEntry?.toJson(),
      };

  ChatMessage copyWithFoodItems(List<ChatFoodItem> items) => ChatMessage(
        id: id,
        rawText: rawText,
        timestamp: timestamp,
        kind: kind,
        foodItems: items,
        mealSlot: mealSlot,
        exerciseEntry: exerciseEntry,
      );
}
