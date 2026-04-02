import 'meal_slot.dart';

class TdeeProfile {
  final double weightKg;
  final double heightCm;
  final int ageYears;
  final String sex; // 'male' | 'female'
  final ActivityLevel activityLevel;
  final String goal; // 'cut' | 'maintain' | 'bulk'

  const TdeeProfile({
    required this.weightKg,
    required this.heightCm,
    required this.ageYears,
    required this.sex,
    required this.activityLevel,
    required this.goal,
  });

  // Mifflin-St Jeor formula
  int get bmr {
    final base = (10 * weightKg) + (6.25 * heightCm) - (5 * ageYears);
    return sex == 'male' ? (base + 5).round() : (base - 161).round();
  }

  int get tdee => (bmr * activityLevel.multiplier).round();

  int get targetCalories {
    switch (goal) {
      case 'cut':
        return tdee - 300;
      case 'bulk':
        return tdee + 250;
      case 'maintain':
      default:
        return tdee;
    }
  }

  // Suggested macros derived from goal + body weight
  // Protein: body-weight based (higher on cut to preserve muscle)
  // Fat: fixed % of target calories
  // Carbs: whatever is left
  int get suggestedProteinG {
    final multiplier = switch (goal) {
      'cut' => 2.2,
      'bulk' => 2.0,
      _ => 1.8, // maintain
    };
    return (weightKg * multiplier).round();
  }

  int get suggestedFatG {
    final pct = switch (goal) {
      'bulk' => 0.25,
      _ => 0.28, // cut / maintain
    };
    return (targetCalories * pct / 9).round();
  }

  int get suggestedCarbsG {
    final remaining =
        targetCalories - (suggestedProteinG * 4) - (suggestedFatG * 9);
    return (remaining / 4).round().clamp(0, 9999);
  }

  factory TdeeProfile.fromJson(Map<String, dynamic> json) => TdeeProfile(
        weightKg: (json['weightKg'] as num).toDouble(),
        heightCm: (json['heightCm'] as num).toDouble(),
        ageYears: json['ageYears'] as int,
        sex: json['sex'] as String,
        activityLevel: ActivityLevel.fromJson(json['activityLevel'] as String),
        goal: json['goal'] as String,
      );

  Map<String, dynamic> toJson() => {
        'weightKg': weightKg,
        'heightCm': heightCm,
        'ageYears': ageYears,
        'sex': sex,
        'activityLevel': activityLevel.name,
        'goal': goal,
      };

  TdeeProfile copyWith({
    double? weightKg,
    double? heightCm,
    int? ageYears,
    String? sex,
    ActivityLevel? activityLevel,
    String? goal,
  }) =>
      TdeeProfile(
        weightKg: weightKg ?? this.weightKg,
        heightCm: heightCm ?? this.heightCm,
        ageYears: ageYears ?? this.ageYears,
        sex: sex ?? this.sex,
        activityLevel: activityLevel ?? this.activityLevel,
        goal: goal ?? this.goal,
      );
}
