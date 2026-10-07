# Credit Accounts Spec — Treasury

> Status: **Draft for approval** · Owner: Treasury · Related: [docs/fasting_loop_spec.md](fasting_loop_spec.md) pattern, `LedgerPresenter`, `BillsReceivablesPresenter`
> Feature lives on its own branch/PR (`feat/040-credit-accounts`) — **not** bundled with `finance-historical-import`.

## 1. Problem

The treasury already has liability account categories (`creditCard`, `creditLine`, `bnpl`) where
`balance` is documented as "debt owed". But the balance engine treats every account the same way:

```dart
// ledger_presenter.dart:640  (_applyBalanceDelta)
final delta = type == TransactionType.inflow ? amount : -amount;
```

For a liability this is **inverted**. Spending on a credit card should *increase* what you owe, but an
`outflow` currently *decreases* the balance — so the user must log a charge as an `inflow` to make the
debt rise. There is also no concept of a **credit limit**, **statement date**, **due date**, **finance
charges**, or a place in the UI that shows **remaining credit** vs **current payable**.

## 2. Goals

1. **Fix the sign bug** — for liability accounts: **spend = outflow (debt ↑)**, **pay = inflow (debt ↓)**.
2. **Credit setup** — when an account is `creditCard`/`creditLine`/`bnpl`, capture **credit limit**,
   **statement day**, **payment due day**, and (optional) **monthly finance-charge rate**.
3. **Pay-the-card via chat** — *"paid bpi cc 5,000 from BPI Savings"* → a **transfer** that debits the
   funding account and reduces the card's owed balance.
4. **Statement → Bill** — when a statement cycle closes, snapshot the payable into a `Bill` so it shows
   in Bills and rides the existing reminder system; fire **due-date reminders**.
5. **Finance charges** — compute interest on balances not paid in full by the due date, using
   documented BPI mechanics (rates configurable per account; BPI preset seeded).
6. **Dedicated Credit section** — a card list below Accounts, **one row per credit account** showing
   **remaining credit limit** and **current payable** (+ due date, utilization).

### Non-goals (this round)
- Reward **points** accrual (explicitly deferred per product decision).
- Brands beyond a **BPI** preset (architecture leaves room; others added later).
- Per-transaction interest on cash advances vs retail split beyond the documented approximation.

## 3. Data model changes

### 3.1 `FinancialAccount` — new optional fields (liability-only)
```dart
final double? creditLimit;        // total approved limit; null for non-liability
final int? statementDay;          // 1–28, day the statement closes
final int? paymentDueDay;         // 1–28, day payment is due
final double? financeChargeRate;  // monthly NOMINAL rate, e.g. 0.03 (3%); null = no interest calc
final String? creditBrand;        // preset key, e.g. 'bpi_rewards'; null = manual
```
- Later additions (see §12): `dueDaysAfterStatement` (due = close + N days, wins over
  `paymentDueDay`), `minimumRule` (`percentOfBalance` / `fixedAmount` / `payInFull`) and
  `minimumFixedAmount`.
- `toJson`/`fromJson`/`copyWith` extended; all nullable → **backward compatible** with stored data.
- Validation lives in the model: these fields are only meaningful when `isLiability`.

New computed getters:
```dart
double get currentPayable => isLiability ? balance : 0;          // what you owe now
double? get availableCredit =>                                   // limit − owed
    (isLiability && creditLimit != null) ? creditLimit! - balance : null;
double? get utilization =>                                       // 0..1 for the meter
    (isLiability && creditLimit != null && creditLimit! > 0) ? balance / creditLimit! : null;
```

### 3.2 Brand preset (BPI Rewards)
A small const map (no institution data hardcoded into accounts — only an opt-in preset the user picks):
```dart
// finance/credit_brand_presets.dart
const kBpiRewards = CreditBrandPreset(
  key: 'bpi_rewards',
  label: 'BPI Rewards (Mastercard/Visa)',
  monthlyFinanceRate: 0.03,   // 3% nominal regular-purchase rate
  minPaymentRate: 0.0357,     // 3.57% of balance...
  minPaymentFloor: 850,       // ...or ₱850, whichever is higher
  lateFeeFlat: 850,           // late fee = min(₱850, unpaid min due)
);
```

## 4. Balance engine fix (the core bug)

In `_applyBalanceDelta`, sign depends on the **target account's** category:

```dart
double _signedDelta(FinancialAccount? a, double amount, TransactionType type) {
  final base = type == TransactionType.inflow ? amount : -amount;
  return (a?.isLiability ?? false) ? -base : base;   // liability: invert
}
```
- **Asset/liquid**: inflow +, outflow − (unchanged).
- **Liability**: outflow (spend) **+debt**, inflow (pay) **−debt**.
- Parent-propagation note: liabilities are top-level (`parentAccountId == null`), so the existing
  sub-account/parent propagation is unaffected. Sign is computed per affected account, so a transfer
  pair (asset outflow + liability inflow) settles correctly: cash ↓ on the funder, debt ↓ on the card.

`_reverseBalanceDelta` already delegates to `_applyBalanceDelta`, so undo/edit/delete stay correct.

> ⚠️ **Migration**: existing users may have logged credit-card charges as `inflow` to work around the
> bug. We will **not** auto-rewrite history (risky). Instead: a one-time, dismissible info note on the
> credit card row explaining the corrected direction. Covered in the plan's rollout step.

## 5. Pay-the-card via chat

The NLP pipeline (`finance_nlp_parser.dart` → AI classifier → `_commitParsed`) already supports
`transfer`. Add a **"pay credit" intent**:
- Triggers: `paid`, `pay`, `settle`, `top up` + a token resolving to a liability account
  (e.g. *"paid bpi cc 5,000 from bpi savings"*, *"settle gcredit 1.2k"*).
- Resolution: `toAccount` = the liability account; `fromAccount` = the named funding account (or ask
  via the existing clarify turn if absent). Amount parsed as today.
- Commit: routes to existing `addTransfer(fromAccountId: funder, toAccountId: card, …)`. With the §4
  fix, the inflow leg on the card reduces debt. No new transfer plumbing.
- If the statement Bill (§6) exists and the payment ≥ payable, mark that `Bill.isPaid = true`.

## 6. Statement → Bill + reminders

On each `statementDay` (evaluated lazily when the presenter loads / month rolls over — no background
job needed), if a statement for that cycle hasn't been snapshotted:
1. Create a `Bill` (`BillType.creditCard`) with `amount = currentPayable at cutoff`,
   `dueDay = paymentDueDay`, linked to the account.
2. The existing `scheduleBillsReminder` already notifies for unpaid bills monthly. Extend with an
   **optional per-account due reminder** (`NotificationService.scheduleCreditDueReminder`) firing the
   morning of (or N days before) `paymentDueDay`, reusing `channelIdFinance` + alarmClock mode.
3. Paying the card (§5) settles the Bill when covered.

## 7. Finance charges (BPI mechanics)

Source: BPI "Rates and Fees" + "Sample Interest Calculation" pages (verify on implementation).

- **Rate**: regular purchases **3% nominal monthly (2.73% effective)**; **BPI Free+ 2.5%**. Stored as
  `financeChargeRate` (nominal). BSP cap is **3%/mo = 36%/yr** (Circular 1165), reviewed every 6 months.
- **Method (documented)**: daily — `dailyRate = monthlyRate × 12 ÷ 360`, applied to the outstanding
  balance per day from posting (cash advance) / day after statement (retail) through payment.
- **v1 approximation** (util `computeFinanceCharge`): if the previous statement balance was **not paid
  in full** by `paymentDueDay`, accrue `outstanding × monthlyRate` on the next statement and add the
  **late fee** = `min(lateFeeFlat, unpaidMinDue)`. The precise day-count method is captured in the util
  signature so we can tighten it later without changing callers.
- **Minimum due**: `max(balance × 0.0357, ₱850) + pastDue` — surfaced on the credit row and as the
  Bill's "minimum" hint.
- All rates **editable per account**; the BPI preset just seeds defaults. No figure is presented as
  guaranteed-current — the setup screen links to the source and shows "as configured".

## 8. UI

### 8.1 Account setup (`account_setup_view.dart`)
When `category ∈ {creditCard, creditLine, bnpl}`, reveal a **Credit details** section:
- Credit limit · Statement day · Payment due day · (advanced) Monthly finance rate · Brand preset
  picker (seeds the rate fields). Touch targets ≥ 44px; theme-aware colors only.
- Payment-due rule and minimum-payment rule controls — see §12.5. The web
  `WebAccountFormDialog` mirrors the mobile form field for field.

### 8.2 Credit section on the dashboard (`treasury_dashboard_view.dart`)
A new section **below the accounts list**, fed by the existing `liabilityAccounts` getter, rendering
**one row card per credit account**:
- Line 1: name + brand chip · current payable (prominent).
- Line 2: utilization meter — **remaining credit / limit** (e.g. *₱32,400 of ₱50,000 available*).
- Line 3: due date (e.g. *Due Jun 25 · min ₱1,250*) with state color (upcoming / due-soon / overdue).
- Tap → account detail; long-press → quick "Pay card" (prefills chat/transfer sheet).
- Card elevation per house rule: section cards on the dashboard background → `surfaceContainerLow`.

Presenter additions (`TreasuryDashboardPresenter`):
```dart
List<FinancialAccount> get creditAccounts => liabilityAccounts;     // explicit name for the section
double get totalCreditOwed => creditAccounts.fold(0.0, (s, a) => s + a.currentPayable);
double get totalCreditAvailable =>
    creditAccounts.fold(0.0, (s, a) => s + (a.availableCredit ?? 0));
```
Net-worth math already treats liabilities separately; the corrected sign makes "owed" rise with spend,
so net worth now moves the right way too.

## 9. Persistence & sync

- No new `StorageService` keys — extended fields ride existing `finance_accounts`; statement Bills ride
  `finance_bills`. All sync under `SyncDomain.financeRecord` (no new domain).
- New nullable fields are forward/backward compatible across app versions.

## 10. Acceptance criteria

1. Logging a spend on a credit card as **outflow** increases its payable; logging a **payment/inflow**
   decreases it. The old inflow-to-spend workaround is no longer required.
2. Credit setup persists limit / statement day / due day / rate / brand and survives sync + restart.
3. *"paid <card> <amount> from <account>"* in chat performs a transfer reducing the payable and (if
   present) settles the matching statement Bill.
4. A statement Bill is generated at cutoff with the correct payable + due day and appears in Bills; a
   due-date reminder fires.
5. Unpaid-by-due balances accrue a finance charge consistent with the configured rate; late fee applied
   per preset.
6. The dashboard shows a Credit section, one row per card, with remaining limit + current payable + due
   date, theme-aware in both light and dark mode.

## 11. Test plan (high level)
- `financial_account_test`: new field round-trip; `availableCredit`/`utilization`/`currentPayable`.
- `ledger_presenter_test`: liability sign (spend↑, pay↓); transfer pay-card; edit/delete reversal.
- `finance_nlp_parser_test`: "pay credit" intent resolution + clarify when funder missing.
- `credit_finance_charge_test`: charge + min-due + late-fee against the BPI worked example.
- `treasury_dashboard_presenter_test`: `creditAccounts`, totals.
- Widget: credit row renders limit/payable/due in both themes.

## 12. Billing cycle, due rules and minimums

Supersedes the due-date and minimum-due parts of §6–§8 where they disagree. The cycle math is
`lib/utils/credit_cycle.dart`; the bill generator, the dashboard due line, the cycle note and the
due reminder all read cycles from there, so they cannot disagree about which cycle is which.

### 12.1 What a cycle is
A cycle runs from the day **after** one statement close through the next close, **inclusive**.
- A charge dated **on** the close day stays on that statement.
- A charge dated the day **after** rides the next one.

Example — closes the 20th, due 15 days later: a charge on Sep 20 is on the Sep 20 statement (due
Oct 5); a charge on Sep 21 lands on the Oct 20 statement (due Nov 4).

`statementDay` stays clamped to 1–28 so every month has a close.

### 12.2 Two due rules
An account stores **exactly one** of:

| Rule | Field | Due date |
|---|---|---|
| Day of month | `paymentDueDay` (1–28) | The first such day strictly after the close (closes the 20th, due the 5th → next month). |
| Days after statement | `dueDaysAfterStatement` (1–`kMaxDueDaysAfterStatement` = 45) | Close + N days, crossing month ends naturally. |

When both are present (older data), the offset wins. The account forms clear the other field on
save.

**Why offset exists:** many PH issuers say "due 15 days after the statement", not "due on the 5th".
A fixed day only matches that while every cycle is the same length. After a 31-day month the real
due date shifts a day against any fixed day of month, so a fixed day is sometimes wrong by a day.
The offset rule is exact for those issuers.

An account **has a billing cycle** (`FinancialAccount.hasBillingCycle`) only with a statement day
**and** one of the two due rules. Without one, the dashboard warns that it is never billed.

### 12.3 Minimum payment rules
`minimumRule` decides the minimum on a statement (`computeMinimumForRule`):

| Rule | Minimum |
|---|---|
| `percentOfBalance` | `max(statement × rate, floor)`, using the card preset's rate/floor, or the BSP-style defaults (3.57%, ₱850). |
| `fixedAmount` | `minimumFixedAmount` (e.g. a monthly installment), never above the statement. |
| `payInFull` | The whole statement. |

Category defaults when `minimumRule` is null (`defaultMinimumRuleFor` / `effectiveMinimumRule`):
**credit card → percent of balance**; **credit line and BNPL → pay in full**. The forms save the
rule explicitly, so a later change to a default never silently re-rules an existing account.

### 12.4 Dashboard semantics
- The **due line** reflects only an **unpaid statement with money on it**: "Due in 4 days · min ₱850",
  or "Due in 4 days · ₱3,000 in full" under pay-in-full. The presenter builds the whole label;
  the view renders it as-is.
- Otherwise it reads **"No payment due"**, including when the card has a balance on a cycle that
  has not closed yet. That balance has no minimum until it is billed.
- **Pay stays available whenever anything is owed** (`currentPayable > 0`), even with no payment
  due. Paying early is always allowed.
- The **cycle note** always shows the current cycle, e.g. "Statement closes Oct 20 · due Nov 4",
  or a warning when the account has no billing cycle. Mobile and web both show it.

### 12.5 Account form (mobile + web)
Inside **Credit details**:
- **Payment due**: segmented "Day of month" | "Days after statement". Day of month shows the
  1–28 due-day picker. Days after statement shows a 1–45 "Due after" picker and the hint
  *"Some issuers count days from the statement, e.g. due 15 days after."* An account saved with an
  offset opens in offset mode.
- **Minimum payment**: segmented "% of balance" | "Fixed amount" | "Pay in full". Fixed amount
  shows a required amount field (> ₱0). A new account follows its category default until the user
  picks a rule. An existing credit account opens on its `effectiveMinimumRule`.
- On save, a non-credit category stores none of these fields. A credit category stores one due rule,
  an explicit `minimumRule`, and `minimumFixedAmount` only under `fixedAmount`.
- These terms are **form-only**: chat and quick-log never create or edit accounts
  (see `docs/chat_logging_coverage.md` §3).

### 12.6 Statement generator rules
`BillsReceivablesPresenter` snapshots closed cycles into `BillType.creditCard` bills:
- **Amount = balance as of the close** (`LedgerPresenter.payableAsOf(account, cycle.close)`), never
  today's balance. The app may open days later, and charges after the close belong to the next
  statement.
- **Never a ₱0 bill.** A cycle that closed owing nothing gets no statement.
- Each bill is filed under the month its payment is **due** (`CreditCycle.dueMonthKey`), with that
  day as its due day. A cycle closing the 20th and due the 5th is therefore not overdue as soon as
  it is generated.
- **Current month:** billed once today reaches the close.
- **Past cycles are backfilled only while their due date is still ahead.** The previous month is
  always checked, since its statement is often still payable. A past-due cycle is skipped because
  its unpaid balance is already carried into the newer statement, and billing it too would count
  the same debt twice.
- **Phantom ₱0 auto-statements are cleaned up.** Earlier versions backfilled ₱0 "review me"
  placeholders whenever the card owed something today. Unpaid, untransacted ₱0 auto-statements
  are swept away before generation.

### 12.7 Installment holds
A credit account's installment plans hold part of its limit before they are billed.
- **The hold is what the plans will still bill**: for each active plan on the account,
  `remainingMonths × monthlyAmount` (`Installment.remainingAmount`). The monthly amount carries the
  add-on interest, so an interest-bearing plan holds the interest still to come as well as the
  principal. That is what issuers hold against the limit. It is not "remaining principal".
- **Owe** (`totalDebt`) = `balance + hold`, floored at zero as a whole. An overpaid card (negative
  balance) offsets its hold: ₱−2,000 with a ₱5,000 hold owes ₱3,000, so ₱47,000 of a ₱50,000 limit
  is available. This matches `totalLiabilities` on the dashboard, which sums `balance + hold`.
  **Available** = limit − owe. **Utilization** = owe / limit.
- **Derived, never stored.** `FinancialAccount.unbilledInstallments` is not written by `toJson`,
  and `fromJson` ignores any value older builds stored. Storage and sync carry no hold.
- **One source.** `InstallmentPresenter` owns the plans. `LedgerPresenter` subscribes to it
  (`watchInstallmentPlans`, wired in `TreasuryPresenters`) and stamps each credit account's live hold
  onto `LedgerPresenter.accounts`, derived from the plans and the payments in its own transactions.
  Every other presenter mirrors those accounts, so the dashboard, bills, the account form and Nudgy's
  credit context all read the same hold, including on a cold start.

### 12.8 Installments are billed onto the card at statement close
An installment purchase is a ledger record with `isInstallment: true` (no balance effect, not
spending) plus an `Installment` plan. Its months sit in the account's **hold**
(`unbilledInstallments` = remaining months × monthly amount), and `totalDebt` = billed balance +
hold. Issuers bill one month per statement ("[1/3] Item ₱82.92"), and the app now does the same:
- **On a card with a billing cycle** (`hasBillingCycle`), when the generator processes a closed
  cycle it first posts an **installment charge** for each active plan due that cycle: an outflow on
  the card, `installmentId` = plan id, `isInstallment: false`, the plan's monthly amount, the plan's
  category (fallback `__installment__`), dated the **close date**, described
  "Item — Installment 2/3". The charge raises the card balance and counts toward the plan's
  `paidCount`, so the hold drops by the same amount. `totalDebt` is unchanged; spending is
  recognised in the plan's category when the month is billed.
- **Idempotent by count, one per statement.** A plan should have
  `installmentChargesDueAt(account, plan, cycle)` charges by now: one per statement from the first
  statement due in or after its start month, capped at its length. Counting statements, not due
  months, keeps a month with no due date (a long days-after-close rule) from billing two months on
  the next statement. Only the shortfall below `paidCount` is posted. Payment records booked under the old model count, so nothing is billed
  twice. Charge ids are deterministic (`instchg_<plan>_<n>`), so two devices write the same rows.
- **Statement amount = `payableAsOf(close)`.** Installment months are already in the balance; there
  is no separate installment sum and no "paid this month" exclusion. A part payment therefore
  never shrinks the statement.
- **Paying is always a plain transfer** to the card for the amount actually paid: Bills "Pay",
  quick pay and a transfer typed into the ledger all settle the statement the same way, through
  the payments made since the close. Nothing is booked against an installment at payment time.
- **No backfill.** Charges are posted only for a cycle that has closed and is not yet past due, and
  never for a cycle whose statement was already settled (paid, or paid through a linked entry).
  Charges are not posted while the ledger is still loading; the run is repeated once it has.
- **Rows.** A plan on a cycle card has no "Mark paid": it reads "on statement · 2/3" until billed,
  then "billed · 2/3". It does not appear separately in Coming Up, because it is inside the
  statement row.
- **Cards without a billing cycle** (a BNPL with no statement day) keep a manual "Mark paid" with
  the same shape: the charge is posted on the card, plus a transfer from the funding account when
  one is given. "Mark unpaid" deletes that charge and its transfer.

Worked example (ShopeePay, statement day 4, due the 15th, ₱845.69 revolving, six 3-month plans
starting 2026-10 totalling ₱1,578.71/month, today Oct 7): six charges dated Oct 4, balance
₱2,424.40, hold ₱3,157.42 (was ₱4,736.13), October statement ₱2,424.40, total owed ₱5,581.82
unchanged. Paying ₱850 leaves ₱1,574.40 on the statement.

### 12.9 Statement items ("View items")
Every credit statement bill whose card has a billing cycle shows a "View items · N" link (Bills
tab card on mobile, bill row on web). It opens the statement's item list — a bottom sheet on
mobile, a dialog on web — modelled on the issuer's own bill screen:
- **Header:** Unpaid amount, then Bill amount / Repaid / Unpaid, the due date, and
  "Transaction total: N items · 05 Sep – 04 Oct" (the cycle from the day after the previous
  close through this close).
- **Lines** are the card's own records in exactly the window `payableAsOf` bills, grouped as
  **Purchases** (outflows), **Installments** (charges with `installmentId`, shown "[1/3] Item"),
  **Refunds** (inflows in the window that are not payments — no transfer group, no bill link) and
  **Repaid** (every inflow after the close, as `paymentsToLiabilitySince` counts them). Installment
  purchase records (`isInstallment`) and other accounts' transfer legs are never lines.
- **Reconciliation:** carried over (owed at the previous close − payments during the cycle) +
  purchases + installments − refunds = bill amount; bill amount − repaid (capped, from statement
  progress) = unpaid = `creditStatementRemaining`. A statement frozen before a line was edited (paid,
  or hand-keyed) says so instead of hiding the difference.
- **Editing:** tapping a line opens that record's transaction form (mobile `AddTransactionSheet`,
  web ledger edit dialog). The list reads the ledger on every rebuild, and an open generated
  statement's amount now follows the ledger as soon as a line in its cycle changes (same scope as
  the generator: unpaid, untransacted, not past due, never down to ₱0).

---

### Sources (verify on implementation)
- BPI Credit Card Rates and Fees — https://www.bpi.com.ph/personal/cards/credit-cards/rates-and-fees
- BPI Sample Interest Calculation — https://www.bpi.com.ph/personal/cards/credit-cards/sample-interest-calculation
- BSP Circular 1165 (3%/mo · 36%/yr cap), via Lexology — https://www.lexology.com/library/detail.aspx?g=c7e64fea-fe99-465d-849a-ed8c0e17d1bc
