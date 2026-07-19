## Context

`budget_view.dart` today: a `_MonthSelector` (`< June >` steppers + manage-groups icon), a flat
`_SummaryBanner` (Allocated / Spent / Remaining), then per-group sections — each an outlined `AppCard`
with `CategoryBudgetTile` rows separated by dividers — and a savings section rendered **last**.
`BudgetPresenter` exposes `totalAllocated`, `totalSpent`, `percentUsed`, `categoriesByGroup`,
`savingsBudgets`, `expenseGroups`, and per-category getters. Categories carry `icon` (name) + `colorHex`;
the app resolves a glyph via `categoryIcon(name, type)` and a color via `resolveSliceColor(hex, i, …)`
(used in ledger/dashboard), so "same icons per card" means reusing those two helpers.

The reference (Frame 4) shows: big "Budget" title + "June ▾" dropdown, a spent% ring with SPENT / of
allocated + an on-pace pill, then budget rows as individual cards with a leading icon chip.

## Goals / Non-Goals

**Goals**
- Title + month-dropdown header; spent-vs-budgeted ring hero (no safe-to-spend).
- One `AppCard` per budget with the category's icon+color, progress, over-budget hint, and an
  expandable transaction list.
- Sections ordered Living Expense → Savings → Variable → Non-Negotiables, savings interleaved.
- Keep pace math and ordering pure/additive in the presenter (Rule 1: no logic in `build`).

**Non-Goals**
- Rewriting budget/spent math, group CRUD, notifications, or the web Budget table.
- New safe-to-spend logic (removed here), per-category projections, migration, or new deps.

## Decisions

- **Default group reorder in the model, not a view constant.** Change `BudgetGroupDef.defaultGroups`
  `sortOrder` to Living Expense=0, Savings=1, Variable/Optional=2, Non-Negotiables=3. Rationale:
  honors user reordering (stored overrides still win via `merge`) while giving the requested order
  out of the box; a hardcoded view order would silently ignore manage-groups. The savings group is no
  longer special-cased to the bottom.
- **Unified `budgetSections` view-model on the presenter.** One ordered list where each entry is a
  group with its display rows — expense rows (category + budget + spent + txns) or savings rows
  (account + contributed) — plus section allocated/spent totals. The view iterates this and never
  branches on savings vs expense or recomputes ordering in `build`. Empty groups are omitted.
- **Reuse `AppRingProgress`** for the ring hero (spent% center, "spent" label), escalating ring + pill
  to `colorScheme.error` when over budget, else the domain blue (`appColors.fast`), blended for both
  themes. Pace pill (`isAheadOfPace`) shown only when `isCurrentMonth`.
- **Additive, pure pace getters:** `isCurrentMonth`, `monthElapsedFraction` (1.0 past / 0.0 future /
  today÷last-day current), `isAheadOfPace` (`percentUsed <= elapsed + 0.02`). No date math in the
  widget; unit-testable without the tree. Safe-to-spend getters are intentionally not added.
- **`BudgetCard` widget** (new file) absorbs `CategoryBudgetTile`: leading icon chip
  (`categoryIcon` + `resolveSliceColor` tinted background), name, spent / allocated (red when over),
  `AppLinearProgress` + %, an "Over by ₱x" line when over, and a tap-to-expand transaction list
  (`transactionsForCategory`). Savings budgets use a sibling `_SavingsBudgetCard` (flag/savings icon,
  contributed / goal, tertiary when met). Each card is its own `AppCard` with vertical spacing — the
  shared divided group card is gone. `category_budget_tile.dart` is removed to avoid dead code.
- **Month switcher = `AppActionSheet`** listing a window of months (≈12 back to 2 ahead) centered on
  today; the header pill shows `monthLabel` + a caret. Rationale: reuses the system sheet, keeps the
  44×44 target, and avoids a bespoke calendar. Prev/next stays reachable by picking adjacent months.
- **Keep manage-groups + FAB.** Manage-groups moves to a small icon button beside the month pill
  (feature not shown in the reference must not be dropped — config rule). FAB unchanged.

## Risks / Trade-offs

- **[Reordering default sortOrder]** → affects any surface reading `groups`/`expenseGroups` order (web
  table, manage-groups list). Acceptable: the order is more intuitive and consistent; users who
  customized keep their order. Documented in tasks so the web table is smoke-checked.
- **[Removing the explicit Remaining number]** → still derivable from the ring + SPENT/of-allocated;
  net clarity rises and matches the reference.
- **[Per-card `AppCard` vs one grouped card]** → slightly more vertical space, but far better scanning
  and the icon identity the brief asks for; spacing tuned to keep density reasonable.
- **[Month-boundary correctness]** → `monthElapsedFraction`/`isCurrentMonth` computed from the selected
  month vs today; covered by past/current/future unit tests.

## Migration Plan

None — additive presenter members + a default-order tweak + a view rebuild. No stored data changes
(existing budgets keep their `group` id; only unset default ordering shifts). Ships on the redesign
branch; rollback restores the banner + grouped card.

## Open Questions

- Later: per-category "trim next week" coaching copy and sparthan-line trends on each card — out of
  scope for this increment.
