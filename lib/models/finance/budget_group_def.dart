import 'dart:convert';

class BudgetGroupDef {
  final String id;
  final String name;
  final bool isSavings;
  final bool isBuiltIn;
  final int sortOrder;

  const BudgetGroupDef({
    required this.id,
    required this.name,
    required this.isSavings,
    required this.isBuiltIn,
    required this.sortOrder,
  });

  factory BudgetGroupDef.fromJson(Map<String, dynamic> json) => BudgetGroupDef(
        id: json['id'] as String,
        name: json['name'] as String,
        isSavings: json['isSavings'] as bool? ?? false,
        isBuiltIn: json['isBuiltIn'] as bool? ?? false,
        sortOrder: json['sortOrder'] as int? ?? 99,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isSavings': isSavings,
        'isBuiltIn': isBuiltIn,
        'sortOrder': sortOrder,
      };

  BudgetGroupDef copyWith({String? name, int? sortOrder}) => BudgetGroupDef(
        id: id,
        name: name ?? this.name,
        isSavings: isSavings,
        isBuiltIn: isBuiltIn,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  // IDs matching the old BudgetGroup enum names — backward-compatible with
  // existing stored budgets (Budget.toJson wrote group.name as a String).
  static const String idNonNegotiables = 'nonNegotiables';
  static const String idLivingExpense = 'livingExpense';
  static const String idVariableOptional = 'variableOptional';
  static const String idSavings = 'savings';

  static const defaultGroups = [
    // Order (sortOrder) drives the Budget tab's section order:
    // Living Expense → Savings → Variable / Optional → Non-Negotiables. A user's
    // manage-groups reordering still wins — merge() overrides these from stored.
    BudgetGroupDef(
      id: idLivingExpense,
      name: 'Living Expense',
      isSavings: false,
      isBuiltIn: true,
      sortOrder: 0,
    ),
    BudgetGroupDef(
      id: idSavings,
      name: 'Savings / Goals',
      isSavings: true,
      isBuiltIn: true,
      sortOrder: 1,
    ),
    BudgetGroupDef(
      id: idVariableOptional,
      name: 'Variable / Optional',
      isSavings: false,
      isBuiltIn: true,
      sortOrder: 2,
    ),
    BudgetGroupDef(
      id: idNonNegotiables,
      name: 'Non-Negotiables',
      isSavings: false,
      isBuiltIn: true,
      sortOrder: 3,
    ),
  ];

  /// Merge stored overrides into defaults. Unknown stored IDs are appended as
  /// custom groups; built-in defaults not present in [stored] keep their defaults.
  static List<BudgetGroupDef> merge(List<BudgetGroupDef> stored) {
    final result = <BudgetGroupDef>[...defaultGroups];
    for (final s in stored) {
      final i = result.indexWhere((g) => g.id == s.id);
      if (i >= 0) {
        // Override name + sortOrder for built-ins (user may have renamed/reordered).
        result[i] = result[i].copyWith(name: s.name, sortOrder: s.sortOrder);
      } else {
        result.add(s);
      }
    }
    result.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return result;
  }

  static List<BudgetGroupDef> fromJsonList(String raw) {
    try {
      return (jsonDecode(raw) as List)
          .map((e) => BudgetGroupDef.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
