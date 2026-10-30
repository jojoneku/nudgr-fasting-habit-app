# Plan 068 — Installment start month: computed unless set by hand

**Status:** approved (2026-10-31). The user chose the recommended option for
all 4 decisions in section 7. Separate PR, stacked on #796 (Plan 067).

**Trigger.** The user said: "maybe there shouldnt be a start month at all it
should be pre computed? or unless overrode". The "Panasonic Refrigerator" plan
stores `startMonth` 2026-12. That is the purchase month (Sep) + 3, from the
no-cycle path of `calculateInstallmentStartMonth`. The card ("Madness Limit",
statement day 15, due day 4) got its cycle later, and nothing recomputed the
month. With the cycle, the month is 2027-02. BPI FlexipayLater posts the first
amortization up to 3 months after purchase (about Dec 25), so it lands on the
Jan 15 statement, due Feb 4. 2027-02 is correct.

**Root cause.** `calculateInstallmentStartMonth` runs only when a plan is made
(`installment_presenter.dart`, `ledger_presenter.dart`, and
`finance_actions_executor.dart`). Nothing recomputes the month when:

- an account's `statementDay`, `paymentDueDay` or `dueDaysAfterStatement` changes;
- a plan's account, purchase date or deferral changes outside the form.

## 1. Model

`startMonth` stays a stored field. About 30 readers use it: statement billing
(`installmentChargesDueAt`), holds, the receivables from #796, Nudgy and the
dashboard. If `startMonth` became a getter, every reader would have to call a
presenter. Instead, a new field says who owns the value:

| `startMonthSource` | Meaning | The app recomputes it? |
|---|---|---|
| `computed` | The month comes from the card's cycle, the purchase date and the deferral | Yes |
| `manual` | The user set the month by hand, or kept a different month | No |
| `review` | An existing plan whose stored month is not the computed month. The user has not decided yet. | No. The plan is listed for review. |

- When `fromJson` finds no source, it returns `null`. The migration (section 4)
  decides the source.
- `Installment.copyWith` gets the field. Every path that builds a new
  `Installment` keeps the field: the ledger purchase edit and the Nudgy
  executor.

## 2. Who recomputes (rule 8)

`InstallmentPresenter` owns the plans and already holds the ledger. It
recomputes in one function, `_normalized(plan)`. For a `computed` plan,
`_normalized` sets `startMonth = calculateInstallmentStartMonth(account,
purchaseDate, deferral)`. Two triggers run it:

1. **Every plan write.** `addInstallment` and `updateInstallment` run each plan
   through `_normalized`. So the form, the ledger's purchase edit
   (`onUpdateInstallment`) and Nudgy's `editInstallment` all get the same
   result, with no new code at the call sites.
2. **An account's cycle changes.** The presenter subscribes to the ledger. It
   keeps a signature of each account: `(statementDay, paymentDueDay,
   dueDaysAfterStatement)`. When a signature changes, it renormalizes the
   `computed` plans on that account and saves once. The first look after a
   load only records the signatures.

When a recompute moves `startMonth`, the bills presenter from #796 sees the
change and moves the plan's open receivables. No new code is needed for that.

**Guard (decision D3).** Recompute only while the plan has no billed or paid
month (`paidCount == 0`). After the first month bills, a moved start month
changes which months count as billed. So the app shows the difference and does
not change the month (section 5).

## 3. Accounts with no billing cycle (decision D4)

The no-cycle formula (purchase month + deferral) does not match what the user
has. The ShopeePay plans have September purchases and start months in Oct or
Nov. Recommendation: a plan on an account with no cycle is always `manual`.
The form still suggests a month, but no recompute happens on an account with
no cycle. Giving the account a cycle later turns on the review (section 4)
for its plans.

## 4. Existing plans (decision D2)

There is a one-time migration on the first load after both the ledger and the
plans load. It changes no month:

- The stored month equals the computed month on a card with a cycle → `computed`.
- The stored month is different, on a card with a cycle → `review`. The fridge
  plan is in this group.
- The account has no cycle → `manual`.
- At least 1 month is billed or paid → `manual` (D3), but the difference still
  shows (section 5).

**Review list.** The Installments tab shows a card when 1 or more plans are in
`review`: "1 plan's first payment month differs from its card's cycle". The
card opens a list. Each row shows the stored month and the computed month, with
2 actions:

- **"Use Feb 2027"** sets the month and changes the source to `computed`.
- **"Keep Dec 2026"** changes the source to `manual` and removes the row.

This is on mobile and on web v2.

## 5. Form, review step and Nudgy

- **Form (mobile + web v2).** The start-month stepper sets the source to
  `manual`. When a plan is `manual` and its month differs from the computed
  month, the form shows "Set by hand · computed: Feb 2027" and a "Use computed"
  action, which sets the source back to `computed`.
- **Review step (#796).** The warning text changes from "Stored Dec 2026 · the
  card's cycle gives Feb 2027" to "Set by hand: Dec 2026 · computed: Feb 2027".
  The warning shows for `manual` and `review` plans only. A `computed` plan
  never differs.
- **Nudgy.** The `find` line in `finance_finder.dart` gives the source and,
  when they differ, the computed month: `first payment month: 2026-12 (set by
  hand; card cycle gives 2027-02)`. In `editInstallment`, a request with an
  explicit first payment month sets the source to `manual`. A change to the
  date, the card or the deferral recomputes the month through `_normalized`.

## 6. Steps

1. Model: `startMonthSource` enum + JSON + `copyWith`; keep the field on the
   ledger and executor paths. Tests: round-trip, old rows load as null.
2. `InstallmentPresenter`: `_normalized`, the write-path hook, the account
   cycle subscription, the migration, the `paidCount == 0` guard,
   `startMonthReviewItems`, `useComputedStartMonth(id)` and
   `keepStartMonth(id)`. Tests, including the fridge case, the ShopeePay case
   (no cycle → manual, month unchanged), a cycle change that moves a
   computed plan and leaves a manual one, a plan with a billed month, and the
   #796 receivables that follow a recompute.
3. Form: stepper → manual, "Use computed", the new review-step text (mobile +
   web v2).
4. The review card and the review list (mobile + web v2), with widget tests.
5. Nudgy: the finder line and the `editInstallment` source rule. Tests.
6. `flutter analyze`, `dart format`, `flutter test`; PR to `dev`.

## 7. Decisions for the user

- **D1 — Branch.** Recommended: build on top of #796's branch and target
  `dev`. The PR says "merge #796 first", and its diff shrinks to this change
  once #796 merges. The other way is to wait until #796 merges, then branch
  from `dev`.
- **D2 — Existing plans.** Recommended: section 4 (matching → computed,
  different → review list, no cycle → manual). No month changes without your
  tap.
- **D3 — Plans with a billed or paid month.** Recommended: never recompute;
  show the difference only.
- **D4 — Accounts with no cycle.** Recommended: always manual (as typed). The
  other way is a per-account "first payment next month" rule, which is
  more scope.

## 8. Risks

- **Cross-device writes.** A recompute is a plan write. Both devices compute
  the same month from the same data, so the last write wins with the same
  value.
- **Older app builds.** An older build that rewrites a plan drops
  `startMonthSource`. The next load migrates it again. A plan the user kept as
  `manual` could then come back as `review` once. That costs 1 extra tap and
  no data is lost.
- **The user's data.** The migration sets only the source. It never changes a
  month. The fridge plan stays Dec 2026 until the user taps "Use Feb 2027" or
  edits it.
