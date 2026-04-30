// Frozen snapshot computed and saved at month close.
// Never mutated after creation — represents the final state of a closed month.
class MonthlySummary {
  final String month; // 'YYYY-MM'
  final double totalInflow;
  final double totalOutflow;
  final double totalBills;
  final double totalBillsPaid;
  final int billCount;
  final int billsPaidCount;
  final double totalReceivables;
  final double totalReceived;
  final int receivableCount;
  final double netSavings; // inflow - outflow
  final double endingCash; // sum of all liquid account balances at close
  final Map<String, double> accountSnapshots; // accountId → balance
  final Map<String, double> categorySpend; // categoryId → total spent
  final DateTime updatedAt;

  MonthlySummary({
    required this.month,
    required this.totalInflow,
    required this.totalOutflow,
    required this.totalBills,
    required this.totalBillsPaid,
    required this.billCount,
    required this.billsPaidCount,
    required this.totalReceivables,
    required this.totalReceived,
    required this.receivableCount,
    required this.netSavings,
    required this.endingCash,
    required this.accountSnapshots,
    required this.categorySpend,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory MonthlySummary.fromJson(Map<String, dynamic> json) {
    return MonthlySummary(
      month: json['month'] as String,
      totalInflow: (json['totalInflow'] as num).toDouble(),
      totalOutflow: (json['totalOutflow'] as num).toDouble(),
      totalBills: (json['totalBills'] as num).toDouble(),
      totalBillsPaid: (json['totalBillsPaid'] as num).toDouble(),
      billCount: json['billCount'] as int,
      billsPaidCount: json['billsPaidCount'] as int,
      totalReceivables: (json['totalReceivables'] as num).toDouble(),
      totalReceived: (json['totalReceived'] as num).toDouble(),
      receivableCount: json['receivableCount'] as int,
      netSavings: (json['netSavings'] as num).toDouble(),
      endingCash: (json['endingCash'] as num).toDouble(),
      accountSnapshots: Map<String, double>.from(
        (json['accountSnapshots'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      ),
      categorySpend: Map<String, double>.from(
        (json['categorySpend'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      ),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'month': month,
        'totalInflow': totalInflow,
        'totalOutflow': totalOutflow,
        'totalBills': totalBills,
        'totalBillsPaid': totalBillsPaid,
        'billCount': billCount,
        'billsPaidCount': billsPaidCount,
        'totalReceivables': totalReceivables,
        'totalReceived': totalReceived,
        'receivableCount': receivableCount,
        'netSavings': netSavings,
        'endingCash': endingCash,
        'accountSnapshots': accountSnapshots,
        'categorySpend': categorySpend,
        'updatedAt': updatedAt.toIso8601String(),
      };
}
