## Why

The Budget tab lists spending limits, but it renders them as **one shared card per group** with each
category crammed into a divided row. Categories now carry an icon and color (used everywhere else in
Treasury — ledger, dashboard), yet the Budget tab shows neither, so a budget row reads as a flat name
+ bar with no glanceable identity. The header is also a utilitarian `< June >` stepper with a plain
three-number banner (Allocated / Spent / Remaining) that never answers the question the screen exists
to answer — *am I on track this month?*

The Nudgr reference (`Nutrition Focus Treasury.dc.html`, Frame 4 "Budget · pace-aware") reframes the
screen: a **big "Budget" title with a month dropdown** top-right, a **spent-vs-budgeted ring hero**
with an on-pace pill, and budgets listed as **individual cards**. This is a **restyle + finally-
surface** of data the presenter already computes — no new budget concepts.

## What Changes

- **Header:** replace the `< June >` stepper + three-number banner with a large **"Budget" title** and
  a **month-switcher dropdown** (tap "June ▾" → month picker) top-right. Manage-groups stays reachable.
- **Ring hero (top card):** a spent-percentage ring (`AppRingProgress`) beside **SPENT ₱x / of ₱y**
  and an **Ahead-of-pace / Over-pace / Over-budget** pill — budgeted-vs-spent at a glance. The old
  three-number `_SummaryBanner` is removed. **No "safe to spend" callout** — the Dashboard already owns
  that figure, so duplicating it here is dropped.
- **One card per budget:** each category budget becomes its **own `AppCard`** with the category's
  **icon in a color chip** (the same icon/color it uses in the ledger & dashboard), name, spent /
  allocated, a progress bar with %, and an **"Over by ₱x" hint** when exceeded. Replaces the shared
  divided group card.
- **Grouped by budget type, reordered:** sections render **Living Expense → Savings → Variable /
  Optional → Non-Negotiables** (the reference's group-first ordering), with the savings group
  interleaved at its position rather than always dumped last.
- **Transactions per budget:** each budget card keeps an **expandable transaction list** (not shown in
  the reference — designed here) so a budget's spend is auditable inline.
- **Additive pace getters** on `BudgetPresenter`: `isCurrentMonth`, `monthElapsedFraction`,
  `isAheadOfPace`, and an ordered `budgetSections` view-model (reusing existing `percentUsed`,
  `totalSpent`, `totalAllocated`). Phosphor-style Material icons + theme tokens only.

Non-breaking. No storage schema, navigation, or budget-math change; only the default group ordering
and the view/presenter presentation change.

## Non-goals

- **No budget-calculation rewrite.** Spent/contributed/received math, budget CRUD, group management,
  and warning notifications are untouched; new presenter members are pure and additive.
- **No new "safe to spend" logic** — it is intentionally *removed* from this screen, not reworked.
- **No per-category pace projection** beyond the over-budget hint, no data migration, no new deps, and
  **no change to the web Budget table** (`web_budget_page.dart` keeps its own layout).
- **Not deleting** the savings/goals concept, manage-groups, or the FAB — only their presentation moves.

## Capabilities

### New Capabilities
- `treasury-budget`: The Budget tab presents a title + month-dropdown header, a spent-vs-budgeted ring
  hero with an on-pace pill, and one card per budget (category icon + color, progress, over-budget
  hint, expandable transactions), grouped Living Expense → Savings → Variable → Non-Negotiables;
  theme-aware, with the pace pill shown only for the current month.

### Modified Capabilities
<!-- None. openspec/specs/ contains only `hub`; no existing budget capability spec to amend. -->

## Impact

- **Modified:** `lib/models/finance/budget_group_def.dart` (default `sortOrder` reordered so savings
  sits between living-expense and variable); `lib/presenters/budget_presenter.dart` (additive
  `isCurrentMonth`, `monthElapsedFraction`, `isAheadOfPace`, `budgetSections` view-model);
  `lib/views/treasury/budget/budget_view.dart` (title + month dropdown, ring hero, per-budget cards,
  unified group ordering — `_SummaryBanner` removed).
- **New:** `lib/views/treasury/budget/budget_card.dart` (per-budget card, replacing/absorbing
  `category_budget_tile.dart`); a `_MonthSwitcher` picker.
- **Reuses (unchanged):** `AppRingProgress`, `AppCard`, `AppLinearProgress`, `AppActionSheet`,
  `categoryIcon`, `resolveSliceColor`, `finance_format.dart`, theme tokens.
- **Deps:** none new. **Risk:** low-medium — additive presenter members + a view rebuild; the default
  reorder only affects users who never customized group order (stored overrides win via `merge`).
  Verified with presenter unit tests (pace + ordering) and a light/dark smoke of ahead/over states.
