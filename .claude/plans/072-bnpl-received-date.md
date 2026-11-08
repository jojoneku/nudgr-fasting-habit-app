# Plan 072 — Received date for "posts on receipt" credit (Shopee PayLater)

> Status: BUILT · Authored: 2026-11-08 · Owner: Treasury

## 1. Problem

Shopee PayLater (and Lazada PayLater, and similar) posts a charge to the
statement when the order is received ("Order Received" tapped), not when it was
ordered. The user logs the expense on the order day. Example: ordered Oct 28,
received Nov 6. The lender put it on the November statement; the app put it on
October's, because every cycle rule reads `TransactionRecord.date`.

## 2. Decision

Keep the order date as the record's date. Spending, budgets and history stay
right: the money was committed on the order day. Add an optional **received
date** (`postedDate`) that only decides which statement the charge lands on.
When it is not set, the order date is used, so nothing changes for anyone who
never sets it.

The user's first idea (a received-date input plus a "confirm received date"
notice on the statement items) is kept, with four changes:

1. **Per account, off by default.** A new account setting, "Charges post when
   the order is received" (`FinancialAccount.postsOnReceipt`), on credit and
   BNPL accounts. Some BNPL lenders post at checkout (GCash GGives) and cards
   post at purchase. The field and the notices only appear on accounts with
   the setting on.
2. **Ask only about items that can move.** The statement notice flags purchases
   with no received date that were ordered in the last 14 days before the
   close (`kReceivedDateReviewDays`). Earlier items are received before the
   close in practice.
3. **One tap to confirm.** Each flagged line gets "Received on…" (date picker
   from the order day to today) and "Received on order day" (stores the order
   date, which also clears the notice). The notice has "All received on order
   day". A line with a different received date reads "Ordered 28 Oct ·
   Received 06 Nov".
4. **Installments too.** `Installment.postedDate`: a computed first payment
   month (Plan 068) uses the received date when set. The Plan 068 guard still
   holds: a plan with a billed or paid month is never moved.

## 3. What reads the received date

`TransactionRecord.statementDate` (`postedDate ?? date`) replaces `date` in:
- `LedgerPresenter.payableAsOf` (the statement amount at close),
- `LedgerPresenter.paymentsToLiabilitySince`,
- `buildStatementBreakdown` (placement and order of lines).

Balances do not move: the account balance still changes on the order day (the
lender holds the limit at checkout). An unpaid statement bill already refreshes
its amount on any ledger change (`_refreshStatementAmounts`), so moving an item
fixes both statements with no new wiring.

Not touched: monthly spending, budgets, history, the Ledger month, Nudgy.

## 4. UI

- Account form (credit section): the switch, with "For Shopee PayLater, Lazada
  PayLater and similar."
- Transaction form: "Received on" under More options, only for an expense on a
  `postsOnReceipt` account. The fold opens when it is set.
- Installment form: the same field under More options.
- Statement items sheet: the notice and per-line actions.

## 5. Data

New optional JSON keys: `TransactionRecord.postedDate`,
`Installment.postedDate`, `FinancialAccount.postsOnReceipt`. Old records load
with null/false. Sync stores the JSON payload, so no schema change. An older
app build that re-saves a record drops the new key (last write wins); this is
a single-user app and all devices update together.

## 6. Follow-ups (not in this plan)

- Web: the statement dialog already places items by the received date (it
  uses the same breakdown), but web has no field to set it yet.
