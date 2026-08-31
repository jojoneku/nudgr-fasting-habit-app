// How far an edit or delete reaches through a recurring series (Plan 059).
//
// Extracted from `BillsReceivablesPresenter._seriesReach`, which was already
// generic over the item type but private to that presenter. Budgets need the
// same answer — "which rows does this change touch, and does it end the
// series?" — and two copies of that question is the pair that drifts.
//
// Pure: lists in, ids out. No I/O, no presenter state.

/// Which rows a scoped change covers, and which series it ends.
///
/// [ids] is every row to act on: the selection itself, plus the later rows of
/// each selected row's series when [applyToFuture]. [endedSeries] is the series
/// whose recurrence should stop — the caller decides what that means for its
/// own model (bills clear `isRecurring`; budgets do the same so carry-forward
/// stops offering the line).
typedef SeriesReach = ({Set<String> ids, Set<String> endedSeries});

/// Resolves the reach of a change over [selected].
///
/// [seriesOf] reads a row's series id, [laterOpen] returns the rows *after* it
/// in the same series that are still eligible to change, and [idOf] reads a
/// row's own id.
///
/// With [applyToFuture] false this is just the selection — the scope is "this
/// one", and nothing recurs onward.
SeriesReach seriesReach<T>(
  List<T> selected, {
  required String? Function(T) seriesOf,
  required List<T> Function(T) laterOpen,
  required String Function(T) idOf,
  required bool applyToFuture,
}) {
  final ids = selected.map(idOf).toSet();
  if (!applyToFuture) {
    return (ids: ids, endedSeries: const <String>{});
  }
  final endedSeries = <String>{};
  for (final item in selected) {
    final series = seriesOf(item);
    // A row with no series has nothing ahead of it and nothing to end, so it
    // must not be matched by a null — that would sweep up every other unstamped
    // row in the list.
    if (series == null) continue;
    endedSeries.add(series);
    ids.addAll(laterOpen(item).map(idOf));
  }
  return (ids: ids, endedSeries: endedSeries);
}
