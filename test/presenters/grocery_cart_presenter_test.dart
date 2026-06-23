import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/grocery/cart_item.dart';
import 'package:intermittent_fasting/models/grocery/item_unit.dart';
import 'package:intermittent_fasting/models/grocery/remembered_price.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import '../mocks.mocks.dart';

void main() {
  group('GroceryCartPresenter', () {
    late MockStorageService storage;

    setUp(() {
      storage = MockStorageService();
      when(storage.loadGroceryCart()).thenAnswer((_) async => []);
      when(storage.loadGroceryPriceMemory()).thenAnswer((_) async => []);
      when(storage.loadGroceryBudget()).thenAnswer((_) async => null);
      when(storage.loadGroceryTripHistory()).thenAnswer((_) async => []);
      // Loads needed when a real LedgerPresenter is wired in (checkout test).
      when(storage.loadAccounts()).thenAnswer((_) async => []);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(storage.loadTransactions()).thenAnswer((_) async => []);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
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

    test('totals round to centavos so an exact-budget cart is not over',
        () async {
      final p = await build();
      await p.setBudget(100);
      // 33.33 + 33.33 + 33.34 = 100.00 — drifts past 100 in raw double math.
      await p.addItem(name: 'A', unitPrice: 33.33);
      await p.addItem(name: 'B', unitPrice: 33.33);
      await p.addItem(name: 'C', unitPrice: 33.34);

      expect(p.grandTotal, 100.0);
      expect(p.isOverBudget, isFalse);
      expect(p.budgetRemaining, 0.0);
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

    test('unit is remembered and restored when the item is re-added', () async {
      final p = await build();
      await p.addItem(name: 'Rice', unitPrice: 55, unit: ItemUnit.kilogram);
      expect(p.lookup(name: 'Rice')?.unit, ItemUnit.kilogram);

      await p.clearCart();
      await p.addItem(name: 'Rice', quantity: 2); // no price/unit supplied
      final item = p.items.single;
      expect(item.priceState, PriceState.remembered);
      expect(item.unitPrice, 55);
      // line total uses the remembered per-kg price × quantity
      expect(p.estimatedTotal, 110);
    });

    test('checkout saves a trip, clears the cart, and records history',
        () async {
      final p = await build();
      await p.addItem(name: 'Eggs', quantity: 2, unitPrice: 8);
      await p.addItem(name: 'Mystery'); // unpriced

      final trip = await p.checkout();

      expect(trip, isNotNull);
      expect(trip!.confirmedTotal, 16);
      expect(trip.unpricedCount, 1);
      expect(trip.postedToLedger, isFalse);
      expect(p.isEmpty, isTrue);
      expect(p.tripHistory, hasLength(1));
    });

    test('checkout on an empty cart is a no-op', () async {
      final p = await build();
      final trip = await p.checkout();
      expect(trip, isNull);
      expect(p.tripHistory, isEmpty);
    });

    test('checkout posts an outflow to the ledger when requested', () async {
      final stats = MockStatsPresenter();
      final ledger = LedgerPresenter(storage, stats);
      await ledger.load();
      final p = GroceryCartPresenter(storage, ledger: ledger);
      await p.load();
      await p.addItem(name: 'Coffee', unitPrice: 120);

      final trip = await p.checkout(postToLedger: true, accountId: 'acc1');

      expect(trip!.postedToLedger, isTrue);
      final outflows = ledger.allTransactions
          .where((t) => t.type == TransactionType.outflow && t.amount == 120);
      expect(outflows, hasLength(1));
      expect(p.isEmpty, isTrue);
    });

    test('repeatTrip re-adds items to the cart, re-priced from memory',
        () async {
      final p = await build();
      await p.addItem(name: 'Milk', unitPrice: 40);
      await p.checkout();
      expect(p.isEmpty, isTrue);

      await p.repeatTrip(p.tripHistory.first.id);

      expect(p.items, hasLength(1));
      expect(p.items.single.name, 'Milk');
      // re-priced from memory → remembered estimate
      expect(p.items.single.priceState, PriceState.remembered);
      expect(p.items.single.unitPrice, 40);
    });

    test('deleteTrip removes a trip from history', () async {
      final p = await build();
      await p.addItem(name: 'Sugar', unitPrice: 50);
      await p.checkout();
      expect(p.tripHistory, hasLength(1));

      await p.deleteTrip(p.tripHistory.first.id);
      expect(p.tripHistory, isEmpty);
    });

    test('restoreItem re-inserts a removed item at its position', () async {
      final p = await build();
      await p.addItem(name: 'Eggs', unitPrice: 8);
      await p.addItem(name: 'Milk', unitPrice: 40);
      await p.addItem(name: 'Bread', unitPrice: 45);

      final removed = p.items[1]; // Milk
      await p.removeItem(removed.id);
      expect(p.items.map((i) => i.name), ['Eggs', 'Bread']);

      await p.restoreItem(removed, 1);
      expect(p.items.map((i) => i.name), ['Eggs', 'Milk', 'Bread']);
      // Same identity and confirmed price preserved (undo, not a fresh add).
      expect(p.items[1].id, removed.id);
      expect(p.items[1].unitPrice, 40);
    });

    test('restoreItem is a no-op if the id already exists', () async {
      final p = await build();
      await p.addItem(name: 'Eggs', unitPrice: 8);
      await p.restoreItem(p.items.first, 0);
      expect(p.itemCount, 1);
    });
  });
}
