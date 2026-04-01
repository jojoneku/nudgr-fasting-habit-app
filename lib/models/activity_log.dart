import 'package:intl/intl.dart';

class ActivityLog {
  final String date; // 'yyyy-MM-dd'
  final int steps;
  final double? activeCalories;
  final double? distanceMeters;
  final bool isManualEntry;
  final bool goalMet;

  const ActivityLog({
    required this.date,
    required this.steps,
    this.activeCalories,
    this.distanceMeters,
    this.isManualEntry = false,
    this.goalMet = false,
  });

  factory ActivityLog.empty(String date) => ActivityLog(date: date, steps: 0);

  /// True if this log's date is yesterday (display helper, avoids logic in build()).
  bool get isYesterday {
    final yesterday = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().subtract(const Duration(days: 1)));
    return date == yesterday;
  }

  factory ActivityLog.fromJson(Map<String, dynamic> json) {
    return ActivityLog(
      date: json['date'] as String,
      steps: json['steps'] as int,
      activeCalories: (json['activeCalories'] as num?)?.toDouble(),
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
      isManualEntry: json['isManualEntry'] as bool? ?? false,
      goalMet: json['goalMet'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'steps': steps,
      'activeCalories': activeCalories,
      'distanceMeters': distanceMeters,
      'isManualEntry': isManualEntry,
      'goalMet': goalMet,
    };
  }

  ActivityLog copyWith({
    int? steps,
    double? activeCalories,
    double? distanceMeters,
    bool? isManualEntry,
    bool? goalMet,
  }) {
    return ActivityLog(
      date: date,
      steps: steps ?? this.steps,
      activeCalories: activeCalories ?? this.activeCalories,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      isManualEntry: isManualEntry ?? this.isManualEntry,
      goalMet: goalMet ?? this.goalMet,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityLog &&
          date == other.date &&
          steps == other.steps &&
          activeCalories == other.activeCalories &&
          distanceMeters == other.distanceMeters &&
          isManualEntry == other.isManualEntry;

  @override
  int get hashCode =>
      Object.hash(date, steps, activeCalories, distanceMeters, isManualEntry);
}
