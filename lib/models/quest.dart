class Quest {
  int id;
  String title;
  int hour;
  int minute;
  bool isEnabled;
  List<bool> days;
  DateTime? lastCompleted;

  Quest({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    this.isEnabled = true,
    required this.days,
    this.lastCompleted,
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
    };
  }
}
