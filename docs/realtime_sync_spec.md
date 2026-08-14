# Realtime Sync Spec

> Status: **implemented**, pending migration 055 + a two-device manual pass ·
> Owner: System Architect · Builds on
> [sync_conflict_resolution_spec.md](sync_conflict_resolution_spec.md), which
> must land first — this feature is only safe because that one made pulls
> re-entrant, idempotent, and conflict-checked.

## Overview

Today a device only learns about another device's edits on boot, on app resume,
or when the user taps "Sync now". A web tab that stays focused never fires
`AppLifecycleState.resumed`, so it can show stale data for an entire session —
the open follow-up from the conflict-resolution spec.

This adds a push channel: the app subscribes to Postgres change events for its
own rows and syncs within a couple of seconds of another device writing.

**Transport.** Not SSE — Supabase Realtime is a WebSocket (Phoenix channels)
carrying `postgres_changes` sourced from Postgres logical replication.
`realtime_client` 2.7.3 already ships inside `supabase_flutter` 2.9, so there is
no new dependency. The practical difference from SSE is that it is bidirectional
and multiplexed, and it reconnects itself.

**The events are a doorbell, not a delivery.** A change event triggers the
existing [`syncCycle`](sync_conflict_resolution_spec.md); the payload is
discarded. That is the whole design: applying payloads directly would mean a
second write path with its own conflict rules, ordering assumptions, and
tombstone handling — exactly the duplication that produced the bugs this branch
just fixed. One reconciliation path, now with a faster trigger.

## User Story

As a user with the ledger open on my laptop and the app on my phone, I want an
edit on either to appear on the other within seconds, so that I stop wondering
which screen is telling the truth.

## Data Model

No new model, no new fields, no change to the cloud row shape. The subscription
carries `PostgresChangePayload`, which is read only for its table name (for
logging) and otherwise dropped.

## Presenter API

No presenter changes. `SyncPresenter.statusLabel` already reflects sync state,
and realtime-triggered cycles flow through it unchanged.

New service, constructor-injected like every other (no locator):

```dart
class RealtimeSyncService {
  RealtimeSyncService({
    required SupabaseClient supabase,
    required String userId,
    required Future<void> Function() onRemoteChange,
    Duration debounce = const Duration(milliseconds: 1500),
  });

  /// Opens the channel. Safe to call once per signed-in user.
  void connect();

  /// True once the channel has reached `subscribed`.
  bool get isConnected;

  /// Last channel error, for diagnostics. Null while healthy.
  String? get lastError;

  Future<void> dispose();
}
```

`SyncService` gains no public surface; two internals change (see Phase 2).

## Design

### Subscription

One channel, one binding per synced table, each filtered server-side to the
signed-in user:

```dart
supabase.channel('sync:$userId').onPostgresChanges(
  event: PostgresChangeEvent.all,
  schema: 'public',
  table: table,                       // × 8 synced tables
  filter: PostgresChangeFilter(
    type: PostgresChangeFilterType.eq,
    column: 'user_id',
    value: userId,
  ),
  callback: (_) => _onChange(table),
).subscribe(_onStatus);
```

Tables: `user_profile`, `user_collections`, `nutrition_logs`, `activity_logs`,
`finance_records`, `fasting_state`, `user_quests`, `advisor_state`.

### Debounce and coalescing

A single user action can write many rows (a bulk finance push is up to 200 per
request), so events arrive in bursts. Every event resets a 1.5s timer; one
`syncCycle` runs per burst. If events arrive *during* a cycle, the service
re-arms after it finishes rather than dropping them — the same rule
`pushPending` uses.

### Echo suppression `[required, not an optimisation]`

A device's own push comes back to it as a change event. Without suppression
every edit would trigger a self-inflicted pull that re-applies the device's own
data and fires `onRemoteDataApplied` → `_reloadAll()` → all twelve presenters
reload. On web that means the ledger reloading under the user while they type.

Two changes make an echo free:

1. **After a successful push, record the stamp that was written** as the
   record's local watermark. The device's own row then no longer looks "newer
   than local" on the next pull, so the echo pull matches nothing. This also
   removes a pre-existing redundancy: every pull after a push re-applied the
   pushing device's own rows.
2. **`onRemoteDataApplied` fires only when a pull actually applied something.**
   It currently fires on every `pullAll`, changed or not. A pull that adopts
   nothing must not churn the UI.

Both are worth having on their own; realtime just makes them mandatory.

### Reconnect and catch-up

The socket drops on sleep, network change, and tab throttling.
`realtime_client` reconnects itself, but events during the gap are gone — they
are not replayed. So a `subscribed` status that is **not** the first one
triggers a catch-up `syncCycle`. The first `subscribed` does not: boot has just
pulled.

### Graceful degradation `[hard requirement]`

If the publication migration has not been applied, `subscribe()` still succeeds
and simply delivers no events. If the channel errors or the socket never opens,
the service logs to `lastError` and stays quiet. In every failure mode the app
falls back to exactly today's behaviour — boot, resume, and manual sync. Nothing
about correctness depends on realtime being reachable.

## Implementation Phases

### Phase 1 — `RealtimeSyncService`

New `lib/services/realtime_sync_service.dart` per the API above. Owns the
channel, the debounce timer, the in-flight/re-arm flags, and the status
handling. No storage access, no Supabase writes — it only calls back.

### Phase 2 — Echo suppression in `SyncService`

- `_noteWritten(entry, writtenAt)` sets the record's watermark to the stamp just
  upserted, called from every push path that succeeds (finance batch, single
  finance record, tombstone, both per-date rows, all five singletons).
- `pullAll` tracks whether any domain adopted remote data (set in
  `_adoptRemote` and in the nutrition apply) and calls
  `_storage.onRemoteDataApplied` only when it did.

### Phase 3 — Wiring

Both shells construct the service after `_initSync` succeeds, `connect()` it,
and dispose it in `_tearDownSync` and `dispose()`. Callback is
`() => _syncService!.syncCycle()` — no staleness, since an event means there is
genuinely something new, but the cycle's own re-entrancy guard still applies.

### Phase 4 — Migration

`docs/supabase_migration_055_realtime.sql` adds the eight tables to the
`supabase_realtime` publication and sets `REPLICA IDENTITY FULL` where delete
events need the old row. Unlike migration 054 this one **is** safe to apply
whenever — the client tolerates its absence, and applying it without the client
merely publishes events nobody listens to.

## UI Requirements

- **No new screens or controls.** Realtime-triggered cycles surface through the
  existing `SyncPresenter.statusLabel` ("Syncing…" → "Synced just now").
- **States:** unchanged.
- **Glanceability:** the win is that a screen left open stops being stale; there
  is nothing new to read.
- **Micro-animations:** none added. Presenter reloads are now *rarer* than
  before (echo suppression), so no new UI churn is introduced.
- **Thumb zone:** N/A — no new interactive elements.

## RPG Mechanics

N/A. No XP, level, or streak behaviour changes. `user_profile` and `user_quests`
carry RPG state, so they propagate faster, but nothing is awarded.

## Storage

- **No new `StorageService` keys.**
- **No cloud schema change** — the migration alters only replication config
  (publication membership + replica identity), not tables.

## Security & Cost

- `postgres_changes` is filtered server-side by `user_id` **and** gated by the
  existing `user_owns_row` RLS policies, which Realtime enforces per subscriber
  using the user's JWT. A user can only ever receive their own rows.
- Enabling the publication means row data flows through the Realtime server.
  That is standard Supabase behaviour and the same trust boundary as PostgREST,
  but it is a deliberate change and worth stating: this app's rows include
  financial records.
- Cost: one WebSocket per active client. For a personal multi-device user this
  is far inside the free tier's 200 concurrent connections / 2M messages. It is
  worth revisiting only if the app gains many users.

## Edge Cases

- **Own-write echo.** Suppressed by Phase 2; an echo pull adopts nothing and
  fires no reload.
- **Burst of writes.** Coalesced into one cycle by the debounce.
- **Event during a running cycle.** Re-armed after it finishes, never dropped.
- **Socket drop.** Auto-reconnect; a non-first `subscribed` triggers catch-up.
- **Publication not applied.** No events; behaviour identical to today.
- **Signed out mid-session.** `dispose()` in `_tearDownSync` closes the channel
  before the user namespace detaches, so no cycle can fire for a stale user.
- **User switch.** The channel name is keyed by user id and the old service is
  disposed first, so events cannot cross accounts.
- **Offline.** No socket, no events; the connectivity listener's existing
  `pushPending` on reconnect is unchanged.
- **Tab throttling.** Background tabs may have the socket suspended; the resume
  path still runs, so nothing regresses versus today.

## Non-Goals

- **Applying event payloads directly.** Events are a trigger only; see Overview.
- **Realtime presence / broadcast.** Only `postgres_changes` is used.
- **Optimistic cross-device UI.** No "another device is editing" indicator.
- **Replacing resume/boot sync.** Realtime is additive; every existing trigger
  stays, because the socket is best-effort.

## Acceptance Criteria

`[test]` = covered by an automated test. `[inspect]` = verified by code review
only. The event plumbing itself needs a live Realtime server, so everything
downstream of an actual socket message is `[inspect]` until the follow-up
harness exists; the debounce/coalescing logic around it — where the risk
actually sits — is driven directly through `debugOnEvent` and is `[test]`.

- [x] `[test]` An event triggers exactly one cycle after the debounce, and
      well-separated events each get their own.
- [x] `[test]` A burst of 50 events collapses into a single cycle.
- [x] `[test]` An event arriving mid-cycle re-arms rather than being dropped.
- [x] `[test]` A throwing cycle does not wedge the service.
- [x] `[test]` Events after `dispose` are ignored and a pending debounce is
      cancelled.
- [x] `[test]` `connect()` survives an unreachable socket, reports via
      `lastError`, and does not break sign-in.
- [x] `[test]` A pull that adopts nothing does not fire `onRemoteDataApplied`.
- [x] `[test]` A *failed* push leaves the watermark at the local edit time.
- [x] `[inspect]` A successful push advances the record's watermark to the stamp
      written (`_noteWritten`, called from all nine push paths).
- [x] `[inspect]` A change written by another device triggers a `syncCycle`.
- [x] `[inspect]` Re-subscribing after a drop triggers a catch-up cycle; the
      first subscribe does not (`_hasSubscribed`).
- [x] `[inspect]` Sign-out, user switch, failed init, and widget dispose all
      close the channel — sign-out before the namespace detaches.
- [x] `flutter analyze` clean (no new errors or warnings); `flutter test` green.

### Not verified here

- **End-to-end against a live Supabase project.** No integration environment in
  CI, and the fake client cannot serve a socket. Two-device behaviour — an edit
  on one appearing on the other — is unproven by test and needs a manual pass
  once migration 055 is applied.
- **Web socket behaviour under tab throttling.** Browsers suspend background
  sockets at their discretion; the resume path still covers it, but the exact
  reconnect timing is browser-specific and untested here.
