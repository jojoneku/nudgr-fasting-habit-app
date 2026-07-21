## Why

`redesign-bills-page` restyled the Bills **tab** but deliberately left the **forms** (the add/edit and
mark sheets) for later. They still use the older field chrome and split flows. The Nudgr reference's
**"Add anything" creation-sheet system** (`Nutrition Focus Treasury.dc.html`, Frames 5–10) shows the
target feel: a bottom sheet over the dimmed page, a grab handle, a bold title, **uppercase muted field
labels** over **46px rounded field boxes**, side-by-side field pairs, **segmented toggles**, **chip
selectors**, a **month stepper**, an optional reminder switch, and a full-width **blue Save** CTA with a
soft glow (destructive actions as a tonal red secondary). The user specifically likes this and wants
the Bills forms to follow it.

Structural cues from the reference: the creation sheets share one language, **Add Bill and Add
Receivable are one sheet** ("New entry") with a type toggle (Frame 7), and the **installment form
already matches** the reference (Frame 10). We take this one step further per the user: a **single FAB**
opens **one unified "New entry" sheet** where you pick the type — **Bill · Receivable · Set-aside ·
Installment** — and the matching fields render below.

This is a **restyle + consolidate**, not a feature change: every existing field and flow is preserved,
re-dressed in the reference's language. One additive feature is included: a **per-bill reminder**.

## What Changes

- **Single FAB → one unified "New entry" sheet.** The FAB stops opening a 4-item menu; it opens the
  "New entry" sheet directly. A **type selector** at the top (an icon + label chip row: *Bill ·
  Receivable · Set-aside · Installment*, extending the reference's Bill/Receivable toggle) chooses the
  type; the sheet renders that type's full field set below and Save routes to the right create flow.
  The sheet is scrollable (installment/set-aside carry more fields). Every current field of every type
  is kept — the reference's minimal frames are the *look*, not a field cull.
- **Per-bill reminder (new, additive).** The bill fields include a **"Remind me N days before"** toggle
  (Frame 7). Backed by a new additive `Bill.reminderDaysBefore` field and per-bill scheduling via
  `NotificationService`; toggling it (or paying/deleting the bill) schedules/cancels the reminder.
- **Reference field chrome everywhere.** Uppercase `SheetFieldLabel` + `sheetFieldDecoration` field
  boxes, side-by-side **Amount | Due day** (bill) and **Amount | Expected date** (receivable), a
  **due-day picker** (ordinal "15th", replacing the free-text 1–31 box), segmented type toggles, category
  **chip rows**, and the blue **Save** CTA with glow. Edit mode keeps a tonal-red **Delete** secondary.
- **Installment sheet formalized/polished** to the reference (name, *Account (credit / BNPL)*, total,
  **month chips** 3/6/12/24/Custom, auto monthly, **start-month stepper**, note) — mostly already there.
- **Budgeted set-aside sheet** re-dressed in the same chrome, keeping its fields (name, allocated
  amount, type, note, fund-from account, category).
- **Mark / confirm sheets** (mark bill paid, mark received, fund set-aside, mark installment paid)
  adopt the same chrome, with the reference's **big centered amount** entry.
- **Shared sheet scaffolding** — a small set of reusable pieces (grab-handle + title header, segmented
  toggle, chip row, month stepper, primary/destructive CTA) so every sheet reads as one system.

## Non-goals

- **No changes to existing business logic** — mark-paid/received, recurring auto-copy, installment
  math, and credit-statement generation are untouched; only the sheets' composition/chrome change (plus
  the additive reminder scheduling).
- **No migration.** The new `Bill.reminderDaysBefore` field is additive and null-tolerant (old records
  load with no reminder).
- **No new dependencies.**
- **Add-account / Add-transaction / Manage-categories** sheets (Frames 5, 6, 8) are Ledger/Dashboard
  forms, out of scope for this Bills-forms change (the shared chrome is reusable by them later).

## Capabilities

### New Capabilities
- `treasury-bills-forms`: The Bills creation/edit/confirm sheets redressed to the Nudgr creation-sheet
  language — a consolidated Bill/Receivable "New entry" sheet, installment and set-aside forms, and the
  mark/confirm sheets — preserving every existing field and flow.

## Impact

- **New:** shared sheet scaffolding widgets under `lib/views/treasury/shared/` (header, segmented
  toggle, chip row, month stepper, CTA) — some may extend the existing `sheet_fields.dart`.
- **Modified:** `add_bill_sheet.dart` + `add_receivable_sheet.dart` + `add_installment_sheet.dart` +
  `_AddBudgetedExpenseSheet` (composed behind one `NewEntrySheet` with a type selector), and the
  mark/fund sheets in `bills_receivables_view.dart`. The FAB opens `NewEntrySheet` directly.
- **Model/service (additive):** `Bill.reminderDaysBefore` (+ fromJson/toJson/copyWith);
  `NotificationService` per-bill reminder schedule/cancel; `BillsReceivablesPresenter` wires it on
  add/update/delete/mark-paid.
- **Reuses (unchanged):** `BillsReceivablesPresenter` / `InstallmentPresenter` create/edit methods,
  `sheet_fields.dart` tokens, theme colors.
- **Deps:** none. **Risk:** medium — form composition across several sheets + additive reminder wiring;
  mitigated by keeping every existing field + presenter call identical and covering the sheet and the
  reminder scheduling with tests.
