# Plan 048 — Stability Hardening (June 2026 Audit Fixes)

> Status: PLANNED — NOT IMPLEMENTED

**Author:** System Architect
**Date:** 2026-06-10
**Spec:** None — this is a fixes plan; each item references existing rules/specs.
**House rule:** One PR per item. Never bundle. Items are ordered by risk (silent data/UX failure first).

---

## Audit verification summary (re-checked against `dev`, 2026-06-10)

| # | Audit finding | Verified status |
|---|---|---|
| 1 | Notify-after-persist violations in 7 presenters | **Mostly already resolved** — all 5 finance hits fixed by Plan 041 / PR #202. Real stragglers: `ActivityPresenter`, `NutritionPresenter` learned-foods |
| 2 | Goal-reached notification silently dropped after downtime | **Confirmed** — `notification_service.dart:1126` skips past-due one-shots; `fasting_presenter.dart:44` reschedules to original end time |
| 3 | Fragile JSON loading, no schema version | **Confirmed** — 23 bare `DateTime.parse` across `lib/models/`, no `schemaVersion` anywhere |
| 4 | `sync_service.dart` bypasses `StorageService` | **Confirmed** — direct `SharedPreferences` at lines 784–792 (initial-push flag) |
| 5 | Zero tests for XP math / streak freeze / transfer / sync / DST | **Mostly already resolved** — XP/leveling, penalty+freeze, and transfer math all have tests. Real gaps: sync conflict LWW, DST-crossing timer |

---

## PR 1 — Fire missed fasting alerts immediately after downtime (highest risk: core-loop silent failure)

**Verified behavior:** `_scheduleOneShotNotification` (`notification_service.dart:1112`) drops any notification scheduled >5 min in the past. `_getRelativeScheduledTime` (`:232`) maps past targets to past tz times. `FastingPresenter._rescheduleActiveAlarms` (`fasting_presenter.dart:44`) re-arms to the *original* `startTime + goalHours`. Net effect: if the app/device was dead past goal time, the "You did it!" alert (id 0) never fires — the user fasts blind into overtime. (The eating-window path already guards expiry at `fasting_presenter.dart:63`; the fasting path does not.)

**Fix:**
- In `scheduleFastingAlarm` (and milestone loop), split past vs future: if the target time has already passed, call `show()` immediately instead of `zonedSchedule()`; only schedule future milestones.
- Idempotency guard so re-init doesn't re-fire: persist `lastGoalAlertFiredFor` (the fast's `startTime` ISO) via a new `StorageService` key; skip the immediate fire when it matches the active fast.
- Keep the 5-minute drop rule for *milestone* notifications (firing "Fat Burning Starts" 9 hours late is spam); the **goal-reached** alert is the one that must always land.

**Tests:** presenter test — fast started 20h ago with an 18h goal → init fires goal alert exactly once; second init fires nothing.

## PR 2 — Defensive JSON parsing + storage schema version (risk: data-wipe on one bad field)

**Verified:** 23 bare `DateTime.parse()` vs 12 `tryParse` in `lib/models/` (e.g. `quest.dart:218` `lastXpAwarded`, `quest_achievement.dart:38` `unlockedAt`, `fasting_log.dart`). One malformed string (cloud-pulled blob, manual import, interrupted write) throws inside `fromJson`, which typically nukes the *entire list* load — a presenter then sees `[]` and may persist it back over good data.

**Fix:**
- `lib/utils/json_safety.dart` (pure functions, Utils layer): `DateTime? tryParseDate(dynamic v)` and `DateTime parseDateOr(dynamic v, DateTime fallback)` — both `debugPrint` the offending key/value on failure.
- Sweep all 23 call sites: nullable fields → `tryParseDate`; required fields → `parseDateOr` with a sane fallback (epoch or `DateTime.now()` per field semantics, decided per model).
- Schema version: `static const int kSchemaVersion = 1` + persisted `storage_schema_version` key in `LocalStorageService`; on init, a `_migrate(from, to)` hook (no-op today) runs before any load. This is the seam every future model migration plugs into.

**Tests:** round-trip tests feeding malformed dates into `Quest.fromJson` / `FastingLog.fromJson` — list load survives, bad entry degrades instead of throwing.

## PR 3 — Remaining notify-after-persist stragglers (risk: visible lag; rule from Plan 041)

Audit flagged 7 presenters. Verified one by one:

| Flagged | Verdict |
|---|---|
| `bills_receivables_presenter.dart` `addBill` (~151) | **ALREADY RESOLVED** — optimistic since PR #202 |
| `budget_presenter.dart` `setBudget`/`removeBudget` (~285/295) | **ALREADY RESOLVED** (has the "Optimistic: repaint before persisting" comment) |
| `installment_presenter.dart` `addInstallment` (~92) | **ALREADY RESOLVED** |
| `ledger_presenter.dart` `addTransfer` (~290) | **ALREADY RESOLVED** |
| `treasury_dashboard_presenter.dart` `addAccount` (~381) | **ALREADY RESOLVED** |
| `activity_presenter.dart` `setManualSteps` (:199–208) + `updateGoals` (:210–214) | **CONFIRMED** — persists before `safeNotify()` |
| `nutrition_presenter.dart` `clearLearnedFoods` (:474), `removeLearnedFood` (:479), `updateLearnedFood` | **CONFIRMED** — awaits `_personalDict` write before `safeNotify()` |

**Fix:** reorder to *mutate → notify → persist* per `.claude/plans/041-optimistic-ui-rollout.md` guidance (keep XP awards and dependent reloads after the await). For the personal-dict methods, mutate the in-memory dictionary first, notify, then persist. This PR also closes the Activity/Nutrition rows of Plan 041's backlog — tick them there; Quest/Fasting rows remain 041's own follow-up.

## PR 4 — Route sync initial-push flag through `StorageService` (risk: low; architecture rule 2)

**Verified:** `sync_service.dart:784–792` (`_isInitialPushDone`/`_markInitialPushDone`) hit `SharedPreferences.getInstance()` directly, bypassing the abstract interface — invisible to mocks, export/import, and the sign-out wipe logic.

**Fix:** add `Future<bool> loadInitialPushDone(String userId)` / `Future<void> saveInitialPushDone(String userId)` to `StorageService` (+ impl with the same `sync_initial_push_done_v2_$userId` key — **no key rename**, existing devices must not re-push). Update the two call sites; regenerate `mocks.mocks.dart`.

**Tests:** existing `sync_service_test.dart` `pushAll` group keeps passing against the mocked storage instead of raw prefs.

## PR 5 — Close the *actual* test gaps (risk: regression safety)

Audit claimed zero coverage on five areas; the tree disagrees:

- XP/leveling math — **ALREADY RESOLVED**: `test/presenters/stats_presenter_test.dart` (level-up thresholds, multi-level, STR bonus, stat points).
- Streak penalty + freeze — **ALREADY RESOLVED**: `test/presenters/quest_presenter_test.dart` (`checkMissedQuestsAndApplyPenalty`, freeze-spend-no-damage, `spendStreakFreeze`).
- Finance transfer math — **ALREADY RESOLVED**: `test/presenters/treasury_presenters_test.dart:290` (two legs, shared `transferGroupId`).

**Genuine gaps to write (this PR):**
1. **Sync conflict last-write-wins** — `sync_service_test.dart` covers queue/push mechanics only; add pull-side tests: remote `updated_at` newer ⇒ remote wins; local dirty + older remote ⇒ local preserved.
2. **DST-crossing fasting timer** — no timezone test exists. Use `timezone` + `fake_async`: an 18h fast spanning a DST shift must compute elapsed/goal from absolute instants (and the scheduled alarm must not drift ±1h).

Follow `test/` Given-When-Then conventions and the shared `mocks.mocks.dart` mocks (regenerate via `build_runner` if PR 4 landed first).

---

## Sequencing & verification

1. PR 1 (notifications) → 2. PR 2 (JSON safety) → 3. PR 3 (optimistic reorder) → 4. PR 4 (sync prefs) → 5. PR 5 (test gap-fill). PRs 1–4 each ship with their own regression tests; PR 5 covers cross-cutting gaps only.
- All PRs target `dev`, Conventional Commits, `dart format` + `flutter analyze` + `flutter test` green before push.

## Acceptance Criteria

- [ ] Device dead past goal time → goal-reached alert fires once on next launch, never duplicated
- [ ] A corrupted date string in any persisted list degrades that entry, never the whole load
- [ ] `storage_schema_version` written on first run after update; migration hook in place
- [ ] Manual-steps and learned-food edits repaint before the storage await
- [ ] `grep -n "SharedPreferences" lib/services/sync_service.dart` → no direct usage outside `LocalStorageService`
- [ ] New tests: LWW conflict (both directions) + DST-crossing fast, green on CI
