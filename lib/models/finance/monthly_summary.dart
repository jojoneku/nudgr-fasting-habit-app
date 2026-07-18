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

  /// Net worth at month close (assets − held − liabilities). Nullable for
  /// backward compatibility: summaries closed before this field existed (and
  /// those reconstructed from a legacy import) may not have it, in which case
  /// consumers fall back to reconstructing from [accountSnapshots].
  final double? netWorth;
  final Map<String, double> categorySpend; // categoryId → total spent

  /// Net amount deliberately set aside into savings/goal/sinking-fund accounts
  /// this month: transfers into savings pockets minus transfers back out. This
  /// is distinct from [netSavings] (income − expenses, the cash-flow surplus) —
  /// it tracks what actually landed in a dedicated pocket. Nullable for backward
  /// compatibility: summaries closed before this field existed won't have it.
  final double? savingsContribution;
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
    this.netWorth,
    this.savingsContribution,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Share of the month's income kept as net savings ([netSavings] /
  /// [totalInflow]), 0–1. Null when there was no income to divide by, so the UI
  /// can show "—" instead of a divide-by-zero. Powers the History "N% saved".
  double? get savingsRate => totalInflow > 0 ? netSavings / totalInflow : null;

  MonthlySummary copyWith({
    double? totalInflow,
    double? totalOutflow,
    double? netSavings,
    Map<String, double>? categorySpend,
    double? savingsContribution,
    DateTime? updatedAt,
  }) {
    return MonthlySummary(
      month: month,
      totalInflow: totalInflow ?? this.totalInflow,
      totalOutflow: totalOutflow ?? this.totalOutflow,
      totalBills: totalBills,
      totalBillsPaid: totalBillsPaid,
      billCount: billCount,
      billsPaidCount: billsPaidCount,
      totalReceivables: totalReceivables,
      totalReceived: totalReceived,
      receivableCount: receivableCount,
      netSavings: netSavings ?? this.netSavings,
      endingCash: endingCash,
      accountSnapshots: accountSnapshots,
      categorySpend: categorySpend ?? this.categorySpend,
      netWorth: netWorth,
      savingsContribution: savingsContribution ?? this.savingsContribution,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

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
      netWorth: (json['netWorth'] as num?)?.toDouble(),
      savingsContribution: (json['savingsContribution'] as num?)?.toDouble(),
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
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
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
        'netWorth': netWorth,
        'savingsContribution': savingsContribution,
        'accountSnapshots': accountSnapshots,
        'categorySpend': categorySpend,
        'updatedAt': updatedAt.toIso8601String(),
      };
}
