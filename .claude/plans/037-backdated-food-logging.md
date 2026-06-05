# Plan 037 — Backdated Food Logging (with Full Retroactive RPG Credit)

## Goal
Let the user log/edit/delete food on **past days** (e.g. a forgotten day), not just today.
The data layer already persists to the selected day; the work is (a) unlocking the UI off-today,
(b) making commit-time side effects date-aware, and (c) the hard part — granting **full retroactive
RPG credit** (streak repair + XP) for backfilled days **without double-awarding or corrupting
the current level/HP**.

Why it matters to the loop: the log streak and calorie/protein-goal XP are core to The System's
daily pull. If backfilling silently skipped them, the RPG loop would feel broken ("I logged that
day, why no credit?"). The user explicitly chose full retroactive credit.

## Key architectural findings (why this is non-trivial)
The RPG state is **forward-only / snapshot**, not a per-day ledger:
- `_logStreak` (int) + `_logStreakDate` (last date) — consecutive-day counter, resets if the last
  logged date wasn't yesterday. No stored set of "which days were logged."
- `_goalMetDate` (single last date) + `_goalStreak` — same shape.
- `StatsPresenter.addXp(int)` **only adds** (level-up does a full HP heal); there is **no `removeXp`**
  and no concept of de-leveling.
- `_history: List<DailyNutritionLog>` **does** give us the full set of logged days, so a streak
  *recompute* is feasible — but XP idempotency is not, because nothing records "day X already
  earned its goal XP."

Consequences:
1. Streak can be **recomputed** deterministically from `_history` + today (bridging gaps a backfill repairs).
2. Retroactive **XP** needs a new **per-day credit ledger** to stay idempotent (backfill → edit → re-backfill
   must not pay twice).
3. **Revocation** (edit/delete drops a previously-credited day below goal) is effectively impossible to do
   safely given one-directional XP. **Recommendation: credit is sticky — never revoked.** (Confirm.)

## Affected Files
| File | Action | Layer |
|---|---|---|
| `lib/services/storage_service.dart` (+ `local_storage_service.dart`) | Modify | Service |
| `lib/presenters/nutrition_presenter.dart` | Modify | Presenter |
| `lib/presenters/stats_presenter.dart` | Read/verify (no new removal API) | Presenter |
| `lib/views/nutrition/nutrition_screen.dart` | Modify | View |

No model changes expected (`DailyNutritionLog` already carries its own `date`).

## Interface Definitions
```dart
// ── StorageService — new per-day credit ledger (idempotency for retro XP) ──
// A set of date keys (yyyy-MM-dd) that have already been awarded each credit type.
Future<Set<String>> loadCalorieGoalCreditedDates();
Future<void> saveCalorieGoalCreditedDates(Set<String> dates);
Future<Set<String>> loadProteinGoalCreditedDates();
Future<void> saveProteinGoalCreditedDates(Set<String> dates);
// Log-streak milestones are recomputed, not per-day; milestone XP guarded by a
// "highest streak milestone already paid" int:
Future<int> loadStreakMilestonePaid();           // 0,7,14,30
Future<void> saveStreakMilestonePaid(int milestone);

// ── NutritionPresenter ──
bool get isViewingToday;                          // already exists (~line 500)
String get _selectedKey => _dateFmt.format(_selectedDate);  // helper

// Commit side effects become date-aware:
Future<void> _applyLogSideEffects(String dateKey);  // replaces today-only block
Future<void> _recomputeLogStreak();                 // from _history + today
Future<void> _awardGoalXpIfUncredited(String dateKey);
```

## Implementation Order
1. [ ] **StorageService** — add the credit-ledger keys + methods above (and SharedPreferences impl).
       User-scoped via existing `_k()`. Add to `_reloadAll()`.
2. [ ] **Presenter — make commit date-aware:**
   - `_commitFoodChat` / quick-add / manual-add (lines ~522, 535, 569, 806, 1840): pass `_selectedKey`.
   - IF-Sync gate (line 1847): `if (isViewingToday && _goals.ifSyncEnabled && !isEatingWindowOpen) return;`
     (gate only applies to *today* — fasting is a now-only concept).
   - `_ensureTodayLogFresh` already bails on past days — keep.
3. [ ] **Presenter — retroactive credit:**
   - `_recomputeLogStreak()`: build the set of logged date keys from `_history` (+ in-memory `_todayLog`
     if today), compute the consecutive run ending at the latest logged day; persist `_logStreak`/`_logStreakDate`.
     Replaces the increment-or-reset logic in `_updateLogStreak`.
   - Streak-milestone XP: pay only the *newly crossed* milestones above `streakMilestonePaid` (guards
     against re-paying when a recompute revisits 7/14/30).
   - `_awardGoalXpIfUncredited(dateKey)`: if that day meets calorie goal AND `dateKey ∉ creditedDates`,
     `addXp(30)` (+IF-sync bonus only if that day was actually fasting-gated — likely drop the bonus for
     backfills), add to ledger, persist. Same for protein (+15).
   - **Goal-met toast / notifications:** suppress for non-today (`isViewingToday` guard) — never fire a
     "goal reached!" toast or push for a backfilled past day.
4. [ ] **View (`nutrition_screen.dart`):**
   - Line 2011: `enabled: isViewingToday ? !locked : true` (past days: input enabled, fasting-lock ignored).
   - Hints (2014-2018): past-day hint → `'Log food for <date>…'`; keep fasting/today hints for today.
   - Verify edit/delete on past entries (chat list swipe/long-press) already routes through the
     date-aware save (they bypass the IF-Sync gate per existing comment ~2196) — fix if they assume today.
5. [ ] **UX verification** — see Acceptance Criteria.

## RPG Impact
- Backfilling a gap day can **repair/extend the log streak** (recompute bridges the gap) and pay any
  newly-crossed milestone XP (7/14/30) exactly once.
- Past-day calorie/protein goal met → one-time XP via the credit ledger.
- **No toasts, dialogs, or push notifications** for past days (silent credit).
- **No XP revocation** on edit/delete (sticky credit) — recommended; flagged for confirmation.

## Risks & Edge Cases
- **Double-award (highest risk):** mitigated by the per-day credit ledger + milestone-paid guard.
- **Level/HP corruption:** `addXp` full-heals on level-up; a backfill that triggers a level-up will
  full-heal HP. Acceptable, but note it. No de-level path exists, so revocation is out of scope.
- **Streak semantics:** define "streak" as consecutive days with ≥1 entry ending at the most recent
  logged day. Decide: does a backfill that makes *today-3..today* contiguous but today is unlogged still
  count? (Recommend streak = run ending at max(today-if-logged, latest logged day).)
- **Existing live counters:** first run with no ledger — seed ledgers from current `_goalMetDate` so we
  don't re-pay already-credited recent days.
- **Editing a past day below goal after credit:** credit stays (sticky). Document in UI? (minor.)
- **Future days:** already blocked by day-chip picker (line ~272) — keep blocked.
- **Sync (Plan 015):** confirm backdated saves enqueue correctly under the right date key.

## Acceptance Criteria
- [ ] On a past day, the composer is enabled and logs persist to that day (survives app restart).
- [ ] Backfilling a forgotten day between two logged days increases `logStreak` via recompute.
- [ ] Past-day goal completion awards XP exactly once; re-opening/editing the day does not re-award.
- [ ] No "goal met" toast or push notification fires for a past day.
- [ ] Logging on a past day while *currently* fasting (ifSync on) is NOT dropped.
- [ ] Editing/deleting a past day's entries updates that day's totals and recomputes streak.
- [ ] Today's logging behavior (gates, toasts, XP) is unchanged.
- [ ] `flutter analyze` + `dart format` clean; existing nutrition tests pass; new tests for recompute + ledger idempotency.

---
## Decisions (confirmed)
1. **Sticky credit** — XP is never revoked when a later edit/delete drops a day below goal. (No `removeXp`/de-level work.)
2. **Drop the IF-sync +10 bonus for backfills** — past days get base goal XP only (+30 cal / +15 protein).
3. **Streak = longest consecutive run ending at the latest logged day** — backfilling past gaps repairs the
   streak even before today is logged. `_recomputeLogStreak()` computes the run ending at `max(logged dates)`.
