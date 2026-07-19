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
        resolveCategoryIcon(
            kAutoCategoryIconKey, 'Groceries', CategoryType.expense),
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

  group('categoryMonogram', () {
    test('single word → one uppercase letter', () {
      expect(categoryMonogram('Allowance'), 'A');
      expect(categoryMonogram('rent'), 'R');
    });

    test('two+ words → initials of the first two', () {
      expect(categoryMonogram('Side gig'), 'SG');
      expect(categoryMonogram('  emergency   fund  '), 'EF');
    });

    test('skips leading symbols; empty/blank → empty string', () {
      expect(categoryMonogram('  #tag'), 'T');
      expect(categoryMonogram(''), '');
      expect(categoryMonogram('   '), '');
      expect(categoryMonogram(null), '');
    });

    test('skips words with no letter/digit (emoji-prefixed names)', () {
      expect(categoryMonogram('🎮 Games'), 'G');
      expect(categoryMonogram('🍔'), '');
    });
  });

  group('resolveCategoryBadge', () {
    test('explicit catalog key → that icon, no monogram', () {
      final spec =
          resolveCategoryBadge('food', 'whatever', CategoryType.expense);
      expect(spec.icon, kCategoryIconCatalog['food']);
      expect(spec.monogram, isNull);
    });

    test('keyword match (no explicit icon) → heuristic glyph, no monogram', () {
      final spec = resolveCategoryBadge(
          kAutoCategoryIconKey, 'Groceries', CategoryType.expense);
      expect(spec.icon, isNotNull);
      expect(spec.monogram, isNull);
    });

    test('no keyword match → name monogram, no icon', () {
      final spec = resolveCategoryBadge(
          kAutoCategoryIconKey, 'Allowance', CategoryType.expense);
      expect(spec.monogram, 'A');
      expect(spec.icon, isNull);
    });

    test('no name and no icon → per-type generic icon (no monogram)', () {
      final spec = resolveCategoryBadge('', '', CategoryType.expense);
      expect(spec.icon, isNotNull);
      expect(spec.monogram, isNull);
    });
  });
}
