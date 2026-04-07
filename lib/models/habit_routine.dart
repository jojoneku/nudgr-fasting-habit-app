/// A named, ordered sequence of quests executed as a daily ritual.
/// e.g. "Morning Ritual" → [Drink water, Meditate, Journal]
class HabitRoutine {
  final String id;
  final String name;
  final String icon; // MDI icon name
  final String colorHex;
  final List<String> questIds; // ordered — defines execution sequence
  final int scheduledHour;
  final int scheduledMinute;

  const HabitRoutine({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.questIds,
    required this.scheduledHour,
    required this.scheduledMinute,
  });

  HabitRoutine copyWith({
    String? id,
    String? name,
    String? icon,
    String? colorHex,
    List<String>? questIds,
    int? scheduledHour,
    int? scheduledMinute,
  }) {
    return HabitRoutine(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      questIds: questIds ?? List.from(this.questIds),
      scheduledHour: scheduledHour ?? this.scheduledHour,
      scheduledMinute: scheduledMinute ?? this.scheduledMinute,
    );
  }

  factory HabitRoutine.fromJson(Map<String, dynamic> json) {
    return HabitRoutine(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? 'lightning-bolt',
      colorHex: json['colorHex'] as String? ?? '#29B6F6',
      questIds: List<String>.from(json['questIds'] as List),
      scheduledHour: json['scheduledHour'] as int? ?? 8,
      scheduledMinute: json['scheduledMinute'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'colorHex': colorHex,
        'questIds': questIds,
        'scheduledHour': scheduledHour,
        'scheduledMinute': scheduledMinute,
      };
}
