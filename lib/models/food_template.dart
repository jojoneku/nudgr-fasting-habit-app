import 'food_entry.dart';
import 'meal_slot.dart';

class FoodTemplate {
  final String id;
  final String name;
  final bool isMeal; // false = single food, true = multi-item meal
  final MealSlot? defaultSlot;
  final List<FoodEntry> entries;
  final int useCount;
  final bool isPinned;

  const FoodTemplate({
    required this.id,
    required this.name,
    required this.isMeal,
    this.defaultSlot,
    required this.entries,
    this.useCount = 0,
    this.isPinned = false,
  });

  int get totalCalories => entries.fold(0, (s, e) => s + e.calories);

  factory FoodTemplate.fromJson(Map<String, dynamic> json) => FoodTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        isMeal: json['isMeal'] as bool,
        defaultSlot: json['defaultSlot'] != null
            ? MealSlot.fromJson(json['defaultSlot'] as String)
            : null,
        entries: (json['entries'] as List<dynamic>)
            .map((e) => FoodEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        useCount: json['useCount'] as int? ?? 0,
        isPinned: json['isPinned'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isMeal': isMeal,
        'defaultSlot': defaultSlot?.jsonKey,
        'entries': entries.map((e) => e.toJson()).toList(),
        'useCount': useCount,
        'isPinned': isPinned,
      };

  FoodTemplate copyWith({
    String? name,
    bool? isMeal,
    MealSlot? defaultSlot,
    List<FoodEntry>? entries,
    int? useCount,
    bool? isPinned,
  }) =>
      FoodTemplate(
        id: id,
        name: name ?? this.name,
        isMeal: isMeal ?? this.isMeal,
        defaultSlot: defaultSlot ?? this.defaultSlot,
        entries: entries ?? this.entries,
        useCount: useCount ?? this.useCount,
        isPinned: isPinned ?? this.isPinned,
      );
}
