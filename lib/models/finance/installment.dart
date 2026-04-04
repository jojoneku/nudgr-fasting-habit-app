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
  final String? note;
  final bool isActive; // false = cancelled early

  const Installment({
    required this.id,
    required this.name,
    required this.accountId,
    required this.totalAmount,
    required this.monthlyAmount,
    required this.totalMonths,
    required this.startMonth,
    this.note,
    this.isActive = true,
  });

  // The 'YYYY-MM' key of the final payment month.
  String get endMonth => _offsetMonth(startMonth, totalMonths - 1);

  // Whether this installment has a payment due in [month].
  bool isDueIn(String month) =>
      isActive &&
      month.compareTo(startMonth) >= 0 &&
      month.compareTo(endMonth) <= 0;

  // The 'YYYY-MM' key for payment index [i] (0-based).
  String monthForIndex(int i) => _offsetMonth(startMonth, i);

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
      note: json['note'] as String?,
      isActive: json['isActive'] as bool? ?? true,
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
        'note': note,
        'isActive': isActive,
      };

  Installment copyWith({
    String? name,
    String? accountId,
    double? totalAmount,
    double? monthlyAmount,
    int? totalMonths,
    String? startMonth,
    String? note,
    bool? isActive,
  }) {
    return Installment(
      id: id,
      name: name ?? this.name,
      accountId: accountId ?? this.accountId,
      totalAmount: totalAmount ?? this.totalAmount,
      monthlyAmount: monthlyAmount ?? this.monthlyAmount,
      totalMonths: totalMonths ?? this.totalMonths,
      startMonth: startMonth ?? this.startMonth,
      note: note ?? this.note,
      isActive: isActive ?? this.isActive,
    );
  }
}
