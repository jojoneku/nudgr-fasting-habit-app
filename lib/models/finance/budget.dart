// Affects styling and calculation logic.
enum BudgetType { monthly, fixed, goal, variable }

// One row per category per month, grouped into named budget sections.
// [group] stores the group ID — matches [BudgetGroupDef.id]. Built-in groups
// use the old enum names as IDs so existing stored data loads without migration.
class Budget {
  final String id;
  final String categoryId;
  final String month; // 'YYYY-MM'
  final double allocatedAmount;
  final String group; // group ID — see BudgetGroupDef
  final BudgetType budgetType;
  final DateTime updatedAt;

  Budget({
    required this.id,
    required this.categoryId,
    required this.month,
    required this.allocatedAmount,
    required this.group,
    required this.budgetType,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'] as String,
      categoryId: json['categoryId'] as String,
      month: json['month'] as String,
      allocatedAmount: (json['allocatedAmount'] as num).toDouble(),
      group: json['group'] as String,
      budgetType: BudgetType.values.byName(json['budgetType'] as String),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'month': month,
        'allocatedAmount': allocatedAmount,
        'group': group,
        'budgetType': budgetType.name,
        'updatedAt': updatedAt.toIso8601String(),
      };

  Budget copyWith({
    String? categoryId,
    String? month,
    double? allocatedAmount,
    String? group,
    BudgetType? budgetType,
    DateTime? updatedAt,
  }) {
    return Budget(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      month: month ?? this.month,
      allocatedAmount: allocatedAmount ?? this.allocatedAmount,
      group: group ?? this.group,
      budgetType: budgetType ?? this.budgetType,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
