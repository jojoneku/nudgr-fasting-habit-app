import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';

/// Ordered keyword → icon rules for [categoryIcon]. Most specific first, so
/// e.g. "grocery" resolves to a cart before the generic "food" rule can claim
/// it. Const so the whole table is evaluated once.
const List<(List<String>, IconData)> _rules = [
  (['grocer', 'supermarket', 'market'], Icons.shopping_cart_outlined),
  (
    [
      'food',
      'dining',
      'restaurant',
      'lunch',
      'dinner',
      'snack',
      'coffee',
      'cafe'
    ],
    Icons.restaurant_outlined
  ),
  (
    [
      'transport',
      'grab',
      'taxi',
      'fuel',
      'gas',
      'fare',
      'commute',
      'car',
      'ride'
    ],
    Icons.directions_car_outlined
  ),
  (['shop', 'clothes', 'apparel', 'mall'], Icons.shopping_bag_outlined),
  (
    ['health', 'medical', 'doctor', 'pharmacy', 'medicine', 'clinic'],
    Icons.medical_services_outlined
  ),
  (['rent', 'housing', 'mortgage', 'home'], Icons.home_outlined),
  (
    [
      'util',
      'electric',
      'power',
      'meralco',
      'water',
      'internet',
      'wifi',
      'phone',
      'bill'
    ],
    Icons.bolt_outlined
  ),
  (
    [
      'entertain',
      'movie',
      'game',
      'netflix',
      'spotify',
      'subscription',
      'stream'
    ],
    Icons.movie_outlined
  ),
  (['travel', 'flight', 'hotel', 'trip', 'vacation'], Icons.flight_outlined),
  (['education', 'school', 'tuition', 'book', 'course'], Icons.school_outlined),
  (['gift', 'donation', 'charity'], Icons.card_giftcard_outlined),
  (['pet'], Icons.pets_outlined),
  (
    ['salary', 'payroll', 'wage', 'income', 'paycheck'],
    Icons.work_outline_rounded
  ),
  (['bonus', 'reward', 'incentive'], Icons.emoji_events_outlined),
  (['refund', 'reimburse', 'rebate', 'cashback'], Icons.replay_rounded),
  (['invest', 'dividend', 'interest', 'stock'], Icons.trending_up_rounded),
  (['freelance', 'business', 'sales', 'commission'], Icons.storefront_outlined),
  (['transfer'], Icons.swap_horiz_rounded),
  (['saving', 'fund'], Icons.savings_outlined),
];

/// Maps a finance category to a representative Material icon for the Nudgr
/// ledger/dashboard rows (`Nutrition Focus Treasury.dc.html` — fork-knife for
/// food, car for transport, briefcase for salary, …).
///
/// Categories in this app don't persist a usable glyph, so the icon is inferred
/// from the category name with a keyword heuristic, falling back to a sensible
/// per-type default. Pure and side-effect free — safe to call from `build`.
IconData categoryIcon(String? name, CategoryType type) {
  final n = (name ?? '').toLowerCase();
  for (final (keywords, icon) in _rules) {
    if (keywords.any(n.contains)) return icon;
  }
  return switch (type) {
    CategoryType.income => Icons.arrow_downward_rounded,
    CategoryType.expense => Icons.receipt_long_outlined,
    CategoryType.transfer => Icons.swap_horiz_rounded,
  };
}
