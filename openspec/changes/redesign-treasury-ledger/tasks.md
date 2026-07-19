## 1. Category-icon helper (shipped in the earlier increment)

- [x] 1.1 Add `lib/utils/category_icon.dart` — pure `categoryIcon(String? name, CategoryType type)` with an ordered keyword→icon table and a per-type fallback (income/expense/transfer). Unit-test the mapping (known keywords, unknown→fallback, each type). → 5 unit tests passing.

## 2. Wire the heuristic into the ledger row (shipped in the earlier increment)

- [x] 2.1 Use `categoryIcon` in `transaction_list_tile.dart` `_categoryIcon()` for non-transfer rows; keep the transfer swap glyph and all badge/subtitle/amount/interaction behavior unchanged.

## 3. Reference header layout

- [x] 3.1 Add a `Ledger` title row (`_LedgerHeader`), left-aligned, 23/800.
- [x] 3.2 Combine the Filter & sort pill and the month/year pill into one in-line controls row (`_LedgerControlsRow` + `_FilterSortButton` + `_MonthPill`); remove the standalone centered month row. Day filter stays inside the Filter & sort sheet.

## 4. Segmented IN / OUT / NET strip

- [x] 4.1 Replace the three summary chips with one segmented card (`_SummaryStrip`): three equal columns, hairline dividers, mono values — IN green, OUT red, NET blue (red when negative, `+/−` prefix). Values from the existing presenter getters.

## 5. "No background" rows

- [x] 5.1 Drop the per-row `AppCard` fill in `_buildTxnTile`; rows render on the screen background (swipe-delete + undo preserved).
- [x] 5.2 Subtitle = account name only, falling back to the category when a txn has no account; remove the account color dot. Title 14.5/600, subtitle 11.5 muted, badge 40/18.
- [x] 5.3 Amount colors stay semantic — expense red, income green, transfer neutral grey.

## 6. User-settable category icons

- [x] 6.1 Add `lib/utils/category_icon_catalog.dart` — `kCategoryIconCatalog` (const), `kCategoryIconGroups`, `kAutoCategoryIconKey` sentinel, and `resolveCategoryIcon(iconKey, name, type)` that prefers the stored catalog key and falls back to `categoryIcon(name, type)` for legacy/auto. Unit-tested (`test/utils/category_icon_catalog_test.dart`): catalog hit, auto→heuristic, legacy/unknown→heuristic, and every grouped key exists in the catalog.
- [x] 6.2 Render the resolved icon in `transaction_list_tile.dart` via `resolveCategoryIcon(category.icon, …)`.
- [x] 6.3 Add an icon picker to `manage_categories_sheet.dart` (`showCategoryIconPicker`): grouped catalog grid + an "Auto" option; tappable preview on the add form and on each category tile; persists via `updateCategory`. No model/storage migration (`FinanceCategory.icon` already persists).

## 7. Taller chat input (TTS deferred)

- [x] 7.1 Restyle the chat input pill (height 52) and send button (48); keep categories/form buttons, hint gating, and the send-arrow affordance. No voice/mic.

## 8. Verification

- [ ] 8.1 `dart format` + `flutter analyze` clean; unit + widget tests green. → Runs on CI (no local Flutter toolchain in the authoring environment); brace/import/reference review done by hand, no presenter API changed so presenter tests are unaffected.
- [ ] 8.2 Live smoke: header pills in line; IN/OUT/NET correct; rows no-bg with chosen category icon; pick an icon in Manage Categories and see it in the row; legacy category still shows a heuristic glyph; chat logging still works. → Deferred to device/emulator run.
