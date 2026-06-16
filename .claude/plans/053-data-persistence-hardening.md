# Plan 053 — Data Persistence Hardening ("Never Lose Data Again")

**Status:** Proposed
**Author:** System Architect (Claude)
**Trigger:** Third confirmed incident of progress loss on sign-out / re-login. Quests, fasting, weight, and body data reverted; cloud `user_quests.data.quests` observed empty (`[]`). Prior fix (PR #185, "flush before wipe") was a band-aid and did not address root cause.

**Scope:** Mobile **and** web (hybrid). Both platforms share `LocalStorageService` (SharedPreferences → browser localStorage on web), `SyncQueue`, and `SyncService`, so every bug below affects both.

---

## 1. Guiding invariant

> **Local user data must never be destroyed unless an equivalent or newer copy is provably safe elsewhere. The cloud must never be overwritten with empty/stale data.**

Everything below is defense-in-depth toward that invariant. We assume any single layer can fail (offline, crash, clock skew, race) and ensure no single failure causes loss.

---

## 2. Root-cause assessment (cross-validated)

### 2.1 The core loss loop (HIGH confidence — explains the observed `quests: []`)
1. **No empty-overwrite guard on PUSH.** `_pushUserQuests`, `_pushUserProfile`, `_pushFastingState`, `_pushUserCollections` upload whatever is local — including `quests: []`, empty `weightLog`, empty `bodyMeasurements` — over a populated cloud row. (`sync_service.dart:153–260`)
2. **No empty/stale guard on PULL.** `_pull*` apply remote arrays even when empty, over populated local. Null-checks exist; empty-checks do not. (`sync_service.dart:547–550` et al.)
3. **Destructive wipe on sign-out** turns any cloud staleness into permanent local loss. `_tearDownSync` wipes `u/$userId/*` when `flushed` (= queue empty), but "queue empty" ≠ "cloud has the data." (`home_screen.dart:286–325`)
4. **After wipe, conflict resolution always favors remote.** `clearUserData()` removes the persisted `syncTimestamps`; `getTimestamp` then returns epoch 0, so any remote row (even an empty/old one) is `isAfter` local and is applied. (`sync_queue.dart:91–113`, `local_storage_service.dart:148–160`)

**Net effect:** once an empty/stale singleton row exists in the cloud, a wipe + re-login deterministically reverts local to that empty state. The QuestPresenter then regenerates default starter quests on top of nothing → "reverted to the beginning."

### 2.2 Contributing factors
5. **Initial-push flag is not user-scoped.** `sync_initial_push_done_v2_$userId` is a **bare** key, so `clearUserData()` doesn't remove it; `pushAll()` (the safety re-upload of all singletons) never runs again after a wipe. (`sync_service.dart:781–791`)
6. **`pushPending` breaks on the first error.** One poison/conflicting entry blocks every entry behind it indefinitely — no skip-and-continue, no backoff, no quarantine. (`sync_service.dart:84–116`)
7. **Queue not wired during reload.** Presenters are constructed with `_userId = null` and `_reloadAll()` runs *before* `setSyncQueue` (`home_screen.dart:236` vs `251`). Any write during load/migration/daily-rollover/penalty-check is silently NOT queued → never pushed.
8. **Migration deletes bare keys non-atomically.** `_migrateUnscopedKeys` writes the scoped key then removes the bare key; a crash in between leaves a half-migrated state. (`local_storage_service.dart:73–92`)

### 2.3 Hybrid / web-specific
9. Web uses the **same** storage + sync stack → inherits 2.1–2.2 entirely. (Note: user *data* is SharedPreferences/localStorage; `sqflite` is only the bundled food DB, not user data.)
10. **Finance deletes are not reconciled on pull.** `_pushDelete` removes the cloud row, but `_pullFinanceRecords` only merges upserts into the local map — it never removes locally-present records absent from the remote set. Cross-device: a delete on A is resurrected on B. (`sync_service.dart:670–764`)
11. **Web staleness:** `pullIfStale` has a 5-minute window and relies on `AppLifecycleState.resumed` mapping to browser tab-visibility (unverified). Stale reads up to 5 min; possible no-pull-on-focus.
12. **Clock-skew LWW:** conflict resolution uses device-clock timestamps; a device clock behind the server can have its edits silently overwritten.

### 2.4 Local-only data (no cloud backup — lost on any wipe)
- **`notification_preferences`** — never synced (HIGH: should be). (`local_storage_service.dart` save has no `_markDirty`)
- `themeMode`, `useCloudAi`, `aiPromptSkippedAt` — device-level prefs (acceptable to leave local, but document).
- `grocery_cart`, `grocery_budget` — transient per-trip (acceptable).
- `widget.lastUserId`, `widget.pendingActions` — device-level widget state (acceptable, but pending actions can be lost on crash).

### 2.5 Test gap
- No tests for: sign-out→re-login with empty local; multi-device empty-overwrite; poison-entry blocking; wipe-then-pull; crash-during-migration. (`test/services/sync_service_test.dart`)

### 2.6 Confidence note
The exact trigger of *this* incident can't be 100% pinned without device logs/DB history. **This plan intentionally closes every hole in 2.1–2.5 regardless**, because "never again" requires eliminating the whole class, not one path.

---

## 3. Phased implementation (one PR per phase; all target `dev`)

### Phase 0 — Stop the bleeding (small, safe, ship first)
**Goal:** make local loss impossible and kill the ghost notifications, immediately.
- **0.1 Make sign-out non-destructive.** Stop calling `clearUserData()` / `clearAll()` on sign-out. User data already lives under `u/$userId/`, invisible to other accounts on the device, so the wipe is housekeeping — not required for privacy/correctness. Keep data; it re-syncs next login. (Optionally gate any future wipe behind a verified cloud read-back; see 1.)
- **0.2 Cancel scheduled notifications on sign-out.** In `_tearDownSync`, call quest/weight/bills/fasting/streak cancels (or `cancelAll()`), mirroring `_widgetBridge.clearForSignOut()`. Fixes ghost quest reminders.
- **Tests:** sign-out keeps `u/$id/*` keys (detach, not wipe); same-user re-login restores; a different account sees nothing; `clearUserData` still wipes.
- **Risk:** very low. **Impact:** eliminates the destructive step behind all three incidents.
- **STATUS: ✅ DONE — PR A (branch `fix/signout-data-loss-guard`).** Added `LocalStorageService.detachUser()` (non-destructive); both `_tearDownSync` (mobile + web) now detach instead of `clearUserData()`; mobile cancels OS notifications via `NotificationService().cancelAll()`. Regression tests added.

### Phase 0.5 — Local autosave backup + restore (MOBILE)
**Goal:** an on-device snapshot the wipe/detach path never touches, for offline recovery.
- Debounced (or on app-pause) write of full local state to `getApplicationDocumentsDirectory()/backup.json` via `path_provider` + `dart:io`. **Never deleted by sign-out/detach.**
- On launch, if local state is empty/fresh but `backup.json` exists, offer "Restore from local backup."
- **Mobile-only:** web has no filesystem — its equivalent is export/import (Plan 044). Guard file I/O behind `!kIsWeb`.
- **Caveat:** the sandbox file is gone on uninstall / "clear data" — it survives sign-out + app updates, not a fresh device. (Phase 3.5 covers device loss.)
- **Tests:** snapshot written after change; restore repopulates presenters; web no-ops.
- **STATUS: ✅ DONE — PR (`feat/local-autosave-backup`).** Generic snapshot: `LocalStorageService.exportUserData`/`importUserData`/`hasUserData` (all `u/$id/` keys, sync bookkeeping excluded; import is a raw write — no dirty mark / no LWW bump, so cloud still wins). New `BackupService` (mobile-only, `kIsWeb` no-op) writes `documents/backup.json` on app-pause; `_initSync` restores-on-empty before reload+sync. Round-trip + exclusion + hasUserData tests. (Auto-restore is silent rather than a prompt — safe because restore can't override newer cloud.)

### Phase 1 — Empty/stale overwrite guards (core correctness)
**Goal:** cloud can never be clobbered by empty/default state, and pull can never wipe populated local.
- **1.1 Push guard.** Before upserting a singleton, refuse to overwrite a populated cloud row with an empty/default local payload. Implement via read-before-write compare or a "non-empty / has-content" guard per domain (e.g., don't push `quests: []` if cloud has quests). Prefer a generic `_isMeaningful(payload)` + remote content check.
- **1.2 Pull guard.** In each `_pull*`, do not apply an empty remote array/object over non-empty local. Apply field-by-field only when remote is non-empty OR local is empty.
- **1.3 User-scope the initial-push flag.** `u/$userId/sync_initial_push_done_v2`; remove the bare key. Clear it in `clearUserData()` (for the rare explicit reset path).
- **1.4 Clear timestamps on wipe + defensive seeding.** Explicitly remove the persisted `syncTimestamps` key on any real reset, and when setting up a fresh scoped namespace that already has local data, seed timestamps to `now` so stale cloud can't blindly win.
- **Tests:** empty push rejected when cloud populated; empty pull rejected when local populated; flag scoped + cleared.
- **STATUS: ✅ DONE — PR B (branch `fix/sync-overwrite-guards`).** Added `_wouldClobberRemote` + per-domain emptiness predicates (`questsDataEmpty`/`fastingDataEmpty`/`profileDataEmpty`/`collectionsDataEmpty`, `@visibleForTesting`); all four singleton pushes skip when local-empty-and-cloud-populated; all four pulls skip when remote-empty-and-local-populated; initial-push flag scoped under `u/$id/`. Predicate unit tests added; full guard wiring lands in Phase 4 harness.

### Phase 2 — Sync engine robustness
- **2.1 `pushPending` skip-and-continue.** Don't `break` on first error: process all entries, keep failures queued, quarantine repeat-failers (failure count + backoff) so one poison entry can't block the rest. **✅ DONE — PR C (`fix/sync-push-resilience`).** Per-entry `_failureCounts` + `_retryAfter` exponential backoff (2s→300s cap); failed entries stay queued and retry; `failureCountFor` `@visibleForTesting`. Tests for failure-count + backoff-quarantine.
- **2.2 Wire queue before reload.** ⚠️ **DEFERRED — risk of a NEW regression.** Naively setting `setSyncQueue` before `_reloadAll()` makes first-login reload-writes (default-quest generation, penalty/rollover) call `markDirty`, which bumps LWW timestamps to `now` — that would make `pullAll` skip the real cloud row (`local newer`) and **break fresh-device restore**. After Phase 0 (non-destructive sign-out) + Phase 1 (guards), the original urgency is largely gone: reload-writes persist locally and re-queue on the next mutation. Proper fix needs to separate "enqueue for push" from "bump LWW timestamp"; do it under the Phase 4 harness so fresh-device restore is proven not to regress.
- **2.3 Atomic migration.** ✅ **Already crash-safe — no change.** `_migrateUnscopedKeys` writes the scoped key then removes the bare key; a crash in between leaves the scoped value present (reads prefer scoped) and a harmless lingering bare key — not data loss. Documented; no edit.
- **Tests:** poison entry recorded + backed-off (done); fresh-device-restore-preserving 2.2 + migration covered in Phase 4 harness.

### Phase 3 — Hybrid completeness & cross-device correctness
- **3.1 Sync `notification_preferences`** (add to a singleton domain, push+pull). Audit remaining local-only keys; document each as "intentionally local" or fold into sync. **✅ DONE — PR (`fix/sync-notification-prefs`).** `saveNotificationPreferences` now marks `userProfile` dirty; prefs ride in the `userProfile` push/pull payload. Test added. (Remaining intentionally-local: `themeMode`/`useCloudAi`/`aiPromptSkippedAt` device prefs; `grocery_cart`/`grocery_budget` transient; widget state.)
- **3.2 Finance delete reconciliation on pull** — tombstones or full-set reconcile so deletes propagate across devices without resurrecting records. **✅ DONE — PR (`fix/finance-delete-reconcile`).** Chose **tombstones** (no migration, no risky absence-inference): `_pushDelete` upserts `{__deleted: true}` instead of hard-deleting; `_pullFinanceTable` removes the local record when it sees a tombstone (respecting LWW). `isTombstone` `@visibleForTesting` + unit test; full reconcile wiring in Phase 4 harness.
- **3.3 Web freshness** — reduce `pullIfStale` window and/or add Supabase realtime subscription for the active user; verify tab-visibility actually triggers a pull (add an explicit `visibilitychange`/focus hook if `AppLifecycleState.resumed` doesn't fire on web). **✅ DONE (lightweight) — PR (`fix/web-pull-freshness-v2`).** Web resume path now passes a 30s staleness window so a tab refocus reliably pulls recent cross-device edits (was 5 min). Realtime subscription + explicit `visibilitychange` hook noted as optional/future (needs in-browser verification).
- **3.4 Clock-skew** — prefer server-authoritative `updated_at` (DB default `now()` returned on upsert) or a monotonic per-record version for LWW instead of the device clock. ⚠️ **DEFERRED.** Rewrites the conflict-resolution model across every push; real-world incidence is low and a mistake risks new conflict bugs. Do it after the Phase 4 harness can prove no regression.

### Phase 3.5 — Immutable cloud snapshots ("the backup that is never deleted")
**Goal:** a durable, cross-platform backup that survives the empty-overwrite bug, sign-out, uninstall, AND device loss — the only layer that does all four.
- On a daily cadence (and/or on meaningful change), write a full-state JSON to an **append-only** location the normal sync code never overwrites or deletes — a Supabase Storage bucket (`backups/$userId/$timestamp.json`) or a `backups(user_id, taken_at, data)` table.
- Retain the last N snapshots (e.g. 30 daily); prune only the oldest, never the newest.
- Add a **restore-from-snapshot** UI (pick a date → preview → restore). Even if live sync clobbers `user_quests` to `[]`, yesterday's snapshot is intact.
- Works on **both web and mobile** (server-side) — the right durable layer for a hybrid app.
- **Security:** financial + health data — RLS-scoped to the user; consider client-side encryption of the snapshot blob.
- **Tests:** snapshot is append-only (never overwritten); restore reconstructs state; retention prunes oldest only.
- **STATUS: ✅ DONE (client) — PR (`feat/cloud-snapshots-v2`).** `backups` table migration (`docs/supabase_migration_053_snapshots.sql`, **manual apply**). `SnapshotService` (mobile+web): `writeSnapshotIfDue` (24h throttle, exports via Phase 0.5, append-only insert, prune to newest 30), `listSnapshots`, `restoreSnapshot` (raw import → cloud still wins). Wired fire-and-forget into mobile `_initSync`; inert until migration applied. `snapshotsToDelete` unit-tested. **Follow-ups:** restore-from-snapshot UI; wire `writeSnapshotIfDue` into the web shell too.

### Phase 4 — Regression harness (so it never comes back)
- In-memory fake Supabase + fake storage. Cover every 2.1–2.5 scenario as an explicit test: sign-out→re-login (empty cloud, populated local) **must not lose data**; multi-device empty-overwrite **must be rejected**; wipe→pull; poison entry; crash-mid-migration; notification cancel on sign-out.
- Add these to CI's `test` job. This is the contract that keeps the invariant true.

### Phase 5 — (Optional, longer-term) durable architecture
- Per-record monotonic versioning + soft-delete tombstones + server-authoritative time; consider breaking the 4 whole-object "singletons" into versioned per-field or per-entity rows so a single empty field can't nuke a whole domain. Larger effort — propose separately once Phases 0–4 land.

---

## 4. Recovery reality (this incident)
The lost progress only ever lived in the wiped local store; the cloud copy is empty and Supabase upserts keep no history. **It is not recoverable.** This plan is about prevention. (Before any further sign-out/re-login, avoid round-trips that could overwrite cloud with reverted state — though Phase 0 removes that hazard.)

---

## 5. Sequencing & PRs
1. **PR A** — Phase 0 (non-destructive sign-out + notification cancel). *Ship immediately.* ✅ **DONE**
2. **PR A2** — Phase 0.5 (local autosave backup + restore, mobile).
3. **PR B** — Phase 1 (overwrite guards + scoped flag + timestamp handling).
4. **PR C** — Phase 2 (engine robustness + ordering + migration).
5. **PR D** — Phase 3 (notification sync, delete reconcile, web freshness, clock).
6. **PR D2** — Phase 3.5 (immutable cloud snapshots + restore UI). ← the durable "never deleted" backup.
7. **PR E** — Phase 4 (regression harness). *Can land alongside B–D, growing per phase.*
8. **PR F** — Phase 5 (optional architecture), separate decision.

All PRs target `dev`, each with tests (`dart format` + `flutter analyze` + `flutter test` green). This is the data-integrity layer — no PR merges without coverage.
