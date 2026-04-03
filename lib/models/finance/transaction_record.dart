// Named TransactionRecord to avoid collision with Dart's Transaction.
enum TransactionType { inflow, outflow, transfer }

class TransactionRecord {
  final String id;
  final DateTime date;
  final String accountId;
  final String categoryId;
  final double amount; // always positive
  final TransactionType type;
  final String description;
  final String? note;
  final String month; // 'YYYY-MM' for filtering
  final String? billId; // links to Bill
  final String? receivableId; // links to Receivable
  final String? transferToAccountId; // outbound leg of transfer
  final String? transferGroupId; // shared by both legs of a transfer pair
  final String? installmentId; // links to Installment

  const TransactionRecord({
    required this.id,
    required this.date,
    required this.accountId,
    required this.categoryId,
    required this.amount,
    required this.type,
    required this.description,
    this.note,
    required this.month,
    this.billId,
    this.receivableId,
    this.transferToAccountId,
    this.transferGroupId,
    this.installmentId,
  });

  factory TransactionRecord.fromJson(Map<String, dynamic> json) {
    return TransactionRecord(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      accountId: json['accountId'] as String,
      categoryId: json['categoryId'] as String,
      amount: (json['amount'] as num).toDouble(),
      type: TransactionType.values.byName(json['type'] as String),
      description: json['description'] as String,
      note: json['note'] as String?,
      month: json['month'] as String,
      billId: json['billId'] as String?,
      receivableId: json['receivableId'] as String?,
      transferToAccountId: json['transferToAccountId'] as String?,
      transferGroupId: json['transferGroupId'] as String?,
      installmentId: json['installmentId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'accountId': accountId,
        'categoryId': categoryId,
        'amount': amount,
        'type': type.name,
        'description': description,
        'note': note,
        'month': month,
        'billId': billId,
        'receivableId': receivableId,
        'transferToAccountId': transferToAccountId,
        'transferGroupId': transferGroupId,
        'installmentId': installmentId,
      };

  TransactionRecord copyWith({
    DateTime? date,
    String? accountId,
    String? categoryId,
    double? amount,
    TransactionType? type,
    String? description,
    String? note,
    String? month,
    String? billId,
    String? receivableId,
    String? transferToAccountId,
    String? transferGroupId,
    String? installmentId,
  }) {
    return TransactionRecord(
      id: id,
      date: date ?? this.date,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      description: description ?? this.description,
      note: note ?? this.note,
      month: month ?? this.month,
      billId: billId ?? this.billId,
      receivableId: receivableId ?? this.receivableId,
      transferToAccountId: transferToAccountId ?? this.transferToAccountId,
      transferGroupId: transferGroupId ?? this.transferGroupId,
      installmentId: installmentId ?? this.installmentId,
    );
  }
}
