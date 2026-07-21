/// Shared, single source of truth for how a [FinancialAccount] is represented
/// as a small badge (icon / monogram) across every surface — mobile dashboard,
/// ledger, goals, account setup, and the Treasury web app.
///
/// Persistence: the choice lives in the existing [FinancialAccount.icon] string
/// (no model migration). Its value is interpreted as:
///   • a key in [kAccountIconCatalog]  → that custom icon (a solid "logo" tile)
///   • [kMonogramBadgeKey]             → a name-derived monogram tile
///   • anything else (a category name, empty, legacy) → the category default
///
/// The app never hardcodes institution identity onto the stored account; the
/// brand monograms below are a render-time cosmetic convenience only.
library;

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';

/// Sentinel stored in [FinancialAccount.icon] to force the monogram badge.
const String kMonogramBadgeKey = 'monogram';

// ---------------------------------------------------------------------------
// Icon catalog — a FIXED, const set of Material icons users can pick from.
// It MUST stay const (no dynamic IconData/codepoints) so Flutter's icon-font
// tree-shaking keeps working in release builds. Add entries freely.
// ---------------------------------------------------------------------------

/// A pickable icon: its stable storage [key] and the const [icon] it renders.
class AccountIconGroup {
  final String label;
  final List<String> keys;
  const AccountIconGroup(this.label, this.keys);
}

/// key → const IconData. Keys are stored verbatim in [FinancialAccount.icon].
/// Keys must never collide with an [AccountCategory] name (those mean "default").
const Map<String, IconData> kAccountIconCatalog = {
  // Money & banking
  'wallet': Icons.account_balance_wallet_rounded,
  'building': Icons.account_balance_rounded,
  'card': Icons.credit_card_rounded,
  'piggy': Icons.savings_rounded,
  'money': Icons.payments_rounded,
  'coins': Icons.monetization_on_rounded,
  'chart': Icons.trending_up_rounded,
  'vault': Icons.lock_rounded,
  // Travel & vacation
  'beach': Icons.beach_access_rounded,
  'flight': Icons.flight_rounded,
  'sailing': Icons.sailing_rounded,
  'surf': Icons.surfing_rounded,
  'cocktail': Icons.local_bar_rounded,
  'luggage': Icons.luggage_rounded,
  'map': Icons.map_rounded,
  'hotel': Icons.hotel_rounded,
  // Transport
  'car': Icons.directions_car_rounded,
  'train': Icons.train_rounded,
  'motorcycle': Icons.two_wheeler_rounded,
  'fuel': Icons.local_gas_station_rounded,
  // Home & bills
  'home': Icons.home_rounded,
  'bed': Icons.bed_rounded,
  'bolt': Icons.bolt_rounded,
  'water': Icons.water_drop_rounded,
  'wifi': Icons.wifi_rounded,
  'phone': Icons.smartphone_rounded,
  // Food & shopping
  'food': Icons.restaurant_rounded,
  'coffee': Icons.local_cafe_rounded,
  'cart': Icons.shopping_cart_rounded,
  'bag': Icons.shopping_bag_rounded,
  'gift': Icons.card_giftcard_rounded,
  // Life, health & family
  'heart': Icons.favorite_rounded,
  'medical': Icons.medical_services_rounded,
  'pet': Icons.pets_rounded,
  'baby': Icons.child_friendly_rounded,
  'school': Icons.school_rounded,
  'book': Icons.menu_book_rounded,
  'work': Icons.work_rounded,
  // Goals & fun
  'star': Icons.star_rounded,
  'flag': Icons.flag_rounded,
  'target': Icons.gps_fixed_rounded,
  'diamond': Icons.diamond_rounded,
  'rocket': Icons.rocket_launch_rounded,
  'celebrate': Icons.celebration_rounded,
};

/// Catalog grouped for display in the picker (order = display order).
const List<AccountIconGroup> kAccountIconGroups = [
  AccountIconGroup('Money & banking', [
    'wallet',
    'building',
    'card',
    'piggy',
    'money',
    'coins',
    'chart',
    'vault'
  ]),
  AccountIconGroup('Travel & vacation', [
    'beach',
    'flight',
    'sailing',
    'surf',
    'cocktail',
    'luggage',
    'map',
    'hotel'
  ]),
  AccountIconGroup('Transport', ['car', 'train', 'motorcycle', 'fuel']),
  AccountIconGroup(
      'Home & bills', ['home', 'bed', 'bolt', 'water', 'wifi', 'phone']),
  AccountIconGroup(
      'Food & shopping', ['food', 'coffee', 'cart', 'bag', 'gift']),
  AccountIconGroup('Life & family',
      ['heart', 'medical', 'pet', 'baby', 'school', 'book', 'work']),
  AccountIconGroup('Goals & fun',
      ['star', 'flag', 'target', 'diamond', 'rocket', 'celebrate']),
];

// ---------------------------------------------------------------------------
// Canonical category → icon (replaces four divergent per-site switches).
// ---------------------------------------------------------------------------

IconData accountCategoryIcon(AccountCategory category) => switch (category) {
      AccountCategory.bank => Icons.account_balance_rounded,
      AccountCategory.ewallet => Icons.account_balance_wallet_rounded,
      AccountCategory.cash => Icons.payments_rounded,
      AccountCategory.savings => Icons.savings_rounded,
      AccountCategory.goal => Icons.flag_rounded,
      AccountCategory.timeDeposit => Icons.lock_clock_rounded,
      AccountCategory.creditCard => Icons.credit_card_rounded,
      AccountCategory.creditLine => Icons.credit_score_rounded,
      AccountCategory.bnpl => Icons.schedule_rounded,
      AccountCategory.investment => Icons.trending_up_rounded,
      AccountCategory.custodian => Icons.people_alt_rounded,
    };

// ---------------------------------------------------------------------------
// Monograms (brand map + heuristic fallback).
// ---------------------------------------------------------------------------

/// Categories whose default (unchosen) badge is a name monogram rather than a
/// category icon.
bool accountUsesMonogramByDefault(AccountCategory category) =>
    category == AccountCategory.bank || category == AccountCategory.ewallet;

/// Optional presentational monograms for widely-used PH institutions, matched
/// loosely (substring, punctuation/space-insensitive) against the account name.
/// Purely cosmetic — nothing is stored; unknown names fall back to a computed
/// monogram. Order = match priority. Add brands here as needed.
const Map<String, String> kBrandMonograms = {
  'metrobank': 'MB',
  'unionbank': 'UB',
  'securitybank': 'SB',
  'chinabank': 'CB',
  'eastwest': 'EW',
  'landbank': 'LB',
  'maribank': 'Mari',
  'seabank': 'Sea',
  'gotyme': 'GT',
  'grabpay': 'GP',
  'shopeepay': 'SP',
  'gcash': 'GCash',
  'maya': 'Maya',
};

String? _brandMonogram(String name) {
  final key = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (key.isEmpty) return null;
  for (final entry in kBrandMonograms.entries) {
    if (key.contains(entry.key)) return entry.value;
  }
  return null;
}

String _initial(String word) =>
    RegExp(r'[A-Za-z0-9]').firstMatch(word)?.group(0) ?? '';

/// A short brand-style monogram derived from the account name: known
/// institutions get a curated wordmark ("Metrobank" → "MB", "GCash" → "GCash"),
/// otherwise it's computed ("BPI Personal" → "BPI", "Security Bank" → "SB",
/// "Metrobank" → "ME").
String accountMonogram(String name) {
  final brand = _brandMonogram(name);
  if (brand != null) return brand;
  final words =
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  // Already an acronym (BPI, BDO, RCBC, PNB) — keep it as-is (2–4 chars).
  if (first.length >= 2 &&
      first.length <= 4 &&
      first == first.toUpperCase() &&
      RegExp(r'^[A-Z]+$').hasMatch(first)) {
    return first;
  }
  // Two+ words → initials of the first two ("Security Bank" → "SB").
  if (words.length >= 2) {
    final a = _initial(words[0]);
    final b = _initial(words[1]);
    if (a.isNotEmpty && b.isNotEmpty) return (a + b).toUpperCase();
  }
  // Single word → first two letters ("Metrobank" → "ME").
  final letters = first.isEmpty ? name.trim() : first;
  return (letters.length >= 2 ? letters.substring(0, 2) : letters)
      .toUpperCase();
}

/// Readable foreground for a solid [bg] badge — dark ink on light colors, white
/// on dark — so any user-picked color stays legible in both themes.
Color accountBadgeForeground(Color bg) =>
    bg.computeLuminance() > 0.6 ? const Color(0xFF15161A) : Colors.white;

// ---------------------------------------------------------------------------
// Resolution — turn an (iconKey, category, name) into a concrete badge spec.
// ---------------------------------------------------------------------------

/// What a resolved account badge should draw.
class AccountBadgeSpec {
  /// The icon to draw, or null when [monogram] is set.
  final IconData? icon;

  /// The monogram text to draw, or null when [icon] is set.
  final String? monogram;

  /// Solid accent fill with a contrast foreground (chosen icon / monogram), vs
  /// a tinted fill with an accent-colored icon (the category default).
  final bool solid;

  const AccountBadgeSpec._({this.icon, this.monogram, required this.solid});

  bool get isMonogram => monogram != null;
}

/// Resolve the badge for an account described by its stored [iconKey],
/// [category], and [name]. See the library doc for how [iconKey] is interpreted.
AccountBadgeSpec resolveAccountBadge({
  required String iconKey,
  required AccountCategory category,
  required String name,
}) {
  final custom = kAccountIconCatalog[iconKey];
  if (custom != null) {
    return AccountBadgeSpec._(icon: custom, solid: true);
  }
  if (iconKey == kMonogramBadgeKey || accountUsesMonogramByDefault(category)) {
    return AccountBadgeSpec._(monogram: accountMonogram(name), solid: true);
  }
  return AccountBadgeSpec._(icon: accountCategoryIcon(category), solid: false);
}
