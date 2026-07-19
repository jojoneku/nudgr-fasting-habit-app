## Context

Three sheets create/edit Bills-tab entities today, all `StatefulWidget` bottom sheets opened via
`AppBottomSheet.show` / `showModalBottomSheet`, using `Form` + `sheetFieldDecoration`:

- `add_bill_sheet.dart` — bill (7 types), amount + due-day, account, category, note, recurrence.
- `add_receivable_sheet.dart` — receivable (4 types), amount + expected-date, category, destination
  account, recurrence.
- `add_installment_sheet.dart` — name, account, total, months, monthly (auto), start-month, note.

They already read theme tokens and share `SheetFieldLabel` + `sheetFieldDecoration`, but the header,
type selectors (Material `ChoiceChip`), account pickers (Material `DropdownButtonFormField`), and the
receivable date box diverge from the reference and from each other (e.g. the receivable date box is
56px / radius 8, the field boxes are radius 12).

## Reference form language (canonical dark tokens)

From `Nutrition Focus Treasury.dc.html` ("Add bill / receivable", "Add installment"). In code, resolve
every color from `Theme`/`context.appColors`; the hex says *which* token.

| Element | Reference spec |
|---|---|
| Sheet surface | `#1A1A1E` (`--bg-sheet`), top radius 26, `border-top #2E2E33`, padding `12 18 20–24` |
| Grab handle | 36×4, radius 999, `#3A3A40`, centered, 14 below |
| Title | 17px, `w800`, `--text-primary` ("New entry" / "New Installment") |
| Segmented toggle | container `#232327` radius 12 pad 4; selected segment accent-filled (`#F6685E` bill), radius 9, pad `8 0`, label 12px `w700` white; unselected 12px `w600` `#9A9FA8` |
| Field label | 10.5px, `w700`, letter-spacing `.05em`, `#83878F`/`#9A9FA8`, uppercase, ~7–8 below |
| Field box | height 46, `#232327`/`#202024` (`--bg-input`), 1px `#2E2E33`, radius 12, row, pad `0 14`; value 13.5–14px `w600–700` `--text-primary` |
| Amount box | field box with a leading `₱` in `#83878F` before the value |
| Picker box | field box with a trailing `ph-caret-down` 12px `#83878F` (justify-between) |
| Account row | field box: 22×22 radius-7 brand-color badge + monogram, then name, caret at right |
| 2-column row | `flex; gap 10–14`, two `flex:1` field groups (e.g. Amount + Due Day) |

## Goals / Non-Goals

**Goals:** one consistent reference form feel across all three sheets; unify Bill+Receivable into a
single toggle sheet; keep every field, default, and validation; keep the kit reusable by other
Treasury sheets (transaction, budget, account).

**Non-Goals:** presenter/model/storage changes; new/removed fields; the Bills list/hero; migrations.

## Decisions

- **Unify Bill + Receivable into `entry_sheet.dart` with a segmented toggle** (per the reference and
  the confirmed product decision). One `Form`; a `_kind` enum (`bill` / `receivable`) drives which
  type-specific fields render. Common fields (name, amount, category, account, recurring+recurrence)
  are shared; bill adds *type* + *due day* + *payment note*, receivable adds *type* + *expected date*
  + destination-account semantics. On save, route to the matching presenter method. **Edit opens
  locked to the entry's kind** (the toggle is shown but disabled) so you can't accidentally convert a
  bill into a receivable. Entry points (FAB / section "+") pass the initial kind.
  *Alternative — keep two sheets:* rejected; it's the main thing the reference changes and keeps the
  two sheets drifting.
- **Account fields use `SheetAccountField`**, not `DropdownButtonFormField` — reuses the existing
  `AccountBadge` (a 22px badge + name) with a trailing caret; tapping opens a simple bottom-sheet
  account list (plus the receivable's "Ask me when received" = null option). Matches the reference
  "PAY FROM" row and stays theme-aware.
- **Type selectors become `SheetSegmentedToggle`** for the 2-way Bill/Receivable kind; the many-valued
  Bill Type (7) and Receivable Type (4) stay as a labelled chip/`SheetPickerField` group (a 7-way
  segmented control won't fit) — restyled to the kit, behavior unchanged.
- **Category stays tap-to-select / tap-to-clear**, presented under a field label; kept as chips inside
  the form (compact), not converted to a modal, to preserve the current one-tap behavior.
- **Standardize the field box** at height ~52 (a touch taller than the reference's 46 for finger
  comfort and to satisfy the 44px rule with the label above), radius 12, `bg-input`; fold the
  receivable date box (was 56/rad 8) into a `SheetPickerField`.
- **View-only.** All create/edit logic (id generation, `_resolvePaymentNote` auto-statement handling,
  installment monthly auto-compute, recurrence gating) moves verbatim into the new/updated sheets.

## Risks / Trade-offs

- **[Unifying two sheets is the biggest change]** → mitigated by moving logic verbatim and adding a
  widget test per kind (bill save, receivable save, edit-locked toggle) so saved objects match today.
- **[Account bottom-sheet picker replaces a native dropdown]** → more code, but consistent and
  theme-correct; the picker is a thin list reusing `AccountBadge`.
- **[7-way Bill Type as chips]** → not a segmented control; acceptable — the reference only shows the
  2-way kind toggle, and 7 segments won't fit a phone width.

## Migration Plan

None — view-only. `entry_sheet.dart` replaces the two old sheets; rollback is restoring them and the
old entry-point wiring. No data or storage effect; saved records are unchanged.

## Open Questions

- Should the kit graduate to a shared `sheet_kit.dart` used by the transaction / budget / account
  sheets too? Proposed yes in a later increment (out of scope here) — keep the widgets general.
