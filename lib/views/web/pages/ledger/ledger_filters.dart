import 'package:flutter/foundation.dart';

/// Ledger table filters + sort + search.
///
/// Lives outside the page widget for two reasons: it survives navigation (page
/// state did not), and accounts/categories are multi-select here just as they
/// are on mobile — the web table used to allow exactly one of each, so the same
/// filter could not be expressed on both platforms.
///
/// Shared by the pre-v2 `WebLedgerPage` and `WebLedgerPageV2` (Plan 063,
/// Phase 4); the shell owns one instance and hands it to whichever page the
/// flag selects.
class WebLedgerFilters extends ChangeNotifier {
  final Set<String> accountIds = <String>{};
  final Set<String> categoryIds = <String>{};
  WebLedgerType type = WebLedgerType.all;
  DateTime? fromDate;
  DateTime? toDate;
  WebLedgerSortKey? sortKey; // null = presenter default (newest first)
  int sortDir = -1;
  String query = '';

  /// A search term or a date range asks a question about the whole ledger, not
  /// about one month — the grid widens its scope to all history when either is
  /// set, and says so.
  bool get spansAllMonths =>
      query.isNotEmpty || fromDate != null || toDate != null;

  int get activeCount => [
        accountIds.isNotEmpty,
        categoryIds.isNotEmpty,
        type != WebLedgerType.all,
        fromDate != null || toDate != null,
        sortKey != null,
      ].where((b) => b).length;

  /// True when anything at all is narrowing the grid — used to tell "you have
  /// no transactions" apart from "your filters hid them".
  bool get isNarrowed => activeCount > 0 || query.isNotEmpty;

  void toggleAccount(String? id) {
    if (id == null) {
      accountIds.clear();
    } else if (!accountIds.remove(id)) {
      accountIds.add(id);
    }
    notifyListeners();
  }

  void toggleCategory(String? id) {
    if (id == null) {
      categoryIds.clear();
    } else if (!categoryIds.remove(id)) {
      categoryIds.add(id);
    }
    notifyListeners();
  }

  void setType(WebLedgerType v) {
    type = v;
    notifyListeners();
  }

  void setFromDate(DateTime? v) {
    fromDate = v;
    // Keep the range coherent rather than silently returning nothing.
    if (v != null && toDate != null && toDate!.isBefore(v)) toDate = v;
    notifyListeners();
  }

  void setToDate(DateTime? v) {
    toDate = v;
    if (v != null && fromDate != null && fromDate!.isAfter(v)) fromDate = v;
    notifyListeners();
  }

  void setSort(WebLedgerSortOption? opt) {
    sortKey = opt?.key;
    sortDir = opt?.dir ?? -1;
    notifyListeners();
  }

  void toggleHeaderSort(WebLedgerSortKey key) {
    if (sortKey == key) {
      sortDir = -sortDir;
    } else {
      sortKey = key;
      sortDir = 1;
    }
    notifyListeners();
  }

  void setQuery(String v) {
    if (v == query) return;
    query = v;
    notifyListeners();
  }

  void clear() {
    accountIds.clear();
    categoryIds.clear();
    type = WebLedgerType.all;
    fromDate = null;
    toDate = null;
    sortKey = null;
    sortDir = -1;
    notifyListeners();
  }
}

enum WebLedgerType { all, inflow, outflow }

enum WebLedgerSortKey {
  date,
  account,
  description,
  category,
  inflow,
  outflow,
  amount
}

/// Preset sort options shown in the Filters & Sort popover.
class WebLedgerSortOption {
  final String label;
  final WebLedgerSortKey key;
  final int dir; // 1 asc, -1 desc
  const WebLedgerSortOption(this.label, this.key, this.dir);
}

const kLedgerSortOptions = <WebLedgerSortOption>[
  WebLedgerSortOption('Newest first', WebLedgerSortKey.date, -1),
  WebLedgerSortOption('Oldest first', WebLedgerSortKey.date, 1),
  WebLedgerSortOption('Highest outflow', WebLedgerSortKey.outflow, -1),
  WebLedgerSortOption('Highest inflow', WebLedgerSortKey.inflow, -1),
  WebLedgerSortOption('Largest amount', WebLedgerSortKey.amount, -1),
];

/// The preset whose key and direction match the current sort, if any.
WebLedgerSortOption? ledgerSortPresetFor(WebLedgerSortKey? key, int dir) {
  for (final o in kLedgerSortOptions) {
    if (o.key == key && o.dir == dir) return o;
  }
  return null;
}
