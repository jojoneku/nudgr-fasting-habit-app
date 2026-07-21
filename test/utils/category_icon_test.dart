import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/utils/category_icon.dart';

void main() {
  group('categoryIcon', () {
    test('maps known expense keywords to specific glyphs', () {
      expect(categoryIcon('Groceries', CategoryType.expense),
          Icons.shopping_cart_outlined);
      expect(categoryIcon('Food & Dining', CategoryType.expense),
          Icons.restaurant_outlined);
      expect(categoryIcon('Transport', CategoryType.expense),
          Icons.directions_car_outlined);
      expect(categoryIcon('Rent', CategoryType.expense), Icons.home_outlined);
      expect(categoryIcon('Electricity bill', CategoryType.expense),
          Icons.bolt_outlined);
      expect(categoryIcon('Health', CategoryType.expense),
          Icons.medical_services_outlined);
    });

    test('maps known income keywords to specific glyphs', () {
      expect(categoryIcon('Salary', CategoryType.income),
          Icons.work_outline_rounded);
      expect(categoryIcon('Investment dividend', CategoryType.income),
          Icons.trending_up_rounded);
    });

    test('specific keyword wins over general (grocer before food)', () {
      // "grocery" must not be captured by the generic food rule.
      expect(categoryIcon('Grocery food run', CategoryType.expense),
          Icons.shopping_cart_outlined);
    });

    test('falls back per type for unknown names', () {
      expect(categoryIcon('Zxqw', CategoryType.expense),
          Icons.receipt_long_outlined);
      expect(categoryIcon('Zxqw', CategoryType.income),
          Icons.arrow_downward_rounded);
      expect(
          categoryIcon(null, CategoryType.transfer), Icons.swap_horiz_rounded);
    });

    test('is case-insensitive', () {
      expect(categoryIcon('TRANSPORT', CategoryType.expense),
          Icons.directions_car_outlined);
    });
  });
}
