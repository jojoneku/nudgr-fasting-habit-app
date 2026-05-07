import 'dart:convert';

/// Progress of the food vector index build.
///
/// Persisted to [StorageService] so a partially built index can resume
/// after the app is killed.
class IndexProgress {
  final int indexed;
  final int total;
  final bool isComplete;
  final String? lastFoodId;
  final DateTime? completedAt;

  const IndexProgress({
    required this.indexed,
    required this.total,
    required this.isComplete,
    this.lastFoodId,
    this.completedAt,
  });

  const IndexProgress.empty()
      : indexed = 0,
        total = 0,
        isComplete = false,
        lastFoodId = null,
        completedAt = null;

  double get fraction => total == 0 ? 0 : (indexed / total).clamp(0.0, 1.0);

  IndexProgress copyWith({
    int? indexed,
    int? total,
    bool? isComplete,
    String? lastFoodId,
    DateTime? completedAt,
  }) =>
      IndexProgress(
        indexed: indexed ?? this.indexed,
        total: total ?? this.total,
        isComplete: isComplete ?? this.isComplete,
        lastFoodId: lastFoodId ?? this.lastFoodId,
        completedAt: completedAt ?? this.completedAt,
      );

  Map<String, dynamic> toJson() => {
        'indexed': indexed,
        'total': total,
        'isComplete': isComplete,
        if (lastFoodId != null) 'lastFoodId': lastFoodId,
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };

  factory IndexProgress.fromJson(Map<String, dynamic> json) => IndexProgress(
        indexed: (json['indexed'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        isComplete: json['isComplete'] as bool? ?? false,
        lastFoodId: json['lastFoodId'] as String?,
        completedAt: json['completedAt'] != null
            ? DateTime.tryParse(json['completedAt'] as String)
            : null,
      );

  String encode() => jsonEncode(toJson());

  static IndexProgress decode(String raw) {
    try {
      return IndexProgress.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const IndexProgress.empty();
    }
  }
}
