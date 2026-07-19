## Why

The History tab is the fifth Treasury screen in the Nudgr redesign. Its structure already mirrors the
reference (`Nutrition Focus Treasury.dc.html`, Frame 5) — a **CURRENT MONTH · LIVE** card above a
**CLOSED MONTHS** list — and each card is actually richer than the mock (net savings, ending cash,
bills paid, inflow/outflow). The one metric the reference emphasises that the current cards don't
surface is the **savings rate ("N% saved")**. This is a **restyle + finally-surface**: add the
savings rate; the layout and per-month detail stay.

## What Changes

- **Add a `savingsRate` computed getter** to `MonthlySummary` (`netSavings / totalInflow`, null when
  there's no income) — a pure model property.
- **Show "N% saved" on each history card** (current + closed months), tinted by whether net savings
  were positive, matching the reference's emphasis on the monthly savings rate.
- Everything else on the tab is unchanged (CURRENT MONTH / CLOSED MONTHS sections, the tap-through to
  the monthly detail view, trend/matrix data, empty state). Theme tokens only.

Non-breaking. No storage/serialization change (the getter is derived, not persisted); no navigation
change.

## Non-goals

- **No presenter/business-logic change.** Trend, matrix, averages, and month-close logic are
  untouched; `savingsRate` is a pure derived getter.
- **Not a rebuild of the cards or the monthly detail view** — they already exceed the reference's
  detail and are retained.
- **No data migration or new dependencies.**

## Capabilities

### New Capabilities
- `treasury-history`: The History tab's per-month savings-rate surfacing — each current/closed month
  card shows "N% saved" (net savings ÷ income), omitted when there was no income, tinted by
  net-savings sign, on top of the existing CURRENT MONTH · LIVE + CLOSED MONTHS layout; theme-aware.

### Modified Capabilities
<!-- None. openspec/specs/ contains only `hub`; no existing history capability, no other spec-level
     requirement changes. -->

## Impact

- **Modified:** `lib/models/finance/monthly_summary.dart` (additive pure `savingsRate` getter);
  `lib/views/treasury/history/monthly_summary_card.dart` (show "N% saved" in the header).
- **Reuses (unchanged):** `TreasuryHistoryPresenter`, the CURRENT MONTH / CLOSED MONTHS sections, the
  monthly detail view, `finance_format.dart`, theme tokens.
- **Deps:** none new. **Risk:** very low — one derived getter + one label; verified with model unit
  tests (positive/zero-income/negative).
