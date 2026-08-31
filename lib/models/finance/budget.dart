/// Sentinel for [Budget.copyWith] so a nullable field can be cleared, not
/// merely left alone. Same device `Bill.copyWith` uses for its `seriesId`.
const Object _kUnset = Object();

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

  /// Links this line to the same budget line in other months (Plan 059).
  ///
  /// Null means a one-off: it belongs to [month] only and is never carried
  /// forward. Every row minted through the normal path gets a series, because
  /// recurring is the default — a budget you set once should keep applying.
  final String? seriesId;

  /// Whether this line still carries into later months.
  ///
  /// Set false when the user deletes the line, which is what ends a series:
  /// carry-forward reads this flag off the source month, so an ended series is
  /// simply not offered again. That is why deleting needs no separate
  /// "deliberately emptied" marker on the month.
  final bool isRecurring;

  Budget({
    required this.id,
    required this.categoryId,
    required this.month,
    required this.allocatedAmount,
    required this.group,
    required this.budgetType,
    this.seriesId,
    this.isRecurring = true,
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
      // Rows written before Plan 059 carry neither field. They load as
      // one-offs (no series, not recurring) rather than silently joining a
      // series they were never part of and propagating into future months.
      seriesId: json['seriesId'] as String?,
      isRecurring: json['isRecurring'] as bool? ?? false,
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
        'seriesId': seriesId,
        'isRecurring': isRecurring,
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// [seriesId] takes a sentinel rather than a plain null so a caller can
  /// actually clear it — `copyWith(seriesId: null)` has to mean "make this a
  /// one-off", and with the usual `?? this.seriesId` idiom it would silently
  /// mean "keep". The one-off switch in the edit sheet depends on this.
  Budget copyWith({
    String? categoryId,
    String? month,
    double? allocatedAmount,
    String? group,
    BudgetType? budgetType,
    Object? seriesId = _kUnset,
    bool? isRecurring,
    DateTime? updatedAt,
  }) {
    return Budget(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      month: month ?? this.month,
      allocatedAmount: allocatedAmount ?? this.allocatedAmount,
      group: group ?? this.group,
      budgetType: budgetType ?? this.budgetType,
      seriesId:
          identical(seriesId, _kUnset) ? this.seriesId : seriesId as String?,
      isRecurring: isRecurring ?? this.isRecurring,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
