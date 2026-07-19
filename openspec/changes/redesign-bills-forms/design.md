## Context

The Bills forms today: `AddBillSheet` (name, bill-type selector, amount, due-day text 1–31, payment
account, category chips, payment note, recurring + recurrence), `AddReceivableSheet` (source/name,
receivable-type selector, expected amount, category chips, account, expected date, recurring +
recurrence), `AddInstallmentSheet` (name, account, total, month chips, auto monthly, start-month
stepper, note — already reference-shaped), plus the inline `_AddBudgetedExpenseSheet` and the mark
sheets (`_MarkBillPaidSheet`, `_MarkReceivedSheet`, `_MarkExpensePaidSheet`, `_MarkInstallmentPaidSheet`)
in `bills_receivables_view.dart`. `sheet_fields.dart` already provides `SheetFieldLabel` +
`sheetFieldDecoration` matching the reference field box.

Reference (`Nutrition Focus Treasury.dc.html`, "Add anything" section): Frame 7 = one **New entry**
sheet with a *Bill to pay / Money owed me* segmented toggle; Frame 10 = **New Installment**; the shared
chrome is a grab handle, bold title, uppercase labels, 46px `#202024/#232327` field boxes, side-by-side
pairs, chip selectors, month stepper, reminder switch, and a `#2E90FA` Save button with a soft glow.

## Goals / Non-Goals

**Goals**
- Redress every Bills sheet in the reference's creation-sheet language, as one consistent system.
- Consolidate Add-Bill + Add-Receivable into one toggle-driven sheet.
- Preserve every existing field, default, validation, and presenter call.

**Non-Goals**
- Model/logic changes, per-bill reminder wiring, and the non-Bills creation sheets (account/txn/category).

## Decisions

- **`NewEntrySheet` merges bill + receivable.** A single `StatefulWidget` holds a `mode`
  (`bill` | `receivable`) toggled by a segmented control (*Bill to pay / Money owed me*, bill=red
  active, receivable=green). It composes the existing per-mode field sets and calls the existing
  presenter methods (`addBill`/`updateBill` or `addReceivable`/`updateReceivable`). Editing an existing
  record opens directly in the right mode with the toggle locked (you don't convert a bill into a
  receivable). The FAB's *Add Bill* / *Add Receivable* both open this sheet, pre-set to the tapped mode.
  *Alternative:* keep two sheets — rejected; the reference explicitly unifies them and the user likes it.
- **Due-day picker, not free text.** Replace the `1–31` text field with a picker showing the ordinal
  ("15th") + caret, backed by the same `dueDay` int. Rationale: matches Frame 7, avoids invalid input.
- **Shared scaffolding widgets** (new, in `shared/`): `SheetHeader` (grab handle + title + optional
  trailing action), `SheetSegmentedToggle`, `SheetChipRow`, `SheetMonthStepper`, and a `SheetSaveButton`
  (blue, glow) + `SheetDestructiveButton` (tonal red). Each sheet is recomposed from these + the
  existing `SheetFieldLabel`/`sheetFieldDecoration`. Keeps the "feel" defined once. *Alternative:*
  restyle each sheet ad hoc — rejected (drift).
- **Big centered amount on mark/confirm sheets.** The amount entry on mark-paid/received/fund and
  mark-installment-paid adopts Frame 6's centered `₱ 285`-style display, keeping the same controllers
  and confirm logic.
- **Installment sheet** is already reference-shaped; this only swaps its ad-hoc pieces for the shared
  `SheetChipRow` / `SheetMonthStepper` / header so it matches pixel-for-pixel. No behavior change.
- **Theme tokens only.** All chrome via `Theme.of(context)` + `context.appColors` (blue=`fast`,
  danger=`error`, success). The reference's hex values map to existing tokens (`#2E90FA`→fast,
  `#F6685E`→error, `#46BD6B`→success, field boxes→`surfaceContainer*`).

## Risks / Trade-offs

- **[Merging two sheets]** → larger `NewEntrySheet`; mitigated by delegating to the existing field
  builders and presenter calls unchanged, and locking the toggle in edit mode to avoid type-conversion
  ambiguity.
- **[Due-day picker vs recurrence]** → a due day only makes sense for dated bills; the picker stays for
  all bills (as today) — no semantic change.
- **[Chrome drift]** → centralised in shared widgets so all sheets stay identical.

## Migration Plan

None — pure UI recomposition over unchanged presenters/models. Rollback = revert the sheet files; the
new shared widgets are inert if unused.

## Open Questions

- **Per-bill reminder toggle** (Frame 7 "Remind me 2 days before"): include now — which requires an
  additive `Bill.reminderDaysBefore` field + per-bill notification scheduling — or defer? Defaulting to
  **defer** (kept out of the initial tasks) unless the user opts in.
- Should the *Add Receivable* FAB entry remain, or collapse into a single *Add bill / receivable* entry
  that opens on the bill mode? Defaulting to **keep both entries** (each pre-selects its mode).
