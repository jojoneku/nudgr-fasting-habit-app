import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/grocery/cart_item.dart';
import 'package:intermittent_fasting/models/grocery/item_unit.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/grocery/price_book_screen.dart';

import '../../../mocks.mocks.dart';

/// The price book is the surface that makes the learned prices real: you can
/// see the whole list, correct one that changed, and add a price off a receipt
/// without pretending to shop.
void main() {
  late MockStorageService storage;

  setUp(() {
    storage = MockStorageService();
    when(storage.loadGroceryCart()).thenAnswer((_) async => []);
    when(storage.loadGroceryPriceMemory()).thenAnswer((_) async => []);
    when(storage.loadGroceryBudget()).thenAnswer((_) async => null);
    when(storage.loadGroceryTripHistory()).thenAnswer((_) async => []);
  });

  Future<GroceryCartPresenter> stocked() async {
    final p = GroceryCartPresenter(storage);
    await p.load();
    await p.addItem(name: 'Bear Brand 1L', unitPrice: 92);
    await p.addItem(name: 'Rice 5kg', unitPrice: 320, unit: ItemUnit.kilogram);
    await p.clearCart();
    return p;
  }

  Widget host(GroceryCartPresenter presenter) => MaterialApp(
        theme: buildDarkTheme(),
        home: PriceBookScreen(presenter: presenter),
      );

  testWidgets('lists every saved price with its unit suffix', (tester) async {
    final presenter = await stocked();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    expect(find.text('Bear Brand 1L'), findsOneWidget);
    expect(find.text('₱92.00'), findsOneWidget);
    expect(find.text('each'), findsOneWidget);
    expect(find.text('Rice 5kg'), findsOneWidget);
    expect(find.text('₱320.00'), findsOneWidget);
    expect(find.text('/kg'), findsOneWidget);
    expect(find.text('2 items · ₱412.00 for one of each'), findsOneWidget);
  });

  testWidgets('search narrows the list', (tester) async {
    final presenter = await stocked();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'bear');
    await tester.pumpAndSettle();

    expect(find.text('Bear Brand 1L'), findsOneWidget);
    expect(find.text('Rice 5kg'), findsNothing);
  });

  testWidgets('a search with no match says so instead of showing nothing',
      (tester) async {
    final presenter = await stocked();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'zzzqqq');
    await tester.pumpAndSettle();

    expect(find.text('No match'), findsOneWidget);
  });

  testWidgets('adding a price off a receipt saves it without a cart line',
      (tester) async {
    final presenter = GroceryCartPresenter(storage);
    await presenter.load();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    expect(find.text('No prices yet'), findsOneWidget);

    await tester.tap(find.text('Add price'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '128');
    await tester.enterText(
        find.byType(TextField).at(1), 'Bear Brand powdered 240g');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save price'));
    await tester.pumpAndSettle();

    expect(presenter.lookup(name: 'Bear Brand powdered 240g')!.lastPrice, 128);
    expect(presenter.isEmpty, isTrue); // nothing landed in the cart
    expect(find.text('Bear Brand powdered 240g'), findsOneWidget);
  });

  testWidgets('tapping a row opens it for correction', (tester) async {
    final presenter = await stocked();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bear Brand 1L'));
    await tester.pumpAndSettle();
    expect(find.text('Edit price'), findsOneWidget);

    // The sheet opens pre-filled with the current price.
    final priceField = tester.widget<TextField>(find.byType(TextField).last);
    expect(priceField.controller?.text, '92.00');

    await tester.enterText(find.byType(TextField).last, '95');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update price'));
    await tester.pumpAndSettle();

    expect(presenter.lookup(name: 'Bear Brand 1L')!.lastPrice, 95);
  });

  testWidgets('the cart shortcut adds the item as an estimate', (tester) async {
    final presenter = await stocked();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add to cart').first);
    await tester.pumpAndSettle();

    expect(presenter.itemCount, 1);
    expect(presenter.items.first.priceState, PriceState.remembered);
  });
}
