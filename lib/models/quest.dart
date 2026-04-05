/// Which character attribute a quest trains.
enum LinkedStat { str, vit, agi, intl, sen }

/// How a quest was completed (affects XP and streak).
enum CompletionType { full, partial, skipped }

class Quest {
  final int id;
  final String title;
  final int hour;
  final int minute;
  final bool isEnabled;
  final List<bool> days;
  // stored as "YYYY-MM-DD"
  final List<String> completedDates;
  // stored as "YYYY-MM-DD" — partial/minimum-version completions
  final List<String> partialDates;
  final DateTime? lastXpAwarded;
  final int xpReward;
  final bool isOneTime;
  final int? reminderMinutes; // null = no reminder

  // --- New fields (plan 005) ---
  final LinkedStat? linkedStat;
  final String? anchorNote;
  final String? minimumVersion;
  final int streakCount;
  final int streakFreezes;
  final String? routineId;

  Quest({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    this.isEnabled = true,
    required this.days,
    List<String>? completedDates,
    List<String>? partialDates,
    this.lastXpAwarded,
    this.xpReward = 10,
    this.isOneTime = false,
    this.reminderMinutes,
    this.linkedStat,
    this.anchorNote,
    this.minimumVersion,
    this.streakCount = 0,
    this.streakFreezes = 0,
    this.routineId,
  })  : completedDates = completedDates ?? [],
        partialDates = partialDates ?? [];

  Quest copyWith({
    int? id,
    String? title,
    int? hour,
    int? minute,
    bool? isEnabled,
    List<bool>? days,
    List<String>? completedDates,
    List<String>? partialDates,
    DateTime? lastXpAwarded,
    bool clearLastXpAwarded = false,
    int? xpReward,
    bool? isOneTime,
    int? reminderMinutes,
    bool clearReminderMinutes = false,
    LinkedStat? linkedStat,
    bool clearLinkedStat = false,
    String? anchorNote,
    bool clearAnchorNote = false,
    String? minimumVersion,
    bool clearMinimumVersion = false,
    int? streakCount,
    int? streakFreezes,
    String? routineId,
    bool clearRoutineId = false,
  }) {
    return Quest(
      id: id ?? this.id,
      title: title ?? this.title,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      isEnabled: isEnabled ?? this.isEnabled,
      days: days ?? List.from(this.days),
      completedDates: completedDates ?? List.from(this.completedDates),
      partialDates: partialDates ?? List.from(this.partialDates),
      lastXpAwarded:
          clearLastXpAwarded ? null : (lastXpAwarded ?? this.lastXpAwarded),
      xpReward: xpReward ?? this.xpReward,
      isOneTime: isOneTime ?? this.isOneTime,
      reminderMinutes: clearReminderMinutes
          ? null
          : (reminderMinutes ?? this.reminderMinutes),
      linkedStat: clearLinkedStat ? null : (linkedStat ?? this.linkedStat),
      anchorNote: clearAnchorNote ? null : (anchorNote ?? this.anchorNote),
      minimumVersion:
          clearMinimumVersion ? null : (minimumVersion ?? this.minimumVersion),
      streakCount: streakCount ?? this.streakCount,
      streakFreezes: streakFreezes ?? this.streakFreezes,
      routineId: clearRoutineId ? null : (routineId ?? this.routineId),
    );
  }

  // ─── Computed helpers ──────────────────────────────────────────────────────

  DateTime? get lastCompleted {
    if (completedDates.isEmpty) return null;
    try {
      return DateTime.parse(completedDates.last);
    } catch (_) {
      return null;
    }
  }

  bool isCompletedOn(DateTime date) {
    final dateStr = _dateKey(date);
    return completedDates.contains(dateStr);
  }

  bool isPartialOn(DateTime date) {
    final dateStr = _dateKey(date);
    return partialDates.contains(dateStr);
  }

  bool get isCompletedToday => isCompletedOn(DateTime.now());
  bool get isPartialToday => isPartialOn(DateTime.now());

  static String _dateKey(DateTime date) => date.toIso8601String().split('T')[0];

  // ─── Serialization ─────────────────────────────────────────────────────────

  factory Quest.fromJson(Map<String, dynamic> json) {
    List<String> loadedDates = [];
    if (json['completedDates'] != null) {
      loadedDates = List<String>.from(json['completedDates'] as List);
    } else if (json['lastCompleted'] != null) {
      // Migration from legacy single-date field
      try {
        final date = DateTime.parse(json['lastCompleted'] as String);
        loadedDates.add(date.toIso8601String().split('T')[0]);
      } catch (_) {/* ignore */}
    }

    LinkedStat? linkedStat;
    if (json['linkedStat'] != null) {
      try {
        linkedStat = LinkedStat.values
            .firstWhere((e) => e.name == json['linkedStat'] as String);
      } catch (_) {/* ignore unknown */}
    }

    return Quest(
      id: json['id'] as int,
      title: json['title'] as String,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      isEnabled: json['isEnabled'] as bool? ?? true,
      days: List<bool>.from(json['days'] as List),
      completedDates: loadedDates,
      partialDates: json['partialDates'] != null
          ? List<String>.from(json['partialDates'] as List)
          : [],
      lastXpAwarded: json['lastXpAwarded'] != null
          ? DateTime.parse(json['lastXpAwarded'] as String)
          : null,
      xpReward: json['xpReward'] as int? ?? 10,
      isOneTime: json['isOneTime'] as bool? ?? false,
      reminderMinutes: json['reminderMinutes'] as int?,
      linkedStat: linkedStat,
      anchorNote: json['anchorNote'] as String?,
      minimumVersion: json['minimumVersion'] as String?,
      // If streakCount = 0 with existing data, QuestPresenter will recalculate
      streakCount: json['streakCount'] as int? ?? 0,
      streakFreezes: json['streakFreezes'] as int? ?? 0,
      routineId: json['routineId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'hour': hour,
      'minute': minute,
      'isEnabled': isEnabled,
      'days': days,
      'completedDates': completedDates,
      'partialDates': partialDates,
      'lastXpAwarded': lastXpAwarded?.toIso8601String(),
      'xpReward': xpReward,
      'isOneTime': isOneTime,
      'reminderMinutes': reminderMinutes,
      'linkedStat': linkedStat?.name,
      'anchorNote': anchorNote,
      'minimumVersion': minimumVersion,
      'streakCount': streakCount,
      'streakFreezes': streakFreezes,
      'routineId': routineId,
    };
  }
}
