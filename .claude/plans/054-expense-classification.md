# Plan 054 — Money-That-Isn't-Yours: Expense Classification

*Source spec: [docs/expense_classification_spec.md](../../docs/expense_classification_spec.md)*

## Goal
Make the ledger tell the truth about three look-alike situations — money spent
for good, money you'll get back, and money that was never yours — so headline
**Expenses**, per-category **budgets**, and **net worth** each stay correct, and
so a user who has never heard of the "transfer leg" trick can still log them
right. Two independent features share one model layer:

- **Reimbursement track (Phases A→B→C):** new behaviour — a `reimbursable` flag
  that counts in total Expenses but is excluded from category budgets and spawns
  a linked `ReceivableType.reimbursement`.
- **Paying-for-someone track (Phases D→E):** *no new accounting* — a Credit Card
  → Cash transfer (already excluded everywhere via `transferGroupId`); only needs
  to be made discoverable via an intent chip, an inline hint, and NLP.

Both tracks are independent once Phase A lands.

## Affected Files
| File | Action | Layer | Phase |
|---|---|---|---|
| `lib/models/finance/transaction_record.dart` | Modify | Model | A |
| `lib/models/finance/receivable.dart` | Modify | Model | A |
| `test/finance_models_roundtrip_test.dart` | Modify | Test | A |
| `lib/presenters/budget_presenter.dart` | Modify | Presenter | B |
| `lib/presenters/treasury_dashboard_presenter.dart` | Modify | Presenter | B,C |
| `test/presenters/treasury_dashboard_parity_test.dart` | Modify | Test | B,C |
| `test/presenters/treasury_presenters_test.dart` | Modify | Test | B |
| `lib/presenters/ledger_presenter.dart` | Modify | Presenter | C,D |
| `lib/presenters/bills_receivables_presenter.dart` | Modify | Presenter | C |
| `lib/views/treasury/ledger/add_transaction_sheet.dart` | Modify | View | C,D |
| `lib/utils/finance_nlp_parser.dart` | Modify | Util | E |
| `test/utils/finance_nlp_parser_test.dart` | Modify | Test | E |

No new `StorageService` keys — new fields ride inside the existing
`transactions` / `receivables` JSON blobs (backward-compatible, all nullable).

## Interface Definitions
```dart
// ── Phase A: Models (additive, nullable/defaulted) ──────────────────────────
// transaction_record.dart
final bool reimbursable;                 // default false; outflow-only
final String? reimbursementReceivableId; // forward link to spawned receivable
//   fromJson: json['reimbursable'] as bool? ?? false
//             json['reimbursementReceivableId'] as String?
//   toJson:   emit both keys
//   copyWith: reimbursable ?? this.reimbursable; nullable-copy for the id

// receivable.dart
final String? reimbursementForTxnId;     // back-link to originating outflow
//   uses the file's existing null-tolerant fromJson/_kUnset copyWith idiom

// ── Phase B: Budget gating ──────────────────────────────────────────────────
// Add `&& !t.reimbursable` next to the existing `t.transferGroupId == null`:
//   budget_presenter.dart        spentFor()      ~line 339
//   budget_presenter.dart        sectionSpent()  ~line 269
//   treasury_dashboard_presenter dart _budgetSpentFor() ~line 498
// monthTotalOutflow (dashboard ~line 239) UNCHANGED — reimbursables still count.

// ── Phase C: Spawn / settle / derived metric ────────────────────────────────
// ledger_presenter.dart (or bills_receivables_presenter) — in the save path:
Future<TransactionRecord> addReimbursableExpense(
  TransactionRecord outflow, {required DateTime expectedReimbursementDate});
// Settlement reuses existing markReceivableReceived() (writes offsetting inflow).
double get pendingReimbursableOutflow;            // open reimbursables, this month
double get monthOutflowNetOfReimbursements;       // monthTotalOutflow - above

// ── Phase D: Paid-for-someone intent (logic in presenter, NOT build()) ───────
Future<void> addPaidForSomeoneTransfer({
  required String creditAccountId, required String cashAccountId,
  required double amount, required String description,
  required DateTime date, String? note,
}); // delegates verbatim to existing addTransfer()

// ── Phase E: NLP ────────────────────────────────────────────────────────────
// finance_nlp_parser.dart — new recognizer mirroring the paid|pay|settle
// pay-down-card pattern (~lines 60–215):
//   "...for <name> ... paid me back"  -> transfer preparse (card -> cash)
//   "...for <name>" (no payback)       -> reimbursable-expense suggestion
```

## Implementation Order

### Phase A — Models (foundation; unblocks both tracks)
1. [ ] Add `reimbursable` (default false) + `reimbursementReceivableId` to
       `TransactionRecord`; update `fromJson`/`toJson`/`copyWith`.
2. [ ] Add `reimbursementForTxnId` to `Receivable`; update the three methods
       using the existing `_kUnset` nullable-copy idiom.
3. [ ] Round-trip tests in `test/finance_models_roundtrip_test.dart`, including
       **old JSON (missing keys) → `reimbursable == false`, links `null`**.

### Phase B — Budget gating (reimbursement track)
4. [ ] Add `&& !t.reimbursable` to `spentFor` (339), `sectionSpent` (269),
       `_budgetSpentFor` (498). Leave `monthTotalOutflow` counting them.
5. [ ] Parity test: a reimbursable outflow **is** in `monthTotalOutflow` but
       **absent** from `spentFor`/`sectionSpent`/`_budgetSpentFor` regardless of
       category. Mirror the transfer-exclusion test shape.

### Phase C — Reimbursable UI + receivable lifecycle
6. [ ] Presenter: `addReimbursableExpense` spawns a `ReceivableType.reimbursement`
       (amount/category from the outflow, `expectedDate = date + 30d`,
       `reimbursementForTxnId = outflow.id`) and stamps
       `reimbursementReceivableId` back. Edit path: create/detach the receivable
       when the flag toggles (mirror transfer-group cleanup at
       `add_transaction_sheet.dart` ~160–193).
7. [ ] `add_transaction_sheet.dart`: when type == Outflow show a **Reimbursable**
       switch; ON reveals an optional **"Expected back by"** date (default +30d).
       Category picker stays normal (flag, not category, gates budget). Helper
       copy theme-aware.
8. [ ] Dashboard: `pendingReimbursableOutflow` + `monthOutflowNetOfReimbursements`;
       Expense-tile sub-line "of which ₱X pending reimbursement" when > 0.
9. [ ] Lifecycle test: paid → counts in outflow, excluded from budget →
       `markReceivableReceived` → inflow offsets → net Income−Expense reconciles.

### Phase D — "Paid for someone" intent (paying-for-someone track)
10. [ ] Presenter `addPaidForSomeoneTransfer` delegating to `addTransfer`.
11. [ ] `add_transaction_sheet.dart`: add intent entry "Paid for someone"
        (alongside Inflow/Outflow/Transfer ~line 374) that pre-configures
        From = card, To = Cash, with plain-language helper copy. Verify the
        account dropdowns already include liability accounts (confirmed: they do).
12. [ ] Inline info chip on the transfer screen: "Paid on your card for someone
        and got cash back? Pick Credit Card → Cash." Theme-aware.
13. [ ] Test: the intent produces exactly one outflow leg on the card + one
        inflow leg on cash sharing a `transferGroupId`; net worth ±0.

### Phase E — NLP recognizers
14. [ ] Extend `finance_nlp_parser.dart` with the two patterns; route to transfer
        preparse (card→cash) vs reimbursable suggestion. Never auto-commit when
        the destination account is ambiguous (existing guard rail).
15. [ ] Parser tests in `test/utils/finance_nlp_parser_test.dart`.

### UX verification (both tracks)
16. [ ] Manual pass in **dark and light** themes — all new copy/chips read from
        `Theme.of(context)`, no `AppColors.*`/`AppColorsLight.*` in widgets.

## RPG Impact
None. These are corrective/classification flows; awarding XP for logging "money
that isn't yours" would gamify noise. Existing ledger-logging XP is unchanged.

## Risks & Edge Cases
- **Partial / never-arriving reimbursement:** outflow stays counted in Expenses
  (correct — you bore it); receivable shows still-owed. `receivedAmount` already
  supports a differing settle amount.
- **Toggling reimbursable on edit:** must create *or* detach the spawned
  receivable consistently — reuse the existing transfer-group cleanup pattern;
  test both directions.
- **"Paid for someone" but no cash yet:** NOT the instant transfer — helper copy
  steers to reimbursable-on-card or a custodian/holding account.
- **Backward compatibility:** every new field nullable/defaulted; old rows and
  cross-version sync deserialize unchanged (verified by Phase A test).
- **Single source of truth for the budget guard:** three call sites must all get
  `!t.reimbursable`; a missed site silently understates/overstates one surface —
  the parity test must assert all three.

## Acceptance Criteria
- [ ] New model fields round-trip; old JSON loads with safe defaults.
- [ ] Reimbursable outflow counts in `monthTotalOutflow`, excluded from all three
      budget tallies regardless of category.
- [ ] Saving reimbursable spawns a linked receivable; settling it offsets via an
      inflow tagged `receivableId`; net reconciles.
- [ ] CC→Cash "paid for someone" transfer excluded from income/expense/budget,
      moves card + cash balances, leaves net worth unchanged.
- [ ] Intent chip produces exactly that transfer; inline hint renders in both
      themes.
- [ ] NLP routes "...paid me back" → transfer, "...for <name>" → reimbursable.
- [ ] No hardcoded theme tokens in any new widget.
- [ ] Tests added to `treasury_dashboard_parity_test.dart`,
      `finance_models_roundtrip_test.dart`, `treasury_presenters_test.dart`,
      `finance_nlp_parser_test.dart`.

## Deferred (follow-up)
- Free-text "who owes me" field on reimbursable (receivable name suffices for v1).
- Top-level ledger filter/badge aggregating open "money I'm owed".

---
*Present this plan for approval before writing any code.*
