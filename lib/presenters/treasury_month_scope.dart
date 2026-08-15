import 'package:flutter/foundation.dart';

import 'package:intermittent_fasting/utils/finance_format.dart';

/// The month the user is currently *reading* across the whole Treasury module.
///
/// Ledger, Bills, Budget and Installments each used to own a private
/// `_selectedMonth`, all seeded to "now". Paging the Ledger back to June and
/// then opening Bills silently dropped you back into the current month, so the
/// two tabs described different months with nothing on screen saying so.
///
/// This is the single source of truth they now share. It is deliberately tiny:
/// it holds a month key and notifies, and each presenter keeps its own copy in
/// sync (adopting changes made from any other tab). Presenters take it as an
/// optional constructor argument, so anything constructed without one — most
/// tests, and standalone views — behaves exactly as before.
class TreasuryMonthScope extends ChangeNotifier {
  String _month;

  TreasuryMonthScope([String? month])
      : _month = month ?? toMonthKey(DateTime.now());

  /// Month key in `YYYY-MM` form.
  String get month => _month;

  /// Adopts [month] and notifies every presenter bound to this scope. A no-op
  /// when nothing changes, which is also what stops the presenter⇄scope
  /// write-back from looping.
  void setMonth(String month) {
    if (_month == month) return;
    _month = month;
    notifyListeners();
  }
}
