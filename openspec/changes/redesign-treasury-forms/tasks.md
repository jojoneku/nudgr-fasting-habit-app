> Implementation in progress. Done so far: the shared kit (§1.1–1.6) and the bill + received
> mark-as-paid sheets (part of §6). Remaining: expense/installment mark-as-paid and the entry forms.

## 1. Shared form kit (land before any form migration)

- [x] 1.1 Add `lib/views/treasury/shared/forms/app_form_field.dart` — labeled wrapper (UPPERCASE tracked
      muted label + child + optional trailing/hint). Theme-aware.
- [x] 1.2 Add `app_amount_field.dart` — big ₱-prefixed numeric field (reuses `amountInputFormatters`).
- [x] 1.3 Add `app_select_field.dart` — presentational `label ▾ value` row calling `onTap`; the form
      supplies options + opens `AppActionSheet`.
- [x] 1.4 Add `app_chip_select.dart` — `AppChipSelect<T>` single-select chip row (+ optional "Custom").
- [x] 1.5 Add `app_form_toggle.dart` — icon · title · helper subtitle · switch row (≥44px).
- [x] 1.6 Add `app_entity_header.dart` — icon tile · name · subtitle · amount, for mark-as-paid.
      Barrel: `forms.dart`.
- [ ] 1.7 Widget tests: each renders in light + dark and reports value changes.

## 2. Migrate Add Transaction (simplest — validates the kit)

- [ ] 2.1 Rebuild `add_transaction_sheet.dart` on the kit: Expense/Income/Transfer segmented toggle, ₱
      amount, description, category select, account select. Keep date, transfer target, reimbursable,
      and all validators/submit unchanged.

## 3. Migrate Add Account

- [ ] 3.1 Rebuild `account_setup_view.dart` on the kit: TYPE chip-row, name, ₱ starting balance, color
      swatches, conditional CREDIT DETAILS (limit, due-day select). Preserve edit + save behavior.

## 4. Migrate Add Installment

- [ ] 4.1 Rebuild `add_installment_sheet.dart` on the kit: name, credit/BNPL account select, ₱ total,
      months chip-row (3/6/12/24/Custom), auto monthly read-only, note, start-month select. Keep the
      auto-monthly logic and manual-override behavior.

## 5. Merge Add Bill + Add Receivable → combined entry sheet

- [ ] 5.1 Create the combined `AddEntrySheet` with a Bill-to-pay / Money-owed-me toggle; render shared
      fields once and swap the type-specific block. Preserve every field from both old sheets (bill
      type, category, payment note, recurring/recurrence; receivable type, expected date) under a
      "More options" section (auto-open when editing an entry that uses them).
- [ ] 5.2 Point both existing entry points at the combined sheet with the toggle pre-set; remove the
      old `add_bill_sheet`/`add_receivable_sheet` only once parity is confirmed.

## 6. Migrate Mark-as-paid (bill / received / expense / installment)

- [x] 6.1 Bill + Received sheets rebuilt on `AppEntityHeader` + ₱ actual-paid + paid-from/deposit-to
      select + "Log to ledger" toggle (inverse of the old "already in ledger" flag). Logic unchanged.
- [ ] 6.2 Expense (Fund from + Set aside into) and Installment mark-as-paid sheets — same treatment.

## 7. Verification

- [ ] 7.1 `dart format` + `flutter analyze` clean.
- [ ] 7.2 Field-parity check per form: every field/behavior that existed before still exists.
- [ ] 7.3 Manual smoke (dark + light): each form add + edit path, combined toggle swap, installment
      auto-monthly, credit-details conditional, mark-as-paid amounts. Confirm nothing regressed.
