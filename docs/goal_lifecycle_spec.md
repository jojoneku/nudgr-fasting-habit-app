# Goal Lifecycle — Spec

> Extends the goal accounts described in [treasury_web_spec.md](treasury_web_spec.md) and the set-aside funding in [finance_audit_remediation_spec.md](finance_audit_remediation_spec.md).

## 🎯 Objective

Give a savings goal an explicit lifecycle, so reaching it and spending it are recorded facts rather than a number that quietly resets.

## 🐞 The problem

A goal is a `FinancialAccount` with `category: goal` and a `goalTarget`. Progress is derived live:

```dart
(account.balance / account.goalTarget!).clamp(0.0, 1.0)
```

Balance is a **current quantity**. Achievement is a **historical fact**. You cannot derive the second from the first, and today the app tries to. Consequences:

1. **Completing a goal erases it.** Save ₱6,000 for a phone over 3 months, buy the phone, and the balance returns to ₱0 — so the card renders `₱0.00 / ₱6,000.00 · 0%` with an empty bar. Identical to a goal never started.
2. **Funding restarts itself.** `BillsReceivablesPresenter._goalIsFunded()` tests `balance >= target` to decide whether to keep auto-generating the recurring set-aside. After the purchase drops the balance, it reads `false` again and the ₱2,000/month set-aside **resumes for a phone already bought**.
3. **Deleting is not an escape hatch.** `deleteAccount` throws `has_transactions` whenever anything is linked, and a funded goal always has its funding transfers plus the purchase. The only way to "clean up" is to destroy ledger history first.

## 🧠 Conceptual model

```
saving  ──(balance reaches target)──▶  funded  ──(user confirms spend)──▶  redeemed
   ▲                                                                          │
   └──────────────────────── restart with a new target ───────────────────────┘
```

Two stamps on the account, both write-once per cycle:

| Field | Set by | Meaning |
|---|---|---|
| `goalFundedAt` | automatically, when balance first reaches the target | "This goal was fully funded on this date." |
| `goalRedeemedAt` + `goalRedeemedAmount` | **only** explicit user action | "The money was spent on what it was for." |

**Redemption is never inferred.** The app cannot tell "bought the phone" from "raided the jar for an emergency"; those are a success and a setback, and guessing would mislabel one as the other. A funded goal offers a *Mark as spent* action; it never fires on its own.

**Funding is never un-stamped by a withdrawal.** Once funded, always funded — that is what makes the fact survive the balance going to zero. The one exception is a deliberate re-plan: raising `goalTarget` above the current balance on a goal that has not been redeemed clears `goalFundedAt`, because the user has redefined what "done" means.

### `GoalStage`

Derived, never stored — a getter on `FinancialAccount`, alongside the existing `isLiquid` / `isSavingsLike` derivations:

| Stage | Condition |
|---|---|
| `notAGoal` | not `category: goal`, or `goalTarget` null/≤ 0 |
| `saving` | `goalFundedAt == null` |
| `funded` | `goalFundedAt != null`, `goalRedeemedAt == null` |
| `redeemed` | `goalRedeemedAt != null` |

## 📱 UI

**Goals & Savings screen**

- **Active goals** — `saving` and `funded`. A funded card shows 100%, a ✅, and "Funded <date>", plus a **Mark as spent** action. When a funded goal's balance has fallen below its target, the card adds a quiet line ("Balance is now ₱0 — spent it?") next to that action. A hint, not a modal: no dismissal state to store and no false positive to apologise for.
- **Completed** — a separate section for `redeemed`, collapsed by default. Reads "Phone · funded ₱6,000 · spent Sep 13, 2026". No progress bar, because 0% would be a lie about a goal that succeeded.
- A redeemed goal offers **Start again**, which clears both stamps and takes a fresh target. Kept explicit rather than automatic: a phone in 2026 and a phone in 2029 are different goals, but an annual insurance fund genuinely is the same one.
- It also offers **Archive**, which sets `isActive: false`. That is the app's existing archived state ("Hidden everywhere until reactivated") and every account picker already filters on it, so finished goals stop cluttering transfer dropdowns without any new concept. Reversible from the accounts inventory; transactions are untouched.

**Progress never reads below 100% once funded**, at any surface, so a drawdown cannot look like regression.

## 🛠 Technical notes

- **Model** — `FinancialAccount` gains `goalFundedAt`, `goalRedeemedAt`, `goalRedeemedAmount`, all nullable and sentinel-guarded in `copyWith` so they can be cleared (the same `_kUnset` pattern the file already uses for `accountId`). `goalStage` and `goalProgress` are getters.
- **Stamping** — `LedgerPresenter._applyBalanceDelta` is the single choke point through which every balance change flows, so the funded check hangs off it. One pass over goal accounts, no extra persistence beyond the account save that already follows.
- **Redemption** — `LedgerPresenter.markGoalRedeemed(id)` / `restartGoal(id, newTarget)`. Presenter-owned, per the RPG-math rule.
- **Set-asides** — `_goalIsFunded()` switches from the live balance test to the account's stage (`funded` or `redeemed` both stop the recurrence). This is what fixes the resuming-set-aside bug.
- **Persistence** — the three fields ride the existing `accounts` blob; no migration, and older rows load with all three null (stage `saving`, which is correct for them).
- **XP** — funding a goal awards 50, sized against the other Treasury award (50 for clearing a month of bills). No `_awardedXpKeys` bookkeeping is needed: the stamp is write-once per cycle, so "newly stamped" already means "not paid for yet". A restarted goal can earn it again, which is correct — that is a second goal reached, not the same one re-counted.

## ⛔ Out of scope

- **`totalContributed`.** While a goal is still `saving`, progress is the live balance, so withdrawing ₱2,000 of ₱4,000 saved drops the bar from 66% to 33%. That figure is *accurate* — ₱2,000 of ₱6,000 really is where you stand — but it cannot distinguish "never saved much" from "saved a lot, then raided it". Fixing that means tracking cumulative inflows per goal, maintained on every transfer and rebuilt for existing accounts from ledger history. A real feature with its own migration, not a line of display logic, and nothing here is wrong without it.
