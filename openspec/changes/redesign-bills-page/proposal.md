## Why

The `redesign-treasury-bills` increment surfaced the next bill as a **DUE SOON hero** on top of the
existing flat screen. That was step one. The screen still opens as a stack of expandable sections, the
month control sits inline instead of in the header, and it mixes concerns the reference splits apart —
credit-card statements live here even though they're an **account** balance, not a monthly bill.

The Nudgr reference (`Nutrition Focus Treasury.dc.html`, Frame 3 + the "Bills" title frame) shows the
finished shape: a left-aligned **"Bills"** title with a **month·year picker** in the top-right, a
**swipeable stack** of due-soon cards, the Pending/Paid/Installments chips, a unified **"Coming up"**
timeline across every obligation type, then clean **titled sections** of tap-to-act cards — one card
per bill/receivable with its **category icon** and a **Pay / Receive** button. Credit cards move to
the Dashboard, under Accounts, where a balance belongs. This is a **restyle + finally-implement** of
the pieces the hero increment deferred; every existing capability (mark-paid, receivables, set-asides,
installments, quick-pay) is preserved, just re-homed and re-skinned.

## What Changes

- **Header into the app bar.** On the Bills tab the shared Treasury app bar title becomes **"Bills"**
  (left-aligned) and a **month + year picker** pill moves into the app bar actions (top-right).
  Other tabs keep the `TREASURY` title. The inline `_MonthSelector` is removed from the Bills body.
- **Swipeable due-soon stack.** Replace the single hero with a horizontally **swipeable stack** of the
  due-soon/overdue unpaid bills (reusing the existing `DueSoonHero` card inside a `PageView` with page
  dots and a stacked-behind visual). Each card keeps Mark-paid + edit, routing to the existing sheets.
- **"Coming up" timeline.** A new section listing the **top 5** upcoming items merged across all four
  types — bills, receivables, budgeted expenses, installments — in the reference's dot/line timeline
  style (inflows in green with a `+`, outflows neutral), sorted soonest-first with undated items last.
- **Titled card sections.** Replace the four expandable `_SectionCard`s with plain **titled sections**
  (Bills, Receivables, Budgeted, Installments). Each item renders a new **card**: leading **category
  icon**, name, amount, and date, with a right-aligned **Pay / Receive** button (paid/received items
  dim and show a check). Bills and receivables use their linked category's icon + color.
- **Credit cards move to the Dashboard.** Remove the credit-card section (and quick-pay) from Bills.
  On the Dashboard, reposition the existing **Credit** section **directly under the Accounts list** and
  add a **Pay** quick action (the `QuickPay` sheet is extracted to a shared widget and reused there).
- **Additive, pure presenter work.** New `imminentUnpaidBills` (list, for the stack), a merged
  `comingUpItems(installmentPresenter)` returning the sorted top-5, and category-lookup helpers. No
  stored state; existing getters and mutation paths untouched.

## Non-goals

- **No forms changes.** Add/edit bill/receivable/set-aside/installment sheets are out of scope; the new
  cards reuse the existing mark-paid / mark-received / edit sheets unchanged. (Category on the card is
  read-only display of the already-stored `categoryId`.)
- **No model/storage change or migration**, no new dependencies, no notification/reminder plumbing
  (the reference's bell stays a no-op affordance as it is today).
- **Not a rewrite of business logic** — credit-card statement generation, recurring auto-copy,
  quick-pay, and XP awards are moved/reused, not re-implemented.

## Capabilities

### Modified Capabilities
- `treasury-bills`: Extends the due-soon hero into the full Bills-tab structure — app-bar "Bills"
  title + month·year picker, a swipeable due-soon **stack**, a unified "Coming up" timeline across all
  obligation types, and titled sections of category-iconed Pay/Receive cards; credit cards are no
  longer part of this capability.
- `treasury-dashboard`: The Credit section is repositioned directly under the Accounts list and gains a
  quick **Pay** action, becoming the single home for credit-card balances.

## Impact

- **New:** `lib/views/treasury/bills/due_soon_stack.dart`,
  `lib/views/treasury/bills/obligation_card.dart`,
  `lib/views/treasury/bills/coming_up_timeline.dart`,
  `lib/views/treasury/shared/month_year_picker.dart`,
  `lib/views/treasury/shared/quick_pay_sheet.dart` (extracted from the bills view).
- **Modified:** `lib/presenters/bills_receivables_presenter.dart` (additive `imminentUnpaidBills`,
  `comingUpItems`, category helpers + the `ComingUpItem`/`ComingUpKind` output type);
  `lib/views/treasury/bills/bills_receivables_view.dart` (new body: stack, chips, timeline, titled
  sections; credit + inline month selector removed);
  `lib/views/treasury/treasury_module_view.dart` (dynamic app-bar title/actions; pass bills presenter
  to the dashboard for quick-pay);
  `lib/views/treasury/dashboard/treasury_dashboard_view.dart` (Credit section under Accounts + Pay).
- **Reuses (unchanged):** `DueSoonHero`, the mark-paid/received/edit sheets, `finance_format.dart`,
  `category_icon.dart`, `category_colors.dart` (`resolveSliceColor`), theme tokens.
- **Deps:** none new. **Risk:** medium — a structural view rebuild, but presenter changes are additive
  and all mutation flows are reused; verified with widget tests on the new widgets + a `flutter
  analyze` clean.
