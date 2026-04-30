import 'dart:math';

import 'estimation_source.dart';
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
  final String? amountText; // original user input e.g. "100g rice"
  final EstimationSource estimationSource;
  final double? confidence;

  const ChatFoodItem({
    required this.entryId,
    required this.name,
    required this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.grams,
    this.amountText,
    this.estimationSource = EstimationSource.db,
    this.confidence,
  });

  bool get isEstimated => !estimationSource.isTrusted;

  /// True when confidence is low, regardless of source. Covers AI estimates,
  /// keyword density fallbacks, and weak DB matches (e.g. "egg noodles"
  /// resolved against "Scrambled Eggs with Noodles" because the DB lacks an
  /// exact entry). UI uses this to flag items the user should review.
  bool get needsConfirmation => (confidence ?? 1.0) < 0.6;

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
        estimationSource: e.estimationSource,
        confidence: e.confidence,
      );

  factory ChatFoodItem.fromJson(Map<String, dynamic> json) {
    final legacyEstimated = json['isEstimated'] as bool? ?? false;
    return ChatFoodItem(
      entryId: json['entryId'] as String,
      name: json['name'] as String,
      calories: json['calories'] as int,
      protein: (json['protein'] as num?)?.toDouble(),
      carbs: (json['carbs'] as num?)?.toDouble(),
      fat: (json['fat'] as num?)?.toDouble(),
      grams: (json['grams'] as num?)?.toDouble(),
      amountText: json['amountText'] as String?,
      estimationSource: json['estimationSource'] != null
          ? EstimationSource.fromJson(json['estimationSource'] as String?)
          : (legacyEstimated
              ? EstimationSource.aiPerItem
              : EstimationSource.db),
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'name': name,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'grams': grams,
        'amountText': amountText,
        'estimationSource': estimationSource.name,
        'isEstimated': isEstimated, // keep for backward compat
        'confidence': confidence,
      };

  ChatFoodItem copyWith({
    String? name,
    int? calories,
    double? protein,
    double? carbs,
    double? fat,
    double? grams,
    String? amountText,
    EstimationSource? estimationSource,
    double? confidence,
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
        estimationSource: estimationSource ?? this.estimationSource,
        confidence: confidence ?? this.confidence,
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
