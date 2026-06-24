# Plan 054 — Money-That-Isn't-Yours: Expense Classification

Spec: [docs/expense_classification_spec.md](../../docs/expense_classification_spec.md)

## Goal
Let users correctly log two kinds of "looks-like-spending-but-isn't" money so
headline **Expenses**, per-category **budgets**, and **net worth** stay truthful:

1. **Reimbursable expense** (your money, recovered later) — counts in total
   Expenses, excluded from the category budget, spawns a linked
   `ReceivableType.reimbursement`.
2. **Paid on my card for someone who paid me back** (never your money) — a
   Credit Card → Cash transfer; already excluded everywhere by the
   `transferGroupId` guard. Needs only discoverability, no new accounting.

Both are corrective/clarity flows — **no new XP** (logging money that isn't
yours shouldn't be gamified). The RPG loop is untouched.

## Tracks (independent after Phase A)
- **Reimbursement track:** A → B → C
- **Paying-for-someone track:** D → E
- Phase A is the only shared dependency (the model fields). D/E touch no model.

## Affected Files
| File | Action | Layer | Phase |
|---|---|---|---|
| `lib/models/finance/transaction_record.dart` | Modify | Model | A |
| `lib/models/finance/receivable.dart` | Modify | Model | A |
| `test/finance_models_roundtrip_test.dart` | Modify | Test | A |
| `lib/presenters/budget_presenter.dart` | Modify | Presenter | B |
| `lib/presenters/treasury_dashboard_presenter.dart` | Modify | Presenter | B |
| `test/presenters/treasury_dashboard_parity_test.dart` | Modify | Test | B |
| `test/presenters/treasury_presenters_test.dart` | Modify | Test | B |
| `lib/presenters/ledger_presenter.dart` | Modify | Presenter | C, D |
| `lib/presenters/bills_receivables_presenter.dart` | Modify | Presenter | C |
| `lib/views/treasury/ledger/add_transaction_sheet.dart` | Modify | View | C, D |
| `lib/utils/finance_nlp_parser.dart` | Modify | Util | E |
| `test/utils/finance_nlp_parser_test.dart` | Modify | Test | E |

No `StorageService` changes — new fields ride inside the existing `transactions`
and `receivables` JSON blobs (all nullable/defaulted on read).

## Interface Definitions

```dart
// ── Phase A · Model ─────────────────────────────────────────────────────────
// transaction_record.dart  (additive, backward-compatible)
final bool reimbursable;                 // default false; never set on transfer/inflow
final String? reimbursementReceivableId; // forward link to spawned receivable
//   fromJson: json['reimbursable'] as bool? ?? false
//            json['reimbursementReceivableId'] as String?
//   toJson:   emit both
//   copyWith: reimbursable ?? this.reimbursable; nullable-string idiom for the id

// receivable.dart  (additive)
final String? reimbursementForTxnId;     // back-link to the originating outflow
//   fromJson/toJson/copyWith via the file's existing null-tolerant pattern

// ── Phase C · Presenter (LedgerPresenter) ───────────────────────────────────
Future<TransactionRecord> addReimbursableExpense(
  TransactionRecord outflow, {           // outflow.reimbursable == true
  required DateTime expectedReimbursementDate, // default: date + 30d (set by UI)
});
// 1. persist outflow  2. create ReceivableType.reimbursement
//    (amount = outflow.amount, categoryId = outflow.categoryId,
//     reimbursementForTxnId = outflow.id)  3. stamp outflow.reimbursementReceivableId
// Edit/clear path: detach+delete the spawned receivable when the flag is turned
// off (mirror transfer-group cleanup in add_transaction_sheet.dart:160–193).
// Settlement reuses existing markReceivableReceived() — no new settle path.

// ── Phase D · Presenter (LedgerPresenter) ───────────────────────────────────
Future<void> addPaidForSomeoneTransfer({
  required String creditAccountId,       // card charged (from leg)
  required String cashAccountId,         // where their cash landed (to leg)
  required double amount,
  required String description,
  required DateTime date,
  String? note,
}) => addTransfer(fromAccountId: creditAccountId, toAccountId: cashAccountId, ...);
// Thin wrapper over existing addTransfer() (ledger_presenter.dart:462) — both
// legs already carry transferGroupId, so exclusion is automatic.

// ── Phase B · Presenter (derived metric, optional sub-line) ─────────────────
double get pendingReimbursableOutflow;       // month's reimbursable outflows, receivable not yet received
double get monthOutflowNetOfReimbursements;  // monthTotalOutflow - pendingReimbursableOutflow
```

## Implementation Order

### Phase A — Model fields + round-trip tests  *(shared foundation)*
1. [ ] Add `reimbursable` (default `false`) + `reimbursementReceivableId` to
       `TransactionRecord`; update `fromJson`/`toJson`/`copyWith`.
2. [ ] Add `reimbursementForTxnId` to `Receivable`; update the trio.
3. [ ] `test/finance_models_roundtrip_test.dart`: new-field round-trip **and**
       legacy JSON (missing keys) loads with `reimbursable == false`, links null.

### Phase B — Budget gating + parity tests  *(reimbursement track)*
4. [ ] Add `&& !t.reimbursable` beside the `transferGroupId == null` guard in:
       - `budget_presenter.dart:339` (`spentFor`)
       - `budget_presenter.dart:269` (`sectionSpent`, body at :254)
       - `treasury_dashboard_presenter.dart:498` (`_budgetSpentFor`)
5. [ ] Leave `monthTotalOutflow` (`treasury_dashboard_presenter.dart:239`)
       **unchanged** — reimbursables still count in headline Expenses.
6. [ ] Add `pendingReimbursableOutflow` + `monthOutflowNetOfReimbursements`.
7. [ ] Parity tests (mirror the transfer-exclusion cases): reimbursable outflow
       **in** `monthTotalOutflow` but **out** of all three budget tallies.

### Phase C — Reimbursable toggle UI + receivable spawn  *(reimbursement track)*
8. [ ] `add_transaction_sheet.dart`: when type == Outflow, add a **Reimbursable**
       switch (category picker stays enabled — flag, not category, gates budget).
9. [ ] When ON, reveal optional **"Expected back by"** date (default `date + 30d`)
       with helper copy. Toggle reveal animates 150–300ms.
10. [ ] Save path calls `addReimbursableExpense(...)`; edit path handles
        on→off (delete receivable) and off→on (spawn) — presenter logic, not `build()`.
11. [ ] Dashboard Expense tile: sub-line "of which ₱X pending reimbursement"
        when `pendingReimbursableOutflow > 0` (theme-aware).

### Phase D — "Paid for someone" intent + inline hint  *(paying-for-someone track)*
12. [ ] `add_transaction_sheet.dart`: add an intent entry "Paid for someone"
        (alongside Inflow/Outflow/Transfer at :374) that pre-builds a transfer
        From = credit/liquid, To = Cash, with plain-language helper copy.
13. [ ] Wire to `addPaidForSomeoneTransfer(...)`.
14. [ ] Inline info hint under the transfer fields: "Paid on your card for
        someone and got cash back? Pick Credit Card → Cash." (theme-aware).

### Phase E — NLP parser patterns  *(paying-for-someone track)*
15. [ ] `finance_nlp_parser.dart`: mirror the existing pay-down-card intent
        (~lines 60–215). Recognize "paid … for … paid me back" → transfer
        preparse (card → cash, never auto-commit when destination ambiguous);
        "paid … for …" with no payback → suggest the reimbursable toggle.
16. [ ] `test/utils/finance_nlp_parser_test.dart`: both routings + ambiguity guard.

### UX verification (per track)
17. [ ] All new copy renders in dark **and** light themes (no hardcoded
        `AppColors.*` / `AppColorsLight.*` in widgets — read `Theme.of(context)`).
18. [ ] Primary actions (type selector, Save) remain in the bottom 30%.

## Open-Question Defaults (resolved for this plan)
- **"Expected back by"** → defaults to **+30 days** (user-editable).
- **No separate "who owes me" field** — the receivable's name suffices.
- **Ledger "money I'm owed" filter/badge** → **deferred** to a follow-up plan.

## Risks & Edge Cases
- **Backward compatibility:** every new field nullable/defaulted; verify a
  pre-update JSON blob (no keys) loads clean (Phase A test).
- **Edit churn:** toggling reimbursable on/off must keep exactly one receivable
  in sync (no orphan, no duplicate) — model on the transfer-group cleanup path.
- **Partial / never reimbursed:** outflow stays counted in Expenses (correct);
  `receivedAmount` may differ; unrecovered remainder is a real expense.
- **"Paid for someone" but paid later (no cash yet):** NOT the instant transfer —
  helper copy + parser steer to the reimbursable path or a custodian/holding acct.
- **Card overpayment / negative liability:** unaffected (existing
  `currentPayable` flooring).

## Acceptance Criteria
- [ ] Models gain the three fields, round-trip, and legacy JSON loads with safe
      defaults (`reimbursable == false`, links null).
- [ ] Saving a reimbursable outflow spawns a linked `ReceivableType.reimbursement`
      (forward + back links set); settling it via `markReceivableReceived`
      writes the offsetting inflow and Income−Expense reconciles.
- [ ] Reimbursable outflow **counted** in `monthTotalOutflow`, **excluded** from
      `spentFor` / `sectionSpent` / `_budgetSpentFor` regardless of category.
- [ ] "Paid for someone" produces a CC → Cash transfer (one outflow leg on the
      card + one inflow leg on cash, shared `transferGroupId`); excluded from
      income/expense/budget; card owed ↑, cash ↑, `netWorth` unchanged.
- [ ] NLP routes "paid … for … paid me back" → transfer preparse; "paid … for …"
      (no payback) → reimbursable suggestion; ambiguous destination not auto-committed.
- [ ] New copy correct in both themes; logic in presenters, not `build()`.
- [ ] Tests added in the `treasury_dashboard_parity_test.dart` exclusion style.

---
*Present this plan for approval before writing any code.*
