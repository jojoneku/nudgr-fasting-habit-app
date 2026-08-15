import 'package:flutter_test/flutter_test.dart';

import 'package:intermittent_fasting/views/web/pages/ledger/web_ledger_page.dart';

/// The web Ledger's filter model.
///
/// This state used to live inside the page widget, so it was single-select and
/// silently reset every time the user visited another destination and came
/// back. It also had no notion of "this filter asks about more than one month",
/// which is why a search that matched only older rows returned an empty grid.
void main() {
  group('WebLedgerFilters', () {
    test('accounts and categories are multi-select, like mobile', () {
      final f = WebLedgerFilters();

      f.toggleAccount('gcash');
      f.toggleAccount('bpi');

      expect(f.accountIds, {'gcash', 'bpi'});

      // Toggling an existing pick removes just that one.
      f.toggleAccount('gcash');
      expect(f.accountIds, {'bpi'});

      // Null clears the whole filter.
      f.toggleAccount(null);
      expect(f.accountIds, isEmpty);
    });

    test('a search term or a date range widens the scope past one month', () {
      final f = WebLedgerFilters();
      expect(f.spansAllMonths, isFalse);

      f.setQuery('netflix');
      expect(f.spansAllMonths, isTrue);

      f.setQuery('');
      expect(f.spansAllMonths, isFalse);

      f.setFromDate(DateTime(2026, 5, 1));
      expect(f.spansAllMonths, isTrue);
    });

    test('an account or type filter alone stays month-scoped', () {
      final f = WebLedgerFilters();
      f.toggleAccount('gcash');
      f.setType(WebLedgerType.outflow);

      expect(f.spansAllMonths, isFalse);
      expect(f.isNarrowed, isTrue);
    });

    test('a backwards date range is corrected rather than matching nothing',
        () {
      final f = WebLedgerFilters()
        ..setFromDate(DateTime(2026, 5, 10))
        ..setToDate(DateTime(2026, 5, 1)); // before "from"

      expect(f.fromDate, DateTime(2026, 5, 1));
      expect(f.toDate, DateTime(2026, 5, 1));

      final g = WebLedgerFilters()
        ..setToDate(DateTime(2026, 5, 1))
        ..setFromDate(DateTime(2026, 5, 10)); // after "to"

      expect(g.toDate, DateTime(2026, 5, 10));
    });

    test('isNarrowed separates "no data" from "your filters hid it"', () {
      final f = WebLedgerFilters();
      expect(f.isNarrowed, isFalse);

      f.setQuery('coffee');
      expect(f.isNarrowed, isTrue);

      f.setQuery('');
      f.toggleCategory('food');
      expect(f.isNarrowed, isTrue);

      f.clear();
      expect(f.isNarrowed, isFalse);
    });

    test('clear resets every filter and the sort', () {
      final f = WebLedgerFilters()
        ..toggleAccount('gcash')
        ..toggleCategory('food')
        ..setType(WebLedgerType.inflow)
        ..setFromDate(DateTime(2026, 5, 1))
        ..toggleHeaderSort(WebLedgerSortKey.amount);

      expect(f.activeCount, greaterThan(0));

      f.clear();

      expect(f.accountIds, isEmpty);
      expect(f.categoryIds, isEmpty);
      expect(f.type, WebLedgerType.all);
      expect(f.fromDate, isNull);
      expect(f.toDate, isNull);
      expect(f.sortKey, isNull);
      expect(f.activeCount, 0);
    });

    test('tapping the same header twice flips the sort direction', () {
      final f = WebLedgerFilters()..toggleHeaderSort(WebLedgerSortKey.amount);
      expect(f.sortKey, WebLedgerSortKey.amount);
      expect(f.sortDir, 1);

      f.toggleHeaderSort(WebLedgerSortKey.amount);
      expect(f.sortDir, -1);

      f.toggleHeaderSort(WebLedgerSortKey.date);
      expect(f.sortKey, WebLedgerSortKey.date);
      expect(f.sortDir, 1);
    });
  });
}
