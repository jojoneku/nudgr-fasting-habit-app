## Why

The Bills tab's creation/edit sheets — **Add Bill**, **Add Receivable**, **Add Installment** — already
use a partial `sheetFieldDecoration` helper, but they don't yet match the reference form language in
`docs/design-reference/Nutrition Focus Treasury.dc.html` (the "Add bill / receivable" and "Add
installment" frames). The reference forms have a distinct, calm "feel": a grab-handle + bold title,
a **segmented type toggle** with an accent-filled selection, small uppercase field labels over 46px
bordered **field boxes**, `₱`-prefixed amount boxes, 2-column rows (Amount + Due), and account fields
that show a **mini account badge + name + caret** instead of a bare Material dropdown.

The reference also **unifies Bill and Receivable into one "New entry" sheet** with a "Bill to pay /
Money owed me" toggle — where today the app has two separate sheets. This change adopts that feel
across all bill-related forms while **keeping every field and behavior** the current forms have.

## What Changes

- **Shared sheet form kit** (extend `views/treasury/shared/sheet_fields.dart`): reference building
  blocks reused by every sheet — `SheetHandle` (grab handle), `SheetTitle`, a `SheetSegmentedToggle`
  (accent-filled selected segment), a `SheetPickerField` (label + 46px bordered box with a trailing
  caret, for taps that open a picker), and a `SheetAccountField` (mini `AccountBadge` + name + caret).
  Field boxes standardize on height ~52, radius 12, `bg-input`, 1px border (`sheetFieldDecoration`
  already most of the way there).
- **Unify Add/Edit Bill + Add/Edit Receivable into one "New entry" sheet** (`entry_sheet.dart`) with a
  Bill / Receivable segmented toggle (bills accent = orange/danger, receivable accent = green). The
  toggle swaps the type-specific fields; entry points pre-select the toggle and edit opens locked to
  the entry's type.
- **Restyle Add/Edit Installment** to the same kit (it already has a handle + title and a months
  chip-picker; align its labels, field boxes, account field, and start-month stepper).
- **Account pickers become `SheetAccountField`** (badge + name + caret opening a bottom-sheet account
  list) instead of `DropdownButtonFormField`, matching the reference "PAY FROM" / "ACCOUNT" rows.
- **Category becomes a compact picker row** consistent with the field boxes (keeps the current
  tap-to-select / tap-to-clear behavior; may keep chips inside an expandable field).

Non-breaking. **View-only** — no model/storage/navigation change; the unified sheet routes to the
existing `addBill`/`updateBill`/`addReceivable`/`updateReceivable` and installment presenter methods.

## Retained (superset — nothing removed)

- **Bill:** name, bill type (7 types), amount, due day (1–31), payment account (defaults to first),
  category (expense), payment note (incl. the hidden auto-statement marker handling), recurring +
  recurrence (Monthly/Weekly/Yearly/Custom), edit mode.
- **Receivable:** source/name, receivable type (Salary/Reimbursement/Business/Other), expected amount,
  expected date, category (income), destination account incl. the "Ask me when received" option,
  recurring + recurrence, edit mode.
- **Installment:** name, account (Credit/BNPL, required), total amount, number of months (3/6/12/24 +
  custom), monthly payment (auto-computed, editable), start month stepper, note, auto-recompute logic.

## Non-goals

- **No presenter/model/storage change.** Bill/receivable/installment models, their presenter methods,
  recurrence generation, auto-statement logic, and mark-paid/mark-received flows are untouched.
- **No new fields or field removals** — this is a reskin + a UI consolidation of two sheets into one.
- **Not the Bills list/hero** (owned by `redesign-treasury-bills`) — only the creation/edit sheets.
- **No data migration, no new dependencies** (Material icons + existing `AccountBadge`).

## Capabilities

### New Capabilities
- `treasury-bill-forms`: The Bills tab's creation/edit sheets rendered in the Nudgr reference form
  language — a shared sheet kit (handle, title, segmented toggle, field boxes, account/picker fields),
  a unified Bill/Receivable "New entry" sheet with a type toggle, and a matching Installment sheet —
  preserving every existing field, validation, default, and the routes to the existing presenter
  methods; theme-aware in dark and light.

## Impact

- **New:** `lib/views/treasury/bills/entry_sheet.dart` (unified Bill/Receivable sheet); shared widgets
  added to `lib/views/treasury/shared/sheet_fields.dart` (or a new `sheet_kit.dart`).
- **Modified:** `add_installment_sheet.dart` (restyle to the kit); `bills_receivables_view.dart` +
  any FAB/entry points (open the unified sheet with a pre-selected type); the old
  `add_bill_sheet.dart` / `add_receivable_sheet.dart` are replaced by `entry_sheet.dart` (their logic
  moves in verbatim).
- **Reuses (unchanged):** `BillsReceivablesPresenter`, `InstallmentPresenter`, `Bill` / `Receivable` /
  `Installment` models, `AccountBadge`, `amount_input_formatter`, theme tokens.
- **Deps:** none new. **Risk:** low — view-only; the presenter methods and validation rules are
  carried over unchanged, so a saved bill/receivable/installment is byte-identical to today's.
