class Habit {
  int id;
  String title;
  int hour;
  int minute;
  bool isEnabled;
  List<bool> days;

  Habit({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    this.isEnabled = true,
    required this.days,
  });

  factory Habit.fromJson(Map<String, dynamic> json) {
    return Habit(
      id: json['id'],
      title: json['title'],
      hour: json['hour'],
      minute: json['minute'],
      isEnabled: json['isEnabled'],
      days: List<bool>.from(json['days']),
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
    };
  }
}
