import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/services/open_food_facts_service.dart';

void main() {
  group('OpenFoodFactsService.parseProduct', () {
    test('returns null when status is 0 (unknown barcode)', () {
      final result = OpenFoodFactsService.parseProduct(
        barcode: '1234567890123',
        json: {'status': 0},
      );
      expect(result, isNull);
    });

    test('returns null when product is missing', () {
      final result = OpenFoodFactsService.parseProduct(
        barcode: '1234567890123',
        json: {'status': 1},
      );
      expect(result, isNull);
    });

    test('returns null when calories are missing', () {
      final result = OpenFoodFactsService.parseProduct(
        barcode: '1234567890123',
        json: {
          'status': 1,
          'product': {
            'product_name': 'Some Snack',
            'brands': 'Unknown',
            'nutriments': {},
          },
        },
      );
      expect(result, isNull);
    });

    test('parses kcal_100g + macros', () {
      final result = OpenFoodFactsService.parseProduct(
        barcode: '4806507023109',
        json: {
          'status': 1,
          'product': {
            'product_name': 'Sterilized Milk',
            'brands': 'Bear Brand',
            'nutriments': {
              'energy-kcal_100g': 67,
              'proteins_100g': 3.2,
              'carbohydrates_100g': 4.8,
              'fat_100g': 3.7,
            },
            'image_small_url': 'https://images.openfoodfacts.org/x.jpg',
          },
        },
      );

      expect(result, isNotNull);
      expect(result!.entry.id, 'off_4806507023109');
      expect(result.entry.name, 'Bear Brand Sterilized Milk');
      expect(result.entry.caloriesPer100g, 67.0);
      expect(result.entry.proteinPer100g, 3.2);
      expect(result.entry.carbsPer100g, 4.8);
      expect(result.entry.fatPer100g, 3.7);
      expect(result.entry.category, 'Barcode (OpenFoodFacts)');
      expect(result.displayName, 'Bear Brand · Sterilized Milk');
      expect(result.imageUrl, isNotNull);
    });

    test('falls back from kJ when kcal missing', () {
      final result = OpenFoodFactsService.parseProduct(
        barcode: '5000159407236',
        json: {
          'status': 1,
          'product': {
            'product_name': 'Choco Bar',
            'brands': 'Some Brand',
            'nutriments': {
              'energy-kj_100g': 2000,
              'proteins_100g': 5,
              'carbohydrates_100g': 60,
              'fat_100g': 25,
            },
          },
        },
      );
      expect(result, isNotNull);
      // 2000 kJ * 0.239 ≈ 478 kcal
      expect(result!.entry.caloriesPer100g, closeTo(478, 1));
    });

    test('does not duplicate brand when product_name already includes it', () {
      final result = OpenFoodFactsService.parseProduct(
        barcode: '0000000000001',
        json: {
          'status': 1,
          'product': {
            'product_name': 'Bear Brand Powdered Milk',
            'brands': 'Bear Brand',
            'nutriments': {'energy-kcal_100g': 480},
          },
        },
      );
      expect(result!.entry.name, 'Bear Brand Powdered Milk');
    });

    test('uses first brand only when multiple comma-separated brands listed',
        () {
      final result = OpenFoodFactsService.parseProduct(
        barcode: '0000000000002',
        json: {
          'status': 1,
          'product': {
            'product_name': 'Soy Milk',
            'brands': 'Vitasoy, Nestle, Other',
            'nutriments': {'energy-kcal_100g': 50},
          },
        },
      );
      expect(result!.entry.name, 'Vitasoy Soy Milk');
    });

    test('handles string-typed nutriment values (OFF inconsistency)', () {
      final result = OpenFoodFactsService.parseProduct(
        barcode: '0000000000003',
        json: {
          'status': 1,
          'product': {
            'product_name': 'Test Product',
            'brands': 'Test',
            'nutriments': {
              'energy-kcal_100g': '200',
              'proteins_100g': '8.5',
            },
          },
        },
      );
      expect(result!.entry.caloriesPer100g, 200);
      expect(result.entry.proteinPer100g, 8.5);
    });

    test('returns null when both product_name and brands are empty', () {
      final result = OpenFoodFactsService.parseProduct(
        barcode: '0000000000004',
        json: {
          'status': 1,
          'product': {
            'product_name': '',
            'brands': '',
            'nutriments': {'energy-kcal_100g': 100},
          },
        },
      );
      expect(result, isNull);
    });
  });
}
