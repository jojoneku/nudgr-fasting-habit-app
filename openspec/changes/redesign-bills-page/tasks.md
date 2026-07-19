## 1. Presenter (additive, pure)

- [x] 1.1 Add `ComingUpKind` enum + `ComingUpItem` value type (kind, name, amount, isInflow, date?, dateLabel, source) to `bills_receivables_presenter.dart` — no Flutter imports.
- [x] 1.2 Add `List<Bill> get imminentUnpaidBills` — unpaid bills with `billDaysUntilDue <= 7` (incl. overdue), soonest-first (for the stack).
- [x] 1.3 Add `List<ComingUpItem> comingUpItems(InstallmentPresenter installments)` — merge unpaid bills, un-received receivables, unpaid budgeted expenses, and due-unpaid installments; sort dated-ascending, undated last; take 5. Build the per-kind `dateLabel`.
- [x] 1.4 Add category-lookup helper `FinanceCategory? categoryById(String id)` (existing getters untouched).

## 2. Shared widgets (extract before UI)

- [x] 2.1 Extract the quick-pay sheet to `lib/views/treasury/shared/quick_pay_sheet.dart` (public `QuickPaySheet` + a `showQuickPaySheet(...)` helper) from the bills view, unchanged behavior.
- [x] 2.2 Add `lib/views/treasury/shared/month_year_picker.dart`: `MonthYearPill(monthKey, onChanged)` (pill showing `MMM yyyy` + caret) opening a year-stepper + 4×3 month-grid bottom sheet. Theme tokens only; 44px targets.

## 3. Bills-tab widgets

- [x] 3.1 Add `lib/views/treasury/bills/due_soon_stack.dart`: swipeable `PageView` of `DueSoonHero` cards (page dots + stacked-behind visual); hidden when the list is empty.
- [x] 3.2 Add `lib/views/treasury/bills/obligation_card.dart`: reusable card (leading category-icon badge, name, `amount · date` subtitle, right-aligned Pay/Receive button; dimmed check when done).
- [x] 3.3 Add `lib/views/treasury/bills/coming_up_timeline.dart`: dot/line timeline rendering `ComingUpItem`s (kind-colored dots, inflow `+`/green), hidden when empty.

## 4. Bills view restructure

- [x] 4.1 Rewrite `bills_receivables_view.dart` body: due-soon stack → 3 stat chips → "Coming up" timeline → titled sections (Bills, Receivables, Budgeted, Installments) of `ObligationCard`s. Keep the FAB + all mark-paid/received/edit sheets.
- [x] 4.2 Remove the inline `_MonthSelector`, the `_CreditCardsSection`/`_CreditCardTile`, and the local `_QuickPaySheet` (now shared); resolve each card's category icon/color via the presenter helper + `resolveSliceColor`.

## 5. App bar (module) + credit re-home (dashboard)

- [x] 5.1 `treasury_module_view.dart`: rebuild on tab change; **hide the shared app bar on the Bills tab** (the Bills view now renders its own in-page "Bills" title + `MonthYearPill`, setting the month on both bills + installment presenters). Pass `billsPresenter` into `TreasuryDashboardView`. (Revised from "rename title" per user request to hide the app bar.)
- [x] 5.2 `treasury_dashboard_view.dart`: move the Credit section to render directly under the Accounts list; add a **Pay** action per credit card opening the shared `QuickPaySheet` (via the passed bills presenter). Null-safe when no bills presenter is supplied (dashboard refreshes via the presenter dependents chain).

## 6. Verification

- [ ] 6.1 `dart format` + `flutter analyze` clean. → **Not run — no Flutter/Dart SDK in this environment.** Reviewed manually; must be run in a Flutter env before merge.
- [ ] 6.2 Presenter unit tests: `imminentUnpaidBills`; `comingUpItems`. → Deferred (need mock setup + a runner not available here).
- [x] 6.3 Widget tests written: `ObligationCard` (Pay/Receive fires, done dims + check), `ComingUpTimeline` (rows + inflow `+`, tap, empty), `MonthYearPill` (label, opens sheet, month select fires / same-month no-op). `DueSoonStack` deferred (needs a presenter mock). **Not executed here.**
- [ ] 6.4 Existing `due_soon_hero_test.dart` + presenter tests still pass. → `DueSoonHero` reused unchanged; needs a run to confirm.
- [ ] 6.5 Live smoke (device/web, both themes): swipe the stack, mark a bill paid from a card, pay a credit card from the Dashboard, change month+year from the in-page pill. → deferred with other Treasury live smoke.
