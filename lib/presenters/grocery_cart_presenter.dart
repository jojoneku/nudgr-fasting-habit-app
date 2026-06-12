import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/grocery/cart_item.dart';
import 'package:intermittent_fasting/models/grocery/item_unit.dart';
import 'package:intermittent_fasting/models/grocery/remembered_price.dart';
import 'package:intermittent_fasting/models/grocery/saved_trip.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/safe_notifier.dart';

/// Owns the active grocery cart and the learned price memory (Plan 038).
///
/// The running total is the whole point of the feature, so it is exposed as a
/// breakdown — [confirmedTotal] (exact) vs [estimatedTotal] (remembered) vs
/// [unpricedCount] — rather than a single number that could silently understate
/// the spend. Prices come entirely from the user: entered once, then auto-filled
/// from [_priceMemory] on the next trip. There is no external price API.
class GroceryCartPresenter extends ChangeNotifier with SafeNotifier {
  GroceryCartPresenter(this._storage, {LedgerPresenter? ledger})
      : _ledger = ledger {
    load();
  }

  final StorageService _storage;

  /// Optional — only needed to post a finished trip to the Ledger. The cart
  /// works fully without it.
  final LedgerPresenter? _ledger;

  bool _isLoading = true;
  final List<CartItem> _items = [];
  final Map<String, RememberedPrice> _priceMemory = {};
  final List<SavedTrip> _tripHistory = [];
  double? _budget;

  /// Whether checkout can offer "log to Ledger" (a ledger was injected).
  bool get canPostToLedger => _ledger != null;
  List<SavedTrip> get tripHistory => List.unmodifiable(_tripHistory);
  bool get hasTripHistory => _tripHistory.isNotEmpty;

  /// Accounts/categories surfaced for the checkout "log to Ledger" picker.
  /// Empty when no ledger is wired.
  List<FinancialAccount> get ledgerAccounts => _ledger?.accounts ?? const [];
  List<FinanceCategory> get ledgerCategories => _ledger?.categories ?? const [];

  // ── Public state ───────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  List<CartItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get itemCount => _items.length;
  double? get budget => _budget;
  bool get hasBudget => _budget != null;

  // ── Running-total breakdown ──────────────────────────────────────────────────

  /// Rounds a peso amount to whole centavos, so summing doubles never drifts
  /// (e.g. 100.00000001) and budget comparisons stay exact at the boundary.
  double _toCents(double v) => (v * 100).roundToDouble() / 100;

  /// Sum of line totals for items whose price the user has confirmed.
  double get confirmedTotal => _toCents(_items
      .where((i) => i.priceState == PriceState.confirmed)
      .fold(0.0, (sum, i) => sum + i.lineTotal));

  /// Sum of line totals for items priced from memory (shown as estimates).
  double get estimatedTotal => _toCents(_items
      .where((i) => i.priceState == PriceState.remembered)
      .fold(0.0, (sum, i) => sum + i.lineTotal));

  /// Confirmed + estimated — the running spend so far.
  double get grandTotal => _toCents(confirmedTotal + estimatedTotal);

  /// Items added without any price; excluded from the total and surfaced so the
  /// user knows the figure is incomplete.
  int get unpricedCount =>
      _items.where((i) => i.priceState == PriceState.unknown).length;

  bool get hasEstimates =>
      _items.any((i) => i.priceState == PriceState.remembered);

  double? get budgetRemaining => _budget == null ? null : _budget! - grandTotal;
  bool get isOverBudget => _budget != null && grandTotal > _budget!;

  /// Fraction of the budget consumed by the running total, clamped to 0..1 for a
  /// progress bar. Returns 0 when no budget is set. Over-budget reads as a full
  /// bar; the overflow is surfaced separately via [isOverBudget].
  double get budgetUsedFraction {
    if (_budget == null || _budget! <= 0) return 0;
    return (grandTotal / _budget!).clamp(0.0, 1.0);
  }

  /// Whether checkout-to-ledger is currently actionable (a ledger is wired, at
  /// least one account exists to charge, and there is a non-zero total to post).
  bool get canCheckoutToLedger =>
      canPostToLedger && ledgerAccounts.isNotEmpty && grandTotal > 0;

  /// Display string for the "budget remaining" KPI tile. Dash when no budget;
  /// the over-budget overflow is rendered as a negative amount.
  String get budgetRemainingLabel {
    if (_budget == null) return '—';
    return formatPeso(budgetRemaining!);
  }

  /// Sub-text under the "budget remaining" KPI tile.
  String get budgetSubLabel {
    if (_budget == null) return 'No budget set';
    return isOverBudget ? 'Over budget' : 'of ${formatPeso(_budget!)}';
  }

  /// One-line status under the budget meter (e.g. "₱120.00 left" or
  /// "Over by ₱45.00"). Empty when no budget is set.
  String get budgetDetailLabel {
    if (_budget == null) return '';
    final remaining = budgetRemaining ?? 0;
    return isOverBudget
        ? 'Over by ${formatPeso(remaining.abs())}'
        : '${formatPeso(remaining)} left';
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _isLoading = true;
    safeNotify();
    final cart = await _storage.loadGroceryCart();
    final memory = await _storage.loadGroceryPriceMemory();
    final budget = await _storage.loadGroceryBudget();
    final history = await _storage.loadGroceryTripHistory();
    _items
      ..clear()
      ..addAll(cart);
    _priceMemory
      ..clear()
      ..addEntries(memory.map((p) => MapEntry(p.key, p)));
    _tripHistory
      ..clear()
      ..addAll(history);
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
    ItemUnit unit = ItemUnit.piece,
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
      unit: unit,
      barcode: barcode,
      addedAt: DateTime.now(),
    ));

    // Optimistic: update memory + notify first so the UI repaints instantly;
    // persistence (encode + prefs write) runs after the paint.
    final remember = state == PriceState.confirmed;
    if (remember) {
      _rememberPrice(
          name: trimmed, barcode: barcode, price: price!, unit: unit);
    }
    safeNotify();
    await _persistCart();
    if (remember) await _persistMemory();
  }

  /// Sets a new quantity; a quantity of zero or less removes the item.
  Future<void> updateQuantity(String id, double quantity) async {
    if (quantity <= 0) return removeItem(id);
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    _items[idx] = _items[idx].copyWith(quantity: quantity);
    safeNotify();
    await _persistCart();
  }

  /// Confirms (or overwrites) a price. Always updates price memory so the next
  /// trip remembers it — this is how stale estimates self-correct.
  Future<void> setPrice(String id, double price) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1 || price < 0) return;
    final item = _items[idx];
    _items[idx] =
        item.copyWith(unitPrice: price, priceState: PriceState.confirmed);
    _rememberPrice(
        name: item.name, barcode: item.barcode, price: price, unit: item.unit);
    safeNotify();
    await _persistCart();
    await _persistMemory();
  }

  Future<void> removeItem(String id) async {
    _items.removeWhere((i) => i.id == id);
    safeNotify();
    await _persistCart();
  }

  /// Sets the optional spending cap. A non-positive value clears it.
  Future<void> setBudget(double? amount) async {
    _budget = (amount != null && amount <= 0) ? null : amount;
    safeNotify();
    await _storage.saveGroceryBudget(_budget);
  }

  /// Empties the cart (price memory and budget are retained for the next trip).
  Future<void> clearCart() async {
    _items.clear();
    safeNotify();
    await _persistCart();
  }

  // ── Checkout & trip history ──────────────────────────────────────────────────

  /// Finishes the current trip: optionally posts the total to the Ledger as an
  /// outflow, saves a snapshot to trip history, then clears the cart. Returns
  /// the saved trip, or null if the cart was empty.
  Future<SavedTrip?> checkout({
    bool postToLedger = false,
    String? accountId,
    String? categoryId,
    String description = 'Groceries',
  }) async {
    if (_items.isEmpty) return null;
    final now = DateTime.now();

    final posted =
        postToLedger && _ledger != null && accountId != null && grandTotal > 0;
    // Capture totals before clearing the cart (they read _items).
    final amount = grandTotal;
    final trip = SavedTrip(
      id: _generateId(),
      savedAt: now,
      items: List.of(_items),
      confirmedTotal: confirmedTotal,
      estimatedTotal: estimatedTotal,
      unpricedCount: unpricedCount,
      postedToLedger: posted,
    );

    // Optimistic: record the trip + empty the cart in memory and repaint, then
    // post to the ledger / persist in the background.
    _tripHistory.insert(0, trip);
    _items.clear();
    safeNotify();

    if (posted) {
      await _ledger.addTransaction(TransactionRecord(
        id: _generateId(),
        date: now,
        accountId: accountId,
        categoryId: categoryId ?? '',
        amount: amount,
        type: TransactionType.outflow,
        description: description,
        month: toMonthKey(now),
      ));
    }
    await _persistHistory();
    await _persistCart();
    return trip;
  }

  /// Re-adds a past trip's items to the current cart, re-pricing each from
  /// current memory (so prices reflect today, not the old snapshot).
  Future<void> repeatTrip(String tripId) async {
    final idx = _tripHistory.indexWhere((t) => t.id == tripId);
    if (idx == -1) return;
    for (final item in _tripHistory[idx].items) {
      await addItem(
        name: item.name,
        quantity: item.quantity,
        unit: item.unit,
        barcode: item.barcode,
      );
    }
  }

  Future<void> deleteTrip(String tripId) async {
    _tripHistory.removeWhere((t) => t.id == tripId);
    safeNotify();
    await _persistHistory();
  }

  // ── Internals ────────────────────────────────────────────────────────────────

  void _rememberPrice({
    required String name,
    String? barcode,
    required double price,
    required ItemUnit unit,
  }) {
    final key = RememberedPrice.keyFor(barcode: barcode, name: name);
    final existing = _priceMemory[key];
    _priceMemory[key] = RememberedPrice(
      key: key,
      displayName: name.trim(),
      lastPrice: price,
      unit: unit,
      lastSeen: DateTime.now(),
      timesSeen: (existing?.timesSeen ?? 0) + 1,
      barcode: barcode,
    );
  }

  Future<void> _persistCart() => _storage.saveGroceryCart(_items);

  Future<void> _persistMemory() =>
      _storage.saveGroceryPriceMemory(_priceMemory.values.toList());

  Future<void> _persistHistory() =>
      _storage.saveGroceryTripHistory(_tripHistory);

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
}
