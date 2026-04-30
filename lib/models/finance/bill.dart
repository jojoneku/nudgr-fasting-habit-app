// BillType is also used by BudgetedExpense.
enum BillType {
  installment,
  creditCard,
  subscription,
  insurance,
  govtContribution,
  utility,
  other,
}

// Used by both Bill and Receivable.
enum RecurrenceType { monthly, weekly, yearly, custom }

class Bill {
  final String id;
  final String name;
  final BillType billType;
  final double amount;
  final double? nextMonthAmount; // pre-set amount for following month
  final int dueDay; // 1–31 day of month
  final String month; // 'YYYY-MM'
  final String categoryId;
  final String? accountId; // preferred payment account
  final String? paymentNote; // e.g. "Gcash 120263075639"
  final bool isRecurring;
  final RecurrenceType? recurrenceType;
  final bool isPaid;
  final DateTime? paidDate;
  final double? paidAmount; // may differ from billed amount (partial pay)
  final String? transactionId; // linked TransactionRecord
  final DateTime updatedAt;

  Bill({
    required this.id,
    required this.name,
    required this.billType,
    required this.amount,
    this.nextMonthAmount,
    required this.dueDay,
    required this.month,
    required this.categoryId,
    this.accountId,
    this.paymentNote,
    this.isRecurring = false,
    this.recurrenceType,
    this.isPaid = false,
    this.paidDate,
    this.paidAmount,
    this.transactionId,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      id: json['id'] as String,
      name: json['name'] as String,
      billType: BillType.values.byName(json['billType'] as String),
      amount: (json['amount'] as num).toDouble(),
      nextMonthAmount: (json['nextMonthAmount'] as num?)?.toDouble(),
      dueDay: json['dueDay'] as int,
      month: json['month'] as String,
      categoryId: json['categoryId'] as String,
      accountId: json['accountId'] as String?,
      paymentNote: json['paymentNote'] as String?,
      isRecurring: json['isRecurring'] as bool? ?? false,
      recurrenceType: json['recurrenceType'] != null
          ? RecurrenceType.values.byName(json['recurrenceType'] as String)
          : null,
      isPaid: json['isPaid'] as bool? ?? false,
      paidDate: json['paidDate'] != null
          ? DateTime.parse(json['paidDate'] as String)
          : null,
      paidAmount: (json['paidAmount'] as num?)?.toDouble(),
      transactionId: json['transactionId'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'billType': billType.name,
        'amount': amount,
        'nextMonthAmount': nextMonthAmount,
        'dueDay': dueDay,
        'month': month,
        'categoryId': categoryId,
        'accountId': accountId,
        'paymentNote': paymentNote,
        'isRecurring': isRecurring,
        'recurrenceType': recurrenceType?.name,
        'isPaid': isPaid,
        'paidDate': paidDate?.toIso8601String(),
        'paidAmount': paidAmount,
        'transactionId': transactionId,
        'updatedAt': updatedAt.toIso8601String(),
      };

  Bill copyWith({
    String? name,
    BillType? billType,
    double? amount,
    double? nextMonthAmount,
    int? dueDay,
    String? month,
    String? categoryId,
    String? accountId,
    String? paymentNote,
    bool? isRecurring,
    RecurrenceType? recurrenceType,
    bool? isPaid,
    DateTime? paidDate,
    double? paidAmount,
    String? transactionId,
    DateTime? updatedAt,
  }) {
    return Bill(
      id: id,
      name: name ?? this.name,
      billType: billType ?? this.billType,
      amount: amount ?? this.amount,
      nextMonthAmount: nextMonthAmount ?? this.nextMonthAmount,
      dueDay: dueDay ?? this.dueDay,
      month: month ?? this.month,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      paymentNote: paymentNote ?? this.paymentNote,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      isPaid: isPaid ?? this.isPaid,
      paidDate: paidDate ?? this.paidDate,
      paidAmount: paidAmount ?? this.paidAmount,
      transactionId: transactionId ?? this.transactionId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
