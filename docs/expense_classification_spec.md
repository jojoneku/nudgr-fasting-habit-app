# Money-That-Isn't-Yours — Expense Classification Spec

## Overview
Three everyday situations look like spending but shouldn't all be treated as
spending. Today the ledger only distinguishes **inflow / outflow / transfer**,
so users either mis-log money they'll get back (inflating expenses) or money
that was never theirs (inflating both expenses and income). This spec defines
how The System classifies these cases so the headline **Expenses**, the
per-category **budget**, and **net worth** each stay truthful — and, just as
important, how a user who has *never heard of the "transfer leg" trick*
discovers the right path.

The three cases, and the single deciding question — **whose money, and when?**

| Situation | Your money spent? | When recovered | Headline Expenses | Category budget | Net worth impact |
|---|---|---|---|---|---|
| **Normal expense** | Yes — gone for good | Never | Counts | Counts | − amount |
| **Reimbursable expense** | Yes — briefly | Later (you're owed) | **Counts** | **Excluded** | ±0 over the cycle |
| **Paid on my card for someone** | **No — never yours** | At the time (cash in hand) | **Excluded** | **Excluded** | **±0 (a wash)** |

The reimbursable case is **new behaviour** (a flag + a spawned receivable). The
"paid for someone" case needs **no new accounting** — it is already expressible
as a Credit Card → Cash transfer; it only needs to be made *discoverable*.

## User Story
- As a user who fronted money I'll be paid back for, I want it to still show as
  cash that left my pocket **without** eating the budget for that category, so
  my budgets reflect what I actually bear and I don't forget I'm owed.
- As a user who paid on my credit card for a friend who handed me cash, I want
  to log it in one obvious step **without** it counting as my spending or income,
  so my Expenses, Income, and net worth stay honest.
- As a user who has never read a finance guide, I want the app to recognise
  these situations from plain language or an obviously-named button, so I never
  have to learn an accounting "trick."

## Data Model

### `TransactionRecord` (additive — `lib/models/finance/transaction_record.dart`)
Two new **nullable / defaulted** fields so older stored/synced rows deserialize
unchanged (mirrors how `transferGroupId` was added):

```dart
class TransactionRecord {
  // ...existing fields...

  /// True when this outflow is money the user expects to recover (e.g. a work
  /// expense to be reimbursed). It STILL counts in headline Expenses (real cash
  /// left) but is excluded from per-category budget spend. Never set on inflow
  /// or transfer legs.
  final bool reimbursable;

  /// Forward link to the ReceivableType.reimbursement this outflow spawned, so
  /// the UI can show "you're owed ₱X" and settle it. Null when not reimbursable
  /// or no receivable was created.
  final String? reimbursementReceivableId;
}
```

- `fromJson`: `reimbursable: json['reimbursable'] as bool? ?? false`,
  `reimbursementReceivableId: json['reimbursementReceivableId'] as String?`.
- `toJson`: emit both keys.
- `copyWith`: add both (the `String?` uses the existing nullable-copy idiom;
  `reimbursable` is a plain `bool?` → `reimbursable ?? this.reimbursable`).

### `Receivable` (additive — `lib/models/finance/receivable.dart`)
One new back-link field; `ReceivableType.reimbursement` already exists:

```dart
class Receivable {
  // ...existing fields...

  /// Back-link to the TransactionRecord whose reimbursable outflow created this
  /// receivable. Null for receivables created directly (salary, business, etc.).
  final String? reimbursementForTxnId;
}
```

- `fromJson` / `toJson` / `copyWith` follow the file's existing null-tolerant
  pattern (`json['reimbursementForTxnId'] as String?`).

### No model change for "paid for someone"
That case is a standard transfer (`type: outflow + inflow` legs sharing a
`transferGroupId`). The Credit Card leg increases the liability via the existing
sign rule (`ledger_presenter.dart` `_applyBalanceDelta`, liability branch). No
new fields.

## Presenter API

### `BillsReceivablesPresenter` / `LedgerPresenter` — spawning the receivable
When a reimbursable outflow is saved, atomically create the linked receivable:

```dart
// In the add-transaction save path (LedgerPresenter), when reimbursable == true:
Future<TransactionRecord> addReimbursableExpense(
  TransactionRecord outflow, {
  required DateTime expectedReimbursementDate,
}) async {
  // 1. persist the outflow (reimbursable: true)
  // 2. create ReceivableType.reimbursement:
  //      amount = outflow.amount, expectedDate = expectedReimbursementDate,
  //      categoryId = outflow.categoryId, reimbursementForTxnId = outflow.id
  // 3. stamp outflow.reimbursementReceivableId = receivable.id
  // Returns the persisted outflow. Settling later reuses the EXISTING
  // markReceivableReceived() path, which already writes the offsetting inflow
  // tagged with receivableId.
}
```

### Budget gating — exclude reimbursables from category spend
Add `&& !t.reimbursable` alongside the existing `transferGroupId == null` guard
in **all three** per-category spend tallies:

- `budget_presenter.dart` → `spentFor(categoryId)` (~line 335)
- `budget_presenter.dart` → `sectionSpent(group)` (~line 266)
- `treasury_dashboard_presenter.dart` → `_budgetSpentFor(b)` (~line 498)

`monthTotalOutflow` (`treasury_dashboard_presenter.dart` ~line 239) is
**unchanged** — reimbursables still count in headline Expenses by design.

### Optional derived metric (net-of-pending view)
```dart
// treasury_dashboard_presenter.dart — for an Expense-tile sub-line.
double get pendingReimbursableOutflow; // this month's reimbursable outflows
                                       // whose receivable is not yet received
double get monthOutflowNetOfReimbursements =>
    monthTotalOutflow - pendingReimbursableOutflow;
```

### Intent presets — "Paid for someone" (logic lives in the presenter)
```dart
// LedgerPresenter — builds the CC->Cash transfer from an intent, NOT in build().
Future<void> addPaidForSomeoneTransfer({
  required String creditAccountId, // the card charged
  required String cashAccountId,   // where their cash landed
  required double amount,
  required String description,
  required DateTime date,
  String? note,
}) => addTransfer(
      fromAccountId: creditAccountId,
      toAccountId: cashAccountId,
      amount: amount, description: description, date: date, note: note,
    );
// Reuses the existing addTransfer() verbatim — both legs already carry
// transferGroupId, so income/expense/budget exclusion is automatic.
```

## NLP Parser (`lib/utils/finance_nlp_parser.dart`)
Mirror the existing "pay down a card" intent pattern (`_tryTransfer` / the
`paid|pay|settle` pattern, ~lines 60–215). Add a **"paid for someone +
got paid back"** recognizer that routes to the transfer structure:

- Triggers on shapes like: *"paid 800 on <card> for <name>, <name> paid me back"*,
  *"covered <name>'s 500 on <card>, they gcash'd me"*, *"spotted <name> 1200 bpi card cash back"*.
- Resolves the card account (liability) and a cash/liquid destination; emits a
  `TransactionType.transfer` preparse (from = card, to = cash) for confirmation,
  **never auto-committed** when the destination account is ambiguous (same
  guard rail the existing parser uses).
- If "paid me back" is **absent** but "for <name>" is present → treat as a
  reimbursable expense candidate instead (suggest the reimbursable toggle), since
  the money hasn't returned yet.

## UI Requirements

### #1 Intent shortcut in the add-transaction type selector
`add_transaction_sheet.dart` currently offers Inflow / Outflow / **Transfer**
(~line 374). "Transfer" is mechanism-language. Add an intent entry:

- **Label:** "Paid for someone" (icon: people/handshake).
- On select: pre-configures a transfer with **From = a credit/liquid account**,
  **To = Cash**, and shows one line of plain copy:
  *"You paid on your card for someone and they paid you back — this won't count
  as your spending or income."*
- Thumb zone: the type selector and primary **Save** stay in the bottom 30%.

### Reimbursable toggle (case 2)
- When type is **Outflow**, show a **"Reimbursable"** switch. Category picker
  stays fully enabled and behaves normally — the flag, not the category, gates
  the budget (so a reimbursable "Travel" expense keeps its real category for
  reporting yet never eats the Travel budget).
- When ON: reveal an optional **"Expected back by"** date (defaults to e.g. +30d)
  and helper copy: *"Counts as cash out, but not against your budget. We'll track
  it as money you're owed."*

### #3 Inline hint on the transfer screen
- A subtle info chip/line under the transfer fields:
  *"Paid on your card for someone and got cash back? Pick Credit Card → Cash."*

### Dashboard surfacing
- Expense tile may show a sub-line when `pendingReimbursableOutflow > 0`:
  *"of which ₱X pending reimbursement"*.

### States
- Loading / Empty / Populated / Error per the standard sheet behaviour.
- **Glanceability:** the chosen situation (normal / reimbursable / paid-for-someone)
  is obvious from the selected chip + helper copy in < 1s.
- **Micro-animations:** toggle reveal of the date field 150–300ms ease.

### Theming
- **All** new copy, icons, chips read from `Theme.of(context)`
  (`colorScheme.*`, `textTheme.*`). No `AppColors.*` / `AppColorsLight.*` inside
  widgets — must work in both dark (Solo Leveling) and light modes.

## RPG Mechanics
- No new XP. These are corrective/classification flows, not achievements;
  awarding XP for logging "money that isn't yours" would gamify noise. Existing
  ledger-logging XP rules are unchanged. (Open question flagged below.)

## Storage
- **No new `StorageService` keys.** New fields ride inside the existing
  `transactions` and `receivables` JSON blobs. Backward-compatible because every
  new field is nullable/defaulted on read.

## Edge Cases
- **Partial reimbursement:** receivable `receivedAmount` may differ from the
  outflow amount (already supported). Net Income−Expense reflects the shortfall
  honestly; the unrecovered remainder remains a real expense.
- **Reimbursement never arrives:** the outflow stays counted in Expenses (correct
  — you bore it). The open receivable surfaces as still-owed; deleting it leaves
  the expense intact.
- **Editing a reimbursable outflow → not reimbursable:** must delete/detach the
  spawned receivable (and vice-versa create one). Mirror the
  transfer-group cleanup already done when converting a transfer to a normal txn
  (`add_transaction_sheet.dart` ~lines 160–193).
- **"Paid for someone" but they pay later (no cash yet):** NOT this transfer.
  Either log a reimbursable expense on the card, or charge the card into a
  `custodian`/holding account until they pay. Helper copy must steer the user
  away from the instant-transfer path when no money has returned.
- **Card overpayment / negative liability:** unaffected — existing
  `currentPayable` flooring handles it.
- **Deleting one transfer leg:** existing transfer-group integrity rules apply;
  no new path.

## Acceptance Criteria
- [ ] `TransactionRecord` gains `reimbursable` (default false) +
      `reimbursementReceivableId`; round-trips through `fromJson`/`toJson`/`copyWith`
      and old JSON (missing keys) loads with `reimbursable == false`.
- [ ] `Receivable` gains `reimbursementForTxnId`; round-trips and is null for
      existing receivables.
- [ ] Saving a reimbursable outflow spawns a `ReceivableType.reimbursement`
      with matching amount/category and `reimbursementForTxnId` == the txn id;
      the txn's `reimbursementReceivableId` points back.
- [ ] Reimbursable outflow **is** included in `monthTotalOutflow` but **excluded**
      from `spentFor`, `sectionSpent`, and `_budgetSpentFor` (regardless of category).
- [ ] Settling the spawned receivable via `markReceivableReceived` creates the
      offsetting inflow (tagged `receivableId`); net Income−Expense reconciles.
- [ ] A Credit Card → Cash transfer ("paid for someone") is excluded from
      `monthTotalInflow`, `monthTotalOutflow`, and all budget spend (existing
      `transferGroupId` guard), increases the card's owed balance and the cash
      balance, and leaves `netWorth` unchanged.
- [ ] The "Paid for someone" intent in the add sheet produces exactly that
      transfer (one outflow leg on the card + one inflow leg on cash, shared
      `transferGroupId`).
- [ ] NLP parser routes "paid … for … paid me back" inputs to a transfer
      preparse (card → cash) and routes "paid … for …" (no payback) to a
      reimbursable-expense suggestion.
- [ ] All new copy renders correctly in both dark and light themes
      (no hardcoded token references in widgets).
- [ ] Tests added to `test/presenters/treasury_dashboard_parity_test.dart`
      (and budget presenter tests) in the existing transfer-exclusion style:
      reimbursable lifecycle (paid → counts in outflow, excluded from budget →
      reimbursed → inflow offsets) and the paid-for-someone wash (net worth ±0).

## Open Questions
1. Should "Reimbursable" expose a free-text "who owes me" field, or is the
   receivable's name enough?
2. Default "Expected back by" horizon — +30 days, end-of-month, or none?
3. Do we want a top-level filter/badge in the ledger for "money I'm owed"
   aggregating open reimbursement receivables?
