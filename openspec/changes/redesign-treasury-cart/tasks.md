## 1. Estimate accent alignment

- [x] 1.1 Swap the estimated-price accent from `colorScheme.secondary` to `context.appColors.fast` (blue) in the breakdown "~₱X est" chip, the item "~ · tap to confirm" subtitle, and the estimated line total; add the `app_colors` import.

## 2. Verify the rest of the Cart

- [x] 2.1 Confirm the running-total header, budget bar, steppers, price-state semantics, finish/checkout/history sheets, empty state, and undo are unchanged.

## 3. Verification

- [x] 3.1 `dart format` + `flutter analyze` clean.
- [ ] 3.2 Live smoke on device/web in both themes (confirmed / estimated / unpriced rows). → Deferred with the other tabs' live smoke.
