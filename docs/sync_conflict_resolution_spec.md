# Sync Conflict Resolution Spec

> Status: **Phases 1–4 implemented**, Phase 5 pending a migration · Owner:
> System Architect · Supersedes the sync-ordering assumptions in Plan 053
> Phase 3.3.

## Overview

Cross-device sync (mobile ⇄ web, same Supabase user) currently loses writes. A
device can push a **stale local edit over a newer cloud record**, and because the
push stamps `updated_at` with "now", every other device then faithfully pulls the
stale value back down. The reported symptom is a ledger/account balance silently
reverting to an older value — "as if the web is outdated and pushes the outdated
one to the mobile".

This spec defines the conflict-resolution contract for `SyncService` and the
changes needed to honour it: **the most recently *edited* copy wins, regardless
of which device pushes last**.

It is a service-layer spec. There is no new UI, no new model, and no RPG
mechanic — the sections below are kept for template parity and marked N/A where
they do not apply.

## User Story

As a user who logs transactions on my phone and does bulk entry on the web, I
want whichever edit I made **last** to survive, so that my account balances and
ledger never silently revert to a number I already corrected.

## Root Cause Analysis

### RC-1 — Last-write-wins is enforced only on pull `[Critical]`

Every push is an unconditional upsert stamping `updated_at` with the pushing
device's clock **at push time**, not at edit time:

- `sync_service.dart:335` — finance batch rows
- `sync_service.dart:431-437` — delete tombstones
- `sync_service.dart:770-776` — single finance record
- `sync_service.dart:573`, `:613`, `:643`, `:668`, `:704`, `:737`, `:755` — singletons and per-date rows

Nothing compares the local edit against the remote row's `updated_at` before
writing. The existing `_wouldClobberRemote` guard (`sync_service.dart:494-508`)
only checks *emptiness*, never *recency*. So a queued edit from hours ago always
wins on the server, and — stamped "now" — then looks newest to the pull-side LWW
check (`sync_service.dart:904`, `:1062`, `:1109`, `:1153`, `:1220`, `:1274`,
`:1376`), which propagates it to every other device.

### RC-2 — Resume pushes before it pulls, and awaits neither `[Critical]`

- Web: `treasury_web_app.dart:225-230` — `pushPending(); pullIfStale(30s);`
- Mobile: `home_screen.dart:484-485` — `pushPending(); pullIfStale(5min);`

The push is built from local state that has not been refreshed yet, and it races
the pull. Boot does the opposite and is therefore safe
(`treasury_web_app.dart:257`, `home_screen.dart:331`) — which is why the bug is
intermittent: a cold load is fine, refocusing a long-open web tab is not.

`pullAll` also never checks `_isSyncing` (it only sets it,
`sync_service.dart:836`), so a push and a pull genuinely interleave, and
`pullAll`'s `finally` clears the flag while a push may still be in flight.

### RC-3 — Superseded queue entries are re-pushed as no-ops `[Medium]`

When a pull decides the remote copy wins for a record, the pending queue entry
for that record is left in place. The next push re-reads local storage (now
holding the pulled value) and writes it straight back with a fresh `updated_at`,
causing every *other* device to re-pull data it already had. Write amplification,
and it muddies the timestamps that LWW depends on.

### RC-4 — A local edit made during a pull is silently never queued `[High]`

`applyRemote` (`local_storage_service.dart:263-274`) guards with a plain
`_applyingRemote` bool while awaiting, and `_markDirty` (`:276-281`) no-ops
whenever it is set. On web the UI stays interactive during a pull, so a user
save landing between those awaits never enters the sync queue at all — and the
next pull overwrites it.

### RC-5 — Client clocks arbitrate `[High, deferred to Phase 5]`

`updated_at` is always the writer's `DateTime.now().toUtc()`; the watermark it is
compared against is this device's `DateTime.now()` from `SyncQueue.markDirty`
(`sync_queue.dart:88`). `TIMESTAMPTZ … DEFAULT now()` in
`docs/supabase_migration.sql` is overridden on every write and there is no
`BEFORE UPDATE` trigger. A browser clock drifting behind a phone clock inverts
the ordering: the phone's newer edit lands with an older stamp, the web skips it
("local is newer, skipping") and re-pushes over it.

Fixing this properly needs a migration, so it is scoped to Phase 5.

## Conflict-Resolution Contract

The rules `SyncService` must obey after this change:

1. **Edit-time ordering.** For a given record, the copy whose *edit* is most
   recent wins — not the copy that reached the cloud most recently.
2. **A push never destroys a newer remote write.** If the cloud row is newer than
   the local edit being pushed, the push is abandoned and the local copy is
   marked for replacement on the next pull.
3. **Pull before push, always.** Every sync cycle reconciles down before it
   writes up, on every entry point (boot, resume, manual).
4. **One sync cycle at a time.** Pulls and pushes never interleave.
5. **Losing an edit is silent to the cloud, never silent to storage.** A local
   copy that loses a conflict is refreshed from the cloud, never left stale.
6. **Granularity is the record.** Finance rows conflict per `(table, id)`;
   singletons (`user_profile`, `fasting_state`, `user_quests`,
   `user_collections`, `advisor_state`) conflict per blob. Blob-granularity means
   two devices editing *different fields of the same blob* concurrently will
   still lose one side — a known limitation, see Non-Goals.

## Data Model

No new model. Two existing structures gain meaning:

```dart
// lib/models/sync_queue_entry.dart — unchanged shape, `queuedAt` is promoted
// from bookkeeping to the authoritative EDIT TIME used for conflict ordering.
class SyncQueueEntry {
  final SyncDomain domain;
  final String key;
  final SyncOp op;
  final DateTime queuedAt; // ← now the LWW ordering key on the push side
}
```

The cloud row shape is unchanged (`user_id`, `data`, `updated_at`, plus
`table_name`/`record_id`/`date` per table). No migration is required for
Phases 1–4.

## Presenter API

`SyncPresenter` is unchanged. `SyncService` gains one public entry point and
tightens two existing ones:

```dart
class SyncService {
  /// One ordered, non-overlapping sync cycle: reconcile down, then write up.
  /// Every caller (boot, resume, manual) funnels through this so the ordering
  /// can never diverge per-platform again.
  Future<void> syncCycle({Duration? staleness});

  /// Now re-entrant-safe: returns immediately if a cycle is already running.
  Future<void> pullAll();

  /// Now conflict-checked: an entry whose cloud copy is newer than the local
  /// edit is dropped instead of pushed.
  Future<void> pushPending();

  /// Manual "Sync now" — pull then push (was push then pull). Unlike
  /// [syncCycle] a pull failure propagates, because a user is watching.
  Future<void> forceSync();

  /// Diagnostics: records whose local edit lost to a newer cloud copy during
  /// the most recent push. Each entry is `'<domain>/<key>'`.
  List<String> get lastConflictsLost;
}
```

```dart
class SyncQueue {
  /// Drops a pending entry whose local edit has been superseded by the cloud.
  void discardEntry(SyncDomain domain, String key);

  /// Resets a record's watermark so the next pull unconditionally applies the
  /// cloud copy. Used when a push is abandoned on conflict.
  void invalidateTimestamp(SyncDomain domain, String key);
}
```

```dart
class LocalStorageService {
  /// Unchanged signature. Dirty marks raised by concurrent local writes during
  /// [block] are now buffered and replayed afterwards instead of dropped.
  Future<void> applyRemote(Future<void> Function() block);
}
```

## Implementation Phases

### Phase 1 — Ordering `[fixes RC-2]`

- Add `SyncService.syncCycle({Duration? staleness})`: `await pullIfStale(...)`
  (or `pullAll()` when `staleness` is null) then `await pushPending()`.
  A pull failure is logged and swallowed so the push still runs — an offline or
  auth-blipped pull must not strand the outbox. This is only safe *because* of
  Phase 2: each push checks the cloud stamp itself, so an unreconciled push
  still cannot clobber a newer copy. `forceSync` keeps propagating the failure.
- Add a re-entrancy guard to `pullAll`: if a cycle is in flight, return without
  starting a second one.
- `forceSync()` becomes pull → push.
- Both shells' `didChangeAppLifecycleState(resumed)` call
  `syncCycle(staleness: …)` and nothing else:
  - web `treasury_web_app.dart:225-230` → `syncCycle(staleness: 30s)`
  - mobile `home_screen.dart:484-485` → `syncCycle(staleness: 5min)`
- Boot paths keep their explicit pull-then-push sequence (already correct) but
  stop being able to overlap with a resume cycle thanks to the guard.

### Phase 2 — Conflict guard on push `[fixes RC-1]`

Before writing, compare the cloud row's `updated_at` against the queue entry's
`queuedAt`. If the cloud is strictly newer, abandon the push for that entry,
`discardEntry` it, and `invalidateTimestamp` so the next pull adopts the cloud
copy.

- **Finance upserts (batched):** one paged `select('table_name, record_id,
  updated_at')` per push cycle builds a stamp map; entries are partitioned into
  winners and losers before any write. Costs one extra small select per cycle,
  not per record.
- **Finance deletes (tombstones):** same rule — a delete queued before a newer
  remote edit must not resurrect as a tombstone.
- **Per-date rows** (`nutrition_logs`, `activity_logs`): fold `updated_at` into
  the select `_pushNutritionLog` already performs; add one for
  `_pushActivityLog`.
- **Singletons:** fold `updated_at` into the existing `_wouldClobberRemote`
  select so the recency check costs no extra round trip. The emptiness guard
  stays — both must pass.

### Phase 3 — Drop superseded entries on pull `[fixes RC-3]`

When `_pullFinanceTable` (or a singleton/per-date pull) applies a remote copy
that beat the local watermark, `discardEntry` any pending entry for that record.
The nutrition heal-push path (`sync_service.dart:1247-1251`) is explicitly
exempt — it re-dirties on purpose.

### Phase 4 — No lost dirty marks during a pull `[fixes RC-4]`

Replace the `_applyingRemote` bool with a **zone value** scoped to the remote
apply's own call chain: `applyRemote` runs its block via `runZoned` with a
marker, and `_markDirty` suppresses only when `Zone.current` carries it. The
marker follows the pull's awaits and nothing else, so a user save on another
async path is correctly seen as local and queued.

A zone is the right tool here precisely because the two writers are
indistinguishable by any *value* — they differ only by which call chain they
belong to, which is exactly what a zone tracks. It also fixes the finance diff
baseline for the same reason: a concurrent local save now diffs against the
baseline instead of silently reseeding it.

### Phase 5 — Server-authoritative time `[fixes RC-5, NOT in this change]`

Requires a migration, so it ships separately and is applied by hand:

- `docs/supabase_migration_054_server_timestamps.sql` — a `set_updated_at()`
  trigger function plus `BEFORE INSERT OR UPDATE` triggers on the seven synced
  tables, so `updated_at` is always the database's `now()`.
- A nullable `client_edited_at TIMESTAMPTZ` column carrying the originating
  device's edit time, so LWW can order by edit time while change detection uses
  the server clock. Null on legacy rows → fall back to `updated_at`.

The Phase 1–4 client is forward-compatible with the trigger (it only ever
*reads* `updated_at`), so the migration can be applied at any time after this
change ships without a client update.

## UI Requirements

- **No new screens or controls.** The only surface is `SyncPresenter.statusLabel`
  in `settings_screen.dart`, which is unchanged.
- **States:** unchanged (`Syncing…` / `N changes pending` / `Synced Xm ago`).
- **Glanceability:** unaffected.
- **Micro-animations:** N/A.
- **Thumb zone:** N/A — no new interactive elements.

## RPG Mechanics

N/A — no XP, level, or streak behaviour changes. Note that `user_profile` and
`user_quests` carry XP/level/streak state, so this fix *protects* RPG progress
from being reverted by a stale device, but awards nothing.

## Storage

- **No new `StorageService` keys.**
- **No cloud schema change** for Phases 1–4.
- `SyncQueue`'s two persisted keys (`u/$userId/syncQueue`,
  `u/$userId/syncTimestamps`) keep their existing JSON shape. `discardEntry` and
  `invalidateTimestamp` write through the same coalesced flush.
- Phase 5 adds the trigger + `client_edited_at` column (separate migration).

## Edge Cases

- **Offline backlog vs. a newer cloud edit.** A three-day-old offline edit loses
  to a newer cloud copy and is replaced on the next pull. Correct per the
  contract, and the losing record is named in `lastConflictsLost`.
- **Clock skew between devices.** Still possible until Phase 5; a device whose
  clock runs fast can still win a conflict it should lose. Reduced in blast
  radius by Phase 1 (a stale push no longer happens *by default* on every
  resume), not eliminated.
- **Delete vs. concurrent edit.** A tombstone queued before a newer remote edit
  is abandoned — the record survives. A tombstone newer than the remote edit
  still deletes. Deleting wins only when it is the later action.
- **Record deleted locally while an upsert is queued.** Unchanged behaviour:
  `buildFinanceUpsertRows` omits it and the caller drops the entry.
- **First sync on a fresh device.** Local watermarks are epoch 0, so every cloud
  row wins and nothing is pushed over it. Unchanged, and now guaranteed by the
  pull-first ordering.
- **Empty cloud row + populated local.** The existing emptiness guards
  (`_wouldClobberRemote`, and the pull-side "remote empty but local populated"
  checks) still apply and take precedence — this change never weakens them.
- **Push fails mid-cycle.** Existing per-entry backoff is untouched; a
  conflict-abandoned entry is *not* a failure and does not accrue a backoff
  count.
- **Two pulls racing (boot + resume).** The re-entrancy guard makes the second a
  no-op rather than an interleaved double-apply.
- **Nutrition heal-push.** The existing "local feed ahead of cloud" re-dirty path
  must keep working; it is exempt from Phase 3's entry-dropping.

## Non-Goals

- **Field-level merge.** Two devices editing different fields of the same
  singleton blob concurrently will still lose one side. A CRDT/field-merge model
  is out of scope.
- **Realtime push.** No Supabase Realtime subscription; sync stays poll-on-
  resume plus the 3s debounced push.
- **Undo/conflict UI.** Losers are logged and exposed via `lastConflictsLost`,
  not surfaced as a user-facing merge prompt.
- **The read-modify-write window inside a pull.** `_pullFinanceTable` loads the
  local list, merges cloud rows into it, and saves the result. A user edit that
  saves between the load and the save is overwritten by the merge — the edit
  still *syncs* after Phase 4 (its dirty mark survives), so the cloud keeps it
  and the next pull restores it, but the local copy flickers. Closing the window
  properly needs a storage-level write lock across all ~90 `saveX` methods, which
  is a larger change than this one.

## Acceptance Criteria

`[test]` = covered by an automated test. `[inspect]` = verified by code review
only — the test suite's Supabase fake throws on every call, so any criterion
needing a *responding* PostgREST cannot be asserted end-to-end. Building that
harness is tracked as follow-up work below.

- [x] `[test]` The conflict rule: the cloud wins only on a strictly newer stamp;
      equal stamps, a missing cloud row, and a seeding push all proceed, and
      ordering holds across a local/UTC stamp mix.
- [x] `[test]` `discardEntry` drops the superseded entry and leaves others alone.
- [x] `[test]` `invalidateTimestamp` resets the watermark to epoch, so the next
      pull cannot skip the winning row as "local is newer".
- [x] `[test]` `syncCycle` still pushes when the pull fails; the failure does not
      propagate to the caller.
- [x] `[test]` `forceSync` propagates a pull failure.
- [x] `[test]` A `saveX` issued while `applyRemote` is running is queued, the
      remote apply's own writes are not, and a throwing block restores normal
      marking.
- [x] `[inspect]` A queued edit is not pushed when the cloud row is newer; the
      entry is dequeued and its watermark invalidated (`_remoteWins` →
      `_noteConflictLost`, applied in the finance batch, single finance record,
      tombstone delete, both per-date pushes, and all five singletons).
- [x] `[inspect]` Tombstone deletes obey the same guard.
- [x] `[inspect]` `pullAll` returns immediately when a cycle is already running.
- [x] `[inspect]` Both shells' resume handlers call only `syncCycle`; boot keeps
      its existing pull-then-push sequence.
- [x] `[inspect]` A pull that applies a remote copy discards the pending entry
      for that record (`_adoptRemote`), except the nutrition heal-push path.
- [x] `[inspect]` The emptiness guards are unchanged and still run alongside the
      new recency guard.
- [x] `[inspect]` Conflict-abandoned entries clear rather than increment their
      backoff state.
- [x] `[inspect]` `lastConflictsLost` names every record whose local edit lost.
- [x] `flutter analyze` clean (no new errors or warnings); `flutter test` green.

### Follow-up

- A responding Supabase/PostgREST fake, so the `[inspect]` rows above become
  `[test]` — in particular the end-to-end regression: web queues an edit at T1,
  mobile writes the cloud at T2 > T1, web resumes, mobile's value survives on
  both devices.
- Phase 5 (`docs/supabase_migration_054_server_timestamps.sql`) — do not apply
  that migration until the client change that writes `client_edited_at` ships
  with it; the file's header explains why the trigger alone is not an
  improvement.
