enum MealSlot {
  breakfast,
  lunch,
  dinner,
  snack,
  meal; // universal slot — all new entries go here

  String get label {
    switch (this) {
      case MealSlot.breakfast:
        return 'Breakfast';
      case MealSlot.lunch:
        return 'Lunch';
      case MealSlot.dinner:
        return 'Dinner';
      case MealSlot.snack:
        return 'Snacks';
      case MealSlot.meal:
        return 'Meals';
    }
  }

  String get jsonKey => name;

  static MealSlot fromJson(String key) => MealSlot.values
      .firstWhere((s) => s.jsonKey == key, orElse: () => MealSlot.meal);
}

enum TrackingMode {
  simple,
  standard;

  String get label {
    switch (this) {
      case TrackingMode.simple:
        return 'Simple';
      case TrackingMode.standard:
        return 'Standard';
    }
  }

  static TrackingMode fromJson(String key) {
    // Migrate old modes → standard
    if (key == 'macro' || key == 'ifSync' || key == 'tdee') {
      return TrackingMode.standard;
    }
    return TrackingMode.values
        .firstWhere((m) => m.name == key, orElse: () => TrackingMode.simple);
  }
}

enum ActivityLevel {
  sedentary,
  lightlyActive,
  moderatelyActive,
  veryActive;

  String get label {
    switch (this) {
      case ActivityLevel.sedentary:
        return 'Sedentary';
      case ActivityLevel.lightlyActive:
        return 'Lightly Active';
      case ActivityLevel.moderatelyActive:
        return 'Moderately Active';
      case ActivityLevel.veryActive:
        return 'Very Active';
    }
  }

  double get multiplier {
    switch (this) {
      case ActivityLevel.sedentary:
        return 1.2;
      case ActivityLevel.lightlyActive:
        return 1.375;
      case ActivityLevel.moderatelyActive:
        return 1.55;
      case ActivityLevel.veryActive:
        return 1.725;
    }
  }

  static ActivityLevel fromJson(String key) => ActivityLevel.values
      .firstWhere((a) => a.name == key, orElse: () => ActivityLevel.sedentary);
}
