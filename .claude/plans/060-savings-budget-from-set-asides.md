# Plan 060 — Savings budget rows derive from Bills set-asides

**Goal:** stop entering the same number twice. A goal's monthly target lives in
one place — the Bills set-aside — and the Budget page reads it.

**Decided with the user:** derive the savings row from the set-aside when one
exists; savings with no set-aside stay manually entered.

---

## 1. Why

The user's own framing, which is the right one:

> The set aside from bills is the amount I set aside each month for the goals.
> The budgets are set ceilings for each category, including savings **hmmm**

That hesitation is correct. For an expense category a budget is a **ceiling**.
For savings it is a **target**, and the set-aside is the mechanism that hits it —
the same number doing two jobs, typed in two screens.

They already interact, one way: settling a set-aside writes a transfer into the
destination account, `fundedInto` counts it, and that fills the savings row's
*progress*. Only the *target* is duplicated.

**The failure that motivates this:** set the budget row to ₱3,000 and the
set-aside to ₱2,000 and the row can never complete, with nothing on screen
saying why. Silent, permanent, and invisible — the worst shape a money bug takes.

The join key already exists and is unused: `BudgetedExpense.destinationAccountId`
is the savings/goal account, and a savings budget row keys on
`categoryId == ` that same account id. No new field.

---

## 2. Behaviour

For a savings/goal account in the selected month:

- **Recurring set-asides target it** → the row's allocation is the sum of the
  **recurring** ones only, read-only, with a "from Bills set-aside" affordance
  that deep-links to it.
- **One-off set-asides are funding, not target.** They flow into `actual` via
  `fundedInto` as they already do, and the row goes past 100%.

  This distinction is the whole design, and an earlier draft got it wrong by
  summing every set-aside. The user funds a goal twice in a month when spare
  money turns up: plan ₱3,000, add ₱2,000 more. Summing makes the target ₱5,000,
  so the row reads exactly 100% — **the target chases the actual**, the plan is
  erased, and a generous month looks identical to a bare-minimum one. Recurring
  is the plan; anything extra is over-performance and should read as 5,000/3,000.
- **No set-aside** → unchanged. Manual entry, exactly as today.

Progress (`actual`) is untouched — it already comes from `fundedInto`.

### Interaction with Plan 059

None, deliberately. The `Budget` record still exists and still carries forward,
so grouping, ordering and the savings section keep working unchanged; only the
*displayed allocation* is overridden at read time. Derivation is a read-time
concern, never a write — writing the derived value back would make a render
mutate storage and race the sync pull.

A consequence worth stating: the stale amount on a derived row's `Budget` record
is shadowed and never shown. Untidy, but strictly better than write-on-read.

---

## 3. Wiring (Rule 8 / Rule 9)

`BudgetPresenter` does not own set-asides and must not keep a private copy
refreshed only by its own `load()` — that is the staleness Rule 8 exists to
prevent. It mirrors them off a listener on `BillsReceivablesPresenter`, the way
`TreasuryDashboardPresenter._syncFromBills` already does.

In `TreasuryPresenters` (Rule 9 — the graph wires this, not the shells):
construct `bills` **before** `budget` and pass it in. Safe: `bills` has no
reference to `BudgetPresenter`, so there is no cycle to invert.

---

## 4. Files

- `lib/presenters/treasury_presenters.dart` — reorder, inject bills into budget
- `lib/presenters/budget_presenter.dart` — `_syncFromBills` mirror; derive the
  savings row's allocation
- `lib/views/treasury/budget/budget_card.dart` — "from Bills set-aside" state
- `lib/views/web/pages/budget/web_budget_page.dart` — same

**Tests**
- a goal with a recurring set-aside shows the set-aside's amount, not the row's
- two RECURRING set-asides on one goal sum into the target
- a one-off set-aside pushes actual past 100% and does NOT move the target
- a savings account with no set-aside is still manually editable
- changing the set-aside moves the budget row without a Budget write
- a non-recurring (one-off) set-aside does not drive the row
- the row is read-only when derived
- expense rows are entirely unaffected

---

## 5. Risks

| Risk | Mitigation |
|---|---|
| Budget goes stale when Bills changes | Listener mirror, never a private copy — the Rule 8 worked example |
| Deriving writes on render and races sync | Read-time only; nothing is persisted |
| Reordering the graph breaks construction | `bills` has no dependency on `budget`; existing tests cover the graph |
| A user wants a target higher than their automation | Explicitly out of scope — that ambiguity is the bug being fixed. Revisit if it bites |

---

## 6. Sequencing

Ships **after** Plan 059, as its own branch and PR
(`feat/savings-budget-from-set-asides`). 059 is complete and independently
valuable; bundling would make both harder to review and to revert.
