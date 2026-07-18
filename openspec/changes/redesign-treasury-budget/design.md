## Context

The Budget tab (`budget_view.dart`) has a month selector, a flat `_SummaryBanner`
(Allocated / Spent / Remaining), per-group category sections (`CategoryBudgetTile` with spent vs
allocated bars), and a savings/goals section. `BudgetPresenter` already exposes `totalAllocated`,
`totalSpent`, `totalRemaining`, and `percentUsed`.

The reference (Frame 4) reframes the header into a **pace ring** — spent% ring + SPENT/of-allocated +
an "Ahead of pace" pill — plus a **safe-to-spend / day** callout. The category bars below already
match the reference's "By category" list.

## Goals / Non-Goals

**Goals:**
- Replace the flat banner with a pace-aware hero + safe-to-spend callout, conveying the same figures
  plus month-pace context.
- Keep pace math pure and additive; keep the category/savings sections intact.

**Non-Goals:**
- Rewriting budget calculation, group management, or the tiles.
- Per-category pace projections, data migration, or new dependencies.

## Decisions

- **Reuse `AppRingProgress`** for the spent ring (already used elsewhere), with the % + "spent" label
  as its center child. Rationale: no new painter; consistent ring visuals.
- **Additive pace getters on the presenter**, all pure: `isCurrentMonth`, `daysLeftInSelectedMonth`,
  `monthElapsedFraction` (1.0 past / 0.0 future / today-over-last-day current), `isAheadOfPace`
  (`percentUsed <= elapsed + 0.02` tolerance), `safeToSpendPerDay` (`remaining / daysLeft`, never
  negative, raw remaining when no days left). Rationale: keeps date math out of `build` (Rule 1) and
  makes pace unit-testable without the widget tree.
- **Pace + safe-to-spend only for the current month.** A closed month has no "pace"; a future month
  hasn't started. The view guards both on `isCurrentMonth`.
- **Replace `_SummaryBanner` rather than stacking it.** The hero conveys allocated + spent (and
  remaining via the ring + safe-to-spend), so keeping the banner too would duplicate. The class is
  removed to avoid dead code.
- **Danger accent when over budget/pace**, else the domain blue — blended for the ring/pill so both
  themes read correctly.
- **Hide the hero when there are no budgets** so the empty state carries the screen (no 0/0 ring).

## Risks / Trade-offs

- **[Removing the explicit "Remaining" number]** → It's still derivable (ring + spent/allocated) and
  the safe-to-spend callout expresses remaining as a per-day figure; net clarity is higher, not lower.
- **[Pace tolerance tuning]** → A ±2% tolerance avoids "over pace" flicker at exactly on-pace; a pure
  function with unit tests, easy to adjust.
- **[Month-boundary correctness]** → `monthElapsedFraction`/`daysLeftInSelectedMonth` are computed
  from the selected month vs today, tested for past/current/future.

## Migration Plan

None — additive presenter getters + a header swap. Ships on `feat/redesign-treasury`; rollback
restores the old banner.

## Open Questions

- Later: per-category "over by ₱X — trim next week" hints (reference) on the category tiles, out of
  scope for this increment.
