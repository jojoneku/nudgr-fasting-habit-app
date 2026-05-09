import 'dart:math';

/// What triggered the feedback record. Used to slice telemetry — e.g. show
/// only [fallbackMiss] entries when curating new DB rows.
enum FoodFeedbackKind {
  /// Hybrid retrieval missed entirely; we logged a keyword-density estimate.
  /// Captured automatically — strong signal that the DB needs an entry.
  fallbackMiss,

  /// User tapped thumbs-down on a chat row. Captured with the picked food's
  /// metadata so a curator can see what bad match was committed.
  userDislike,

  /// User swapped to one of the alternative chips. Implicit negative feedback
  /// on the original auto-pick AND positive feedback on the chosen alternative.
  swap,
}

/// One feedback event the matcher should learn from. Persisted in a rolling
/// log capped at [maxStoredEntries] so it doesn't grow unbounded.
class FoodFeedback {
  static const int maxStoredEntries = 500;

  final String id;
  final DateTime timestamp;
  final FoodFeedbackKind kind;

  /// Raw user input that triggered the parse (chat message text).
  final String userQuery;

  /// What the matcher picked — name + DB id (null for keyword-density estimates).
  final String pickedName;
  final String? pickedDbId;

  /// `EstimationSource.name` of the picked entry — "db", "keywordDensity", etc.
  final String estimationSource;

  /// Confidence at time of pick (null if not tracked for this source).
  final double? confidence;

  /// For [FoodFeedbackKind.swap] only — the alternative the user chose.
  final String? swappedToName;

  const FoodFeedback({
    required this.id,
    required this.timestamp,
    required this.kind,
    required this.userQuery,
    required this.pickedName,
    this.pickedDbId,
    required this.estimationSource,
    this.confidence,
    this.swappedToName,
  });

  static String generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  factory FoodFeedback.fromJson(Map<String, dynamic> json) => FoodFeedback(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        kind: FoodFeedbackKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => FoodFeedbackKind.fallbackMiss,
        ),
        userQuery: json['userQuery'] as String,
        pickedName: json['pickedName'] as String,
        pickedDbId: json['pickedDbId'] as String?,
        estimationSource: json['estimationSource'] as String,
        confidence: (json['confidence'] as num?)?.toDouble(),
        swappedToName: json['swappedToName'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'kind': kind.name,
        'userQuery': userQuery,
        'pickedName': pickedName,
        'pickedDbId': pickedDbId,
        'estimationSource': estimationSource,
        'confidence': confidence,
        'swappedToName': swappedToName,
      };
}
