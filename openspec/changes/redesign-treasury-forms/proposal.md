## Why

Every Treasury data-entry form (add bill, add receivable, add installment, add transaction, add
account, mark-as-paid) predates the Nudgr redesign. They use raw `TextFormField` + `InputDecoration`,
`ChoiceChip` wraps, `DropdownButtonFormField`, and `SwitchListTile` — each styled slightly
differently, none matching the reference "feel". The Nudgr reference (`Nutrition Focus Treasury.dc.html`)
shows a single, consistent form language across all of these: a segmented **type toggle** at the top,
**UPPERCASE field labels**, a large **₱ amount** field, **caret dropdown** selects, **chip-row**
pickers for finite choices, **auto-computed** read-only fields, **icon toggle** rows, and a primary
**Save** button — with mark-as-paid leading on a **context header** (icon · name · due · amount).

This is a **restyle + consolidate**: give the existing forms one shared Nudgr form language. No new
data, no new persistence — every field and behavior that exists today is preserved.

## What Changes

- **Introduce a shared Treasury "form kit"** (theme-aware, reused across all forms): a labeled-field
  wrapper (uppercase label + child), a big ₱ amount field, a caret "select" field that opens an
  `AppActionSheet` picker, a chip-row selector for finite choices, an auto-computed read-only field, an
  icon toggle row (icon · title · helper · switch), and a context "entity header" chip. Built on the
  existing system primitives (`AppSegmentedControl`, `AppTextField`, `AppActionSheet`,
  `AppPrimaryButton`).
- **Restyle each form to the kit**, preserving all current fields/behavior:
  - **Add transaction** (Ledger): Expense/Income/Transfer segmented toggle, ₱ amount, description,
    category select, account select — plus the existing date, transfer target, reimbursable, etc.
  - **Add account** (Treasury): TYPE chip-row (Bank / eWallet / Cash / Savings / Credit), name, ₱
    starting balance, color swatches, and the conditional **credit details** (limit, due day).
  - **Add bill / receivable**: a **combined entry sheet** with a Bill-to-pay / Money-owed-me toggle
    at the top (the reference's "New entry"), swapping the type-specific fields; name, ₱ amount, due
    day / expected date select, pay-from / deposit-to account select. The existing extras (bill type,
    category, payment note, recurring/recurrence; receivable type + category) are retained, grouped
    under a "More options" area so the core stays clean.
  - **Add installment**: name, credit/BNPL account select, ₱ total, **months chip-row**
    (3 / 6 / 12 / 24 / Custom), auto **monthly payment** read-only, plus the existing note + start month.
  - **Mark as paid** (bill / expense / installment): a context header (icon · name · subtitle · billed
    amount), ₱ actual-amount-paid, paid-from account select, and the "log to ledger" toggle — mapped to
    the current mark-paid behavior.

## Non-goals

- **No new persistence or business logic.** No model/storage/notification changes; every field maps to
  a field that exists today. RPG/finance math stays in presenters.
- **The reference's "Remind me N days before" bill toggle is deferred** — bills carry no reminder field
  and no bill-reminder scheduling exists, so adding it is a separate feature, not part of this restyle.
- **Not a redesign of the Bills/Ledger list screens** themselves — only the entry/edit forms and the
  mark-as-paid sheet. **No grocery/cart form** changes in this pass.
- No change to the **web** Treasury forms (`web_*_page.dart`, `web_account_form_dialog.dart`).

## Capabilities

### New Capabilities
- `treasury-forms`: A shared Nudgr form language for all Treasury entry/edit forms — segmented type
  toggle, uppercase labels, ₱ amount field, caret selects, chip-row pickers, auto-computed read-only
  fields, icon toggles, and a context entity header — applied to add-transaction, add-account,
  add-bill/receivable (combined), add-installment, and mark-as-paid, preserving all existing fields and
  behavior; theme-aware (dark + light).

### Modified Capabilities
<!-- None. openspec/specs/ holds only `hub`; there is no existing forms capability spec to amend. -->

## Impact

- **New (shared kit):** `lib/views/treasury/shared/forms/` — `app_form_field.dart` (labeled wrapper),
  `app_amount_field.dart`, `app_select_field.dart`, `app_chip_select.dart`, `app_form_toggle.dart`,
  `app_entity_header.dart`.
- **Modified (restyle only):** `lib/views/treasury/ledger/add_transaction_sheet.dart`,
  `lib/views/treasury/shared/account_setup_view.dart`,
  `lib/views/treasury/bills/add_bill_sheet.dart` + `add_receivable_sheet.dart` (merged into a combined
  entry sheet), `lib/views/treasury/bills/add_installment_sheet.dart`, and the mark-as-paid sheets in
  `lib/views/treasury/bills/bills_receivables_view.dart`.
- **Reuses (unchanged):** `AppSegmentedControl`, `AppTextField`, `AppActionSheet`, `AppPrimaryButton`,
  `AppBottomSheet`, `amount_input_formatter`, `finance_format`, theme tokens.
- **Deps:** none new. **Risk:** medium — touches many forms and merges two sheets; mitigated by
  preserving field-for-field parity, landing the kit first, and migrating one form at a time. This
  change is **specs only** — no code yet.
