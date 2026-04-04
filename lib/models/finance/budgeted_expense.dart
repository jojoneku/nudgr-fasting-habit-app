import 'bill.dart';

// Planned spending commitments (Family Support, Braces Sinking Fund, EF top-up).
// These appear in the Bills & Receivables sheet under "BUDGETED EXPENSE".
class BudgetedExpense {
  final String id;
  final String name;
  final BillType budgetedType; // reuses BillType taxonomy
  final String month; // 'YYYY-MM'
  final double allocatedAmount;
  final double? nextMonthAmount; // pre-set amount for following month
  final double spentAmount; // actual expense recorded
  final String categoryId;
  final String? note; // e.g. "Cash", "Maya Savings"
  final bool isPaid;
  final String? transactionId; // linked TransactionRecord

  const BudgetedExpense({
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
  });

  factory BudgetedExpense.fromJson(Map<String, dynamic> json) {
    return BudgetedExpense(
      id: json['id'] as String,
      name: json['name'] as String,
      budgetedType: BillType.values.byName(json['budgetedType'] as String),
      month: json['month'] as String,
      allocatedAmount: (json['allocatedAmount'] as num).toDouble(),
      nextMonthAmount: (json['nextMonthAmount'] as num?)?.toDouble(),
      spentAmount: (json['spentAmount'] as num?)?.toDouble() ?? 0,
      categoryId: json['categoryId'] as String,
      note: json['note'] as String?,
      isPaid: json['isPaid'] as bool? ?? false,
      transactionId: json['transactionId'] as String?,
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
      };

  BudgetedExpense copyWith({
    String? name,
    BillType? budgetedType,
    String? month,
    double? allocatedAmount,
    double? nextMonthAmount,
    double? spentAmount,
    String? categoryId,
    String? note,
    bool? isPaid,
    String? transactionId,
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
    );
  }
}
