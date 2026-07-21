## 1. Category-icon helper (shipped in the earlier increment)

- [x] 1.1 Add `lib/utils/category_icon.dart` — pure `categoryIcon(String? name, CategoryType type)` with an ordered keyword→icon table and a per-type fallback (income/expense/transfer). Unit-test the mapping (known keywords, unknown→fallback, each type). → 5 unit tests passing.

## 2. Wire the heuristic into the ledger row (shipped in the earlier increment)

- [x] 2.1 Use `categoryIcon` in `transaction_list_tile.dart` `_categoryIcon()` for non-transfer rows; keep the transfer swap glyph and all badge/subtitle/amount/interaction behavior unchanged.

## 3. Reference header layout

- [x] 3.1 Add a `Ledger` title row (`_LedgerHeader`), left-aligned, 23/800.
- [x] 3.2 Combine the Filter & sort pill and the month/year pill into one in-line controls row (`_LedgerControlsRow` + `_FilterSortButton` + `_MonthPill`); remove the standalone centered month row. Day filter stays inside the Filter & sort sheet. Guard against overflow on narrow screens (Expanded + loose Flexible, ellipsizing label).
- [x] 3.3 Hide the module's shared "TREASURY" app bar while the Ledger tab is active (`treasury_module_view.dart`) so the Ledger's own title owns the top; flip the Ledger's top `SafeArea` on to clear the status bar. Other tabs keep the app bar.

## 4. Segmented IN / OUT / NET strip

- [x] 4.1 Replace the three summary chips with one segmented card (`_SummaryStrip`): three equal columns, hairline dividers, mono values — IN green, OUT red, NET blue (red when negative, `+/−` prefix). Values from the existing presenter getters.

## 5. "No background" rows

- [x] 5.1 Drop the per-row `AppCard` fill in `_buildTxnTile`; rows render on the screen background (swipe-delete + undo preserved).
- [x] 5.2 Subtitle = account name only (category name dropped — the icon carries it), falling back to the category when a txn has no account. Keep the account color dot before the account name (retained from the pre-redesign row so accounts stay distinguishable). Title 14.5/600, subtitle 11.5 muted, badge 40/18.
- [x] 5.3 Amount colors stay semantic — expense red, income green, transfer neutral grey.

## 6. User-settable category icons

- [x] 6.1 Add `lib/utils/category_icon_catalog.dart` — `kCategoryIconCatalog` (const), `kCategoryIconGroups`, `kAutoCategoryIconKey` sentinel, and `resolveCategoryIcon(iconKey, name, type)` that prefers the stored catalog key and falls back to `categoryIcon(name, type)` for legacy/auto. Unit-tested (`test/utils/category_icon_catalog_test.dart`): catalog hit, auto→heuristic, legacy/unknown→heuristic, and every grouped key exists in the catalog.
- [x] 6.2 Render the resolved icon in `transaction_list_tile.dart` via `resolveCategoryIcon(category.icon, …)`.
- [x] 6.3 Add an icon picker to `manage_categories_sheet.dart` (`showCategoryIconPicker`): grouped catalog grid + an "Auto" option; tappable preview on the add form and on each category tile; persists via `updateCategory`. No model/storage migration (`FinanceCategory.icon` already persists).
- [x] 6.4 Name-monogram fallback so unmatched categories stay visually distinct: `resolveCategoryBadge` resolves in order catalog icon → keyword glyph → name monogram → per-type generic icon; `categoryMonogram` derives 1 letter (single word) / first-two initials (multi-word); new shared `CategoryBadge` widget renders icon-or-monogram, wired into the ledger row and Manage Categories (tile + add-form preview). Unit-tested (monogram derivation + badge resolution order).

## 7. Taller chat input (TTS deferred)

- [x] 7.1 Restyle the chat input pill (height 52) and send button (48); keep categories/form buttons, hint gating, and the send-arrow affordance. No voice/mic.

## 8. Verification

- [ ] 8.1 `dart format` + `flutter analyze` clean; unit + widget tests green. → Runs on CI (no local Flutter toolchain in the authoring environment); brace/import/reference review done by hand, no presenter API changed so presenter tests are unaffected.
- [ ] 8.2 Live smoke: header pills in line; IN/OUT/NET correct; rows no-bg with chosen category icon; pick an icon in Manage Categories and see it in the row; legacy category still shows a heuristic glyph; chat logging still works. → Deferred to device/emulator run.

## 9. Review-driven consistency polish

- [x] 9.1 Restore the account color dot in the ledger row subtitle (dropped in the reskin) — superset guardrail; category name stays removed (icon carries it).
- [x] 9.2 Manage Categories: live-rebuild the add-form icon/monogram preview as the name is typed.
- [x] 9.3 Manage Categories: tint the category badge with the category's own color (matches the ledger row) instead of the flat type accent — on existing-category tiles AND the add-form icon preview (previews the color the new category will get); 44×44 hit area around the tappable icon.
- [x] 9.4 Add screen-reader semantics (Income/Expenses/Net + value) to the abbreviated IN/OUT/NET strip via `excludeSemantics` so the value isn't announced twice.
- [x] 9.6 `categoryMonogram` skips words with no Latin letter/digit (e.g. a leading emoji), so "🎮 Games" → "G" instead of a generic glyph. Unit-tested.
- [x] 9.7 Stamp `updatedAt` centrally in `LedgerPresenter.addCategory`/`updateCategory` (was left at epoch-0 / unchanged by the copyWith call sites) so category creates and edits — including the new icon picker — win under last-write-wins sync. The one-time colour migration still saves directly (no timestamp churn).
- [x] 9.5 Unify the minus glyph (U+2212) across the strip, row amounts, and daily-net badge; the daily-net badge now signs negatives explicitly (was color-only).
