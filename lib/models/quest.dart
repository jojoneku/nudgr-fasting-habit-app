class Quest {
  int id;
  String title;
  int hour;
  int minute;
  bool isEnabled;
  List<bool> days;
  DateTime? lastCompleted;
  DateTime? lastXpAwarded;
  int xpReward;

  Quest({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    this.isEnabled = true,
    required this.days,
    this.lastCompleted,
    this.lastXpAwarded,
    this.xpReward = 10,
  });

  bool get isCompletedToday {
    if (lastCompleted == null) return false;
    final now = DateTime.now();
    return lastCompleted!.year == now.year &&
           lastCompleted!.month == now.month &&
           lastCompleted!.day == now.day;
  }

  factory Quest.fromJson(Map<String, dynamic> json) {
    return Quest(
      id: json['id'],
      title: json['title'],
      hour: json['hour'],
      minute: json['minute'],
      isEnabled: json['isEnabled'],
      days: List<bool>.from(json['days']),
      lastCompleted: json['lastCompleted'] != null 
          ? DateTime.parse(json['lastCompleted']) 
          : null,
      lastXpAwarded: json['lastXpAwarded'] != null 
          ? DateTime.parse(json['lastXpAwarded']) 
          : null,
      xpReward: json['xpReward'] ?? 10,
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
      'lastCompleted': lastCompleted?.toIso8601String(),
      'lastXpAwarded': lastXpAwarded?.toIso8601String(),
      'xpReward': xpReward,
    };
  }
}
