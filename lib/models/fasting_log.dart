class FastingLog {
  DateTime fastStart;
  DateTime fastEnd;
  double fastDuration;
  bool success;
  DateTime eatingStart;
  DateTime? eatingEnd;
  double? eatingDuration;
  String? note;
  int? _goalDuration; // Backing field for goalDuration

  int get goalDuration => _goalDuration ?? 16; // Default to 16 if null

  FastingLog({
    required this.fastStart,
    required this.fastEnd,
    required this.fastDuration,
    required this.success,
    required this.eatingStart,
    this.eatingEnd,
    this.eatingDuration,
    this.note,
    int? goalDuration,
  }) : _goalDuration = goalDuration ?? 16;

  factory FastingLog.fromJson(Map<String, dynamic> json) {
    return FastingLog(
      fastStart: DateTime.parse(json['fastStart']),
      fastEnd: DateTime.parse(json['fastEnd']),
      fastDuration: json['fastDuration'].toDouble(),
      success: json['success'],
      eatingStart: DateTime.parse(json['eatingStart']),
      eatingEnd: json['eatingEnd'] != null ? DateTime.parse(json['eatingEnd']) : null,
      eatingDuration: json['eatingDuration']?.toDouble(),
      note: json['note'],
      goalDuration: json['goalDuration'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fastStart': fastStart.toIso8601String(),
      'fastEnd': fastEnd.toIso8601String(),
      'fastDuration': fastDuration,
      'success': success,
      'eatingStart': eatingStart.toIso8601String(),
      'eatingEnd': eatingEnd?.toIso8601String(),
      'eatingDuration': eatingDuration,
      'note': note,
      'goalDuration': goalDuration,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FastingLog &&
          fastStart == other.fastStart &&
          fastEnd == other.fastEnd &&
          fastDuration == other.fastDuration &&
          success == other.success &&
          eatingStart == other.eatingStart &&
          eatingEnd == other.eatingEnd &&
          eatingDuration == other.eatingDuration &&
          note == other.note &&
          goalDuration == other.goalDuration;

  @override
  int get hashCode => Object.hash(
      fastStart, fastEnd, fastDuration, success, eatingStart, eatingEnd,
      eatingDuration, note, goalDuration);
}
