import 'item_unit.dart';

/// How a cart item's price was obtained — drives how it counts toward the
/// running total and how it is rendered.
///
/// * [confirmed] — the user typed (or OCR-confirmed) the price this trip; exact.
/// * [remembered] — auto-filled from the user's price memory (last paid price);
///   shown as an estimate (`~`) until confirmed.
/// * [unknown] — no price available; excluded from the total and surfaced as
///   "N unpriced" so the running total never silently understates the spend.
enum PriceState { confirmed, remembered, unknown }

/// Where the item entry originated. [manual] is the only Phase-1 source; the
/// others are reserved for the OCR / barcode follow-up phases.
enum ItemSource { manual, ocr, barcode }

/// A single line in the active grocery cart.
///
/// Immutable; mutations go through [copyWith]. The running-total math lives in
/// [GroceryCartPresenter], not here — this model only holds data + derived
/// per-line values.
class CartItem {
  final String id;
  final String name;

  /// Quantity is a [double] so half-units (0.5 kg) work. Cosmetic unit labels
  /// are deferred to a later phase.
  final double quantity;

  /// Null only when [priceState] is [PriceState.unknown].
  final double? unitPrice;
  final PriceState priceState;
  final ItemSource source;

  /// Unit the [quantity] is measured in (pieces, kg, …). The price is per unit.
  final ItemUnit unit;

  /// Optional barcode — used as the price-memory key when present. Null in the
  /// manual-entry Phase 1 path.
  final String? barcode;
  final DateTime addedAt;

  const CartItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.priceState,
    required this.addedAt,
    this.source = ItemSource.manual,
    this.unit = ItemUnit.piece,
    this.barcode,
  });

  /// Line subtotal. Unknown-priced items contribute 0 (and are counted
  /// separately by the presenter), so this never throws on a null price.
  double get lineTotal => (unitPrice ?? 0) * quantity;

  bool get isPriced => unitPrice != null;

  CartItem copyWith({
    String? name,
    double? quantity,
    double? unitPrice,
    PriceState? priceState,
    ItemSource? source,
    ItemUnit? unit,
    String? barcode,
    DateTime? addedAt,
  }) {
    return CartItem(
      id: id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      priceState: priceState ?? this.priceState,
      source: source ?? this.source,
      unit: unit ?? this.unit,
      barcode: barcode ?? this.barcode,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as String,
      name: json['name'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unitPrice: (json['unitPrice'] as num?)?.toDouble(),
      priceState: PriceState.values.byName(json['priceState'] as String),
      source: ItemSource.values.byName(
        json['source'] as String? ?? ItemSource.manual.name,
      ),
      unit: ItemUnit.values.byName(
        json['unit'] as String? ?? ItemUnit.piece.name,
      ),
      barcode: json['barcode'] as String?,
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'priceState': priceState.name,
        'source': source.name,
        'unit': unit.name,
        'barcode': barcode,
        'addedAt': addedAt.toIso8601String(),
      };
}
