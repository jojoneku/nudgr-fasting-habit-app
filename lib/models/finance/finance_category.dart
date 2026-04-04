enum CategoryType { income, expense }

// No default seeding — users create all categories themselves.
class FinanceCategory {
  final String id;
  final String name;
  final CategoryType type;
  final String icon; // MDI icon name
  final String colorHex;

  const FinanceCategory({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.colorHex,
  });

  factory FinanceCategory.fromJson(Map<String, dynamic> json) {
    return FinanceCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      type: CategoryType.values.byName(json['type'] as String),
      icon: json['icon'] as String,
      colorHex: json['colorHex'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'icon': icon,
        'colorHex': colorHex,
      };

  FinanceCategory copyWith({
    String? name,
    CategoryType? type,
    String? icon,
    String? colorHex,
  }) {
    return FinanceCategory(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
    );
  }
}
