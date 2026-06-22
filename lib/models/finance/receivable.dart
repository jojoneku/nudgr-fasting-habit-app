import 'bill.dart' show RecurrenceType, recurrenceTypeFromName;

enum ReceivableType { salary, reimbursement, business, other }

/// Parses a [ReceivableType] name, falling back to [ReceivableType.other] for an
/// unknown or null value — so a corrupt/version-skewed record loads instead of
/// throwing out of sync. Mirrors `billTypeFromName` / `setAsideTypeFromName`.
ReceivableType receivableTypeFromName(String? name) {
  if (name == null) return ReceivableType.other;
  for (final t in ReceivableType.values) {
    if (t.name == name) return t;
  }
  return ReceivableType.other;
}

/// copyWith sentinel — see the note in `bill.dart`. Lets [Receivable.copyWith]
/// clear the nullable [accountId] with an explicit `null` while omitting it
/// leaves the current value untouched.
const Object _kUnset = Object();

class Receivable {
  final String id;
  final String name;
  final ReceivableType receivableType;
  final double amount;
  final double? nextMonthAmount; // pre-set amount for following month
  final DateTime expectedDate;
  final String month; // 'YYYY-MM'
  final String categoryId;
  final bool isRecurring;
  final RecurrenceType? recurrenceType;
  final bool isReceived;
  final DateTime? receivedDate;
  final double? receivedAmount; // may differ from expected
  final String? transactionId; // linked TransactionRecord
  /// Optional default destination account — pre-fills the dropdown in
  /// _MarkReceivedSheet so recurring receivables don't need re-picking each
  /// month. Null means "no preference, ask at received-time".
  final String? accountId;
  final DateTime updatedAt;

  Receivable({
    required this.id,
    required this.name,
    required this.receivableType,
    required this.amount,
    this.nextMonthAmount,
    required this.expectedDate,
    required this.month,
    required this.categoryId,
    this.isRecurring = false,
    this.recurrenceType,
    this.isReceived = false,
    this.receivedDate,
    this.receivedAmount,
    this.transactionId,
    this.accountId,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory Receivable.fromJson(Map<String, dynamic> json) {
    return Receivable(
      // Null-tolerant: a corrupt cloud row (missing date/category/type/etc.)
      // loads with safe defaults instead of throwing out of sync and being
      // dropped. Review-and-fix in-app beats silent data loss.
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      receivableType: receivableTypeFromName(json['receivableType'] as String?),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      nextMonthAmount: (json['nextMonthAmount'] as num?)?.toDouble(),
      expectedDate: DateTime.tryParse(json['expectedDate'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      month: json['month'] as String? ?? '',
      categoryId: json['categoryId'] as String? ?? '',
      isRecurring: json['isRecurring'] as bool? ?? false,
      recurrenceType: recurrenceTypeFromName(json['recurrenceType'] as String?),
      isReceived: json['isReceived'] as bool? ?? false,
      receivedDate: json['receivedDate'] != null
          ? DateTime.parse(json['receivedDate'] as String)
          : null,
      receivedAmount: (json['receivedAmount'] as num?)?.toDouble(),
      transactionId: json['transactionId'] as String?,
      accountId: json['accountId'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'receivableType': receivableType.name,
        'amount': amount,
        'nextMonthAmount': nextMonthAmount,
        'expectedDate': expectedDate.toIso8601String(),
        'month': month,
        'categoryId': categoryId,
        'isRecurring': isRecurring,
        'recurrenceType': recurrenceType?.name,
        'isReceived': isReceived,
        'receivedDate': receivedDate?.toIso8601String(),
        'receivedAmount': receivedAmount,
        'transactionId': transactionId,
        'accountId': accountId,
        'updatedAt': updatedAt.toIso8601String(),
      };

  Receivable copyWith({
    String? name,
    ReceivableType? receivableType,
    double? amount,
    double? nextMonthAmount,
    DateTime? expectedDate,
    String? month,
    String? categoryId,
    bool? isRecurring,
    RecurrenceType? recurrenceType,
    bool? isReceived,
    DateTime? receivedDate,
    double? receivedAmount,
    String? transactionId,
    Object? accountId = _kUnset,
    DateTime? updatedAt,
  }) {
    return Receivable(
      id: id,
      name: name ?? this.name,
      receivableType: receivableType ?? this.receivableType,
      amount: amount ?? this.amount,
      nextMonthAmount: nextMonthAmount ?? this.nextMonthAmount,
      expectedDate: expectedDate ?? this.expectedDate,
      month: month ?? this.month,
      categoryId: categoryId ?? this.categoryId,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      isReceived: isReceived ?? this.isReceived,
      receivedDate: receivedDate ?? this.receivedDate,
      receivedAmount: receivedAmount ?? this.receivedAmount,
      transactionId: transactionId ?? this.transactionId,
      accountId:
          identical(accountId, _kUnset) ? this.accountId : accountId as String?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
