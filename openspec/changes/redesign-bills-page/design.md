## Context

After `redesign-treasury-bills`, `bills_receivables_view.dart` (~1.9k lines) has: an inline
`_MonthSelector`, the `DueSoonHero` section, a `_StatsBar` (Pending/Paid/Installments), a
`_CreditCardsSection` (+ `_QuickPaySheet`), and four expandable `_SectionCard`s (bills, receivables,
budgeted, installments) with their tiles and mark-paid/received/edit sheets. The shared
`TreasuryModuleView` owns a centered `TREASURY` app bar over a 6-tab `TabBar`. The Dashboard
(`treasury_dashboard_view.dart`) already has a `_CreditSection` (payable + utilization + due), placed
low in the scroll, tap-to-edit only.

Domain data: `Bill` (dueDay + month → due date, `categoryId`), `Receivable` (`expectedDate`,
`categoryId`), `BudgetedExpense` (no date), `Installment` (due-this-month, no day). Categories carry a
name + `colorHex`; `category_icon.dart#categoryIcon` and `category_colors.dart#resolveSliceColor`
already turn those into a Material icon + a theme-aware color.

## Goals / Non-Goals

**Goals**
- Match the reference's Bills structure: app-bar title + month·year picker, swipeable due-soon stack,
  "Coming up" timeline across all types, titled Pay/Receive card sections with category icons.
- Re-home credit cards on the Dashboard under Accounts with a Pay action, without losing quick-pay.
- Keep all presenter additions pure/additive; reuse every existing mutation flow and sheet.

**Non-Goals**
- Add/edit forms, model/storage/migrations, notification wiring, or business-logic rewrites.

## Decisions

- **App bar hidden on the Bills tab; header moves in-page.** `TreasuryModuleView` rebuilds on tab
  change (a `setState` in the existing `_onTabChanged`) and passes `appBar: index == 2 ? null : AppBar('TREASURY')`.
  The Bills view renders its own header (a large left-aligned "Bills" title + a `MonthYearPill` at
  top-right) wrapped in `SafeArea` since there's no app bar to clear the status bar. The picker sets the
  month on both the bills and installment presenters (the view owns both). *Alternative:* rename the
  shared app bar title to "Bills" and put the pill in its actions — was the first cut, changed per the
  user's request to hide the app bar so the reference's in-page header shows.
- **Month + year picker is a shared widget.** `MonthYearPill(monthKey, onChanged)` shows
  `MMM yyyy` + a caret and opens a bottom sheet with a year stepper (◀ 2026 ▶) and a 3×4 month grid.
  Selecting a month calls back into the module, which sets the month on **both** the bills and
  installment presenters (today's `_setMonth`). Rationale: the reference explicitly wants month **and**
  year; the inline chevron selector couldn't jump years.
- **Swipeable stack reuses `DueSoonHero` unchanged.** `DueSoonStack(bills, onMarkPaid, onEdit, …)`
  wraps the existing card in a `PageView` (viewportFraction ~0.92) with page dots and a subtle
  stacked-behind card for depth. Reusing the widget keeps its passing widget test green. Contents:
  `presenter.imminentUnpaidBills` (unpaid, `daysUntilDue <= 7`, incl. overdue, soonest-first). Hidden
  when empty. *Alternative:* a brand-new card — rejected (needless churn, breaks the tested widget).
- **"Coming up" is presenter-computed (Rule 1).** `comingUpItems(InstallmentPresenter)` merges unpaid
  bills, un-received receivables, unpaid budgeted expenses, and due-unpaid installments into a list of
  a small value type `ComingUpItem { kind, name, amount, isInflow, date?, dateLabel, source }`, sorts
  dated-ascending with undated last, and takes 5. The view maps `source` (Bill/Receivable/…) back to
  the right action. `ComingUpKind` drives the timeline dot color. The type is defined in the presenter
  file (its output), carries no Flutter types, so the presenter stays UI-free.
- **One reusable `ObligationCard`.** Leading `AppIconBadge(categoryIcon, categoryColor)`; title = name;
  subtitle = `formatPeso(amount) · dateLabel`; trailing = a `Pay`/`Receive` `FilledButton` (44px) or,
  when done, a dimmed check. Sections are plain `title + column of cards` (no `ExpansionTile`). The
  view resolves icon/color per item from `presenter.categoryById(...)` + `categoryIcon` +
  `resolveSliceColor(brightness)` — the same in-`build` icon/color resolution the ledger tiles already
  use in this codebase. Installments/budgeted (no category link) fall back to their type accent.
- **Credit cards: delete from Bills, re-home on Dashboard.** Remove `_CreditCardsSection` +
  `_QuickPaySheet` from the bills view; extract the quick-pay sheet to
  `shared/quick_pay_sheet.dart`. On the Dashboard, move `_CreditSection` to render **immediately after
  the Accounts list** and give each credit card a **Pay** action that opens the shared sheet.
  Quick-pay lives on `BillsReceivablesPresenter`, so `TreasuryModuleView` passes `billsPresenter` into
  `TreasuryDashboardView` (new optional param) for the Pay callback, reloading the dashboard after.
  *Alternative:* duplicate quick-pay onto the dashboard presenter — rejected (logic duplication).

## Risks / Trade-offs

- **[Structural view rebuild]** → higher regression surface than the additive hero. Mitigation: reuse
  all sheets/flows verbatim; cover the new widgets (stack, card, timeline) with widget tests; keep the
  presenter changes pure and unit-testable.
- **[Cross-presenter merge for "Coming up"]** → installments live in `InstallmentPresenter`. Passing it
  into `comingUpItems` keeps the merge in one place without a new coupling in the constructor.
- **[Credit Pay needs the bills presenter on the dashboard]** → threaded as an optional constructor
  param from the module (which already holds both presenters); null-safe so the dashboard still builds
  standalone (e.g. in tests) without a Pay action.
- **[Duplicate spotlight]** → a due-soon bill shows in both the stack and its section; acceptable and
  matches the reference (stack = call-to-action, section = record).

## Migration Plan

None — additive presenter + view restructure. No stored data changes; credit-card statement bills are
untouched (only their *live-balance* card moves screens). Rollback = revert the view/module/dashboard
edits; the new presenter members are inert if unused.

## Open Questions

- The reference's per-card bell (reminder) affordance stays out until notification plumbing lands.
- Whether due-soon **receivables** should also join the swipe stack — deferred; this increment keeps the
  stack bills-only per the reference, with receivables surfaced in "Coming up" and their own section.
