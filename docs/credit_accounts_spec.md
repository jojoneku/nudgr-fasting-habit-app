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

---

### Sources (verify on implementation)
- BPI Credit Card Rates and Fees — https://www.bpi.com.ph/personal/cards/credit-cards/rates-and-fees
- BPI Sample Interest Calculation — https://www.bpi.com.ph/personal/cards/credit-cards/sample-interest-calculation
- BSP Circular 1165 (3%/mo · 36%/yr cap), via Lexology — https://www.lexology.com/library/detail.aspx?g=c7e64fea-fe99-465d-849a-ed8c0e17d1bc
