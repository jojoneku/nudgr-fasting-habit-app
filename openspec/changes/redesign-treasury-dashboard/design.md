## Context

The Treasury Dashboard is the finance module's landing tab (`TreasuryDashboardView`, mounted at index
0 of `TreasuryModuleView`). It renders a `CashSummaryBanner`, a 2×2 `MetricCardsGrid`, an accounts
grid, and a stack of analytics cards (spending analytics, category pie, upcoming bills, budget
overview, goals & savings, credit, held/external funds). All numbers come from
`TreasuryDashboardPresenter`, which already exposes everything the reference needs — `netWorth`,
`monthNetCashFlow`, `monthTotalInflow` / `monthTotalOutflow`, `forecastedNetBalance`, `liquidAccounts`,
`heldAmountByAccountId`, and `netWorthTrend()`.

The redesign reference (`Nutrition Focus Treasury.dc.html`, Frame 1) reframes the top of the screen
into: a greeting + "Treasury" title + "Synced" pill header, a blue-gradient **NET WORTH hero** with a
trend pill and sparkline, a **cashflow strip** (income/expense bars ending in "Projected spare"), and
a compact **Accounts** list with a "+N more accounts" expander. The web companion
(`web_dashboard_page.dart`, Plan 050-A) already mirrors this structure with the shared web design
system; it needs a token/contrast pass, not a rebuild.

Constraints: MVP architecture (no math in `build()`), theme-aware colors only (read
`Theme.of(context)` / `context.appColors`; direct `AppColors`/`AppColorsLight` only in
`fasting_app.dart`), Material icons (not Phosphor), and the standing rule — mirror the reference but
never delete existing features absent from it.

## Goals / Non-Goals

**Goals:**
- Rebuild the **top** of the mobile dashboard to the reference: header, NET WORTH hero + sparkline,
  cashflow strip, Accounts list with overflow expander.
- Re-skin the retained analytics cards to Nudgr tokens without changing content or behavior.
- Align the web dashboard to the shipped Nudgr tokens/contrast.
- Keep the presenter's public API stable; add at most small additive computed getters.

**Non-Goals:**
- The other Treasury tabs (Ledger, Bills, Budget, History, Cart) — later increments.
- Any presenter/model/storage/business-logic change or migration.
- Reworking the add/edit-account, goal-savings, or credit "Pay Now" flows (styling only).

## Decisions

- **Extract the new top section into focused widgets** under `lib/views/treasury/dashboard/`:
  `net_worth_hero.dart` (hero card + sparkline painter), `cashflow_strip.dart`, and an accounts-list
  widget (rows + "+N more" expander). Rationale: keeps `treasury_dashboard_view.dart` a thin
  composition root and mirrors how the Hub/Nutrition redesigns were structured. *Alternative:* inline
  everything in the view — rejected; it would bloat `build()` and hurt reuse/testing.

- **Sparkline is a new small `CustomPainter`** driven by `netWorthTrend()` values, not a new charting
  dependency. Rationale: the mobile side has no line-chart widget (only ring/pie painters), the
  sparkline is a trivial polyline + area fill, and the reference draws exactly that. *Alternative:*
  pull in a charts package — rejected (new dependency for one sparkline).

- **Net-worth momentum via an additive presenter getter.** The trend pill needs a month-over-month
  net-worth delta and percentage. If not already derivable, add a pure getter (e.g.
  `netWorthMonthDelta` / `netWorthMonthDeltaPct`) computed from `netWorthTrend()` — no stored state,
  no behavior change. Rationale: keeps the "±%" out of `build()` per the no-math rule.

- **"Projected spare" = `forecastedNetBalance`.** The reference's "Projected spare" maps to the
  presenter's existing month-end forecast (already used by the web dashboard's "Proj. Month-End
  Cash"), so mobile and web report the same number. "Days left" is derived from the current date.

- **Cashflow bars are sized relative to the larger of income/expense** so the dominant flow fills the
  bar and the other is proportional — matching the reference (income bar full, expense ~61%).

- **Accounts list collapses beyond a threshold (default 3, matching the reference's "+3 more").**
  Tapping a row opens the existing edit sheet; the Add-account FAB is retained. Rationale: preserves
  all current behavior while adopting the reference's compact list.

- **Sync pill is additive and best-effort.** Render a status pill in the header sourced from existing
  sync state; wire it via an optional parameter so `TreasuryDashboardView`'s existing call sites keep
  working. Rationale: honors "no new sync plumbing" and keeps the constructor backward-compatible.
  *Alternative:* thread `SyncPresenter` as a required dependency — deferred to avoid touching the
  composition root in a view-only change.

- **Web dashboard: token/contrast alignment only.** Audit `web_dashboard_page.dart` against the
  shipped Nudgr tokens (accents, surfaces, chart colors) and adjust where it drifts; do not restructure
  its cards. Rationale: it already implements the reference IA (Plan 050-A).

## Risks / Trade-offs

- **[Dropping a retained card during re-skin]** → Work against a card-inventory checklist: cash
  summary, metric grid, accounts, spending analytics, category pie, upcoming bills, budget overview,
  goals & savings, credit, held/external funds — each must still render with its data guard intact.
- **[Sparkline with sparse/flat history]** → Degrade gracefully: hide the sparkline and % pill when
  `netWorthTrend()` has fewer than two points; clamp a flat series to a centered line rather than
  dividing by a zero range.
- **[Hero gradient contrast in light mode]** → The reference gradient is dark-canonical; derive a
  light-mode variant from tokens so text/accent contrast holds, verified in both themes.
- **[Duplicate net-worth surfaces]** → The hero now leads with net worth, and `MetricCardsGrid` /
  `CashSummaryBanner` may also show it; consolidate so the same figure isn't shown twice adjacently
  (fold the redundant metric tile rather than removing the grid).

## Migration Plan

None — view-layer only, no data or storage change. Rollout is a normal feature branch
(`feat/redesign-treasury-dashboard`) → PR to `dev`. Rollback is reverting the PR; no data touched.

## Open Questions

- Should the header sync pill reflect *live* sync progress now, or ship as a static status pill and
  wire live state when the Ledger/Bills increments touch the composition root? (Leaning: static now,
  live later.)
- Does the reference's "+2.7% / +₱12,840 this month" pill use net-worth delta or cash-flow delta? We
  map it to net-worth month-over-month for consistency with the hero's own figure; confirm on review.
