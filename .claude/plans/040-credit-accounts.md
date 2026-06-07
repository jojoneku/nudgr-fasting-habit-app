# Plan 040 — Credit Accounts (Treasury)

> Spec: [docs/credit_accounts_spec.md](../../docs/credit_accounts_spec.md)
> Branch: **`feat/040-credit-accounts`** off `dev`. **Own PR** (do not bundle with finance-historical-import).
> Per repo workflow: PR `--base dev` (dev→main auto-promotes).

## Goal
Make credit cards / credit lines / BNPL first-class in the treasury: correct debt direction, credit
limit + statement/due dates, pay-the-card via chat, statement→bill reminders, BPI finance-charge calc,
and a dedicated Credit section showing remaining limit + current payable per row.

---

## Conflict Check

| Check | Finding |
|---|---|
| **File overlap** | Edits `financial_account.dart`, `ledger_presenter.dart`, `treasury_dashboard_presenter.dart`, `account_setup_view.dart`, `treasury_dashboard_view.dart`, `finance_nlp_parser.dart`, `notification_service.dart`. `finance-historical-import` (current branch) touches import service/payload + ledger import test — **disjoint** from these, but branch off `dev` clean to avoid carrying its WIP. |
| **Model overlap** | Adds nullable fields to `FinancialAccount` (backward compatible). Reuses existing `Bill`/`BillType.creditCard`. No new model clashes. |
| **StorageService keys** | None new — rides `finance_accounts` + `finance_bills`. |
| **Sync** | `SyncDomain.financeRecord` (existing). |
| **Supersedes** | None. |
| **Dependency order** | Standalone. Step 1 (sign fix) is independently shippable if we want to split. |

---

## Steps (each = one logical commit)

### Step 1 — Fix liability balance sign  *(the bug; smallest shippable unit)*
- `ledger_presenter.dart`: replace the flat `delta` in `_applyBalanceDelta` with category-aware
  `_signedDelta` (invert for `isLiability`). Verify `addTransfer` pay-card leg + `_reverseBalanceDelta`.
- Tests: spend↑ / pay↓ on a liability; transfer funder↓ + card↓; edit/delete reversal symmetry.
- ✅ Acceptance #1.

### Step 2 — Model: credit fields + getters + brand preset
- `financial_account.dart`: add `creditLimit`, `statementDay`, `paymentDueDay`, `financeChargeRate`,
  `creditBrand`; extend `fromJson`/`toJson`/`copyWith`; add `currentPayable`/`availableCredit`/
  `utilization`.
- New `lib/models/finance/credit_brand_presets.dart` with `CreditBrandPreset` + `kBpiRewards`.
- Tests: round-trip incl. old JSON without the new keys; getter math.
- ✅ Acceptance #2 (model half).

### Step 3 — Account setup UI: Credit details
- `account_setup_view.dart`: conditional "Credit details" section for liability categories
  (limit / statement day / due day / advanced rate / brand picker that seeds rate). Theme-aware,
  ≥44px targets, validation.
- ✅ Acceptance #2 (UI half).

### Step 4 — Dashboard Credit section
- `treasury_dashboard_presenter.dart`: `creditAccounts`, `totalCreditOwed`, `totalCreditAvailable`.
- `treasury_dashboard_view.dart`: Credit section below accounts — one row card per account (payable,
  utilization meter = remaining/limit, due-date chip w/ state color). Long-press → Pay card.
  `surfaceContainerLow` on dashboard bg.
- Tests: presenter getters/totals; widget renders in light + dark.
- ✅ Acceptance #6.

### Step 5 — Pay-the-card chat intent
- `finance_nlp_parser.dart` (+ classifier prompt if needed): "pay credit" intent → transfer with
  `toAccount` = liability; clarify funder if missing. Commit via existing `addTransfer`; settle the
  statement Bill when covered.
- Tests: parse "paid bpi cc 5000 from bpi savings"; clarify path; bill settled on full pay.
- ✅ Acceptance #3.

### Step 6 — Statement → Bill + due reminder
- Lazy statement snapshot on presenter load / month rollover → `Bill(BillType.creditCard, …)`.
- `notification_service.dart`: `scheduleCreditDueReminder` (alarmClock, `channelIdFinance`); wire into
  `BillsReceivablesPresenter` reminder refresh alongside `scheduleBillsReminder`.
- Tests: statement creates bill once per cycle; reminder scheduled; idempotent.
- ✅ Acceptance #4.

### Step 7 — Finance charges
- New `lib/utils/credit_finance_charge.dart`: `computeFinanceCharge` (v1 monthly-rate approximation,
  day-count params reserved), `computeMinimumDue`, `computeLateFee`.
- Apply at statement close when prior balance unpaid by due date; surface min due on row + bill.
- Tests: against BPI worked example numbers; cap clamp (≤3%/mo); min-due floor ₱850.
- ✅ Acceptance #5.

### Step 8 — Rollout note + format/test gate
- Dismissible one-time info on the credit row re: corrected spend/pay direction (no history rewrite).
- `dart format` validation, full `flutter test`, manual smoke (add card → spend → pay via chat →
  see Credit section + reminder).
- Open PR `--base dev`, own branch.

---

## Risks / decisions
- **History not auto-migrated** — old inflow-workaround charges stay as-is; info note instead of risky
  rewrite. (Revisit if users ask for a migration tool.)
- **Interest precision** — v1 uses monthly-rate approximation; daily day-count method is documented in
  the util for a later tightening. Rates are user-editable; BPI figures are a seed, not a guarantee.
- **Splittable** — Step 1 (sign fix) can ship as its own small PR first if you want the bug gone now
  while the rest is built.

## Out of scope (future)
Reward points; non-BPI brand presets; cash-advance-specific interest split; multi-currency cards.
