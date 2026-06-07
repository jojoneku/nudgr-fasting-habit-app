import 'cart_item.dart';

/// A completed shopping trip — a snapshot of the cart at checkout. Kept in
/// history so the user can review past trips or repeat one (re-adding its items
/// to a fresh cart, re-priced from current memory).
class SavedTrip {
  final String id;
  final DateTime savedAt;

  /// Snapshot of the items as they were at checkout.
  final List<CartItem> items;

  /// Totals captured at checkout, so history shows what was actually spent
  /// even if price memory changes later.
  final double confirmedTotal;
  final double estimatedTotal;
  final int unpricedCount;

  /// True when the trip was posted to the Ledger as an outflow.
  final bool postedToLedger;

  const SavedTrip({
    required this.id,
    required this.savedAt,
    required this.items,
    required this.confirmedTotal,
    required this.estimatedTotal,
    required this.unpricedCount,
    this.postedToLedger = false,
  });

  double get total => confirmedTotal + estimatedTotal;
  int get itemCount => items.length;

  factory SavedTrip.fromJson(Map<String, dynamic> json) {
    return SavedTrip(
      id: json['id'] as String,
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      items: (json['items'] as List? ?? [])
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      confirmedTotal: (json['confirmedTotal'] as num?)?.toDouble() ?? 0,
      estimatedTotal: (json['estimatedTotal'] as num?)?.toDouble() ?? 0,
      unpricedCount: (json['unpricedCount'] as num?)?.toInt() ?? 0,
      postedToLedger: json['postedToLedger'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'savedAt': savedAt.toIso8601String(),
        'items': items.map((e) => e.toJson()).toList(),
        'confirmedTotal': confirmedTotal,
        'estimatedTotal': estimatedTotal,
        'unpricedCount': unpricedCount,
        'postedToLedger': postedToLedger,
      };
}
