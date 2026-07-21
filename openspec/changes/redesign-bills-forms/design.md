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

- **One `NewEntrySheet` for all four types; single FAB.** The FAB opens `NewEntrySheet` directly (no
  more 4-item menu). A `type` (`bill` | `receivable` | `setAside` | `installment`) is chosen by a
  **type selector at the top** — an **icon + label chip row** (extending the reference's Bill/Receivable
  segmented toggle to four), not a cramped 2-segment pill. The sheet is scrollable and renders the
  chosen type's full field set below by composing the existing per-type field bodies, calling the
  existing presenter methods (`addBill`/`updateBill`, `addReceivable`/`updateReceivable`,
  `addBudgetedExpense`/`updateBudgetedExpense`, installment add/update). Editing an existing record opens
  the sheet **locked to that type** (the selector is hidden/disabled — you don't convert a bill into an
  installment). *Alternative:* FAB opens a type chooser that launches four separate sheets — rejected;
  the user wants the pick inside one sheet. *Alternative:* only bill+receivable unified (reference
  literal) — rejected; the user wants all four.
- **Per-bill reminder.** Add an additive, null-tolerant `Bill.reminderDaysBefore` (`int?`; null = off).
  The bill fields show a *"Remind me N days before"* switch (default N = 2 when turned on, per Frame 7).
  `NotificationService` gains schedule/cancel for a per-bill due reminder (fired N days before the bill's
  due date); `BillsReceivablesPresenter` (re)schedules on add/update and cancels on delete / mark-paid,
  gated by the global bills-reminder preference. Reminder is **bill-only** for now (receivables/other
  types don't show it). *Alternative:* reuse the global monthly bills reminder — rejected; the reference
  is a per-bill lead-time reminder.
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

Additive only: `Bill.reminderDaysBefore` defaults to null (no reminder) and old records load unchanged.
UI is recomposition over the existing presenters. Rollback = revert the sheet files + the field (inert
if unused).

## Open Questions

- **Resolved (user):** include the per-bill reminder now; collapse the FAB into one unified sheet with a
  four-type selector.
- Should **receivables** also get a lead-time reminder later? Out of scope now (bill-only), easy to
  extend once the bill path is proven.
- The type selector's exact form (icon-chip row vs 2×2 grid) is a visual detail to settle during build;
  the requirement only fixes that all four types are pickable in one sheet.
