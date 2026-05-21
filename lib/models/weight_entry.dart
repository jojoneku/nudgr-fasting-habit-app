class WeightEntry {
  final String id;
  final double weightKg;
  final DateTime loggedAt;

  const WeightEntry({
    required this.id,
    required this.weightKg,
    required this.loggedAt,
  });

  static String generateId() =>
      DateTime.now().millisecondsSinceEpoch.toString();

  factory WeightEntry.fromJson(Map<String, dynamic> json) => WeightEntry(
        id: json['id'] as String,
        weightKg: (json['weightKg'] as num).toDouble(),
        loggedAt: DateTime.parse(json['loggedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'weightKg': weightKg,
        'loggedAt': loggedAt.toIso8601String(),
      };
}
