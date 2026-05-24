class BodyMeasurementEntry {
  final String id;
  final DateTime loggedAt;
  final double? waistCm;
  final double? neckCm;
  final double? hipsCm;
  final double? chestCm;
  final double? bicepCm;
  final double? thighCm;
  final String? notes;

  const BodyMeasurementEntry({
    required this.id,
    required this.loggedAt,
    this.waistCm,
    this.neckCm,
    this.hipsCm,
    this.chestCm,
    this.bicepCm,
    this.thighCm,
    this.notes,
  });

  static String generateId() =>
      DateTime.now().millisecondsSinceEpoch.toString();

  factory BodyMeasurementEntry.fromJson(Map<String, dynamic> json) =>
      BodyMeasurementEntry(
        id: json['id'] as String,
        loggedAt: DateTime.parse(json['loggedAt'] as String),
        waistCm: (json['waistCm'] as num?)?.toDouble(),
        neckCm: (json['neckCm'] as num?)?.toDouble(),
        hipsCm: (json['hipsCm'] as num?)?.toDouble(),
        chestCm: (json['chestCm'] as num?)?.toDouble(),
        bicepCm: (json['bicepCm'] as num?)?.toDouble(),
        thighCm: (json['thighCm'] as num?)?.toDouble(),
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'loggedAt': loggedAt.toIso8601String(),
        'waistCm': waistCm,
        'neckCm': neckCm,
        'hipsCm': hipsCm,
        'chestCm': chestCm,
        'bicepCm': bicepCm,
        'thighCm': thighCm,
        'notes': notes,
      };

  BodyMeasurementEntry copyWith({
    String? id,
    DateTime? loggedAt,
    double? waistCm,
    double? neckCm,
    double? hipsCm,
    double? chestCm,
    double? bicepCm,
    double? thighCm,
    String? notes,
  }) =>
      BodyMeasurementEntry(
        id: id ?? this.id,
        loggedAt: loggedAt ?? this.loggedAt,
        waistCm: waistCm ?? this.waistCm,
        neckCm: neckCm ?? this.neckCm,
        hipsCm: hipsCm ?? this.hipsCm,
        chestCm: chestCm ?? this.chestCm,
        bicepCm: bicepCm ?? this.bicepCm,
        thighCm: thighCm ?? this.thighCm,
        notes: notes ?? this.notes,
      );
}
