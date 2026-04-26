import 'dart:math';

class ExerciseEntry {
  final String id;
  final String name;
  final String rawText;
  final double? distanceKm;
  final int? durationMinutes;
  final int caloriesBurned;
  final bool isEstimated;
  final DateTime loggedAt;

  const ExerciseEntry({
    required this.id,
    required this.name,
    required this.rawText,
    this.distanceKm,
    this.durationMinutes,
    required this.caloriesBurned,
    this.isEstimated = true,
    required this.loggedAt,
  });

  static String generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  factory ExerciseEntry.fromJson(Map<String, dynamic> json) => ExerciseEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        rawText: json['rawText'] as String,
        distanceKm: (json['distanceKm'] as num?)?.toDouble(),
        durationMinutes: json['durationMinutes'] as int?,
        caloriesBurned: json['caloriesBurned'] as int,
        isEstimated: json['isEstimated'] as bool? ?? true,
        loggedAt: DateTime.parse(json['loggedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rawText': rawText,
        'distanceKm': distanceKm,
        'durationMinutes': durationMinutes,
        'caloriesBurned': caloriesBurned,
        'isEstimated': isEstimated,
        'loggedAt': loggedAt.toIso8601String(),
      };

  /// Short human-readable summary, e.g. "3.0 km · 36 min".
  String get statsLabel {
    final parts = <String>[];
    if (distanceKm != null) {
      parts.add('${distanceKm!.toStringAsFixed(1)} km');
    }
    if (durationMinutes != null) {
      parts.add('$durationMinutes min');
    }
    return parts.join(' · ');
  }
}
