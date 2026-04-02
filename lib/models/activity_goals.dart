class ActivityGoals {
  final int dailyStepGoal;
  final double dailyDistanceGoalMeters; // 0 = no goal

  const ActivityGoals({
    required this.dailyStepGoal,
    this.dailyDistanceGoalMeters = 0.0,
  });

  factory ActivityGoals.initial() => const ActivityGoals(
        dailyStepGoal: 8000,
        dailyDistanceGoalMeters: 5000.0,
      );

  factory ActivityGoals.fromJson(Map<String, dynamic> json) {
    return ActivityGoals(
      dailyStepGoal: json['dailyStepGoal'] as int? ?? 8000,
      dailyDistanceGoalMeters:
          (json['dailyDistanceGoalMeters'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'dailyStepGoal': dailyStepGoal,
        'dailyDistanceGoalMeters': dailyDistanceGoalMeters,
      };

  ActivityGoals copyWith(
      {int? dailyStepGoal, double? dailyDistanceGoalMeters}) {
    return ActivityGoals(
      dailyStepGoal: dailyStepGoal ?? this.dailyStepGoal,
      dailyDistanceGoalMeters:
          dailyDistanceGoalMeters ?? this.dailyDistanceGoalMeters,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityGoals && dailyStepGoal == other.dailyStepGoal;

  @override
  int get hashCode => dailyStepGoal.hashCode;
}
