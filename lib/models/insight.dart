/// Whether an [Insight] is the once-a-day morning summary or a one-off
/// event-triggered nudge (over-goal, overspend, streak-at-risk, ...).
enum InsightKind { dailyBrief, nudge }

/// Tone the Hub coach line / brief sheet should render with.
enum InsightMood { neutral, urgent, positive }

/// Which tier actually phrased the text — always `rules` when no AI is
/// configured or available; the fallback template is never lost, only
/// upgraded.
enum InsightSource { rules, onDevice, cloud }

/// A generated insight or nudge, persisted so the Hub coach line survives an
/// app restart. Produced by `InsightsPresenter` (Phase 3) from a rule in
/// `insight_triggers.dart` (for [InsightKind.nudge]) or from the full
/// snapshot (for [InsightKind.dailyBrief]).
class Insight {
  const Insight({
    required this.id,
    required this.kind,
    required this.mood,
    required this.text,
    this.triggerId,
    required this.createdAt,
    required this.source,
  });

  /// Unique id — used for dedup and as the ring-buffer key.
  final String id;

  final InsightKind kind;

  final InsightMood mood;

  /// One line for a nudge; a short paragraph for a daily brief.
  final String text;

  /// Which `InsightTrigger.id` fired this — `null` for a daily brief.
  final String? triggerId;

  final DateTime createdAt;

  final InsightSource source;

  Insight copyWith({
    String? id,
    InsightKind? kind,
    InsightMood? mood,
    String? text,
    String? triggerId,
    bool clearTriggerId = false,
    DateTime? createdAt,
    InsightSource? source,
  }) {
    return Insight(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      mood: mood ?? this.mood,
      text: text ?? this.text,
      triggerId: clearTriggerId ? null : (triggerId ?? this.triggerId),
      createdAt: createdAt ?? this.createdAt,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'mood': mood.name,
        'text': text,
        'triggerId': triggerId,
        'createdAt': createdAt.toIso8601String(),
        'source': source.name,
      };

  factory Insight.fromJson(Map<String, dynamic> json) => Insight(
        id: json['id'] as String,
        kind: InsightKind.values.byName(json['kind'] as String),
        mood: InsightMood.values.byName(json['mood'] as String),
        text: json['text'] as String,
        triggerId: json['triggerId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        source: InsightSource.values.byName(json['source'] as String),
      );
}
