## Why

`redesign-bills-page` restyled the Bills **tab** but deliberately left the **forms** (the add/edit and
mark sheets) for later. They still use the older field chrome and split flows. The Nudgr reference's
**"Add anything" creation-sheet system** (`Nutrition Focus Treasury.dc.html`, Frames 5–10) shows the
target feel: a bottom sheet over the dimmed page, a grab handle, a bold title, **uppercase muted field
labels** over **46px rounded field boxes**, side-by-side field pairs, **segmented toggles**, **chip
selectors**, a **month stepper**, an optional reminder switch, and a full-width **blue Save** CTA with a
soft glow (destructive actions as a tonal red secondary). The user specifically likes this and wants
the Bills forms to follow it.

Two structural cues from the reference: **Add Bill and Add Receivable are one sheet** ("New entry")
with a *Bill to pay / Money owed me* toggle (Frame 7), and the **installment form already matches** the
reference (Frame 10 — name, credit/BNPL account, total, month chips, auto monthly, start-month stepper).

This is a **restyle + consolidate**, not a feature change: every existing field and flow is preserved,
re-dressed in the reference's language.

## What Changes

- **Consolidated "New entry" sheet (Bill / Receivable).** One sheet with a segmented *Bill to pay /
  Money owed me* toggle that swaps between the bill and receivable field sets. All current fields are
  kept (bill: type, category, payment note, recurring; receivable: type, category, expected date,
  recurring) — the reference's minimal frame is the *look*, not a field cull.
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

- **No data model changes** and **no new business logic** — mark-paid/received, recurring auto-copy,
  installment math, credit-statement generation are untouched; only the sheets' composition/chrome change.
- **No new dependencies, no migration.**
- **Per-bill reminder toggle** ("Remind me 2 days before", Frame 7) is **deferred** — it needs a new
  `Bill` field + per-bill notification scheduling. Captured as an open decision, not built here (see
  design.md Open Questions).
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
- **Modified:** `add_bill_sheet.dart` + `add_receivable_sheet.dart` (merged behind a `NewEntrySheet`),
  `add_installment_sheet.dart`, and the mark/fund sheets in `bills_receivables_view.dart` (+ the
  budgeted add sheet). The FAB menu's Add Bill / Add Receivable entries route to the one sheet.
- **Reuses (unchanged):** `BillsReceivablesPresenter` / `InstallmentPresenter` methods, `sheet_fields.dart`
  tokens, theme colors.
- **Deps:** none. **Risk:** medium — form composition changes across several sheets; mitigated by
  keeping every field + presenter call identical and covering each sheet with a widget test.
