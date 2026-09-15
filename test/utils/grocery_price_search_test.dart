import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/grocery/item_unit.dart';
import 'package:intermittent_fasting/models/grocery/remembered_price.dart';
import 'package:intermittent_fasting/utils/grocery_price_search.dart';

RememberedPrice _p(
  String name, {
  double price = 10,
  int seen = 1,
  ItemUnit unit = ItemUnit.piece,
  String? barcode,
  DateTime? lastSeen,
}) {
  return RememberedPrice(
    key: RememberedPrice.keyFor(barcode: barcode, name: name),
    displayName: name,
    lastPrice: price,
    unit: unit,
    lastSeen: lastSeen ?? DateTime(2026, 1, 1),
    timesSeen: seen,
    barcode: barcode,
  );
}

List<String> _names(List<RememberedPrice> results) =>
    results.map((r) => r.displayName).toList();

void main() {
  group('searchPriceMemory', () {
    final memory = [
      _p('Bear Brand 1L', price: 92),
      _p('Bear Brand powdered milk 240g', price: 128),
      _p('Eggs (tray)', price: 250, seen: 5),
      _p('Rice 5kg', price: 320, unit: ItemUnit.kilogram),
    ];

    test('a partial name keeps every past variant until one is chosen', () {
      final results = searchPriceMemory('bear', memory);
      expect(_names(results),
          containsAll(['Bear Brand 1L', 'Bear Brand powdered milk 240g']));
      expect(results.length, 2);
    });

    test('typing the full name still returns that item', () {
      final results = searchPriceMemory('Bear Brand 1L', memory);
      expect(results.first.displayName, 'Bear Brand 1L');
      expect(results.first.lastPrice, 92);
    });

    test('an exact match outranks a longer partial match', () {
      final results = searchPriceMemory('bear brand 1l', memory);
      expect(results.first.displayName, 'Bear Brand 1L');
    });

    test('a mid-name word matches ("brand", "powdered")', () {
      expect(_names(searchPriceMemory('powdered', memory)),
          ['Bear Brand powdered milk 240g']);
      expect(searchPriceMemory('brand', memory).length, 2);
    });

    test('a glued query reaches the spaced name ("bearbrand")', () {
      expect(searchPriceMemory('bearbrand', memory).length, 2);
    });

    test('a typo still matches ("bera brand" → Bear Brand)', () {
      expect(searchPriceMemory('bera', memory), isNotEmpty);
    });

    test('non-adjacent tokens match ("bear 240")', () {
      expect(_names(searchPriceMemory('bear 240', memory)),
          ['Bear Brand powdered milk 240g']);
    });

    test('an unrelated query matches nothing', () {
      expect(searchPriceMemory('zzzqqq', memory), isEmpty);
    });

    test('an empty query returns the most-bought items first', () {
      final results = searchPriceMemory('', memory);
      expect(results.first.displayName, 'Eggs (tray)'); // seen 5×
      expect(results.length, 4);
    });

    test('empty memory yields no suggestions', () {
      expect(searchPriceMemory('bear', const []), isEmpty);
    });

    test('results are capped at the limit', () {
      expect(searchPriceMemory('', memory, limit: 2).length, 2);
    });

    test('frequency breaks ties within a tier', () {
      final tied = [
        _p('Milk A', seen: 1),
        _p('Milk B', seen: 9),
      ];
      expect(_names(searchPriceMemory('milk', tied)), ['Milk B', 'Milk A']);
    });

    test('a barcode-keyed item can be recalled by its code', () {
      final withBarcode = [_p('Bear Brand 1L', barcode: '4800361')];
      expect(searchPriceMemory('48003', withBarcode), isNotEmpty);
    });
  });
}
