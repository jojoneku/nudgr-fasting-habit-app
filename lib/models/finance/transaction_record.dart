// Named TransactionRecord to avoid collision with Dart's Transaction.
enum TransactionType { inflow, outflow, transfer }

/// copyWith sentinel — see the note in `bill.dart`. Lets
/// [TransactionRecord.copyWith] set [TransactionRecord.createdAt] back to null.
const Object _kUnset = Object();

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
  // outflow leg: the account money flows TO. inflow leg: the account money came
  // FROM (mirrors the outflow leg's accountId, set symmetrically by addTransfer).
  final String? transferToAccountId;
  final String? transferGroupId; // shared by both legs of a transfer pair
  final String? installmentId; // links to Installment
  /// Whether this record represents the original purchase of an item split
  /// into installments. Unlike regular expenses, an installment purchase holds
  /// credit limit upfront on a liability account, but is excluded from immediate
  /// headline cash expenses (which are only incurred when monthly installments are billed/paid).
  final bool isInstallment;
  // Money you spent but expect to recover (e.g. a work expense to be
  // reimbursed). STILL counts in headline Expenses (real cash left your pocket)
  // but is excluded from per-category budget spend. Only ever set on outflows.
  final bool reimbursable;
  // Forward link to the ReceivableType.reimbursement this outflow spawned, so
  // the UI can show what you're owed and settle it. Null unless reimbursable.
  final String? reimbursementReceivableId;
  // Who owes you back for a reimbursable expense (free text, e.g. "Acme Corp"
  // or "Jana"). Surfaced on the spawned receivable. Null/empty when unknown.
  final String? owedBy;

  /// When the record was first created on a device. Set once by the owning
  /// presenter's create path and never changed by an edit. Null on records
  /// saved before this field shipped ("added before this release"). It is not
  /// [updatedAt], which is a sync stamp.
  final DateTime? createdAt;
  final DateTime updatedAt;

  TransactionRecord({
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
    this.isInstallment = false,
    this.reimbursable = false,
    this.reimbursementReceivableId,
    this.owedBy,
    this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

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
      isInstallment: json['isInstallment'] as bool? ?? false,
      reimbursable: json['reimbursable'] as bool? ?? false,
      reimbursementReceivableId: json['reimbursementReceivableId'] as String?,
      owedBy: json['owedBy'] as String?,
      // Tolerant: a record saved before this field shipped (or a bad value)
      // loads as null rather than failing the pull.
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
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
        'isInstallment': isInstallment,
        'reimbursable': reimbursable,
        'reimbursementReceivableId': reimbursementReceivableId,
        'owedBy': owedBy,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
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
    bool? isInstallment,
    bool? reimbursable,
    String? reimbursementReceivableId,
    String? owedBy,
    // Sentinel-guarded so a presenter can carry the stored value onto an
    // edited record exactly, null included. Omitting it keeps the current one.
    Object? createdAt = _kUnset,
    DateTime? updatedAt,
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
      isInstallment: isInstallment ?? this.isInstallment,
      reimbursable: reimbursable ?? this.reimbursable,
      reimbursementReceivableId:
          reimbursementReceivableId ?? this.reimbursementReceivableId,
      owedBy: owedBy ?? this.owedBy,
      createdAt: identical(createdAt, _kUnset)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
