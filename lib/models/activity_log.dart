class ActivityLog {
  final String date; // 'yyyy-MM-dd'
  final int steps;
  final double? activeCalories;
  final double? distanceMeters;
  final bool isManualEntry;

  const ActivityLog({
    required this.date,
    required this.steps,
    this.activeCalories,
    this.distanceMeters,
    this.isManualEntry = false,
  });

  factory ActivityLog.empty(String date) => ActivityLog(date: date, steps: 0);

  factory ActivityLog.fromJson(Map<String, dynamic> json) {
    return ActivityLog(
      date: json['date'] as String,
      steps: json['steps'] as int,
      activeCalories: (json['activeCalories'] as num?)?.toDouble(),
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
      isManualEntry: json['isManualEntry'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'steps': steps,
      'activeCalories': activeCalories,
      'distanceMeters': distanceMeters,
      'isManualEntry': isManualEntry,
    };
  }

  ActivityLog copyWith({
    int? steps,
    double? activeCalories,
    double? distanceMeters,
    bool? isManualEntry,
  }) {
    return ActivityLog(
      date: date,
      steps: steps ?? this.steps,
      activeCalories: activeCalories ?? this.activeCalories,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      isManualEntry: isManualEntry ?? this.isManualEntry,
    );
  }
}
