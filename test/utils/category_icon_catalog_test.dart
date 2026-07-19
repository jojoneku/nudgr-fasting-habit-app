import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/utils/category_icon.dart';
import 'package:intermittent_fasting/utils/category_icon_catalog.dart';

void main() {
  group('resolveCategoryIcon', () {
    test('uses the catalog icon when the stored key is a catalog entry', () {
      expect(
        resolveCategoryIcon('food', 'anything', CategoryType.expense),
        kCategoryIconCatalog['food'],
      );
      expect(
        resolveCategoryIcon('salary', 'anything', CategoryType.income),
        kCategoryIconCatalog['salary'],
      );
    });

    test('the auto sentinel routes through the name heuristic', () {
      // kAutoCategoryIconKey ("tag") is deliberately NOT a catalog key.
      expect(kCategoryIconCatalog.containsKey(kAutoCategoryIconKey), isFalse);
      expect(
        resolveCategoryIcon(kAutoCategoryIconKey, 'Groceries', CategoryType.expense),
        categoryIcon('Groceries', CategoryType.expense),
      );
    });

    test('legacy / unknown keys fall back to the name heuristic', () {
      // e.g. the reserved transfer category persisted icon 'bank-transfer'.
      expect(
        resolveCategoryIcon('bank-transfer', 'Transport', CategoryType.expense),
        categoryIcon('Transport', CategoryType.expense),
      );
      expect(
        resolveCategoryIcon(null, 'Zxqw', CategoryType.income),
        categoryIcon('Zxqw', CategoryType.income),
      );
    });

    test('every grouped key exists in the catalog', () {
      for (final group in kCategoryIconGroups) {
        for (final key in group.keys) {
          expect(kCategoryIconCatalog.containsKey(key), isTrue,
              reason: 'group "${group.label}" key "$key" missing from catalog');
        }
      }
    });
  });
}
