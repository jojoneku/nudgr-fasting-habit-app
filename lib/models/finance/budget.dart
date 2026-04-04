// Maps to the 3 sections in the Budget sheet.
enum BudgetGroup { nonNegotiables, livingExpense, variableOptional }

// Affects styling and calculation logic.
enum BudgetType { monthly, fixed, goal, variable }

// One row per category per month, grouped into 3 budget sections.
class Budget {
  final String id;
  final String categoryId;
  final String month; // 'YYYY-MM'
  final double allocatedAmount;
  final BudgetGroup group;
  final BudgetType budgetType;

  const Budget({
    required this.id,
    required this.categoryId,
    required this.month,
    required this.allocatedAmount,
    required this.group,
    required this.budgetType,
  });

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'] as String,
      categoryId: json['categoryId'] as String,
      month: json['month'] as String,
      allocatedAmount: (json['allocatedAmount'] as num).toDouble(),
      group: BudgetGroup.values.byName(json['group'] as String),
      budgetType: BudgetType.values.byName(json['budgetType'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'month': month,
        'allocatedAmount': allocatedAmount,
        'group': group.name,
        'budgetType': budgetType.name,
      };

  Budget copyWith({
    String? categoryId,
    String? month,
    double? allocatedAmount,
    BudgetGroup? group,
    BudgetType? budgetType,
  }) {
    return Budget(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      month: month ?? this.month,
      allocatedAmount: allocatedAmount ?? this.allocatedAmount,
      group: group ?? this.group,
      budgetType: budgetType ?? this.budgetType,
    );
  }
}
