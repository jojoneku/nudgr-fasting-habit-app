## 1. Category-icon helper

- [x] 1.1 Add `lib/utils/category_icon.dart` — pure `categoryIcon(String? name, CategoryType type)` with an ordered keyword→icon table and a per-type fallback (income/expense/transfer). Unit-test the mapping (known keywords, unknown→fallback, each type). → 5 unit tests passing.

## 2. Wire into the ledger row

- [x] 2.1 Use `categoryIcon` in `transaction_list_tile.dart` `_categoryIcon()` for non-transfer rows; keep the transfer swap glyph and all badge/subtitle/amount/interaction behavior unchanged.

## 3. Verify the rest of the Ledger

- [x] 3.1 Confirm day headers, filter chips, summary card, and input bar already match the reference and read theme tokens; correct any drift only. → Verified: filter chips, summary card, day headers, and input bar already use colorScheme tokens; no drift, no structural change needed.

## 4. Verification

- [x] 4.1 `dart format` + `flutter analyze` clean; unit + widget tests green. → analyze: "No issues found"; 7/7 tests pass (5 icon + 2 dashboard).
- [ ] 4.2 Widget smoke on a live row (food/transport/salary → glyph; unknown/transfer → fallback/swap). → Covered by unit tests over the mapping; live on-device smoke deferred with dashboard 5.3.
