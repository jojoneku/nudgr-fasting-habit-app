/// Durable, user-curated facts the financial advisor remembers between
/// sessions: goals, risk tolerance, and freeform notes the user shares.
///
/// Immutable. Injected into every advisor turn via [promptSummary] so advice
/// stays personal. The user owns it — it is viewable and clearable in the
/// advisor's memory view. (Automatic model-proposed updates are a deferred
/// enhancement; for now the user curates it explicitly.)
class AdvisorProfile {
  final List<String> goals;

  /// Free-text risk tolerance (e.g. "conservative", "aggressive builder"), or
  /// null when the user hasn't set one.
  final String? riskTolerance;

  /// Freeform facts the user wants the advisor to keep in mind.
  final List<String> facts;
  final DateTime updatedAt;

  const AdvisorProfile({
    this.goals = const [],
    this.riskTolerance,
    this.facts = const [],
    required this.updatedAt,
  });

  factory AdvisorProfile.empty() =>
      AdvisorProfile(updatedAt: DateTime.fromMillisecondsSinceEpoch(0));

  bool get isEmpty =>
      goals.isEmpty &&
      (riskTolerance == null || riskTolerance!.isEmpty) &&
      facts.isEmpty;

  factory AdvisorProfile.fromJson(Map<String, dynamic> json) => AdvisorProfile(
        goals: (json['goals'] as List?)?.map((e) => '$e').toList() ?? const [],
        riskTolerance: json['riskTolerance'] as String?,
        facts: (json['facts'] as List?)?.map((e) => '$e').toList() ?? const [],
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
        'goals': goals,
        if (riskTolerance != null) 'riskTolerance': riskTolerance,
        'facts': facts,
        'updatedAt': updatedAt.toIso8601String(),
      };

  AdvisorProfile copyWith({
    List<String>? goals,
    String? riskTolerance,
    List<String>? facts,
    DateTime? updatedAt,
  }) =>
      AdvisorProfile(
        goals: goals ?? this.goals,
        riskTolerance: riskTolerance ?? this.riskTolerance,
        facts: facts ?? this.facts,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Compact summary injected into the advisor system prompt as background
  /// context (never as instructions). Returns null when there's nothing to say.
  String? promptSummary() {
    if (isEmpty) return null;
    final buf = StringBuffer();
    if (goals.isNotEmpty) {
      buf.writeln('Goals:');
      for (final g in goals) {
        buf.writeln('  - $g');
      }
    }
    if (riskTolerance != null && riskTolerance!.isNotEmpty) {
      buf.writeln('Risk tolerance: $riskTolerance');
    }
    if (facts.isNotEmpty) {
      buf.writeln('Notes:');
      for (final f in facts) {
        buf.writeln('  - $f');
      }
    }
    return buf.toString().trim();
  }
}
