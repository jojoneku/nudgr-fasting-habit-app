import 'item_unit.dart';

/// A learned price for an item the user has bought before. The price-memory is
/// a `Map<String, RememberedPrice>` keyed by [key]; on the next trip an item's
/// price auto-fills from here so the running total is accurate with no re-entry.
///
/// Since no reliable free Philippine grocery price API exists (Open Food Facts
/// in particular does not recognise PH products), this *is* the price source —
/// built up entirely from the user's own confirmed prices.
class RememberedPrice {
  /// Stable lookup key — `'barcode:<code>'` when a barcode is known, otherwise
  /// `'name:<normalized name>'`. Build via [keyFor].
  final String key;

  /// Human-friendly name to show in suggestions (preserves original casing).
  final String displayName;

  final double lastPrice;

  /// Unit the [lastPrice] applies to, so re-adding restores the right unit.
  final ItemUnit unit;
  final DateTime lastSeen;

  /// How many times this item has been confirmed — lets the UI rank frequent
  /// items and conveys confidence in the remembered price.
  final int timesSeen;

  final String? barcode;

  const RememberedPrice({
    required this.key,
    required this.displayName,
    required this.lastPrice,
    required this.lastSeen,
    this.unit = ItemUnit.piece,
    this.timesSeen = 1,
    this.barcode,
  });

  /// Normalizes an item identity into a stable memory key. Prefers the barcode
  /// (exact) and falls back to the lower-cased, whitespace-collapsed name.
  static String keyFor({String? barcode, required String name}) {
    if (barcode != null && barcode.trim().isNotEmpty) {
      return 'barcode:${barcode.trim()}';
    }
    final normalized =
        name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return 'name:$normalized';
  }

  RememberedPrice copyWith({
    String? displayName,
    double? lastPrice,
    ItemUnit? unit,
    DateTime? lastSeen,
    int? timesSeen,
    String? barcode,
  }) {
    return RememberedPrice(
      key: key,
      displayName: displayName ?? this.displayName,
      lastPrice: lastPrice ?? this.lastPrice,
      unit: unit ?? this.unit,
      lastSeen: lastSeen ?? this.lastSeen,
      timesSeen: timesSeen ?? this.timesSeen,
      barcode: barcode ?? this.barcode,
    );
  }

  factory RememberedPrice.fromJson(Map<String, dynamic> json) {
    return RememberedPrice(
      key: json['key'] as String,
      displayName: json['displayName'] as String,
      lastPrice: (json['lastPrice'] as num).toDouble(),
      unit: ItemUnit.values.byName(
        json['unit'] as String? ?? ItemUnit.piece.name,
      ),
      lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      timesSeen: (json['timesSeen'] as num?)?.toInt() ?? 1,
      barcode: json['barcode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'displayName': displayName,
        'lastPrice': lastPrice,
        'unit': unit.name,
        'lastSeen': lastSeen.toIso8601String(),
        'timesSeen': timesSeen,
        'barcode': barcode,
      };
}
