import 'transaction_record.dart';

// Represents a purchase split into equal monthly payments.
// Each month the installment is "due", and paying it creates a
// TransactionRecord with installmentId linking back to this installment.
//
// Examples: credit card 0% plans (3/6/12/24 months), SPayLater, BillEase.
class Installment {
  final String id;
  final String name; // "MacBook Pro 14"" / "Braces DP"
  final String accountId; // credit card / BNPL account being charged
  final double totalAmount; // original purchase price
  final double monthlyAmount; // amount per payment
  final int totalMonths; // total number of payments
  final String startMonth; // 'YYYY-MM' — first payment month
  final DateTime? purchaseDate; // date the installment purchase was made
  final int deferralMonths; // months first payment is deferred (0 = none)
  final double
      interestRate; // monthly add-on interest rate in percent (0.0 = 0% promo)
  final String? note;
  final String?
      categoryId; // category of the original purchase (e.g. tech, food)
  final bool isActive; // false = cancelled early
  final DateTime updatedAt;

  Installment({
    required this.id,
    required this.name,
    required this.accountId,
    required this.totalAmount,
    required this.monthlyAmount,
    required this.totalMonths,
    required this.startMonth,
    this.purchaseDate,
    this.deferralMonths = 0,
    this.interestRate = 0.0,
    this.note,
    this.categoryId,
    this.isActive = true,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether this installment incurs interest.
  bool get hasInterest => interestRate > 0;

  /// Monthly interest amount charged per payment period.
  double get monthlyInterest =>
      hasInterest ? (totalAmount * (interestRate / 100.0)) : 0.0;

  /// Total interest charged over the lifetime of the installment.
  double get totalInterest => monthlyInterest * totalMonths;

  /// Total payable amount (original purchase price / principal + total interest).
  double get totalPayable => totalAmount + totalInterest;

  /// Computes the suggested monthly payment for a [principal] amount split across [months]
  /// at a monthly add-on [monthlyRate] in percent.
  static double computeMonthlyAmount({
    required double principal,
    required int months,
    double monthlyRate = 0.0,
  }) {
    if (months <= 0) return principal;
    final monthlyPrincipal = principal / months;
    final monthlyInterest = principal * (monthlyRate / 100.0);
    return monthlyPrincipal + monthlyInterest;
  }

  // The 'YYYY-MM' key of the final payment month.
  String get endMonth => _offsetMonth(startMonth, totalMonths - 1);

  // Whether this installment has a payment due in [month].
  bool isDueIn(String month) =>
      isActive &&
      month.compareTo(startMonth) >= 0 &&
      month.compareTo(endMonth) <= 0;

  // The 'YYYY-MM' key for payment index [i] (0-based).
  String monthForIndex(int i) => _offsetMonth(startMonth, i);

  /// How many payments have been recorded for this installment in [transactions].
  int paidCount(Iterable<TransactionRecord> transactions) => transactions
      .where((t) => t.installmentId == id && !t.isInstallment)
      .length;

  /// Remaining unpaid/unbilled payment periods.
  int remainingMonths(Iterable<TransactionRecord> transactions) =>
      (totalMonths - paidCount(transactions)).clamp(0, totalMonths);

  /// Total unbilled principal remaining to be charged.
  double remainingAmount(Iterable<TransactionRecord> transactions) =>
      remainingMonths(transactions) * monthlyAmount;

  /// Total unbilled installment debt across all active installments for [accountId].
  static double totalUnbilledForAccount(
    String accountId,
    Iterable<Installment> installments,
    Iterable<TransactionRecord> transactions,
  ) {
    var total = 0.0;
    for (final inst in installments) {
      if (!inst.isActive || inst.accountId != accountId) continue;
      total += inst.remainingAmount(transactions);
    }
    return total;
  }

  static String _offsetMonth(String monthKey, int months) {
    final date = DateTime.parse('$monthKey-01');
    final result = DateTime(date.year, date.month + months);
    return '${result.year}-${result.month.toString().padLeft(2, '0')}';
  }

  factory Installment.fromJson(Map<String, dynamic> json) {
    return Installment(
      id: json['id'] as String,
      name: json['name'] as String,
      accountId: json['accountId'] as String,
      totalAmount: (json['totalAmount'] as num).toDouble(),
      monthlyAmount: (json['monthlyAmount'] as num).toDouble(),
      totalMonths: json['totalMonths'] as int,
      startMonth: json['startMonth'] as String,
      purchaseDate: json['purchaseDate'] != null
          ? DateTime.tryParse(json['purchaseDate'] as String)
          : null,
      deferralMonths: json['deferralMonths'] as int? ?? 0,
      interestRate: (json['interestRate'] as num?)?.toDouble() ?? 0.0,
      note: json['note'] as String?,
      categoryId: json['categoryId'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'accountId': accountId,
        'totalAmount': totalAmount,
        'monthlyAmount': monthlyAmount,
        'totalMonths': totalMonths,
        'startMonth': startMonth,
        if (purchaseDate != null)
          'purchaseDate': purchaseDate!.toIso8601String(),
        if (deferralMonths > 0) 'deferralMonths': deferralMonths,
        if (interestRate > 0) 'interestRate': interestRate,
        'note': note,
        if (categoryId != null) 'categoryId': categoryId,
        'isActive': isActive,
        'updatedAt': updatedAt.toIso8601String(),
      };

  Installment copyWith({
    String? name,
    String? accountId,
    double? totalAmount,
    double? monthlyAmount,
    int? totalMonths,
    String? startMonth,
    DateTime? purchaseDate,
    int? deferralMonths,
    double? interestRate,
    String? note,
    String? categoryId,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return Installment(
      id: id,
      name: name ?? this.name,
      accountId: accountId ?? this.accountId,
      totalAmount: totalAmount ?? this.totalAmount,
      monthlyAmount: monthlyAmount ?? this.monthlyAmount,
      totalMonths: totalMonths ?? this.totalMonths,
      startMonth: startMonth ?? this.startMonth,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      deferralMonths: deferralMonths ?? this.deferralMonths,
      interestRate: interestRate ?? this.interestRate,
      note: note ?? this.note,
      categoryId: categoryId ?? this.categoryId,
      isActive: isActive ?? this.isActive,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
