import 'package:intermittent_fasting/models/finance/bill.dart'
    show RecurrenceType, recurrenceTypeFromName;

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

/// copyWith sentinel: distinguishes "leave [accountId] as is" (omit the
/// argument) from "clear it" (pass an explicit `null`). Mirrors the pattern in
/// bill.dart so picking "None" in the editor can actually null the account back
/// out — `field ?? this.field` never could.
const Object _kUnset = Object();

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
  final String? accountId; // funding account this set-aside is moved from

  /// Where the money lands when this set-aside is funded — the transfer's
  /// destination (e.g. "BPI → Maya"). Optional: null means the destination was
  /// never decided, and the funding sheet asks for it at confirmation time
  /// rather than guessing a savings account on the user's behalf.
  final String? destinationAccountId;
  final bool isPaid;
  final bool isRecurring; // re-created each month via auto-generation
  final RecurrenceType? recurrenceType;
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
    this.accountId,
    this.destinationAccountId,
    this.isPaid = false,
    this.isRecurring = false,
    this.recurrenceType,
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
      accountId: json['accountId'] as String?,
      destinationAccountId: json['destinationAccountId'] as String?,
      isPaid: json['isPaid'] as bool? ?? false,
      isRecurring: json['isRecurring'] as bool? ?? false,
      recurrenceType: recurrenceTypeFromName(json['recurrenceType'] as String?),
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
        'accountId': accountId,
        'destinationAccountId': destinationAccountId,
        'isPaid': isPaid,
        'isRecurring': isRecurring,
        'recurrenceType': recurrenceType?.name,
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
    Object? accountId = _kUnset,
    // Sentinel-guarded for the same reason as [accountId]: picking "Spend it"
    // in the editor has to be able to clear a saved destination back out.
    Object? destinationAccountId = _kUnset,
    bool? isPaid,
    bool? isRecurring,
    RecurrenceType? recurrenceType,
    // Sentinel-guarded so undoing a funding can clear the ledger link back out;
    // `field ?? this.field` never could, which left an unfunded set-aside still
    // pointing at a transaction that no longer exists.
    Object? transactionId = _kUnset,
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
      accountId:
          identical(accountId, _kUnset) ? this.accountId : accountId as String?,
      destinationAccountId: identical(destinationAccountId, _kUnset)
          ? this.destinationAccountId
          : destinationAccountId as String?,
      isPaid: isPaid ?? this.isPaid,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      transactionId: identical(transactionId, _kUnset)
          ? this.transactionId
          : transactionId as String?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
