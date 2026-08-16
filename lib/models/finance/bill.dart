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

/// Parses a [BillType] name, falling back to [BillType.other] for an unknown or
/// null value — so a record written by a newer/older build (or with corrupt
/// data) loads instead of throwing out of sync. Mirrors `setAsideTypeFromName`.
BillType billTypeFromName(String? name) {
  if (name == null) return BillType.other;
  for (final t in BillType.values) {
    if (t.name == name) return t;
  }
  return BillType.other;
}

/// Parses a [RecurrenceType] name; null/unknown → null (treated as one-off).
RecurrenceType? recurrenceTypeFromName(String? name) {
  if (name == null) return null;
  for (final t in RecurrenceType.values) {
    if (t.name == name) return t;
  }
  return null;
}

/// copyWith sentinel: lets a caller distinguish "leave this nullable field as
/// is" (omit the argument) from "clear it" (pass an explicit `null`). Without
/// this, `field ?? this.field` can never null a value back out.
const Object _kUnset = Object();

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

  /// Ties every monthly copy of one recurring bill together. Each month is a
  /// separate row, so without this the only thing linking August's "Internet"
  /// to September's is that they happen to share a name — which breaks the
  /// moment the edit being propagated *is* a rename, or two bills share a name.
  ///
  /// Stamped once when a recurring bill is created and inherited by every
  /// generated copy. Null on one-off bills, and on recurring rows saved before
  /// this field shipped — [BillsReceivablesPresenter] backfills those on load.
  final String? seriesId;
  final bool isPaid;
  final DateTime? paidDate;
  final double? paidAmount; // may differ from billed amount (partial pay)
  final String? transactionId; // linked TransactionRecord
  /// Lead time for a per-bill "remind me N days before due" reminder. Null means
  /// no reminder. Additive/null-tolerant — bills saved before this field load
  /// with no reminder.
  final int? reminderDaysBefore;
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
    this.seriesId,
    this.isPaid = false,
    this.paidDate,
    this.paidAmount,
    this.transactionId,
    this.reminderDaysBefore,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Sentinel stored in [paymentNote] to flag a credit-card statement that was
  /// auto-generated from the linked account's billing cycle, as opposed to a
  /// user-created bill. It is an internal marker only and must never be shown
  /// to the user — see [isAutoStatement] for the display-side guard.
  static const String autoStatementNote = '__auto_statement__';

  /// True when this bill is an auto-generated credit-card statement (it carries
  /// [autoStatementNote] in [paymentNote]). Used to exclude it from the
  /// recurring auto-copy guard and to suppress the raw marker in the UI.
  bool get isAutoStatement =>
      billType == BillType.creditCard && paymentNote == autoStatementNote;

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      // Null-tolerant: a corrupt cloud row (missing amount/dueDay/etc.) loads
      // with safe defaults instead of throwing out of sync and being dropped.
      // Review-and-fix in-app is far better than silent data loss.
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      billType: billTypeFromName(json['billType'] as String?),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      nextMonthAmount: (json['nextMonthAmount'] as num?)?.toDouble(),
      dueDay: (json['dueDay'] as num?)?.toInt() ?? 1,
      month: json['month'] as String? ?? '',
      categoryId: json['categoryId'] as String? ?? '',
      accountId: json['accountId'] as String?,
      paymentNote: json['paymentNote'] as String?,
      isRecurring: json['isRecurring'] as bool? ?? false,
      recurrenceType: recurrenceTypeFromName(json['recurrenceType'] as String?),
      seriesId: json['seriesId'] as String?,
      isPaid: json['isPaid'] as bool? ?? false,
      paidDate: json['paidDate'] != null
          ? DateTime.parse(json['paidDate'] as String)
          : null,
      paidAmount: (json['paidAmount'] as num?)?.toDouble(),
      transactionId: json['transactionId'] as String?,
      reminderDaysBefore: (json['reminderDaysBefore'] as num?)?.toInt(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
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
        'seriesId': seriesId,
        'isPaid': isPaid,
        'paidDate': paidDate?.toIso8601String(),
        'paidAmount': paidAmount,
        'transactionId': transactionId,
        'reminderDaysBefore': reminderDaysBefore,
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
    Object? accountId = _kUnset,
    String? paymentNote,
    bool? isRecurring,
    RecurrenceType? recurrenceType,
    // Sentinel-guarded so switching a bill off recurring can drop it out of its
    // series; `field ?? this.field` would leave the stale link behind.
    Object? seriesId = _kUnset,
    bool? isPaid,
    // Sentinel-guarded so undoing a payment can clear the settlement fields back
    // out; `field ?? this.field` never could, which left an un-paid bill still
    // carrying its old paid date/amount and ledger link.
    Object? paidDate = _kUnset,
    Object? paidAmount = _kUnset,
    Object? transactionId = _kUnset,
    Object? reminderDaysBefore = _kUnset,
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
      accountId:
          identical(accountId, _kUnset) ? this.accountId : accountId as String?,
      paymentNote: paymentNote ?? this.paymentNote,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      seriesId:
          identical(seriesId, _kUnset) ? this.seriesId : seriesId as String?,
      isPaid: isPaid ?? this.isPaid,
      paidDate:
          identical(paidDate, _kUnset) ? this.paidDate : paidDate as DateTime?,
      // Through num, not a straight `as double?`: the sentinel makes this
      // parameter Object?, which switches off the int→double coercion a
      // `double` slot would have applied — so an integer argument
      // (`paidAmount: 500`) arrives still an int and a double cast throws.
      paidAmount: identical(paidAmount, _kUnset)
          ? this.paidAmount
          : (paidAmount as num?)?.toDouble(),
      transactionId: identical(transactionId, _kUnset)
          ? this.transactionId
          : transactionId as String?,
      reminderDaysBefore: identical(reminderDaysBefore, _kUnset)
          ? this.reminderDaysBefore
          : reminderDaysBefore as int?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
