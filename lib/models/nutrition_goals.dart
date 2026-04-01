import 'meal_slot.dart';

class NutritionGoals {
  final TrackingMode mode;
  final int dailyCalories;       // used in simple mode; fallback in standard
  final double? proteinGrams;
  final double? carbsGrams;
  final double? fatGrams;
  final bool ifSyncEnabled;      // standard mode: lock logging during fast
  final bool overshootPenaltyEnabled;

  const NutritionGoals({
    this.mode = TrackingMode.simple,
    required this.dailyCalories,
    this.proteinGrams,
    this.carbsGrams,
    this.fatGrams,
    this.ifSyncEnabled = false,
    this.overshootPenaltyEnabled = false,
  });

  factory NutritionGoals.initial() =>
      const NutritionGoals(dailyCalories: 2000);

  factory NutritionGoals.fromJson(Map<String, dynamic> json) {
    final modeKey = json['mode'] as String? ?? 'simple';
    final mode = TrackingMode.fromJson(modeKey);
    // Migrate: old ifSync mode had implicit IF lock enabled
    final ifSyncEnabled = json['ifSyncEnabled'] as bool? ??
        (modeKey == 'ifSync');
    return NutritionGoals(
      mode: mode,
      dailyCalories: json['dailyCalories'] as int,
      proteinGrams: (json['proteinGrams'] as num?)?.toDouble(),
      carbsGrams: (json['carbsGrams'] as num?)?.toDouble(),
      fatGrams: (json['fatGrams'] as num?)?.toDouble(),
      ifSyncEnabled: ifSyncEnabled,
      overshootPenaltyEnabled:
          json['overshootPenaltyEnabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'dailyCalories': dailyCalories,
        'proteinGrams': proteinGrams,
        'carbsGrams': carbsGrams,
        'fatGrams': fatGrams,
        'ifSyncEnabled': ifSyncEnabled,
        'overshootPenaltyEnabled': overshootPenaltyEnabled,
      };

  NutritionGoals copyWith({
    TrackingMode? mode,
    int? dailyCalories,
    double? proteinGrams,
    double? carbsGrams,
    double? fatGrams,
    bool? ifSyncEnabled,
    bool? overshootPenaltyEnabled,
  }) =>
      NutritionGoals(
        mode: mode ?? this.mode,
        dailyCalories: dailyCalories ?? this.dailyCalories,
        proteinGrams: proteinGrams ?? this.proteinGrams,
        carbsGrams: carbsGrams ?? this.carbsGrams,
        fatGrams: fatGrams ?? this.fatGrams,
        ifSyncEnabled: ifSyncEnabled ?? this.ifSyncEnabled,
        overshootPenaltyEnabled:
            overshootPenaltyEnabled ?? this.overshootPenaltyEnabled,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NutritionGoals &&
          mode == other.mode &&
          dailyCalories == other.dailyCalories &&
          proteinGrams == other.proteinGrams &&
          carbsGrams == other.carbsGrams &&
          fatGrams == other.fatGrams &&
          ifSyncEnabled == other.ifSyncEnabled &&
          overshootPenaltyEnabled == other.overshootPenaltyEnabled;

  @override
  int get hashCode => Object.hash(mode, dailyCalories, proteinGrams, carbsGrams,
      fatGrams, ifSyncEnabled, overshootPenaltyEnabled);
}
