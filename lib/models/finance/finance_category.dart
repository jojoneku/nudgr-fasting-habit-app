enum CategoryType { income, expense, transfer }

// No default seeding — users create all categories themselves, except the one
// reserved [FinanceCategory.transfer] category the ledger maintains internally.
class FinanceCategory {
  /// Stable id of the reserved, system-owned category that tags both legs of an
  /// internal transfer. Never shown in pickers/breakdowns (filtered out by the
  /// expense/income type checks) and never user-editable. See
  /// [LedgerPresenter] for how it is seeded and applied.
  static const String transferCategoryId = '__transfer__';

  /// The reserved transfer category instance. Created on demand by the ledger.
  factory FinanceCategory.transfer() => FinanceCategory(
        id: transferCategoryId,
        name: 'Transfer',
        type: CategoryType.transfer,
        icon: 'bank-transfer',
        colorHex: '#64748B', // slate — neutral, never a spending color
      );

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
      // Tolerant of unknown/future type names (defensive against an older build
      // pulling a newer category type from sync) — defaults to expense.
      type: CategoryType.values.asNameMap()[json['type'] as String?] ??
          CategoryType.expense,
      icon: json['icon'] as String,
      colorHex: json['colorHex'] as String,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
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
