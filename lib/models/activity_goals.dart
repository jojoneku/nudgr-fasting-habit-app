class ActivityGoals {
  final int dailyStepGoal;

  const ActivityGoals({required this.dailyStepGoal});

  factory ActivityGoals.initial() => const ActivityGoals(dailyStepGoal: 8000);

  factory ActivityGoals.fromJson(Map<String, dynamic> json) {
    return ActivityGoals(
      dailyStepGoal: json['dailyStepGoal'] as int? ?? 8000,
    );
  }

  Map<String, dynamic> toJson() => {'dailyStepGoal': dailyStepGoal};

  ActivityGoals copyWith({int? dailyStepGoal}) {
    return ActivityGoals(dailyStepGoal: dailyStepGoal ?? this.dailyStepGoal);
  }
}
