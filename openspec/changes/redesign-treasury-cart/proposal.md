## Why

The Cart (grocery running-total) tab is the sixth and final Treasury screen in the Nudgr redesign. It
was built as the "running total" feature (Plan 038) directly mirroring the reference
(`Nutrition Focus Treasury.dc.html`, Frame 7), so it already matches it almost exactly — a RUNNING
TOTAL header (grand total + confirmed/estimated/unpriced breakdown + budget bar), an items list with
price-state subtitles and −/+ quantity steppers, and a Finish-trip / Add-item bottom bar. The only
drift from the reference is the **accent used for estimated (remembered) prices**: the reference uses
the blue accent, the code uses `colorScheme.secondary`. This increment is a **token alignment** — no
structural change.

## What Changes

- **Use the blue domain accent (`context.appColors.fast`) for estimated prices** instead of
  `colorScheme.secondary`, in the breakdown "~₱X est" chip, the item "~₱X · tap to confirm" subtitle,
  and the estimated line-total — matching the reference's blue treatment for not-yet-confirmed prices.
- Everything else on the tab is unchanged (header, budget bar, steppers, price-state semantics,
  finish/checkout/history sheets, empty state, undo).

Non-breaking. No presenter/model/storage/navigation change.

## Non-goals

- **No presenter/business-logic change** — running total, price memory, budget, checkout, and trip
  history are untouched.
- **Not a rebuild** — the tab already mirrors the reference; this only corrects the estimate accent.
- **No new dependencies or data migration.**

## Capabilities

### New Capabilities
- `treasury-cart`: The Cart tab's price-state accent alignment — estimated (remembered) prices use the
  blue domain accent across the breakdown chip, item subtitle, and line total, matching the Nudgr
  reference, while confirmed (neutral) and unpriced (danger) states and all cart behavior are
  retained; theme-aware.

### Modified Capabilities
<!-- None. openspec/specs/ contains only `hub`; no existing cart capability, no other spec-level
     requirement changes. -->

## Impact

- **Modified:** `lib/views/treasury/grocery/grocery_cart_view.dart` (estimate accent → blue in three
  spots; add the `app_colors` import).
- **Reuses (unchanged):** `GroceryCartPresenter`, the header/list/stepper/bottom-bar structure, the
  checkout/history/set-price/set-budget sheets, theme tokens.
- **Deps:** none new. **Risk:** minimal — a color-token swap on an already-reference-aligned screen;
  verified by `flutter analyze` and the existing grocery cart tests.
