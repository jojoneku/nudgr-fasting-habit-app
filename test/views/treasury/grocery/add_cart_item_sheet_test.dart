import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/grocery/cart_item.dart';
import 'package:intermittent_fasting/models/grocery/item_unit.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/grocery/add_cart_item_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

import '../../../mocks.mocks.dart';

/// The add-item sheet is where a whole grocery trip gets typed in, one item at
/// a time. It has to recall what the shopper bought before — with the price, so
/// they can cross-check the shelf tag — and keep "Add & next" the obvious
/// action, since that is the loop they stay in for twenty items.
void main() {
  late MockStorageService storage;

  setUp(() {
    storage = MockStorageService();
    when(storage.loadGroceryCart()).thenAnswer((_) async => []);
    when(storage.loadGroceryPriceMemory()).thenAnswer((_) async => []);
    when(storage.loadGroceryBudget()).thenAnswer((_) async => null);
    when(storage.loadGroceryTripHistory()).thenAnswer((_) async => []);
  });

  Future<GroceryCartPresenter> presenterWithMemory() async {
    final p = GroceryCartPresenter(storage);
    await p.load();
    await p.addItem(name: 'Bear Brand 1L', unitPrice: 92);
    await p.addItem(name: 'Bear Brand powdered milk 240g', unitPrice: 128);
    await p.addItem(name: 'Rice 5kg', unitPrice: 320, unit: ItemUnit.kilogram);
    await p.clearCart();
    return p;
  }

  Widget host(GroceryCartPresenter presenter) => MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AddCartItemSheet(presenter: presenter),
          ),
        ),
      );

  testWidgets('typing a partial name lists every past match with its price',
      (tester) async {
    final presenter = await presenterWithMemory();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'bear');
    await tester.pumpAndSettle();

    // Both variants stay listed until one is chosen or the name is typed out.
    expect(find.textContaining('Bear Brand 1L', findRichText: true),
        findsOneWidget);
    expect(
        find.textContaining('Bear Brand powdered milk 240g',
            findRichText: true),
        findsOneWidget);
    // Unrelated memory is filtered out.
    expect(find.textContaining('Rice 5kg', findRichText: true), findsNothing);
    // The last paid price rides along for cross-checking at the shelf.
    expect(find.text('₱92.00 each'), findsOneWidget);
    expect(find.text('₱128.00 each'), findsOneWidget);
  });

  testWidgets('tapping a suggestion fills the name and keeps it an estimate',
      (tester) async {
    final presenter = await presenterWithMemory();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'powdered');
    await tester.pumpAndSettle();
    await tester.tap(find.text('₱128.00 each'));
    await tester.pumpAndSettle();

    final nameField = tester.widget<TextField>(find.byType(TextField).first);
    expect(nameField.controller?.text, 'Bear Brand powdered milk 240g');

    await tester.tap(find.text('Add & next'));
    await tester.pumpAndSettle();

    expect(presenter.itemCount, 1);
    // Price left blank ⇒ auto-filled from memory and flagged as an estimate,
    // not a price confirmed at the shelf.
    expect(presenter.items.first.priceState, PriceState.remembered);
    expect(presenter.items.first.unitPrice, 128);
  });

  testWidgets('"Use it" confirms the remembered price instead of estimating',
      (tester) async {
    final presenter = await presenterWithMemory();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Bear Brand 1L');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use it'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add & next'));
    await tester.pumpAndSettle();

    expect(presenter.items.first.priceState, PriceState.confirmed);
    expect(presenter.items.first.unitPrice, 92);
  });

  testWidgets('the quantity steppers move by the selected unit\'s increment',
      (tester) async {
    final presenter = await presenterWithMemory();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    // Pieces step by 1.
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    // Kilograms step by 0.25.
    await tester.tap(find.widgetWithText(ChoiceChip, 'kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('2.25'), findsOneWidget);

    await tester.tap(find.byTooltip('Less'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('the quantity stepper never goes to zero', (tester) async {
    final presenter = await presenterWithMemory();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Less'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('"Add & next" is the filled primary action', (tester) async {
    final presenter = await presenterWithMemory();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.text('Add & next'),
        matching: find.byType(AppPrimaryButton),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Add & close'),
        matching: find.byType(AppSecondaryButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a brand-new item shows no suggestions and adds unpriced',
      (tester) async {
    final presenter = GroceryCartPresenter(storage);
    await presenter.load();
    await tester.pumpWidget(host(presenter));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Tinapa');
    await tester.pumpAndSettle();
    expect(find.textContaining('bought', findRichText: true), findsNothing);

    await tester.tap(find.text('Add & next'));
    await tester.pumpAndSettle();

    expect(presenter.items.first.priceState, PriceState.unknown);
  });
}
