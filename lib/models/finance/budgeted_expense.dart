/// Classifies a budgeted set-aside so the UI can group/label it. Replaces the
/// old reuse of `BillType`, which was bill-oriented and a poor fit here.
enum SetAsideType { savings, goal, sinkingFund, gift, other }

extension SetAsideTypeLabel on SetAsideType {
  String get label => switch (this) {
        SetAsideType.savings => 'Savings',
        SetAsideType.goal => 'Goal',
        SetAsideType.sinkingFund => 'Sinking Fund',
        SetAsideType.gift => 'Gift',
        SetAsideType.other => 'Other',
      };
}

/// Parses a stored type name, tolerating legacy `BillType` values (e.g.
/// "utility", "creditCard") and anything unknown by mapping them to
/// [SetAsideType.other] — so existing set-asides load without error.
SetAsideType setAsideTypeFromName(String? name) {
  if (name == null) return SetAsideType.other;
  for (final t in SetAsideType.values) {
    if (t.name == name) return t;
  }
  return SetAsideType.other;
}

// Planned spending commitments (Family Support, Braces Sinking Fund, EF top-up).
// These appear in the Bills & Receivables sheet under "BUDGETED EXPENSE".
class BudgetedExpense {
  final String id;
  final String name;
  final SetAsideType budgetedType;
  final String month; // 'YYYY-MM'
  final double allocatedAmount;
  final double? nextMonthAmount; // pre-set amount for following month
  final double spentAmount; // actual expense recorded
  final String categoryId;
  final String? note; // e.g. "Cash", "Maya Savings"
  final bool isPaid;
  final String? transactionId; // linked TransactionRecord
  final DateTime updatedAt;

  BudgetedExpense({
    required this.id,
    required this.name,
    required this.budgetedType,
    required this.month,
    required this.allocatedAmount,
    this.nextMonthAmount,
    this.spentAmount = 0,
    required this.categoryId,
    this.note,
    this.isPaid = false,
    this.transactionId,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory BudgetedExpense.fromJson(Map<String, dynamic> json) {
    return BudgetedExpense(
      id: json['id'] as String,
      name: json['name'] as String,
      budgetedType: setAsideTypeFromName(json['budgetedType'] as String?),
      month: json['month'] as String,
      allocatedAmount: (json['allocatedAmount'] as num).toDouble(),
      nextMonthAmount: (json['nextMonthAmount'] as num?)?.toDouble(),
      spentAmount: (json['spentAmount'] as num?)?.toDouble() ?? 0,
      categoryId: json['categoryId'] as String,
      note: json['note'] as String?,
      isPaid: json['isPaid'] as bool? ?? false,
      transactionId: json['transactionId'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'budgetedType': budgetedType.name,
        'month': month,
        'allocatedAmount': allocatedAmount,
        'nextMonthAmount': nextMonthAmount,
        'spentAmount': spentAmount,
        'categoryId': categoryId,
        'note': note,
        'isPaid': isPaid,
        'transactionId': transactionId,
        'updatedAt': updatedAt.toIso8601String(),
      };

  BudgetedExpense copyWith({
    String? name,
    SetAsideType? budgetedType,
    String? month,
    double? allocatedAmount,
    double? nextMonthAmount,
    double? spentAmount,
    String? categoryId,
    String? note,
    bool? isPaid,
    String? transactionId,
    DateTime? updatedAt,
  }) {
    return BudgetedExpense(
      id: id,
      name: name ?? this.name,
      budgetedType: budgetedType ?? this.budgetedType,
      month: month ?? this.month,
      allocatedAmount: allocatedAmount ?? this.allocatedAmount,
      nextMonthAmount: nextMonthAmount ?? this.nextMonthAmount,
      spentAmount: spentAmount ?? this.spentAmount,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      isPaid: isPaid ?? this.isPaid,
      transactionId: transactionId ?? this.transactionId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
