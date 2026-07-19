## Why

The Budget tab is the fourth Treasury screen in the Nudgr redesign. It already lists per-group
category budgets with spent/allocated bars and a savings section — but it opens with a plain
three-number banner (Allocated / Spent / Remaining) that answers "how much" without answering the
question a budget screen exists to answer: **am I on track for the month?** The reference
(`Nutrition Focus Treasury.dc.html`, Frame 4) leads with a **pace-aware ring hero** (% spent + SPENT
/ of allocated + an "Ahead of pace" pill) and a **safe-to-spend / day** callout. This is a
**restyle + finally-surface**: replace the flat banner with the pace hero + safe-to-spend; the
category/savings sections stay.

## What Changes

- **Replace the three-number summary banner with a pace-ring hero**: a spent-percentage ring
  (`AppRingProgress`) beside the SPENT figure, "of {allocated}", and an **Ahead of pace / Over pace /
  Over budget** pill. Conveys the same allocated + spent + remaining relationship, plus pace.
- **Add a "Safe to spend · N days left" callout** (blue-tinted) showing remaining budget spread over
  the days left this month — shown only for the current month.
- **Add pure additive presenter getters**: `isCurrentMonth`, `daysLeftInSelectedMonth`,
  `monthElapsedFraction`, `isAheadOfPace`, `safeToSpendPerDay` (reusing the existing `percentUsed`,
  `totalSpent`, `totalAllocated`, `totalRemaining`).
- **Escalate the ring + pill to the danger accent when over budget.** The hero is hidden (with the
  empty state carrying the screen) when no budgets exist. Category/savings sections unchanged.
- Material icons + theme tokens only.

Non-breaking. No model/storage/navigation change; the hero reads existing budget totals.

## Non-goals

- **No presenter/business-logic rewrite.** Budget CRUD, spent/contributed calculation, group
  management, and warning notifications are untouched; the new getters are pure and additive.
- **Not a rebuild of the category or savings sections** — they already match the reference's
  by-category bars and are retained as-is.
- **No per-category pace/over-by projections** beyond what the tiles already show, and **no data
  migration or new dependencies.**

## Capabilities

### New Capabilities
- `treasury-budget`: The Budget tab's pace hero — a spent-percentage ring with the SPENT / of-allocated
  figures and an Ahead-of-pace / Over-pace / Over-budget pill, plus a current-month "safe to spend /
  day" callout, replacing the flat summary banner while retaining the category and savings sections;
  theme-aware (no hardcoded per-mode colors), pace/safe-to-spend shown only for the current month.

### Modified Capabilities
<!-- None. openspec/specs/ contains only `hub`; no existing budget capability, no other spec-level
     requirement changes. -->

## Impact

- **Modified:** `lib/presenters/budget_presenter.dart` (additive `isCurrentMonth`,
  `daysLeftInSelectedMonth`, `monthElapsedFraction`, `isAheadOfPace`, `safeToSpendPerDay`);
  `lib/views/treasury/budget/budget_view.dart` (pace hero + safe-to-spend replace `_SummaryBanner`).
- **Reuses (unchanged):** `AppRingProgress`, `AppCard`, category/savings sections + tiles,
  `finance_format.dart`, theme tokens.
- **Deps:** none new. **Risk:** low — additive getters + a header swap that preserves the same
  figures; verified with presenter unit tests over the pace math (past/current/future month).
