## 1. Presenter (additive only)

- [x] 1.1 Add pure getters to `BillsReceivablesPresenter`: `imminentUnpaidBill`, `billDueDate`, `billDaysUntilDue`, `billDueInfo` (label + overdue + imminent). No stored state; existing getters untouched.

## 2. Due-soon hero widget

- [x] 2.1 Add `lib/views/treasury/bills/due_soon_hero.dart` — dumb, theme-token gradient card (bills accent; danger when overdue) with due label, name, subtitle, amount, Mark-paid button + edit affordance.

## 3. Wire into the Bills view

- [x] 3.1 Add `_DueSoonHeroSection` at the top of the bills list; resolve name/amount/dueLabel/subtitle from the presenter; show only when due within 7 days or overdue; route Mark-paid/edit to the existing sheets.

## 4. Verification

- [x] 4.1 `dart format` + `flutter analyze` clean.
- [x] 4.2 Widget test on `DueSoonHero`: renders label/name/subtitle/amount, Mark-paid + edit fire callbacks, overdue uses the error accent/icon.
- [ ] 4.3 Live smoke on device/web in both themes with a due-soon and an overdue bill. → Deferred with the dashboard/ledger live smoke.
