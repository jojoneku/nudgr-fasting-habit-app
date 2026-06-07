/// Unit a grocery item is counted in. [piece]/[pack] are whole-count; the rest
/// are measured amounts where the price is "per unit".
enum ItemUnit { piece, pack, kilogram, gram, liter, milliliter }

extension ItemUnitX on ItemUnit {
  /// Short label used in price suffixes, e.g. 'kg'.
  String get label => switch (this) {
        ItemUnit.piece => 'pc',
        ItemUnit.pack => 'pack',
        ItemUnit.kilogram => 'kg',
        ItemUnit.gram => 'g',
        ItemUnit.liter => 'L',
        ItemUnit.milliliter => 'mL',
      };

  /// Whether this unit is a whole count (price shown as "each") vs. a measured
  /// amount (price shown as "/kg").
  bool get isCount => this == ItemUnit.piece || this == ItemUnit.pack;

  /// Price suffix, e.g. 'each' for pieces or '/kg' for weight.
  String get priceSuffix => isCount ? 'each' : '/$label';

  /// Sensible +/- step for the quantity stepper.
  double get step => switch (this) {
        ItemUnit.kilogram || ItemUnit.liter => 0.25,
        ItemUnit.gram || ItemUnit.milliliter => 50,
        ItemUnit.piece || ItemUnit.pack => 1,
      };

  /// Renders a quantity for display, e.g. '×2', '3 packs', '1.5 kg'.
  String quantityLabel(double quantity) {
    final n = quantity == quantity.truncateToDouble()
        ? quantity.toInt().toString()
        : quantity.toString();
    return switch (this) {
      ItemUnit.piece => '×$n',
      ItemUnit.pack => '$n ${quantity == 1 ? 'pack' : 'packs'}',
      _ => '$n $label',
    };
  }
}
