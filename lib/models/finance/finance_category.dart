enum CategoryType { income, expense }

// No default seeding — users create all categories themselves.
class FinanceCategory {
  final String id;
  final String name;
  final CategoryType type;
  final String icon; // MDI icon name
  final String colorHex;
  final DateTime updatedAt;

  FinanceCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.colorHex,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory FinanceCategory.fromJson(Map<String, dynamic> json) {
    return FinanceCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      type: CategoryType.values.byName(json['type'] as String),
      icon: json['icon'] as String,
      colorHex: json['colorHex'] as String,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'icon': icon,
        'colorHex': colorHex,
        'updatedAt': updatedAt.toIso8601String(),
      };

  FinanceCategory copyWith({
    String? name,
    CategoryType? type,
    String? icon,
    String? colorHex,
    DateTime? updatedAt,
  }) {
    return FinanceCategory(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
