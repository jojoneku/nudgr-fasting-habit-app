# Plan 013 — Supabase Sync (Local-First)
**Status:** DRAFT — Awaiting Approval
**Phase:** 1 of 1
**Depends on:** Plan 014 (Authentication) — `userId` required to scope Supabase data

---

## Goal

Keep all finance data synced to Supabase so it survives app uninstalls, phone changes, and is accessible across devices — while remaining fully functional offline.

The user never waits for the network. All reads and writes go to SharedPreferences first. Supabase is an eventually-consistent mirror, not a gatekeeper.

---

## Architecture: Local-First with Background Sync

```
User action
    │
    ▼
SharedPreferencesStorageService   ← primary read/write (always works)
    │
    ├─► mark record dirty in SyncQueue
    │
    ▼
SyncService (background)
    │  watches connectivity
    │
    ├─► online:  drain SyncQueue → upsert to Supabase
    └─► on resume: pull latest from Supabase → merge into local (last-write-wins)
```

**Conflict resolution:** last-write-wins via `updatedAt` timestamp.
If local `updatedAt` > remote → local wins (already pushed).
If remote `updatedAt` > local → remote wins (pull and overwrite local).

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/services/storage_service.dart` | Modify → extract abstract interface | Service |
| `lib/services/local_storage_service.dart` | Create → rename/move existing impl | Service |
| `lib/services/sync_service.dart` | Create | Service |
| `lib/models/sync_queue_entry.dart` | Create | Model |
| `lib/presenters/sync_presenter.dart` | Create | Presenter |
| `lib/views/settings_screen.dart` | Modify — add sync status indicator | View |
| `lib/views/home_screen.dart` | Modify — wire SyncService | Wiring |
| `pubspec.yaml` | Modify — add supabase_flutter, connectivity_plus | — |

---

## New Dependencies

```yaml
supabase_flutter: ^2.0.0   # already added by Plan 014
connectivity_plus: ^6.0.0  # watch online/offline state
```

---

## StorageService → Abstract Interface

Current `StorageService` becomes an abstract class. Existing implementation moves to `LocalStorageService`.

```dart
// lib/services/storage_service.dart — now abstract
abstract class StorageService {
  // All existing method signatures unchanged — no presenter changes needed
  Future<void> saveAccounts(List<FinancialAccount> accounts);
  Future<List<FinancialAccount>> loadAccounts();
  // ... all existing methods ...
  Future<String> exportAllData();
  Future<void> importAllData(String jsonString);
}

// lib/services/local_storage_service.dart
class LocalStorageService extends StorageService {
  // Exact copy of current StorageService implementation
  // + after every finance save*() call: _syncQueue.markDirty(table, id, SyncOp.upsert)
}
```

**Impact on existing code:** only `AppShell` instantiates `StorageService()` directly (1 line in `home_screen.dart`). All presenters receive it via constructor — zero changes to presenters or views.

One exception — `fasting_presenter.dart` has a fallback default:
```dart
StorageService? storage, ... : _storageService = storage ?? StorageService()
```
This becomes `storage ?? LocalStorageService()`.

---

## Model: `SyncQueueEntry`

```dart
enum SyncOp { upsert, delete }

class SyncQueueEntry {
  final String table;   // 'finance_accounts' | 'finance_transactions' | ...
  final String id;      // record id
  final SyncOp op;      // upsert | delete
  final DateTime queuedAt;
}
```

Persisted as a JSON array under SharedPreferences key `sync_queue`. Survives app restarts — if offline, queue accumulates and drains when connectivity returns.

---

## Supabase Schema

One table per finance entity. JSONB column stores the full record — no field-by-field column mapping needed.

```sql
-- Repeated for each of the 8 finance tables
CREATE TABLE finance_accounts (
  id          TEXT NOT NULL,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  data        JSONB NOT NULL,           -- full model JSON
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (id, user_id)
);

-- Row-level security: users only see their own rows
ALTER TABLE finance_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_owns_row" ON finance_accounts
  USING (user_id = auth.uid());
```

Tables: `finance_accounts`, `finance_transactions`, `finance_categories`,
`finance_budgets`, `finance_budgeted_expenses`, `finance_bills`,
`finance_receivables`, `finance_monthly_summaries`

---

## SyncService Interface

```dart
class SyncService {
  SyncService(SupabaseClient supabase, LocalStorageService storage, String userId);

  bool get isSyncing;
  DateTime? get lastSyncedAt;
  int get pendingCount;          // entries in SyncQueue

  Future<void> init();           // subscribe to connectivity changes
  Future<void> pushPending();    // drain SyncQueue → upsert/delete in Supabase
  Future<void> pullAll();        // fetch all user rows → merge into local (last-write-wins)
  Future<void> forcSync();       // pushPending() then pullAll()
  void dispose();
}
```

**`pullAll()` merge logic (last-write-wins):**
1. Fetch all rows for `userId` from each table
2. For each remote row: parse `updated_at`
3. Compare against local record's `updatedAt` (stored in the JSON `data` field)
4. If remote is newer → overwrite local via `LocalStorageService.save*()`
5. `notifyListeners()` so presenters reload

**Note:** finance models don't currently have `updatedAt`. They need it added — see Model Changes below.

---

## Model Changes: Add `updatedAt`

All 8 finance models get one new field:

```dart
final DateTime updatedAt; // set on create/update, used for conflict resolution
```

`fromJson`: `updatedAt = DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now()`
`toJson`: `'updatedAt': updatedAt.toIso8601String()`
`copyWith`: includes `updatedAt`

This is backwards-compatible — old JSON without `updatedAt` defaults to `DateTime.now()`.

---

## SyncPresenter Interface

```dart
class SyncPresenter extends ChangeNotifier {
  SyncPresenter(SyncService sync);

  bool get isSyncing;
  DateTime? get lastSyncedAt;
  int get pendingCount;
  String get statusLabel;   // "Synced", "Syncing...", "3 pending", "Offline"

  Future<void> forceSync();
}
```

---

## Settings Screen Addition

A small sync status row added to the existing `SettingsScreen`:

```
┌─────────────────────────────────────────────┐
│  Cloud Sync                                 │
│  Last synced: 2 minutes ago    [Sync now]   │
│  3 changes pending                          │
└─────────────────────────────────────────────┘
```

- "Sync now" button → `syncPresenter.forceSync()`
- Status updates reactively via `ListenableBuilder`

---

## Implementation Order

1. [ ] Add `updatedAt` to all 8 finance models (backwards-compatible)
2. [ ] Create `SyncQueueEntry` model
3. [ ] Extract `StorageService` abstract interface; rename impl to `LocalStorageService`
4. [ ] Add `SyncQueue` dirty-marking to all `save*()` finance methods in `LocalStorageService`
5. [ ] Create Supabase tables + RLS policies (SQL migration)
6. [ ] Implement `SyncService` — `pushPending()` and `pullAll()`
7. [ ] Create `SyncPresenter`
8. [ ] Wire `SyncService` into `AppShell` (after auth — requires `userId`)
9. [ ] Add sync status row to `SettingsScreen`
10. [ ] Hook `pullAll()` on first sign-in (via Plan 014's `onFirstSignIn` callback)

---

## RPG Impact

None. Sync is infrastructure — no XP or stat changes.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Large transaction list (500+ rows) floods Supabase on first push | Batch upserts in chunks of 100 |
| Supabase free tier pauses after 1 week inactivity | Personal daily use prevents this; document in README |
| Remote delete vs local edit conflict | Deletes win — if a record is deleted remotely, remove locally too |
| `updatedAt` clock skew between devices | Use server-side `now()` on Supabase upsert as the authoritative timestamp |
| User clears app data (wipes SharedPreferences) | `pullAll()` on next sign-in restores everything from Supabase |
| Non-finance data (fasting logs, quests, stats) | Out of scope — sync finance only in Phase 1 |
| SyncQueue grows unbounded while offline | Cap at 1000 entries; compact by deduplicating same-id entries (keep latest) |

---

## Acceptance Criteria

- [ ] Writing a transaction offline adds it to SyncQueue
- [ ] Going online drains SyncQueue and upserts to Supabase
- [ ] Uninstalling and reinstalling the app restores all finance data after sign-in
- [ ] Remote record newer than local → local is overwritten after `pullAll()`
- [ ] Local record newer than remote → local wins, no overwrite
- [ ] Settings screen shows correct sync status and pending count
- [ ] "Sync now" triggers a full push + pull cycle
- [ ] No presenter or view changes required (StorageService interface unchanged)
- [ ] All existing 142 tests continue to pass (LocalStorageService is a drop-in)

---

*Present this plan for approval before writing any code.*
*Implementation order: Plan 014 (Auth) first → Plan 013 (Sync).*
