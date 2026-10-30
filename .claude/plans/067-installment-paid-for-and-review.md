# Plan 067 — Installment form: "Paying for someone" and a review step

**Status:** approved (2026-10-30). The user chose the recommended option for
all 4 decisions in section 6.

**Trigger.** The user buys items on installment for other people (for example
"Papa's Xiaomi Redmi Note 15"). Today the user must add one receivable per month
by hand. The user also wants to check the schedule before a plan saves. The
"Panasonic Refrigerator" plan shows why: its stored `startMonth` is 2026-12,
but its card ("Madness Limit", statement close 15th, due 4th) gives 2027-02
for a purchase on 2026-09-25 with 3 months deferred. 2026-12 is the purchase
month + 3, which is the result for a card with no billing cycle. So the plan
was probably saved before the card had a statement day. The edit form keeps
the stored month, so nothing showed the difference.

**Scope.** The manual installment form only: the mobile sheet
(`add_installment_sheet.dart`, also embedded in `new_entry_sheet.dart`) and the
web v2 dialog (`showWebInstallmentDialog` in `web_bills_forms_v2.dart`), in
add mode and edit mode. Chat / Nudgy writes are out of scope (section 8).

## 1. Data model

| Model | New field | Meaning |
|---|---|---|
| `Installment` | `String? paidForName` | The person the plan is for. Null = for yourself (toggle off). |
| `Receivable` | `String? installmentId` | Back-link to the plan that owns this receivable. |
| `Receivable` | `int? installmentNumber` | Which payment (1-based) of the plan this receivable is. |

- All 3 fields are optional in `fromJson`/`toJson`, so old rows load.
- Cloud sync stores each row in a `data` jsonb blob, so no DB migration.
- `copyWith` on `Installment` gets a sentinel for `paidForName`, so an edit can
  clear it (toggle off).

## 2. The receivables a plan makes

One receivable for each payment month of the plan:

| Field | Value |
|---|---|
| `id` | `instrcv_<planId>_<n>` — deterministic, like `Installment.chargeId`, so 2 devices write the same row |
| `name` | `"<person> — <plan name> (n/N)"`, for example `Papa — Xiaomi Redmi Note 15 (1/12)` |
| `receivableType` | `reimbursement` (the person pays you back) |
| `amount` | `plan.monthlyAmount` |
| `month` | `plan.monthForIndex(n-1)` — the same month the plan bills |
| `expectedDate` | the card's due date in that month (`InstallmentPresenter.dueDate`), else null |
| `categoryId` | `plan.categoryId ?? kInstallmentCategoryId` — the receipt nets out the charge, as a reimbursement does |
| `installmentId`, `installmentNumber` | the plan id, `n` |

A reimbursement receivable with no linked outflow does not change the ledger's
"owed to you" total (`isOutstandingReimbursable` reads only outflows), so the
Receivables tab is the only place these show. That is correct: they are
future months, not money owed today.

## 3. Who owns what (rule 8, rule 9)

- `InstallmentPresenter` owns plans. `BillsReceivablesPresenter` owns
  receivables. Bills already holds the installment presenter (it bills plan
  months onto statements).
- **Bills subscribes to the installment presenter.** It keeps a snapshot of
  each plan it saw last. On a notify, it compares each plan with the snapshot.
  For a new, changed or removed plan, it reconciles that plan's receivables
  (section 4). The first notify after both presenters load only records the
  snapshot, so a launch never rewrites receivables.
- This covers every write path (mobile, web, a plan pulled from another
  device) with one hook in the graph. The installment presenter does not call
  Bills, so there is no push from the owner.
- A pure function `planInstallmentReceivables(plan, linked, dueDateFor)` in
  `lib/utils/installment_receivables.dart` returns the diff:
  `toAdd`, `toUpdate`, `toRemove`, `keptReceived`. The reconcile step and the
  review step both use it, so the review shows exactly what the save does.

## 4. Sync rules (recommended — see decisions D1 and D2)

| Event | Open receivables | Received receivables |
|---|---|---|
| Plan saved with toggle on (add) | Create one per month | — |
| Edit: months, amount, start month, deferral, name, person | Payment `n` moves to the new month `n`, new amount, new name. Extra open ones (n > new total) are deleted. Missing ones are added. | Never changed |
| Edit: toggle turned off | Deleted | Kept, unlinked from the plan |
| Plan deleted | Deleted | Kept, unlinked from the plan |
| Plan cancelled (`isActive: false`; no UI does this today) | Deleted for months after the last billed month | Kept |

- "Received" means `isReceived == true`. A received receivable keeps its
  month, amount and ledger inflow. Sync never touches it, and the payment
  number it holds is not created again.
- A receivable deleted by hand comes back on the next edit of its plan. The
  review step shows it as "new", so the user sees it before saving.

## 5. The review step

Save on the form no longer saves. It validates, builds the draft plan, and
opens a review (a bottom sheet on mobile, a second dialog page on web). The
review lists:

1. First payment month and last payment month.
2. Monthly amount and total (monthly × months, interest included).
3. Deferral ("None" or "3 months").
4. For the first payment: the card's statement close date and due date
   (from the cycle whose due month is the start month). "No billing cycle on
   this card" when the card has none.
5. When the toggle is on: the person, and one row per receivable (month,
   amount, status: new / updated / kept (received) / removed). On edit with the
   toggle turned off: the open receivables that will be deleted.
6. **On edit only:** a warning when the stored start month is not the month
   the card cycle gives (`suggestedStartMonth`). Example: "Stored Dec 2026 ·
   the card's cycle gives Feb 2027". See decision D3.

Buttons: "Back" (returns to the form with all input kept) and "Confirm"
(saves). Nothing saves before Confirm. The review view model is built in the
presenters (`InstallmentPresenter.reviewPlan(...)` for items 1–4 and 6,
`BillsReceivablesPresenter.installmentReceivablePreview(...)` for item 5), so
`build()` only reads strings.

## 6. Decisions for the user

- **D1 — Edit sync.** Recommended: the rule in section 4 (open ones follow the
  plan, received ones never change).
- **D2 — Delete / toggle off.** Recommended: delete open, keep received.
- **D3 — Stored start month that does not match the card cycle.** Recommended:
  the review shows the warning and a "Use Feb 2027" button. The app never
  changes a stored start month by itself. Recompute on a card's cycle change
  is a separate follow-up.
- **D4 — Surfaces.** Recommended: mobile sheet and web v2 dialog both, since
  they share the presenter.

## 7. Steps

1. Models: `Installment.paidForName`, `Receivable.installmentId` and
   `installmentNumber` (+ JSON round-trip tests).
2. `lib/utils/installment_receivables.dart`: the pure diff function (+ tests:
   add, edit months up/down, amount change, start-month shift, received kept,
   toggle off, delete).
3. `BillsReceivablesPresenter`: subscribe to installments, snapshot, reconcile
   (mutate → notify → persist, one save per reconcile) + tests through the real
   presenters with a fake storage.
4. `InstallmentPresenter`: `buildInstallment(paidForName:)`, `knownPeople`
   (names from plans and from `owedBy` on ledger rows), `reviewPlan(...)` with
   the statement close/due dates and the start-month warning (+ tests,
   including the Panasonic case).
5. Mobile sheet: toggle + person field (chips of known names + text field),
   review sheet, Confirm saves. Pass the bills presenter from both call sites.
6. Web v2 dialog: the same.
7. Widget tests for the toggle and the review (add and edit).
8. `flutter analyze`, `dart format`, `flutter test`; PR to `dev`.

## 8. Out of scope (follow-ups)

- Nudgy / chat creating a plan "for Papa" (its tools would need `paidForName`).
- Recomputing stored start months when a card's statement day changes.
- Showing "for Papa" on the installment row and the receivable row's link to
  its plan.

## 9. Risks

- An older app build that rewrites a receivable or plan drops the new fields
  (Plan 062 write guard covers the outdated-client case only partly). The
  receivable then loses its link and is not synced any more; it does not
  break.
- Reconcile on a notify from `load()` after a cloud pull: the snapshot diff
  runs only for plans that changed, and ids are deterministic, so 2 devices
  converge.
