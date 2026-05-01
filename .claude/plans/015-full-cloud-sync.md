# Plan 015 — Full Cloud Sync (All Data, Local-First)

**Status:** READY — Rubber-duck reviewed; 6 blockers resolved inline
**Author:** System Architect
**Date:** 2026-04-28 (reviewed 2026-04-29)
**Depends on:** Plan 013 (Authentication) ✅ DONE
**Supersedes:** Plan 014 (finance-only scope — absorbed into this plan)

---

## ⚠️ Rubber-Duck Review Findings (all resolved in this plan)

A rubber-duck critique identified 6 blockers before implementation. Each is addressed below:

| # | Blocker | Resolution |
|---|---|---|
| 1 | No local domain timestamps — LWW not implementable | Store `sync_timestamps` JSON in SharedPrefs keyed by `SyncDomain.name` |
| 2 | Pull re-dirties — `save*()` marks dirty during remote apply (ping-pong) | Add `_applyingRemote` flag in `LocalStorageService`; dirty-marking skipped when true |
| 3 | Finance deletes not representable — list-replace loses deleted IDs | Diff old vs new list in each finance `save*()`; enqueue `SyncOp.delete` for removed IDs |
| 4 | Quest ownership leak — `saveState()`/`loadState()` still writes/returns quests | Remove quests from `saveState()` params and `loadState()` return map |
| 5 | Post-pull rehydration — in-memory presenter caches stale after pull | `LocalStorageService` exposes `VoidCallback onRemoteDataApplied`; `home_screen.dart` calls `reloadAll()` |
| 6 | `updatedAt` migration — `DateTime.now()` default corrupts LWW for legacy data | Use `DateTime.fromMillisecondsSinceEpoch(0)` (epoch) as fallback so remote always wins on first sync |

---

## Goal

Sync **all user data** to Supabase so it survives app uninstalls and is accessible across devices — while remaining fully functional offline.

The user never waits for the network. All reads and writes go to `SharedPreferences` first (local-first). Supabase is an eventually-consistent mirror, not a gatekeeper. Conflict resolution is **last-write-wins** via `updatedAt` timestamps.

---

## Data Inventory

| Domain | Storage Pattern | Sync Table |
|---|---|---|
| User stats (XP, level, HP, streaks) | Singleton blob | `user_profile` |
| Fasting state + history | Singleton blob | `user_profile` |
| Quests | List blob | `user_collections` |
| Quest achievements | List blob | `user_collections` |
| Habit routines | List blob | `user_collections` |
| Nutrition goals | Singleton blob | `user_profile` |
| TDEE profile | Singleton blob | `user_profile` |
| Nutrition streaks + dates | Singleton blob | `user_profile` |
| Log streaks + dates | Singleton blob | `user_profile` |
| Activity goals + streaks | Singleton blob | `user_profile` |
| Food library (templates) | List blob | `user_collections` |
| Nutrition daily logs | Time-series (date key) | `nutrition_logs` |
| Chat messages (food log feed) | Time-series (date key) | `nutrition_logs` |
| Activity daily logs | Time-series (date key) | `activity_logs` |
| Finance accounts | Record-level | `finance_records` |
| Finance transactions | Record-level | `finance_records` |
| Finance categories | Record-level | `finance_records` |
| Finance budgets | Record-level | `finance_records` |
| Finance budgeted expenses | Record-level | `finance_records` |
| Finance bills | Record-level | `finance_records` |
| Finance receivables | Record-level | `finance_records` |
| Finance installments | Record-level | `finance_records` |
| Finance monthly summaries | Record-level | `finance_records` |

---

## Architecture: Local-First with Background Sync

```
User action
    │
    ▼
StorageService (abstract interface)
    │
    ├── LocalStorageService (SharedPreferences — always fast)
    │       │
    │       └── after each save*(): marks domain dirty in SyncQueue
    │
    ▼
SyncService (background)
    │  watches connectivity + app lifecycle
    │
    ├── online:   drain SyncQueue → upsert to Supabase
    └── on resume / first sign-in: pull all → merge into local (last-write-wins)
```

**Conflict resolution:**
- `local.updatedAt > remote.updatedAt` → local wins (already newest, no-op on pull)
- `remote.updatedAt > local.updatedAt` → remote wins (overwrite local via `LocalStorageService`)

---

## Affected Files

| File | Action |
|---|---|
| `lib/services/storage_service.dart` | Modify — extract as `abstract class StorageService` |
| `lib/services/local_storage_service.dart` | Create — rename existing impl; add dirty-marking |
| `lib/services/sync_service.dart` | Create — push/pull logic |
| `lib/models/sync_queue_entry.dart` | Create |
| `lib/presenters/sync_presenter.dart` | Create |
| `lib/views/settings_screen.dart` | Modify — add sync status row |
| `lib/views/home_screen.dart` | Modify — wire `SyncService`; inject `LocalStorageService` |
| `pubspec.yaml` | Modify — add `connectivity_plus` |

---

## New Dependencies

```yaml
connectivity_plus: ^6.0.0   # watch online/offline transitions
# supabase_flutter already added by Plan 013
```

---

## Step 1 — Extract StorageService as Abstract Interface

Current `StorageService` becomes `abstract class StorageService` with the same method signatures. The concrete implementation moves to `LocalStorageService extends StorageService` — exact same code, just renamed. No presenter changes needed anywhere (they all receive `StorageService` via constructor).

**One exception** in `fasting_presenter.dart`:
```dart
// Before
_storageService = storage ?? StorageService()
// After
_storageService = storage ?? LocalStorageService()
```

All other call sites (`home_screen.dart`) change:
```dart
// Before
final _storage = StorageService();
// After
final _storage = LocalStorageService();
```

### 1a — Fix Quest Ownership Leak (Blocker #4)

Remove quests from `saveState()` and `loadState()` to eliminate dual ownership with `QuestPresenter`. `QuestPresenter` already calls `saveQuests()`/`loadQuests()` independently — the leak in `saveState()`/`loadState()` is redundant and causes stale data on pull.

```dart
// saveState() — remove quests param and the prefs.setString(keyQuests, ...) line
Future<void> saveState({
  required bool isFasting,
  DateTime? startTime,
  // ... (no quests param)
}) async { ... }

// loadState() — remove quests parsing; return map no longer has 'quests' key
```

Callers of `loadState()` that read `state['quests']` must be updated to call `loadQuests()` separately.

---

## Step 2 — SyncQueue

### Model: `SyncQueueEntry`

```dart
// lib/models/sync_queue_entry.dart

enum SyncOp { upsert, delete }

enum SyncDomain {
  userProfile,      // fasting state, user stats, all goals/streaks
  userCollections,  // quests, achievements, routines, food library
  nutritionLog,     // one entry per date key
  activityLog,      // one entry per date key
  financeRecord,    // one entry per (table, id)
}

class SyncQueueEntry {
  final SyncDomain domain;
  final String key;       // 'default' | 'yyyy-MM-dd' | 'table/recordId'
  final SyncOp op;
  final DateTime queuedAt;
}
```

### SyncMeta — Per-Domain Timestamps (Blocker #1)

`SyncQueue` also manages a `sync_timestamps` map in SharedPrefs — keyed by `SyncDomain.name`, value is ISO-8601 string. Updated whenever a domain is marked dirty (local write time), and updated after a successful pull (remote write time wins).

```dart
// Reading local timestamp for LWW comparison
DateTime localUpdatedAt = _syncQueue.getTimestamp(SyncDomain.nutritionLog, key: '2025-01-15');

// After successful push/pull
_syncQueue.setTimestamp(SyncDomain.nutritionLog, key: '2025-01-15', time: remoteUpdatedAt);
```

### Anti-Dirty-Mark Flag (Blocker #2)

`LocalStorageService` exposes `void applyRemote(Future<void> Function() block)` which sets `_applyingRemote = true`, runs `block()`, then resets to `false`. All `save*()` methods check `if (!_applyingRemote)` before calling `_syncQueue.markDirty(...)`.

```dart
// SyncService calls this during pullAll():
await _storage.applyRemote(() async {
  await _storage.saveNutritionLog(remoteLog);  // won't re-dirty the queue
});
```

### Finance Delete Tracking (Blocker #3)

Each finance `save*(List<T> items)` method diffs the stored list against the new list and enqueues `SyncOp.delete` for any IDs that were removed:

```dart
Future<void> saveAccounts(List<FinancialAccount> accounts) async {
  final existing = await loadAccounts();
  final removedIds = existing.map((e) => e.id).toSet()
      .difference(accounts.map((e) => e.id).toSet());
  // ... write to SharedPrefs ...
  for (final id in removedIds) {
    _syncQueue.markDirty(SyncDomain.financeRecord, 'finance_accounts/$id', op: SyncOp.delete);
  }
  for (final a in accounts) {
    if (!_applyingRemote) {
      _syncQueue.markDirty(SyncDomain.financeRecord, 'finance_accounts/${a.id}');
    }
  }
}
```

### Rehydration Callback (Blocker #5)

`LocalStorageService` has a `VoidCallback? onRemoteDataApplied` field. After `pullAll()` completes, `SyncService` calls this callback. `home_screen.dart` wires it to `reloadAll()` which calls `init()` on each presenter:

```dart
_storage.onRemoteDataApplied = () {
  _fastingPresenter.reloadState();
  _nutritionPresenter.reload();
  _questPresenter.reload();
  // etc.
};
```

```dart
// Example
Future<void> saveUserStats(UserStats stats) async {
  // ... existing SharedPrefs write ...
  _syncQueue.markDirty(SyncDomain.userProfile, 'default');
}

Future<void> saveNutritionLog(DailyNutritionLog log) async {
  // ... existing SharedPrefs write ...
  _syncQueue.markDirty(SyncDomain.nutritionLog, log.dateKey);
}

Future<void> saveAccounts(List<FinancialAccount> accounts) async {
  // ... existing SharedPrefs write ...
  for (final a in accounts) {
    _syncQueue.markDirty(SyncDomain.financeRecord, 'finance_accounts/${a.id}');
  }
}
```

---

## Step 3 — Supabase Schema

### Tables

```sql
-- ── user_profile (one row per user) ─────────────────────────────────────────
-- Stores: fasting state + history, user stats, all goals, all streaks, TDEE
CREATE TABLE user_profile (
  user_id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  data        JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── user_collections (one row per user) ──────────────────────────────────────
-- Stores: quests[], achievements[], routines[], food_library[]
CREATE TABLE user_collections (
  user_id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  data        JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── nutrition_logs (one row per user per date) ────────────────────────────────
-- Stores: DailyNutritionLog + chat messages for that date
CREATE TABLE nutrition_logs (
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        TEXT NOT NULL,          -- 'yyyy-MM-dd'
  data        JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, date)
);

-- ── activity_logs (one row per user per date) ─────────────────────────────────
CREATE TABLE activity_logs (
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        TEXT NOT NULL,
  data        JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, date)
);

-- ── finance_records (one row per user per record) ─────────────────────────────
-- Single table for all 9 finance collections — discriminated by `table_name`
CREATE TABLE finance_records (
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  table_name  TEXT NOT NULL,          -- 'accounts' | 'transactions' | ...
  record_id   TEXT NOT NULL,
  data        JSONB NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, table_name, record_id)
);
```

### Row Level Security (all 5 tables)

```sql
ALTER TABLE user_profile       ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_collections   ENABLE ROW LEVEL SECURITY;
ALTER TABLE nutrition_logs     ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_logs      ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance_records    ENABLE ROW LEVEL SECURITY;

-- Repeat for each table:
CREATE POLICY "user_owns_row" ON user_profile
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
-- (same policy for the other 4 tables)
```

---

## Step 4 — SyncService

```dart
// lib/services/sync_service.dart

class SyncService {
  SyncService({
    required SupabaseClient supabase,
    required LocalStorageService storage,
    required SyncQueue queue,
    required String userId,
  });

  bool get isSyncing;
  DateTime? get lastSyncedAt;
  int get pendingCount;

  Future<void> init();          // subscribe to connectivity; auto-push when back online
  Future<void> pushPending();   // drain SyncQueue → upsert to Supabase
  Future<void> pullAll();       // fetch all user rows → last-write-wins merge into local
  Future<void> forceSync();     // pushPending() then pullAll()
  void dispose();
}
```

### Push Logic (per SyncDomain)

| Domain | Supabase operation |
|---|---|
| `userProfile` | Build profile blob from `loadState()` + `loadUserStats()` + all goals/streaks → `upsert` into `user_profile` |
| `userCollections` | Build collections blob from `loadQuests()` + `loadAchievements()` + `loadRoutines()` + `loadFoodLibrary()` → `upsert` into `user_collections` |
| `nutritionLog` (key=date) | `loadNutritionLogForDate(date)` + `loadChatMessagesRaw(date)` → `upsert` into `nutrition_logs` |
| `activityLog` (key=date) | `loadActivityLogForDate(date)` → `upsert` into `activity_logs` |
| `financeRecord` (key=table/id) | Load full list for that table → find record by id → `upsert` single row into `finance_records` |

Batch upserts in chunks of 100 to stay within Supabase limits.

### Pull Logic (last-write-wins)

1. Fetch all rows for `userId` from each of the 5 tables
2. Compare `remote.updated_at` vs local `updatedAt` (read from local data)
3. If remote is newer → call the corresponding `LocalStorageService.save*()` to overwrite local
4. Notify `SyncPresenter` so UI rebuilds

---

## Step 5 — updatedAt Fields

To enable last-write-wins, a small number of models need an `updatedAt` field. Rather than polluting every model, `updatedAt` is stored **at the blob level** in Supabase, not per-record inside the JSON.

For **singleton and list domains** (`user_profile`, `user_collections`): `SyncService` stamps `updatedAt = DateTime.now()` at push time. No model changes needed.

For **finance records** (which change independently): each finance model gets one new field:

```dart
final DateTime updatedAt;
// fromJson: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now()
// toJson: 'updatedAt': updatedAt.toIso8601String()
// copyWith: includes updatedAt
```

Affected finance models (9 files):
`FinancialAccount`, `TransactionRecord`, `FinanceCategory`, `Budget`,
`BudgetedExpense`, `Bill`, `Receivable`, `Installment`, `MonthlySummary`

All backwards-compatible — old JSON without `updatedAt` defaults to **`DateTime.fromMillisecondsSinceEpoch(0)`** (epoch/1970), NOT `DateTime.now()`. This ensures remote data always wins over uninitialized local data on first sync, rather than local "winning" with a fake timestamp. (Blocker #6 fix)

---

## Step 6 — SyncPresenter

```dart
// lib/presenters/sync_presenter.dart

class SyncPresenter extends ChangeNotifier {
  SyncPresenter(SyncService sync, AuthPresenter auth);

  bool get isSyncing;
  DateTime? get lastSyncedAt;
  int get pendingCount;
  String get statusLabel;  // "Synced", "Syncing…", "3 pending", "Offline", "Sign in to sync"

  Future<void> forceSync();
}
```

Listens to `AuthPresenter` — if user signs out, `statusLabel` shows "Sign in to sync" and sync is suspended.

---

## Step 7 — Settings Screen Addition

Replaces the existing stub Cloud Sync section with a live status row:

```
┌─────────────────────────────────────────────────┐
│  ☁  Cloud Sync                                  │
│     Last synced: 2 minutes ago      [Sync now]  │
│     3 changes pending                           │
└─────────────────────────────────────────────────┘
```

- Reactive via `ListenableBuilder` on `SyncPresenter`
- "Sync now" → `syncPresenter.forceSync()`
- Shows "Sign in to sync" when not authenticated

---

## Step 8 — Home Screen Wiring

```dart
// home_screen.dart changes

// 1. Use LocalStorageService instead of StorageService
final LocalStorageService _storage = LocalStorageService();

// 2. Init SyncService after auth is ready
// In the onFirstSignIn callback (already wired in AuthPresenter):
onFirstSignIn: (userId) {
  _syncService = SyncService(
    supabase: Supabase.instance.client,
    storage: _storage,
    queue: _syncQueue,
    userId: userId,
  );
  _syncPresenter = SyncPresenter(_syncService!, _authPresenter);
  _syncService!.init();         // subscribe to connectivity
  _syncService!.pullAll();      // restore cloud data on first sign-in
}

// 3. On subsequent launches (session already exists):
// In postFrameCallback, after authPresenter.init():
if (_authPresenter.isSignedIn) {
  // init SyncService with restored userId
}
```

---

## Implementation Order

1. [ ] Add `connectivity_plus: ^6.0.0` to `pubspec.yaml` *(already done)*
2. [ ] Extract `StorageService` → `abstract class`; create `LocalStorageService`
   - Fix quest ownership leak (remove quests from `saveState`/`loadState`)
   - Add `_applyingRemote` flag + `applyRemote()` wrapper
   - Add `onRemoteDataApplied` callback field
3. [ ] Update `home_screen.dart` and `fasting_presenter.dart` to use `LocalStorageService`
4. [ ] Create `SyncQueueEntry` model + `SyncQueue` helper (with SyncMeta timestamps)
5. [ ] Add dirty-marking to all `save*()` methods in `LocalStorageService` (with delete diffing for finance)
6. [ ] Add `updatedAt` field (epoch default) to 9 finance models
7. [ ] Run Supabase SQL migration (5 tables + RLS policies) — provide SQL for user to run in dashboard
8. [ ] Implement `SyncService` — `pushPending()` + `pullAll()` with LWW via SyncMeta
9. [ ] Create `SyncPresenter`
10. [ ] Wire `SyncService` in `home_screen.dart` via `onFirstSignIn` + session-restore; wire `reloadAll()` to `onRemoteDataApplied`
11. [ ] Update `SettingsScreen` sync status row
12. [ ] `flutter analyze` — 0 errors
13. [ ] Smoke test: offline write → reconnect → data appears in Supabase dashboard
14. [ ] Smoke test: uninstall + reinstall → sign in → all data restored

---

## RPG Impact

None. Sync is infrastructure — no XP, level, or stat changes.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Large fasting history or transaction list floods Supabase on first push | Batch upserts in chunks of 100 |
| `updatedAt` clock skew between two devices | Supabase uses server-side `now()` as the authoritative timestamp on upsert |
| User clears app data (wipes SharedPrefs) | `pullAll()` on next sign-in restores everything |
| SyncQueue grows unbounded while offline for weeks | Cap at 1000; compact by deduplicating same `(domain, key)` — keep latest op |
| User signs out with pending queue items | Flush `pushPending()` before sign-out; if offline, warn user |
| Non-signed-in users (offline-only) | `SyncService` is never instantiated; app behaves exactly as before |
| `pullAll()` during active fast — overwrites local live state | Pull applies only when `remote.updated_at > local.updated_at`; mid-fast local state is newer so it wins |
| Two devices editing the same finance record simultaneously | Last-write-wins; the device that syncs last wins — acceptable for personal use |
| Supabase free tier pauses after 1 week inactivity | Personal daily use prevents this; documented in README |

---

## Acceptance Criteria

- [ ] Offline write (any domain) queues correctly; SyncQueue count increments
- [ ] Going online drains queue; data visible in Supabase dashboard
- [ ] Uninstall + reinstall + sign in → all data fully restored
- [ ] Remote record newer than local → local is overwritten after `pullAll()`
- [ ] Local record newer than remote → local wins, no overwrite
- [ ] Settings shows correct sync status and pending count reactively
- [ ] "Sync now" triggers push + pull cycle; spinner visible during sync
- [ ] No presenter or view changes required (StorageService interface unchanged)
- [ ] Signing out suspends sync; status shows "Sign in to sync"
- [ ] Mid-fast state is never overwritten by a stale remote snapshot

---

*Implementation order: Plan 013 (Auth) ✅ done → Plan 015 (this plan).*
*Plan 014 is superseded — its finance-only scope is absorbed here.*
