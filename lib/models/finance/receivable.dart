import 'bill.dart' show RecurrenceType;

enum ReceivableType { salary, reimbursement, business, other }

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
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory Receivable.fromJson(Map<String, dynamic> json) {
    return Receivable(
      id: json['id'] as String,
      name: json['name'] as String,
      receivableType:
          ReceivableType.values.byName(json['receivableType'] as String),
      amount: (json['amount'] as num).toDouble(),
      nextMonthAmount: (json['nextMonthAmount'] as num?)?.toDouble(),
      expectedDate: DateTime.parse(json['expectedDate'] as String),
      month: json['month'] as String,
      categoryId: json['categoryId'] as String,
      isRecurring: json['isRecurring'] as bool? ?? false,
      recurrenceType: json['recurrenceType'] != null
          ? RecurrenceType.values.byName(json['recurrenceType'] as String)
          : null,
      isReceived: json['isReceived'] as bool? ?? false,
      receivedDate: json['receivedDate'] != null
          ? DateTime.parse(json['receivedDate'] as String)
          : null,
      receivedAmount: (json['receivedAmount'] as num?)?.toDouble(),
      transactionId: json['transactionId'] as String?,
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
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
