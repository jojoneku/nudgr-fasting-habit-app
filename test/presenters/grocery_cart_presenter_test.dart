import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/grocery/cart_item.dart';
import 'package:intermittent_fasting/models/grocery/remembered_price.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import '../mocks.mocks.dart';

void main() {
  group('GroceryCartPresenter', () {
    late MockStorageService storage;

    setUp(() {
      storage = MockStorageService();
      when(storage.loadGroceryCart()).thenAnswer((_) async => []);
      when(storage.loadGroceryPriceMemory()).thenAnswer((_) async => []);
      when(storage.loadGroceryBudget()).thenAnswer((_) async => null);
    });

    Future<GroceryCartPresenter> build() async {
      final p = GroceryCartPresenter(storage);
      await p.load();
      return p;
    }

    test('adding an item with a price marks it confirmed and totals it',
        () async {
      final p = await build();
      await p.addItem(name: 'Eggs', quantity: 2, unitPrice: 8.5);

      expect(p.itemCount, 1);
      expect(p.items.first.priceState, PriceState.confirmed);
      expect(p.confirmedTotal, 17.0); // 8.5 × 2
      expect(p.estimatedTotal, 0);
      expect(p.unpricedCount, 0);
      expect(p.grandTotal, 17.0);
    });

    test('confirming a price teaches the price memory', () async {
      final p = await build();
      await p.addItem(name: 'Bear Brand 320g', unitPrice: 58);

      final remembered = p.lookup(name: 'bear brand 320g');
      expect(remembered, isNotNull);
      expect(remembered!.lastPrice, 58);
      verify(storage.saveGroceryPriceMemory(any)).called(greaterThan(0));
    });

    test('an item with no price and no memory is flagged unknown', () async {
      final p = await build();
      await p.addItem(name: 'Mystery item');

      expect(p.items.first.priceState, PriceState.unknown);
      expect(p.items.first.unitPrice, isNull);
      expect(p.unpricedCount, 1);
      expect(p.grandTotal, 0); // unknown items never inflate the total
    });

    test('a remembered price auto-fills as an estimate (case-insensitive)',
        () async {
      when(storage.loadGroceryPriceMemory()).thenAnswer((_) async => [
            RememberedPrice(
              key: RememberedPrice.keyFor(name: 'rice'),
              displayName: 'Rice',
              lastPrice: 55,
              lastSeen: DateTime(2026, 1, 1),
              timesSeen: 3,
            ),
          ]);
      final p = await build();

      await p.addItem(name: 'RICE', quantity: 2); // no price supplied

      expect(p.items.first.priceState, PriceState.remembered);
      expect(p.items.first.unitPrice, 55);
      expect(p.estimatedTotal, 110); // 55 × 2
      expect(p.confirmedTotal, 0);
      expect(p.grandTotal, 110);
    });

    test('setPrice converts an unknown item to confirmed and updates total',
        () async {
      final p = await build();
      await p.addItem(name: 'Onions');
      final id = p.items.first.id;

      await p.setPrice(id, 30);

      expect(p.items.first.priceState, PriceState.confirmed);
      expect(p.unpricedCount, 0);
      expect(p.grandTotal, 30);
      // and it is now remembered for next time
      expect(p.lookup(name: 'Onions')?.lastPrice, 30);
    });

    test('updateQuantity scales the line total; zero removes the item',
        () async {
      final p = await build();
      await p.addItem(name: 'Milk', unitPrice: 40);
      final id = p.items.first.id;

      await p.updateQuantity(id, 3);
      expect(p.grandTotal, 120);

      await p.updateQuantity(id, 0);
      expect(p.itemCount, 0);
    });

    test('budget remaining and over-budget flag track the running total',
        () async {
      final p = await build();
      await p.setBudget(100);
      await p.addItem(name: 'Coffee', unitPrice: 70);

      expect(p.hasBudget, isTrue);
      expect(p.budgetRemaining, 30);
      expect(p.isOverBudget, isFalse);

      await p.addItem(name: 'Sugar', unitPrice: 50);
      expect(p.budgetRemaining, -20);
      expect(p.isOverBudget, isTrue);
    });

    test('clearCart empties items but retains price memory', () async {
      final p = await build();
      await p.addItem(name: 'Bread', unitPrice: 45);

      await p.clearCart();

      expect(p.isEmpty, isTrue);
      expect(p.grandTotal, 0);
      // memory survives the trip
      expect(p.lookup(name: 'Bread')?.lastPrice, 45);
    });
  });
}
