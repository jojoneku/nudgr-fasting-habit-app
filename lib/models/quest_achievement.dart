/// Milestone badge earned when a quest streak hits a threshold.
class QuestAchievement {
  final String id;
  final int questId;
  final int streakMilestone; // 7, 21, 30, 66, 100
  final DateTime unlockedAt;
  final bool seen; // false = show unlock animation on next view

  const QuestAchievement({
    required this.id,
    required this.questId,
    required this.streakMilestone,
    required this.unlockedAt,
    this.seen = false,
  });

  QuestAchievement copyWith({
    String? id,
    int? questId,
    int? streakMilestone,
    DateTime? unlockedAt,
    bool? seen,
  }) {
    return QuestAchievement(
      id: id ?? this.id,
      questId: questId ?? this.questId,
      streakMilestone: streakMilestone ?? this.streakMilestone,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      seen: seen ?? this.seen,
    );
  }

  factory QuestAchievement.fromJson(Map<String, dynamic> json) {
    return QuestAchievement(
      id: json['id'] as String,
      questId: json['questId'] as int,
      streakMilestone: json['streakMilestone'] as int,
      unlockedAt: DateTime.parse(json['unlockedAt'] as String),
      seen: json['seen'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'questId': questId,
        'streakMilestone': streakMilestone,
        'unlockedAt': unlockedAt.toIso8601String(),
        'seen': seen,
      };
}
