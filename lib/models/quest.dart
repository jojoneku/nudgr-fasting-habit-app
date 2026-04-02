class Quest {
  int id;
  String title;
  int hour;
  int minute;
  bool isEnabled;
  List<bool> days;
  // stored as "YYYY-MM-DD"
  List<String> completedDates;
  DateTime? lastXpAwarded;
  int xpReward;
  bool isOneTime;
  int? reminderMinutes; // null = no reminder

  Quest({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    this.isEnabled = true,
    required this.days,
    List<String>? completedDates,
    this.lastXpAwarded,
    this.xpReward = 10,
    this.isOneTime = false,
    this.reminderMinutes,
  }) : completedDates = completedDates ?? [];

  DateTime? get lastCompleted {
    if (completedDates.isEmpty) return null;
    // Assuming sorted or just getting last added?
    // Ideally we should parse and find max, but usually we append.
    // Let's parse the last one.
    try {
      return DateTime.parse(completedDates.last);
    } catch (e) {
      return null;
    }
  }

  set lastCompleted(DateTime? date) {
    if (date == null)
      return; // Can't really unset only the last one easily without context
    final dateStr = date.toIso8601String().split('T')[0];
    if (!completedDates.contains(dateStr)) {
      completedDates.add(dateStr);
      // Keep sorted?
      completedDates.sort();
    }
  }

  bool isCompletedOn(DateTime date) {
    final dateStr = date.toIso8601String().split('T')[0];
    return completedDates.contains(dateStr);
  }

  bool get isCompletedToday {
    return isCompletedOn(DateTime.now());
  }

  factory Quest.fromJson(Map<String, dynamic> json) {
    List<String> loadedDates = [];
    if (json['completedDates'] != null) {
      loadedDates = List<String>.from(json['completedDates']);
    } else if (json['lastCompleted'] != null) {
      // Migration from legacy
      try {
        final date = DateTime.parse(json['lastCompleted']);
        loadedDates.add(date.toIso8601String().split('T')[0]);
      } catch (e) {/* ignore */}
    }

    return Quest(
      id: json['id'],
      title: json['title'],
      hour: json['hour'],
      minute: json['minute'],
      isEnabled: json['isEnabled'],
      days: List<bool>.from(json['days']),
      completedDates: loadedDates,
      lastXpAwarded: json['lastXpAwarded'] != null
          ? DateTime.parse(json['lastXpAwarded'])
          : null,
      xpReward: json['xpReward'] ?? 10,
      isOneTime: json['isOneTime'] ?? false,
      reminderMinutes: json['reminderMinutes'],
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
      'lastXpAwarded': lastXpAwarded?.toIso8601String(),
      'xpReward': xpReward,
      'isOneTime': isOneTime,
      'reminderMinutes': reminderMinutes,
    };
  }
}
