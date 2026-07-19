## Context

Treasury forms today (all `StatefulWidget` sheets shown via `AppBottomSheet.show`):
- `add_transaction_sheet.dart` — Expense/Income/Transfer, amount, description, category, account, date,
  transfer target, reimbursable.
- `account_setup_view.dart` — account type, name, starting balance, color, credit limit/due day.
- `add_bill_sheet.dart` — name, bill-type chips, amount, due day, account dropdown, category chips,
  payment note, recurring + recurrence.
- `add_receivable_sheet.dart` — name, receivable-type, amount, category, account, expected date,
  recurring.
- `add_installment_sheet.dart` — name, account, total, months, auto monthly, note, start month.
- mark-as-paid sheets (bill / expense / installment) in `bills_receivables_view.dart`.

They mix `TextFormField`+`InputDecoration`, `ChoiceChip`, `DropdownButtonFormField`, `SwitchListTile` —
inconsistent, none matching the reference. The reference frames ("New entry", "New Installment",
"Mark as paid", "Log transaction", "Add account") share one visual grammar.

## Goals / Non-Goals

**Goals:** one shared, theme-aware form language across all Treasury forms; field-for-field parity with
today; the combined bill/receivable entry the reference shows.

**Non-Goals:** new persistence/logic; the "remind me before due" toggle; list-screen redesigns; web
forms; grocery form.

## The Nudgr form grammar (from the reference)

| Element | Reference | Kit component | Built on |
|---|---|---|---|
| Type toggle (top) | Bill/Receivable, Expense/Income/Transfer, account TYPE | `AppSegmentedControl` (or `AppChipSelect` when >3) | existing |
| Field label | UPPERCASE, ~10.5px, tracked, muted | `AppFormField(label, child)` | Text + theme |
| Amount | big `₱ 3,200` | `AppAmountField` | `AppTextField` + `amountInputFormatters` |
| Select | `BPI ▾`, `15th ▾` | `AppSelectField(value, onTap)` → `AppActionSheet` | existing |
| Finite choice | `3mo 6mo 12mo 24mo Custom` | `AppChipSelect<T>` | ChoiceChip styled |
| Auto value | `MONTHLY PAYMENT (AUTO)` | `AppFormField` + read-only display | Text |
| Toggle row | bell · "Remind me…"; book · "Log to ledger" | `AppFormToggle(icon,title,subtitle,value)` | Switch |
| Entity header | icon · Meralco · due Jun 28 · ₱3,200 | `AppEntityHeader` | Container |
| Save | primary button, bottom | `AppPrimaryButton` | existing |

## Decisions

- **Shared kit lives in `lib/views/treasury/shared/forms/`**, not `system/`. Rationale: the pieces are
  finance-flavored (₱ amount, entity header) and only Treasury needs them now; promoting to `system/`
  later is easy if other modules adopt them. Each is theme-aware (Rule 7) and stateless where possible.
- **Selects use `AppActionSheet`, not `DropdownButtonFormField`.** Rationale: matches the reference's
  bottom-sheet picker feel, gives ≥44px targets, and reuses an existing component. `AppSelectField`
  renders `label ▾ value` and calls a supplied `onTap` (the form owns the picker + options), so the kit
  widget stays presentational and logic stays in the sheet/presenter (Rule 1).
- **Merge add-bill + add-receivable into one `AddEntrySheet`** with a top Bill/Receivable toggle
  (`AppSegmentedControl`). The shared fields (name, amount, account, due-day/expected-date) render once;
  the toggle swaps the type-specific block. Both sheets' full field sets are preserved; the two old
  entry points both open this sheet with the toggle pre-set. Rationale: it's the reference's "New entry"
  and the feature the user explicitly likes.
- **Preserve extras under "More options".** Bill type (7), category, payment note, recurring/recurrence,
  receivable type, expected date — the fields the reference omits but that exist today — live in a
  collapsible "More options" section so the core stays reference-clean without deleting anything.
- **Chip-row for finite enums** (installment months; account type; bill/receivable type when it stays a
  chip set). `Custom` months keeps the existing numeric entry.
- **Amount + auto fields** reuse `amountInputFormatters` and `finance_format`; the installment
  auto-monthly keeps its current "total ÷ months unless manually edited" logic in the sheet.
- **Mark-as-paid** keeps its three variants (bill/expense/installment) but each renders `AppEntityHeader`
  + `AppAmountField` (actual paid) + `AppSelectField` (paid-from) + `AppFormToggle` (log to ledger),
  wired to the current mark-paid calls. No behavior change.
- **Validation & submit** stay in each sheet (form key, validators, `_submit`), unchanged in logic —
  only the widgets they wrap change.

## Risks / Trade-offs

- **[Merging two sheets]** → most structural change; mitigated by preserving every field per mode and
  keeping both entry points. If merge proves risky, the kit still applies to two separate sheets — the
  merge is the one reversible decision here.
- **[Kit scope creep]** → keep the kit to the six components above; resist per-form specials.
- **[Select-as-actionsheet vs inline dropdown]** → an extra tap to open the picker, but far better touch
  ergonomics and the reference feel; acceptable.
- **[Reminder toggle omitted]** → the reference shows it; deferring avoids inventing persistence. Called
  out in Open Questions.

## Migration Plan

Specs only in this change. Implementation order (see tasks): build the kit → migrate the simplest form
(add transaction) to validate the kit → account → installment → combined bill/receivable → mark-as-paid.
No data migration; each form keeps its model and presenter calls.

## Open Questions

- **Bill reminders:** add a `remindDaysBefore` to `Bill` + scheduling so the reference's reminder toggle
  can ship? Separate change.
- **"Log to ledger" toggle:** confirm the current mark-paid always creates a transaction; if so the
  toggle gates that, else it's informational until the option exists.
- Should the combined entry sheet's "More options" be open by default when editing an entry that uses
  those fields (e.g. a recurring bill)? Leaning yes.
