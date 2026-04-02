typedef Attributes = ({int str, int vit, int agi, int intl, int sen});

class UserStats {
  final String name;
  final int level;
  final int currentXp;
  final int currentHp;
  final int statPoints; // Points available to spend
  final int streak;
  final Attributes attributes;

  const UserStats({
    required this.name,
    required this.level,
    required this.currentXp,
    required this.currentHp,
    required this.statPoints,
    required this.streak,
    required this.attributes,
  });

  factory UserStats.initial() {
    return const UserStats(
      name: 'Player',
      level: 1,
      currentXp: 0,
      currentHp: 100,
      statPoints: 0,
      streak: 0,
      attributes: (str: 1, vit: 1, agi: 1, intl: 1, sen: 1),
    );
  }

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      name: json['name'] as String? ?? 'Player',
      level: json['level'] as int,
      currentXp: json['currentXp'] as int,
      currentHp: json['currentHp'] as int,
      statPoints: json['statPoints'] as int,
      streak: json['streak'] as int,
      attributes: (
        str: json['attributes']['str'] as int,
        vit: json['attributes']['vit'] as int,
        agi: json['attributes']['agi'] as int,
        intl: json['attributes']['intl'] as int,
        sen: json['attributes']['sen'] as int,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'level': level,
      'currentXp': currentXp,
      'currentHp': currentHp,
      'statPoints': statPoints,
      'streak': streak,
      'attributes': {
        'str': attributes.str,
        'vit': attributes.vit,
        'agi': attributes.agi,
        'intl': attributes.intl,
        'sen': attributes.sen,
      },
    };
  }

  UserStats copyWith({
    String? name,
    int? level,
    int? currentXp,
    int? currentHp,
    int? statPoints,
    int? streak,
    Attributes? attributes,
  }) {
    return UserStats(
      name: name ?? this.name,
      level: level ?? this.level,
      currentXp: currentXp ?? this.currentXp,
      currentHp: currentHp ?? this.currentHp,
      statPoints: statPoints ?? this.statPoints,
      streak: streak ?? this.streak,
      attributes: attributes ?? this.attributes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserStats &&
          name == other.name &&
          level == other.level &&
          currentXp == other.currentXp &&
          currentHp == other.currentHp &&
          statPoints == other.statPoints &&
          streak == other.streak &&
          attributes == other.attributes;

  @override
  int get hashCode => Object.hash(
      name, level, currentXp, currentHp, statPoints, streak, attributes);
}
