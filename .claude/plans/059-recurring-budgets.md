# Plan 059 — Recurring Budgets

**Goal:** a budget line set once keeps applying every month, until you change it.

**Decided with the user:**
- Editing an amount applies to **this month and all future** — the edit becomes
  the new going rate.
- Deleting a row **ends the series** — it does not come back next month.

---

## 1. What exists

`Budget` is already per-month: one row per category per month, keyed by
`month: 'YYYY-MM'` ([budget.dart:12](../../lib/models/finance/budget.dart)).
There is **no carry-forward anywhere** — open a new month and the Budget page is
empty, so every month is retyped from scratch. That is the whole complaint.

So "recurring" here is not a repeat schedule. It is: **materialise last month's
rows into this one**.

Bills already solved this exact shape — `seriesId` links a row across months,
and edits/deletes take an `applyToFuture` scope
([bills_receivables_presenter.dart:1915](../../lib/presenters/bills_receivables_presenter.dart)).
Budgets should mirror it rather than invent a second recurrence idea in the same
app.

---

## 2. Model

Two fields on `Budget`, both defaulted so existing stored rows load with no
migration (the same trick `group` already relies on):

```dart
final String? seriesId;      // links this line across months
final bool isRecurring;      // default true
```

`seriesId` is minted when a row is first created and copied forward unchanged.
A row with `seriesId == null` is a one-off and never carries.

---

## 3. Materialisation — lazy, persisted, forward-only

When a month is selected and has **no** rows of its own, carry forward from the
most recent **earlier** month that has rows: copy each row where `isRecurring`,
with a fresh `id`, the same `seriesId`, and the new `month`. Persist.

Three rules that matter more than they look:

- **Forward only.** Never backfill a month earlier than the earliest data. A
  past month with no budget had no budget; inventing one rewrites history.
- **Only when the month is empty.** Idempotent — a month that already has rows
  is authoritative and is never re-derived. This *is* "unless modified".
- **Not during load or a sync pull.** Materialising mid-pull would race the
  incoming rows and could double-write a month. Gate on load complete + no pull
  in flight.

### Why lazy rather than at month rollover

Eager materialisation needs a scheduler, writes rows for months the user may
never open, and multiplies what sync carries. Lazy-on-view costs one write the
first time a month is actually looked at. `availableMonths` derives from stored
rows, so an unvisited future month simply doesn't appear yet — which is what
happens today.

---

## 4. Edit → this month and all future

`setBudget` updates the selected month's row, then applies the same amount to
every **later** materialised row sharing its `seriesId`.

Months not yet materialised need no special handling: they will be created from
the most recent earlier month, which now holds the new amount. Both paths agree,
which is the property to hold on to — the "already materialised" and "not yet"
cases must never disagree about what October's Groceries is.

Earlier months are never touched. Editing September must not rewrite August.

---

## 5. Delete → ends the series

`removeBudget` on a recurring row:

1. removes the selected month's row,
2. removes later materialised rows of that series,
3. sets `isRecurring = false` on the remaining (earlier) rows of that series.

Step 3 is what stops it coming back: materialisation reads `isRecurring` from
the carry-forward source, so an ended series is no longer offered. **No
"deliberately emptied" marker is needed** — the ended flag already encodes it.
That is the load-bearing consequence of the user's delete choice, and it is why
delete-ends-series is simpler to implement than delete-this-month-only.

---

## 6. Reuse, don't fork

`_seriesReach<T>` ([bills_receivables_presenter.dart:2011](../../lib/presenters/bills_receivables_presenter.dart))
is already generic over the item type, but private to that presenter. Extract it
to `lib/utils/recurring_series.dart` as a pure function and call it from both
presenters. Two copies of "how far does this series reach" is exactly the pair
that drifts.

---

## 7. UI

- **Recurring is the default and mostly invisible.** No toggle in the common
  path — that is the point of the request.
- **A one-off escape hatch:** a "Just this month" switch in the row's edit
  sheet, which clears `seriesId`.
- **Say when a month was carried over.** A quiet line on the Budget page —
  "Carried over from August" — the first time a month is auto-populated. A month
  that silently has numbers in it is worse than one that explains itself, and
  this is the only moment the user learns the feature exists.
- Both surfaces: `budget_card.dart` (mobile) and `web_budget_page.dart` (web).

---

## 8. Sync

Budgets already sync as `finance_budgets`
([sync_service.dart:635](../../lib/services/sync_service.dart)). The new fields
ride along in `toJson`; `fromJson` defaults them, so a row written by an older
client loads as a non-recurring one-off rather than failing. No migration, no
new table.

---

## 9. Files

**New**
- `lib/utils/recurring_series.dart` — extracted `seriesReach`, pure

**Modified**
- `lib/models/finance/budget.dart` — `seriesId`, `isRecurring`
- `lib/presenters/bills_receivables_presenter.dart` — use the extracted util
- ⛔ `lib/presenters/budget_presenter.dart` — materialise / edit-forward / delete-ends
- ⛔ `lib/views/treasury/budget/budget_card.dart` — carried-over line, one-off switch
- ⛔ `lib/views/web/pages/budget/web_budget_page.dart` — same

⛔ = currently carrying the uncommitted AccountBadge rollout. Blocked until the
other session commits.

**Tests**
- carry-forward populates an empty month from the most recent earlier month
- a month with its own rows is never re-derived
- past months are never backfilled
- edit applies to this month and later, never earlier
- edit agrees whether the later month was already materialised or not
- delete removes later rows and ends the series
- an ended series never re-materialises
- a one-off (`seriesId == null`) never carries
- `seriesReach` behaves identically for bills after extraction (no regression)

---

## 10. Phases

| # | Work | Blocked? |
|---|---|---|
| 1 | `Budget` model fields + round-trip tests | no |
| 2 | Extract `seriesReach` to utils; bills use it; bills tests stay green | no |
| 3 | Presenter: materialise, edit-forward, delete-ends + tests | ⛔ WIP |
| 4 | Mobile + web UI: carried-over line, one-off switch | ⛔ WIP |
| 5 | `dart format`, full suite, PR to `dev` | — |

Branch: `feat/recurring-budgets`, based on `dev`. Its own PR — separate from
[#579](https://github.com/jojoneku/nudgr-fasting-habit-app/pull/579).

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| Materialising races a sync pull and double-writes a month | Gate on load-complete + no pull in flight; only ever write when the month is empty |
| Carry-forward fires for a month the user deliberately emptied | Can't happen — delete ends the series, so there is nothing left to carry |
| Editing a month rewrites history backwards | Forward-only by construction; test asserts the earlier month is untouched |
| Bills regress when `seriesReach` moves | Pure extraction, no behaviour change; existing bills tests are the guard |
| A month silently fills with numbers | The "Carried over from August" line |
