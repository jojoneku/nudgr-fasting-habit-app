/// User-pickable icons for [FinanceCategory]s — the finance-domain counterpart
/// to the account icon catalog in `account_badge.dart`.
///
/// A category already persists its choice in [FinanceCategory.icon] (a string).
/// Its value is interpreted as:
///   • a key in [kCategoryIconCatalog] → that custom icon
///   • anything else (legacy free-text, `'tag'`, `'bank-transfer'`, empty) →
///     the name-heuristic fallback in `category_icon.dart`
///
/// so no migration is needed: categories created before the picker existed still
/// render a sensible glyph.
library;

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/utils/category_icon.dart';

/// A named group of catalog keys for the picker grid (order = display order).
class CategoryIconGroup {
  final String label;
  final List<String> keys;
  const CategoryIconGroup(this.label, this.keys);
}

// ---------------------------------------------------------------------------
// Icon catalog — a FIXED, const set of Material icons users can pick from.
// It MUST stay const (no dynamic IconData/codepoints) so Flutter's icon-font
// tree-shaking keeps working in release builds. Add entries freely, but keys
// are stored verbatim in [FinanceCategory.icon] — never rename an existing key.
// ---------------------------------------------------------------------------

/// key → const IconData. Keys are stored verbatim in [FinanceCategory.icon].
const Map<String, IconData> kCategoryIconCatalog = {
  // Food & drink
  'food': Icons.restaurant_rounded,
  'coffee': Icons.local_cafe_rounded,
  'fastfood': Icons.fastfood_rounded,
  'grocery': Icons.shopping_cart_rounded,
  'bar': Icons.local_bar_rounded,
  // Transport
  'car': Icons.directions_car_rounded,
  'ride': Icons.local_taxi_rounded,
  'fuel': Icons.local_gas_station_rounded,
  'transit': Icons.directions_transit_rounded,
  'flight': Icons.flight_rounded,
  // Home & bills
  'home': Icons.home_rounded,
  'bolt': Icons.bolt_rounded,
  'water': Icons.water_drop_rounded,
  'wifi': Icons.wifi_rounded,
  'phone': Icons.smartphone_rounded,
  'bill': Icons.receipt_long_rounded,
  // Shopping & lifestyle
  'shopping': Icons.shopping_bag_rounded,
  'gift': Icons.card_giftcard_rounded,
  'entertainment': Icons.movie_rounded,
  'subscription': Icons.subscriptions_rounded,
  'sports': Icons.sports_basketball_rounded,
  // Life, health & family
  'health': Icons.medical_services_rounded,
  'fitness': Icons.fitness_center_rounded,
  'pet': Icons.pets_rounded,
  'baby': Icons.child_friendly_rounded,
  'education': Icons.school_rounded,
  'book': Icons.menu_book_rounded,
  // Income
  'salary': Icons.work_rounded,
  'bonus': Icons.emoji_events_rounded,
  'refund': Icons.replay_rounded,
  'invest': Icons.trending_up_rounded,
  'business': Icons.storefront_rounded,
  'savings': Icons.savings_rounded,
  // Misc / generic
  'transfer': Icons.swap_horiz_rounded,
  'label': Icons.sell_rounded,
  'star': Icons.star_rounded,
  'heart': Icons.favorite_rounded,
};

/// Catalog grouped for display in the picker (order = display order).
const List<CategoryIconGroup> kCategoryIconGroups = [
  CategoryIconGroup(
      'Food & drink', ['food', 'coffee', 'fastfood', 'grocery', 'bar']),
  CategoryIconGroup(
      'Transport', ['car', 'ride', 'fuel', 'transit', 'flight']),
  CategoryIconGroup(
      'Home & bills', ['home', 'bolt', 'water', 'wifi', 'phone', 'bill']),
  CategoryIconGroup('Shopping & lifestyle',
      ['shopping', 'gift', 'entertainment', 'subscription', 'sports']),
  CategoryIconGroup('Life & family',
      ['health', 'fitness', 'pet', 'baby', 'education', 'book']),
  CategoryIconGroup('Income',
      ['salary', 'bonus', 'refund', 'invest', 'business', 'savings']),
  CategoryIconGroup('More', ['transfer', 'label', 'star', 'heart']),
];

/// Sentinel [FinanceCategory.icon] value meaning "no explicit pick — derive the
/// glyph from the category name" (the picker's "Auto" choice). Deliberately NOT
/// a key in [kCategoryIconCatalog] so it routes through the name heuristic. This
/// is also the historical default stamped on categories created before the
/// picker existed, so those keep their smart auto-glyph.
const String kAutoCategoryIconKey = 'tag';

/// Resolves the glyph for a category row/badge.
///
/// Prefers the user's stored [iconKey] when it names a catalog entry; otherwise
/// falls back to the name heuristic so legacy categories (icon = `'tag'` before
/// it was a catalog key, `'bank-transfer'`, or any free-text) still render
/// meaningfully. Pure and side-effect free — safe to call from `build`.
IconData resolveCategoryIcon(String? iconKey, String? name, CategoryType type) {
  final fromCatalog = iconKey == null ? null : kCategoryIconCatalog[iconKey];
  if (fromCatalog != null) return fromCatalog;
  return categoryIcon(name, type);
}

/// A resolved category badge: either an [icon] or a short name [monogram]
/// (never both). Mirrors the account-badge pattern so a category with no
/// explicit icon and no keyword match still gets a distinct, name-derived badge
/// instead of a generic look-alike glyph.
class CategoryBadgeSpec {
  final IconData? icon;
  final String? monogram;
  const CategoryBadgeSpec.icon(IconData this.icon) : monogram = null;
  const CategoryBadgeSpec.monogram(String this.monogram) : icon = null;
}

/// A short, name-derived monogram for a category (1 letter for a single word,
/// initials of the first two words otherwise; up to 2 chars, uppercased).
/// Returns '' when the name has no usable letters/digits.
///
/// Words with no Latin letter/digit (e.g. a leading emoji) are skipped, so
/// "🎮 Games" → "G" rather than falling through to a generic glyph.
String categoryMonogram(String? name) {
  final initials = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .map((w) => RegExp(r'[A-Za-z0-9]').firstMatch(w)?.group(0))
      .whereType<String>()
      .toList();
  if (initials.isEmpty) return '';
  if (initials.length >= 2) return (initials[0] + initials[1]).toUpperCase();
  return initials.first.toUpperCase();
}

/// Resolves the badge for a category (icon-or-monogram), Option-1 order:
///   1. explicit catalog icon (user pick)
///   2. keyword-heuristic glyph (shopping → cart, salary → briefcase, …)
///   3. name monogram (so unmatched categories stay visually distinct)
///   4. per-type generic icon (only when the name has no usable letters)
CategoryBadgeSpec resolveCategoryBadge(
    String? iconKey, String? name, CategoryType type) {
  final fromCatalog = iconKey == null ? null : kCategoryIconCatalog[iconKey];
  if (fromCatalog != null) return CategoryBadgeSpec.icon(fromCatalog);
  final keyword = categoryKeywordIcon(name);
  if (keyword != null) return CategoryBadgeSpec.icon(keyword);
  final mono = categoryMonogram(name);
  if (mono.isNotEmpty) return CategoryBadgeSpec.monogram(mono);
  return CategoryBadgeSpec.icon(categoryIcon(name, type));
}
