import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/grocery/cart_item.dart';
import 'package:intermittent_fasting/models/grocery/remembered_price.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/safe_notifier.dart';

/// Owns the active grocery cart and the learned price memory (Plan 038).
///
/// The running total is the whole point of the feature, so it is exposed as a
/// breakdown — [confirmedTotal] (exact) vs [estimatedTotal] (remembered) vs
/// [unpricedCount] — rather than a single number that could silently understate
/// the spend. Prices come entirely from the user: entered once, then auto-filled
/// from [_priceMemory] on the next trip. There is no external price API.
class GroceryCartPresenter extends ChangeNotifier with SafeNotifier {
  GroceryCartPresenter(this._storage) {
    load();
  }

  final StorageService _storage;

  bool _isLoading = true;
  final List<CartItem> _items = [];
  final Map<String, RememberedPrice> _priceMemory = {};
  double? _budget;

  // ── Public state ───────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  List<CartItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get itemCount => _items.length;
  double? get budget => _budget;
  bool get hasBudget => _budget != null;

  // ── Running-total breakdown ──────────────────────────────────────────────────

  /// Sum of line totals for items whose price the user has confirmed.
  double get confirmedTotal => _items
      .where((i) => i.priceState == PriceState.confirmed)
      .fold(0.0, (sum, i) => sum + i.lineTotal);

  /// Sum of line totals for items priced from memory (shown as estimates).
  double get estimatedTotal => _items
      .where((i) => i.priceState == PriceState.remembered)
      .fold(0.0, (sum, i) => sum + i.lineTotal);

  /// Confirmed + estimated — the running spend so far.
  double get grandTotal => confirmedTotal + estimatedTotal;

  /// Items added without any price; excluded from the total and surfaced so the
  /// user knows the figure is incomplete.
  int get unpricedCount =>
      _items.where((i) => i.priceState == PriceState.unknown).length;

  bool get hasEstimates =>
      _items.any((i) => i.priceState == PriceState.remembered);

  double? get budgetRemaining => _budget == null ? null : _budget! - grandTotal;
  bool get isOverBudget => _budget != null && grandTotal > _budget!;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _isLoading = true;
    safeNotify();
    final cart = await _storage.loadGroceryCart();
    final memory = await _storage.loadGroceryPriceMemory();
    final budget = await _storage.loadGroceryBudget();
    _items
      ..clear()
      ..addAll(cart);
    _priceMemory
      ..clear()
      ..addEntries(memory.map((p) => MapEntry(p.key, p)));
    _budget = budget;
    _isLoading = false;
    safeNotify();
  }

  // ── Price memory lookup ──────────────────────────────────────────────────────

  /// Returns the remembered price for an item identity, or null if unseen.
  RememberedPrice? lookup({String? barcode, String? name}) {
    if ((name == null || name.trim().isEmpty) &&
        (barcode == null || barcode.trim().isEmpty)) {
      return null;
    }
    final key = RememberedPrice.keyFor(barcode: barcode, name: name ?? '');
    return _priceMemory[key];
  }

  // ── Mutations ────────────────────────────────────────────────────────────────

  /// Adds an item to the cart. When [unitPrice] is null the price auto-fills
  /// from memory (→ [PriceState.remembered]); if still unknown the item is added
  /// flagged (→ [PriceState.unknown]) so it never blocks the cart.
  Future<void> addItem({
    required String name,
    double quantity = 1,
    double? unitPrice,
    String? barcode,
    ItemSource source = ItemSource.manual,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    double? price = unitPrice;
    final PriceState state;
    if (price != null) {
      state = PriceState.confirmed;
    } else {
      final remembered = lookup(barcode: barcode, name: trimmed);
      if (remembered != null) {
        price = remembered.lastPrice;
        state = PriceState.remembered;
      } else {
        state = PriceState.unknown;
      }
    }

    _items.add(CartItem(
      id: _generateId(),
      name: trimmed,
      quantity: quantity <= 0 ? 1 : quantity,
      unitPrice: price,
      priceState: state,
      source: source,
      barcode: barcode,
      addedAt: DateTime.now(),
    ));

    await _persistCart();
    if (state == PriceState.confirmed) {
      _rememberPrice(name: trimmed, barcode: barcode, price: price!);
      await _persistMemory();
    }
    safeNotify();
  }

  /// Sets a new quantity; a quantity of zero or less removes the item.
  Future<void> updateQuantity(String id, double quantity) async {
    if (quantity <= 0) return removeItem(id);
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    _items[idx] = _items[idx].copyWith(quantity: quantity);
    await _persistCart();
    safeNotify();
  }

  /// Confirms (or overwrites) a price. Always updates price memory so the next
  /// trip remembers it — this is how stale estimates self-correct.
  Future<void> setPrice(String id, double price) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1 || price < 0) return;
    final item = _items[idx];
    _items[idx] =
        item.copyWith(unitPrice: price, priceState: PriceState.confirmed);
    _rememberPrice(name: item.name, barcode: item.barcode, price: price);
    await _persistCart();
    await _persistMemory();
    safeNotify();
  }

  Future<void> removeItem(String id) async {
    _items.removeWhere((i) => i.id == id);
    await _persistCart();
    safeNotify();
  }

  /// Sets the optional spending cap. A non-positive value clears it.
  Future<void> setBudget(double? amount) async {
    _budget = (amount != null && amount <= 0) ? null : amount;
    await _storage.saveGroceryBudget(_budget);
    safeNotify();
  }

  /// Empties the cart (price memory and budget are retained for the next trip).
  Future<void> clearCart() async {
    _items.clear();
    await _persistCart();
    safeNotify();
  }

  // ── Internals ────────────────────────────────────────────────────────────────

  void _rememberPrice({
    required String name,
    String? barcode,
    required double price,
  }) {
    final key = RememberedPrice.keyFor(barcode: barcode, name: name);
    final existing = _priceMemory[key];
    _priceMemory[key] = RememberedPrice(
      key: key,
      displayName: name.trim(),
      lastPrice: price,
      lastSeen: DateTime.now(),
      timesSeen: (existing?.timesSeen ?? 0) + 1,
      barcode: barcode,
    );
  }

  Future<void> _persistCart() => _storage.saveGroceryCart(_items);

  Future<void> _persistMemory() =>
      _storage.saveGroceryPriceMemory(_priceMemory.values.toList());

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
}
