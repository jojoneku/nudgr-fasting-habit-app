import 'meal_slot.dart';

class NutritionGoals {
  final TrackingMode mode;
  final int dailyCalories;
  final double? proteinGrams;
  final double? carbsGrams;
  final double? fatGrams;
  final bool overshootPenaltyEnabled; // default false — opt-in

  const NutritionGoals({
    this.mode = TrackingMode.simple,
    required this.dailyCalories,
    this.proteinGrams,
    this.carbsGrams,
    this.fatGrams,
    this.overshootPenaltyEnabled = false,
  });

  factory NutritionGoals.initial() =>
      const NutritionGoals(dailyCalories: 2000);

  factory NutritionGoals.fromJson(Map<String, dynamic> json) => NutritionGoals(
        mode: TrackingMode.fromJson(json['mode'] as String? ?? 'simple'),
        dailyCalories: json['dailyCalories'] as int,
        proteinGrams: (json['proteinGrams'] as num?)?.toDouble(),
        carbsGrams: (json['carbsGrams'] as num?)?.toDouble(),
        fatGrams: (json['fatGrams'] as num?)?.toDouble(),
        overshootPenaltyEnabled:
            json['overshootPenaltyEnabled'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'dailyCalories': dailyCalories,
        'proteinGrams': proteinGrams,
        'carbsGrams': carbsGrams,
        'fatGrams': fatGrams,
        'overshootPenaltyEnabled': overshootPenaltyEnabled,
      };

  NutritionGoals copyWith({
    TrackingMode? mode,
    int? dailyCalories,
    double? proteinGrams,
    double? carbsGrams,
    double? fatGrams,
    bool? overshootPenaltyEnabled,
  }) =>
      NutritionGoals(
        mode: mode ?? this.mode,
        dailyCalories: dailyCalories ?? this.dailyCalories,
        proteinGrams: proteinGrams ?? this.proteinGrams,
        carbsGrams: carbsGrams ?? this.carbsGrams,
        fatGrams: fatGrams ?? this.fatGrams,
        overshootPenaltyEnabled:
            overshootPenaltyEnabled ?? this.overshootPenaltyEnabled,
      );
}
