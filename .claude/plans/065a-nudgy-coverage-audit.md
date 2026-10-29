# Plan 065a — Nudgy coverage audit (2026-10-29)

This is a read-only code audit of the finance (Treasury) module, in support of Plan 065. Two agents ran it, and I checked the key claims in the code.

Path abbreviations:
- **Presenters:** Snap = `_buildContext` in `lib/presenters/ai_coach_presenter.dart`, Exec = `lib/presenters/finance_actions_executor.dart`, LP = `ledger_presenter.dart`, BRP = `bills_receivables_presenter.dart`, BP = `budget_presenter.dart`, IP = `installment_presenter.dart`, TDP = `treasury_dashboard_presenter.dart`, GCP = `grocery_cart_presenter.dart`.
- **Views:** BRV = `lib/views/treasury/bills/bills_receivables_view.dart`, ATS = `lib/views/treasury/ledger/add_transaction_sheet.dart`.

## Part 1 — Data Nudgy cannot read

### 1.1 Stored fields

| Model | Field | Can Nudgy read it? |
|---|---|---|
| All finance and grocery models | `createdAt` | The field does not exist. Models have only `updatedAt` (a sync stamp), and a transaction has its `date`. |
| Bill | `billType`, `categoryId`, `recurrenceType`, `reminderDaysBefore`, `seriesId`, `transactionId`, `paidDate` | No |
| Bill | `paidAmount` | Partly: only this month's paid list. `findBills` prints only the billed amount. |
| Bill | `accountId`, `paymentNote` | Partly: only this month's unpaid bills (Snap 1415-1432). `findBills` leaves them out (Exec 92-95). |
| Bill | `nextMonthAmount` | Partly, through `recurringCommitments` |
| Receivable | `receivableType`, `receivedDate`, `accountId`, `reimbursementForTxnId`, `categoryId` | No |
| Receivable | `expectedDate`, `receivedAmount` | Partly: this month only. `findReceivables` leaves them out. |
| Set-aside (BudgetedExpense) | `note`, `accountId`, `destinationAccountId`, `categoryId`, `recurrenceType` | No |
| Budget | `budgetType`, `isRecurring`, the group of each row, spent for each row | No. `findBudgets` prints only the limit. |
| Budget (savings rows) | The whole row | The tool is broken here. `categoryId` is an account id, so `findBudgets` prints the raw id and a name query never matches (Exec 121-128). |
| FinanceCategory | `type`, `excludeFromTotals`, the full list | No |
| FinancialAccount | `creditBrand`, `currency`, `minimumRule`, `minimumFixedAmount`, `statementDay`, `paymentDueDay`, `dueDaysAfterStatement`, `goalFundedAt` | Partly: due and close labels only |
| FinancialAccount | `isActive` | Inactive accounts are hidden from Snap. `findAccounts` shows no active flag. |
| FinancialAccount | `parentAccountId`, `maturityDate`, `goalTarget` | Snap yes. `findAccounts` no. |
| Installment | `startMonth`, `endMonth`, `purchaseDate`, `deferralMonths`, `note`, `categoryId`, `totalInterest`, `totalPayable` | No |
| Installment | `isActive` | Cancelled plans appear in `findInstallments` with no label |
| TransactionRecord | `billId`, `receivableId`, `installmentId`, repayment status of a reimbursable | No. The tool prints `[reimbursable]` even after repayment. |
| MonthlySummary | `accountSnapshots`, `endingCash`, counts, months older than 12 | No |
| FinanceDictEntry, Grocery (cart, price memory, trips) | All fields | No |

### 1.2 Screen figures Nudgy cannot reach

| Screen | Figure (presenter getter) | Status |
|---|---|---|
| Dashboard | Budget left `budgetRemainingNetOfObligations` | No |
| Dashboard | Budget overview totals | No, and the figure differs from Nudgy's |
| Dashboard | Next-month forecast `nextMonthForecast` | No. Snap has only next month's stored bills and receivables. |
| Dashboard | Daily spend charts | Partly, through `findTransactions` |
| Budget | Hero totals, `percentUsed`, pace pill | No, and the figure differs from Nudgy's |
| Budget | Savings `withdrawn`, funded-in, set-aside target | No, and the figure differs from Nudgy's |
| Bills | Statement line items, pending and paid totals, coming-up timeline | Partly or no |
| History | Averages, cumulative net, balance of each account at month end, counts | No |
| Ledger | Owed chip `outstandingOwedTotal`; calendar daily average (different definition) | No |
| Grocery | Everything | No |

### 1.3 Places where Nudgy and a screen disagree today

1. **Three different budget totals.** Snap, the dashboard overview and the Budget tab each compute it differently.
2. **Three different "saved this month" figures.** Snap's savings rate, Snap's trend "set aside", and the History card differ.
3. **The `findTransactions` "Spent" total includes money the app excludes.** It counts reimbursables and categories marked "exclude from totals" (Exec 425-436). The app's `isSpendingOutflow` leaves them out. Checked in the code.
4. **Some values follow the month a tab is showing, not today's month:**
   - Snap's budget fields follow the Budget tab.
   - The find tools follow the Bills tab.
   - `findBudgetGroups` ignores its `month` input.
   - The installment monthly load follows the installment screen's month.
5. **One prompt can hold two totals for the same past month.** The trend lines come from frozen month summaries, but the category grid is recomputed live.
6. **The prompt text is wrong about past bills.** It says past bill line items "are not retained". They are kept, and `findBills(month)` reads them.
7. **A budgeted income category appears as spending** ("₱0 of ₱X target").
8. **Trend labels have no year.**

### 1.4 Questions that fail today

1. "How much budget do I have left?"
2. "Where will my cash be at the end of next month?"
3. "What's on my BPI statement from last month?"
4. "Did Mark pay me back?"
5. "When did I pay Meralco in August?"
6. "Average monthly spending since I started?"
7. "GCash balance at the end of June?"
8. "Last grocery run, and what do eggs cost?"
9. "When does my iPhone installment end, and how much total interest?"
10. "Why isn't this expense counted?"

## Part 2 — Actions Nudgy cannot do

Risk tiers:
- **T1:** a single create that is easy to reverse.
- **T2:** an edit of existing data, or an action that moves money.
- **T3:** a delete, a cascade, a bulk change, a change to later months, or an action with no undo.

| Area | Action | Can Nudgy do it? | Tier |
|---|---|---|---|
| Accounts | Create, edit (sub-account, credit limit, statement and due day, goal target, maturity) | No | T2 |
| Accounts | Delete (refused if the account has sub-accounts or transactions) | No | T3, no undo |
| Accounts | Archive, redeem or restart a goal | No | T2 |
| Transactions | Add an expense or income; a reimbursable | Yes (review card) | T1 |
| Transactions | Transfer | Yes | T2 |
| Transactions | Installment purchase or split | Partly (no deferral, start month or monthly amount) | T2 |
| Transactions | Convert an installment back to a regular entry | No | T2 |
| Transactions | Edit | Partly (no type, transfer destination or reimbursable fields) | T2 |
| Transactions | Delete (also deletes the transfer partner and the installment plan) | Yes, but with no undo and no warning about the cascade | T3 |
| Transactions | Bulk delete; undo a delete | No | T3 / – |
| Bills | Add, edit | Partly | T1 / T2 (T3 if later months change) |
| Bills | Delete | Yes | T3 |
| Bills | Mark paid (full or partial) | Partly (no "already in ledger" option, so a payment can be recorded twice) | T2 |
| Bills | Mark unpaid; bulk paid, unpaid or delete | No | T2 / T3 |
| Bills | Pay a credit card | Yes | T2 |
| Receivables | Add, edit, mark received | Partly / yes | T1 / T2 |
| Receivables | Delete | Yes | T3 |
| Receivables | Mark not received; bulk actions; reorder | No | T2 / T3 / T1 |
| Set-asides | Add, edit, delete | Partly / partly / yes | T1 / T2 / T3 |
| Set-asides | Fund ("Set aside into"), unfund, bulk | No | T2 / T3 |
| Installments | Add | Partly | T2 |
| Installments | Edit plan, delete plan (also deletes its ledger records), mark a month paid or unpaid, bulk | No | T2 / T3 |
| Budgets | Set, edit (changes later months), recurring toggle | No | T2 |
| Budgets | Remove (ends the series) | No | T3 |
| Budgets | Add or rename a group | No | T1 |
| Budgets | Delete a group (moves its budgets) | No | T3 |
| Categories | Add | No | T1 |
| Categories | Edit, archive | No | T2 |
| Categories | Delete (also clears learned words) | No | T3 |
| Grocery | Add, quantity, price, remove items | No | T1 |
| Grocery | Checkout (writes to the ledger), clear cart | No | T2 |
| Grocery | Delete a trip, clear the price book | No | T3 |
| Data | Import (overwrites the whole app), export | No | Never through Nudgy |

### 2.1 Bugs: the confirm card shows one thing and the app saves another

All of these are in Exec. I checked those marked ✔ in the code.

1. ✔ **`addBill`** shows "Pay from" on the card, but does not save the account (Exec 1381-1393). It cannot set the bill type, a reminder, a payment note or the recurrence type.
2. **`addReceivable`** has 2 problems:
   - It shows `owedBy` on the card, but `Receivable` has no such field.
   - It accepts `expectedDay` but does not save it.
3. **`addSetAside`** shows "Into" (the destination account) on the card, but does not save it.
4. ✔ **`editReceivable`** has 2 problems:
   - It shows the new amount on the card, but does not apply it.
   - It builds the expected date in the current calendar month, not in the receivable's own month (Exec 1294-1304).
5. **`editBill` and `editTransaction`:** a category name that does not match any category clears the category. The card still shows the typed name.
6. **`payCredit`** shows a note on the card, but does not save it.
7. **`markBillPaid`** has no "already in ledger" option, so the payment can be recorded twice.
8. **`deleteTransaction`** has 2 problems:
   - The card does not warn that the transfer partner or the installment plan is deleted too.
   - The removed records are discarded, so there is no undo.
9. **Unknown ids:** a delete call with an unknown id shows a "₱0" card, then does nothing.

### 2.2 Writes that save with no confirm card

- ✔ **The quick-log fallback.** When the cloud extractor is unavailable, `_legacyChatInput` saves a fully resolved entry or batch with no card (LP 2501-2503, 2560-2562). A message in Nudgy's chat that looks like an expense can reach this path. This is the same regex binding that once filed "BPI Credit Card" into BPI Savings.
- **`autoResolve: true`** would save directly, but no caller uses it today.
- **Learned category words** are saved when the user confirms an entry. The risk is low.
