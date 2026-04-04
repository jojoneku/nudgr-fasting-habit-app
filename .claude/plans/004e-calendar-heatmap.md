# Plan 004e — Treasury Module: Calendar Spending Heatmap
**Status:** DRAFT — Awaiting Approval
**Phase:** Extension to 004b (Ledger)
**Depends on:** Plan 004b completed (LedgerPresenter and LedgerView exist)
**Package already available:** `table_calendar: ^3.0.9` (already in pubspec.yaml)

---

## Goal

Add a toggleable calendar view to the Ledger tab. Each day is color-coded by spending
intensity — heavier spend days appear darker red, income days appear green, mixed days
show the dominant side. Tapping a day scrolls the transaction list to that date group.

This mirrors Tarsi's "Calendar spending heatmap" feature and gives users a spatial
overview of their month rather than just a chronological list.

---

## Design

```
┌── LEDGER ─────────────────── [≡ list] [📅 calendar] ──┐
│  All Accounts ▾    ◀ April 2026 ▶                      │
│                                                         │
│  Mon  Tue  Wed  Thu  Fri  Sat  Sun                     │
│   -    1    2    3    4    5    6                       │
│        ·    ██   ·    ░    ██   ·                      │
│   7    8    9    10   11   12   13                      │
│   ░    ██   ·    ███  ·    ·    ░                       │
│   ...                                                   │
│                                                         │
│  ── April 10 ────────────────────────────── ₱3,200 ──  │
│  [transaction tiles below, same as list view]           │
└─────────────────────────────────────────────────────────┘
```

**Color encoding:**
- No transactions: transparent (default cell)
- Outflow only: `AppColors.danger` at 20%–90% opacity (mapped to spend amount)
- Inflow only: `AppColors.success` at 30%–80% opacity
- Both: dominant side wins; dot below the day number indicates the other side

**Intensity mapping:**
- Opacity = `clamp(dailyAmount / monthlyAverageDaily, 0.15, 0.90)`
- Monthly average = `monthTotalOutflow / daysWithAnySpend`
- This makes the scale relative to the user's own habits, not absolute thresholds

---

## Presenter Changes: `LedgerPresenter`

Two new getters — no new storage, computed from existing `_transactions`:

```dart
// Map of 'YYYY-MM-DD' → total outflow for that day (filtered by selectedAccountId)
Map<String, double> get dailyOutflowMap;

// Map of 'YYYY-MM-DD' → total inflow for that day (filtered by selectedAccountId)
Map<String, double> get dailyInflowMap;

// Average daily outflow for selected month (excludes days with zero spend)
double get averageDailyOutflow;
```

Both are derived from `filteredTransactions` so they automatically respect the
active account filter.

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/presenters/ledger_presenter.dart` | Modify — add 3 getters | Presenter |
| `lib/views/treasury/ledger/ledger_view.dart` | Modify — add toggle + calendar mode | View |
| `lib/views/treasury/ledger/spending_calendar.dart` | Create | View |

---

## View Changes: `LedgerView`

`LedgerView` becomes `StatefulWidget` (needs `_showCalendar` toggle state).

```dart
bool _showCalendar = false;
```

The `_MonthSelectorRow` gets a trailing icon button to toggle:
```
◀  April 2026  ▶   [list icon / calendar icon]
```

When `_showCalendar == true`:
- Replace `Expanded(child: _TransactionList(...))` with:
  ```
  SpendingCalendar(presenter: presenter, onDaySelected: _scrollToDate)
  + Expanded(child: _TransactionList(...))
  ```
  The calendar sits above the list; tapping a day calls `_scrollToDate` which
  uses a `ScrollController` to jump to that date group in the list.

When `_showCalendar == false`:
- Current list-only view (no change)

---

## Widget: `SpendingCalendar`

```dart
class SpendingCalendar extends StatelessWidget {
  final LedgerPresenter presenter;
  final ValueChanged<DateTime> onDaySelected;
  ...
}
```

Uses `TableCalendar` with:
- `calendarFormat: CalendarFormat.month` (fixed, no week/2-week toggle)
- `firstDay` / `lastDay` derived from `presenter.selectedMonth`
- `focusedDay` = first day of `presenter.selectedMonth`
- `onDaySelected` → calls parent callback
- `calendarBuilders`:
  - `defaultBuilder`: draws the heatmap cell
  - `todayBuilder`: same as default but with accent ring
  - `selectedBuilder`: selected day with accent ring + white text

### Heatmap cell logic (inside `defaultBuilder`):
```dart
final key = DateFormat('yyyy-MM-dd').format(day);
final outflow = presenter.dailyOutflowMap[key] ?? 0;
final inflow = presenter.dailyInflowMap[key] ?? 0;
final avg = presenter.averageDailyOutflow;

Color? bg;
if (outflow > 0 && outflow >= inflow) {
  final opacity = (outflow / avg).clamp(0.15, 0.90);
  bg = AppColors.danger.withOpacity(opacity);
} else if (inflow > 0) {
  final opacity = (inflow / avg).clamp(0.15, 0.70);
  bg = AppColors.success.withOpacity(opacity);
}
```

Cell renders:
- Filled `CircleAvatar` with `bg` color (or transparent)
- Day number text (white if bg is dark enough, `textPrimary` otherwise)
- Optional tiny dot below the number for the secondary direction (if both exist)

### Calendar height: fixed at `280` — enough for a 5-week month with headers.

---

## Scroll-to-Date Integration

`LedgerView` needs a `ScrollController` and a way to map a `DateTime` to a list index.

```dart
// In _TransactionList: expose sorted date keys so parent can compute offset
// Simpler approach: store a Map<String, GlobalKey> per date group header
// Tap a day → find the matching GlobalKey → Scrollable.ensureVisible(...)
```

Implementation:
1. `_DateGroup` accepts an optional `key` (already standard Flutter behavior via `ValueKey`)
2. `_scrollToDate(DateTime d)` finds the `sortedDates` index and uses
   `itemScrollController.jumpTo(index: i)` — requires `scrollable_positioned_list`
   **OR** simpler: filter `presenter.selectedDate = d` — show only that day's transactions.

**Recommended (simpler):** Add `DateTime? selectedDate` to `LedgerPresenter`.
When set, `groupedTransactions` filters to only that day's transactions.
Tapping the selected day again clears the filter (shows all).
A chip above the list shows "Filtered: Apr 10 ✕" when active.

```dart
// LedgerPresenter addition
DateTime? _selectedDate;
DateTime? get selectedDate => _selectedDate;
void setSelectedDate(DateTime? d) { _selectedDate = d; notifyListeners(); }

// groupedTransactions uses _selectedDate if set
```

This avoids `scrollable_positioned_list` dependency and keeps the presenter as the
source of truth.

---

## Month Navigation

When `presenter.setMonth(...)` is called (prev/next arrows), `SpendingCalendar`
rebuilds with the new month's data automatically — `TableCalendar`'s `focusedDay`
and `firstDay`/`lastDay` are derived from `presenter.selectedMonth`.

---

## RPG Impact

None directly — this is a pure observability feature. Future: could trigger an
insight notification if spending on a particular day type (weekends, Fridays)
is consistently high.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Month with no transactions | Calendar renders without color; list shows empty state |
| All spending on one day (avg skewed) | `clamp(0.15, 0.90)` prevents invisible or fully opaque cells |
| Selected date has no transactions (tapped empty day) | Show empty state inline below calendar |
| TableCalendar rebuild performance | Wrap `SpendingCalendar` in `RepaintBoundary`; maps computed in presenter not build() |
| Month with 6 calendar rows | TableCalendar handles this; fixed height 280 may clip — use `rowHeight: 42` to fit |

---

## Acceptance Criteria

- [ ] Calendar toggle button switches between calendar+list and list-only views
- [ ] Each day cell colored by outflow intensity relative to monthly average
- [ ] Income-only days show success green
- [ ] Tapping a day filters the list below to that day's transactions
- [ ] Tapping the selected day again clears the filter
- [ ] "Filtered: [date] ✕" chip visible when date filter is active
- [ ] Month navigation arrows update both calendar and list
- [ ] Account filter chip applies to both heatmap colors and list
- [ ] No logic in any `build()` method
- [ ] Touch targets ≥ 44×44px (TableCalendar `rowHeight` ≥ 44)

---

*Extends Plan 004b. Can be implemented independently — only touches LedgerPresenter
and LedgerView. No new models or storage keys required.*
