## Context

The History tab (`treasury_history_view.dart`) already renders a CURRENT MONTH section with a LIVE
badge over a CLOSED MONTHS list of `MonthlySummaryCard`s, each showing net savings, ending cash,
bills paid, and inflow/outflow — structurally matching and exceeding the reference (Frame 5). The
`TreasuryHistoryPresenter` exposes summaries, trend points, and averages. The only reference metric
absent from the cards is the per-month savings rate.

## Goals / Non-Goals

**Goals:**
- Surface each month's savings rate ("N% saved") on its card.

**Non-Goals:**
- Any change to trend/matrix/averages logic, the monthly detail view, or month-close.
- Storage/serialization changes or migration.

## Decisions

- **`savingsRate` as a pure getter on `MonthlySummary`.** `netSavings / totalInflow`, null when
  income is 0. Rationale: it's a derivation over the model's own fields, so it belongs on the model
  (not persisted, no migration), and keeps the calc out of `build` (Rule 1). *Alternative:* compute
  in the card — rejected (math in build; also useful elsewhere, e.g. averages).
- **Render "N% saved" in the card header**, tinted by the net-savings sign (success when positive,
  error when negative), omitted when `savingsRate` is null. Rationale: matches the reference's
  emphasis with minimal restructuring.

## Risks / Trade-offs

- **[Negative savings rate]** → Shown tinted error (overspent the month); the label reads e.g.
  "−20% saved" via the sign of the value — acceptable and informative.
- **[Header crowding on the LIVE card]** → The rate sits before the LIVE badge and chevron; short
  ("45% saved") so it fits; verified against the widest realistic values.

## Migration Plan

None — a derived getter + a label. Ships on `feat/redesign-treasury`; rollback removes the label.

## Open Questions

- Later: the reference's richer History (trend sparkline, goal-checks, KPI tiles) — the presenter
  already computes trend/averages, so a follow-up could add a trend header. Out of scope here.
