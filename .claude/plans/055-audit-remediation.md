# Plan 055 — Audit Remediation (2026-07-04 Five-Dimension Audit)

**Source:** [docs/audit_report_2026-07-04.md](../../docs/audit_report_2026-07-04.md)
**Scope:** The 5 high + top medium findings, split into per-feature PRs per repo convention (one PR per feature, all targeting `dev`). Lower-severity findings are batched into follow-up waves at the end.

## Goal

Close the audit's data-integrity and security holes before they cost real user data. The two sync findings can silently destroy edits today (multi-device LWW clobbering + queue eviction); the Lambda logs a live JWT; two finance flows corrupt or block data (mobile pocket orphaning, web statement bills unpayable). Secondary goal: stop the XP economy being farmable — the RPG loop's integrity is the product's core motivator.

## PR Order & Dependency

Wave 1 (independent, can be parallel): PR-1, PR-2, PR-3, PR-4
Wave 2: PR-5 … PR-8 (independent of wave 1 and of each other)
Wave 3: batched med/low cleanups

---

## PR-1 · `fix/sync-diff-dirty-marking` — Sync integrity (audit #1 + #2) — **FIRST**

### Problem
`LocalStorageService.saveTransactions` (and sibling finance saves) call `markDirty` for **every** record on every save (`local_storage_service.dart:1007`). Consequences:
1. `markDirty` bumps the per-record LWW timestamp to `now` (`sync_queue.dart:79`), so after any local save, `pull` sees local-newer for *all* records and discards every remote edit from other devices.
2. `SyncQueue._maxEntries = 1000` silently evicts the oldest marks (`sync_queue.dart:76`) — past 1000 finance rows, an edit to an older row is evicted before push *and* (timestamp already bumped) refuses the remote copy on pull. Permanently stranded; lost on sign-out.
3. `markDirty`'s `removeWhere` over a 1000-entry list per record × n records per save = O(n²) main-isolate churn.

### Approach
**Diff at the storage layer** (presenters keep passing full lists — no call-site changes):
- `TransactionRecord`/`FinancialAccount` are immutable (final fields + `copyWith`), so extend the existing id-cache pattern to full object caches: `Map<String, TransactionRecord> _cachedTransactionsById` (refs to the same objects the presenter holds — no meaningful memory cost), populated in `loadTransactions`/`saveTransactions`.
- Per row on save: not in cache → dirty (new); `identical(cached, t)` → skip (the common case for unedited rows); otherwise compare `jsonEncode(old.toJson()) == jsonEncode(new.toJson())` → skip if equal, dirty if changed. Deletes keep the existing id-set difference.
- Apply the same pattern to all finance saves that currently mark-all: `saveAccounts`, `saveFinanceCategories`, `saveBills`, `saveReceivables`, `saveInstallments` (each currently also does a full `load` just to diff ids — the object cache removes that too, closing scalability finding `local_storage_service.dart:1041`).

**Make the queue safe and O(1):**
- Back `SyncQueue` with `Map<String /*domain::key*/, SyncQueueEntry>` instead of `List` — `markDirty` and `removeEntries` become O(1); closes scalability med `sync_queue.dart:69`.
- **Remove the 1000-entry cap** (no silent eviction, ever). With diff-based marking the queue holds only genuinely-dirty records; a large offline backlog is exactly what must survive. `entries` getter keeps returning a stable list for `SyncService`.

### Affected Files
| File | Action | Layer |
|---|---|---|
| `lib/services/local_storage_service.dart` | Modify (diff-based marking, object caches) | Service |
| `lib/services/sync_queue.dart` | Modify (Map-backed, cap removed) | Service |
| `test/services/sync_queue_test.dart` + new storage diff tests | Create/Modify | Test |

### Interface Definitions
```dart
// SyncQueue — public API unchanged (markDirty, removeEntries, entries,
// getTimestamp, setTimestamp, clear, clearAll, load). Internal:
final Map<String, SyncQueueEntry> _entryByKey = {}; // 'domain::key' → entry
// _maxEntries deleted.

// LocalStorageService — internal only:
Map<String, TransactionRecord>? _cachedTransactionsById;
Map<String, FinancialAccount>? _cachedAccountsById;
// ... same for categories/bills/receivables/installments
bool _sameJson(Object a, Object b); // jsonEncode equality fallback
```

### Risks & Edge Cases
- **First save after boot:** caches are populated by the initial `load*` calls (every presenter loads before saving), so the first save diffs correctly. If a save ever lands before a load (cache null), fall back to the current mark-all behavior *once* — correct, just not optimal.
- **`_applyingRemote` guard must stay** — remote-applied saves still must not mark dirty.
- **Do not change timestamp semantics on pull** — `setTimestamp(remoteTime)` on accept stays as-is; this PR only stops *unchanged* records from getting fake-fresh local timestamps.
- **Queue persistence format:** keep the same JSON list shape on disk so an old queue restores into the new Map (key collision = keep latest `queuedAt`, matching today's dedupe).
- Existing users already have inflated timestamps; that heals naturally (next genuine remote edit wins once local stops re-bumping).

### Acceptance Criteria
- [ ] Editing 1 transaction in a 5k-row ledger enqueues exactly 1 upsert (plus deletes if any), verified by unit test.
- [ ] Pull after an unrelated local save applies a newer remote edit (LWW no longer clobbered) — service-level test with fake queue timestamps.
- [ ] No eviction path exists; 2k dirty records all survive load→persist round-trip.
- [ ] `flutter test` green; `dart format` clean.

---

## PR-2 · `fix/lambda-event-logging` — Lambda logs live JWT + PII (audit #3)

### Problem
`backend/ai-coach/lambda_function.py:94` — unconditional `print(json.dumps(event))` writes the `Authorization` header (replayable Supabase access token), chat text, base64 food photos, and finance-classifier prompts to CloudWatch on every invocation.

### Approach
- Delete the full-event dump. Replace with a structured one-liner: route/intent, userId (already extracted post-auth), payload byte size, and duration — no headers, no bodies.
- Sweep the rest of the handler for other `print`s of request/response bodies; gate any genuinely useful ones behind a `DEBUG_LOGGING` env var that defaults off (and still redacts `Authorization`).
- Also fold in the adjacent low: make the Bedrock daily-cap limiter **fail closed** (`lambda_function.py:88`) — on Supabase/transport error, deny with a retryable message instead of silently waiving the only billing guard. Same file, same deploy unit; splitting it would be ceremony.
- **Manual follow-up (not in the PR, flag in description):** set CloudWatch log-group retention short (e.g. 1 day) and delete existing log streams — historical logs already contain tokens; Supabase access tokens are short-lived, but old PII persists until purged. Deploy is automatic on `main` per CI (memory: deploy workflow).

### Acceptance Criteria
- [ ] No code path logs headers or request/response bodies with `DEBUG_LOGGING` unset.
- [ ] Rate limiter denies (429-style body) when its Supabase check fails.
- [ ] Existing Lambda tests (if any) pass; manual smoke: photo log + chat still work in prod after deploy.

---

## PR-3 · `fix/mobile-account-edit-parent-id` — Pocket orphaning on mobile edit (audit #4)

### Problem
`lib/views/treasury/shared/account_setup_view.dart:188` — `_submit` builds the edited account with `parentAccountId: widget.parentAccountId`, which is null when a pocket is opened from anywhere but its parent's sub-account list. Saving detaches the pocket while the parent balance still includes it → double-counted in `totalAssets`/net worth. Web already fixed this exact bug (Plan 052 C1, `_effectiveParentId`).

### Approach
Back-port the web fix: when editing, preserve the existing linkage.
```dart
parentAccountId: widget.existing?.parentAccountId ?? widget.parentAccountId,
```
Mirror web's `_effectiveParentId` getter naming for consistency. Audit whether the same form loses `linkedAccountId`-adjacent fields the same way (it already preserves `icon` via the C5 pattern — follow that precedent).

### Acceptance Criteria
- [ ] Widget test: open an existing sub-account with `parentAccountId: null` passed in, save unchanged → record retains its original `parentAccountId`.
- [ ] Creating a new sub-account from the parent flow still sets the parent id.
- [ ] Manual: dashboard net worth unchanged after editing a pocket from the Goals section.

---

## PR-4 · `fix/web-bills-statement-payer` — Credit-card statement bills unpayable on web (audit #5)

### Problem
`lib/views/web/pages/bills/web_bills_page.dart:1053` — web mark-paid passes the bill's own `accountId` (the liability account for auto-generated statements) as payer; `markBillPaid` throws `ArgumentError`, the Future is discarded, and the bill silently stays unpaid.

### Approach
- Use the presenter's existing `payerAccountsFor(bill)` (mobile's path) to pick the payer: default to the first eligible account but show the picker dialog web already has patterns for (`web_searchable_dropdown`).
- `await` the call inside try/catch and surface failures via the web toast/snackbar pattern — no more discarded Futures.
- Same treatment for mark-received if it shares the discard pattern (`web_bills_page.dart:1111` notes full-amount/today only — *scope that parity gap out*; this PR is only "statement bills can be paid and errors are visible").

### Acceptance Criteria
- [ ] A credit-card statement bill can be marked paid on web against a chosen liquid account; the payment transaction lands with correct payer.
- [ ] A thrown `ArgumentError` (forced in test) surfaces a visible error instead of vanishing.
- [ ] Regular (non-statement) bill mark-paid unchanged.

---

## PR-5 · `fix/activity-day-rollover` — Activity data overwrites yesterday (audit #6)

`lib/presenters/activity_presenter.dart:183` — no rollover guard on `_todayLog`; overnight resume writes today's Health Connect totals under yesterday's key (and syncs the corruption). NutritionPresenter already solved this with `_ensureTodayLogFresh`.

**Approach:** replicate the `_ensureTodayLogFresh` pattern: before any `_todayLog` write, compare its date key to `DateTime.now()`'s; on mismatch, persist the old log untouched and start a fresh one. Also fix the sibling med (`activity_presenter.dart:359`): reset the activity streak on a missed day (copy NutritionPresenter's reset pattern) so "+1 AGI per 5 consecutive days" means consecutive.

**Acceptance:** unit test with injected clock crossing midnight — yesterday's totals survive; streak resets after a gap day. (These two share one presenter and one root theme, but if review prefers, the streak fix splits cleanly into its own PR.)

---

## PR-6 · `fix/web-ledger-inline-edit-category` — Type flip keeps stale category (audit #7)

`lib/views/web/pages/ledger/web_ledger_page.dart:348` — inline amount edit that flips outflow→inflow keeps the expense category, creating rows excluded from every aggregation. Mobile and the web *modal* both clear category on type change.

**Approach:** on type flip in the inline editor, clear `categoryId` (match the modal's behavior) and visually flag the row as needing a category. Also close the adjacent med at `:409`: draft add-row must require explicit category + account (reuse the modal's validation) instead of silently stamping firsts.

**Acceptance:** widget test — inline type flip produces a row with null category, not an expense-categorized income; draft add without category is rejected with visible validation.

---

## PR-7 · `fix/dashboard-custodian-kpis` — Unlinked custodians understate KPIs (audit #8)

`lib/presenters/treasury_dashboard_presenter.dart:182` — `totalLiquidCash`/`netWorth` subtract *unlinked* custodian balances that were never added to the asset base; `heldAmountByAccountId` counts only linked custodians, so KPIs disagree with the rows beneath them.

**Approach:** subtract only custodians whose `linkedAccountId` resolves to a counted asset account (align with `heldAmountByAccountId`'s definition — one shared helper in the presenter, per the account model rule "yours = balance − held").

**Acceptance:** presenter unit tests: unlinked custodian leaves totals unchanged; linked custodian subtracts exactly once; dashboard held-funds rows sum to the KPI deduction.

---

## PR-8 · `fix/xp-award-ledger` — Farmable XP economy (audit theme)

Four independent unguarded award paths: quest toggle streak inflation (`quest_presenter.dart:198`), all-bills-paid +50 re-awardable (`bills_receivables_presenter.dart:554`), installment unpay/re-pay +70 loop (`installment_presenter.dart:178`), activity streak on non-consecutive days (moved to PR-5). BudgetPresenter already proved the fix: a persisted per-period award key.

**Approach:** extract BudgetPresenter's guard into a small shared service-backed helper, then apply per path:
```dart
// lib/services/award_ledger.dart (backed by StorageService, new key)
class AwardLedger {
  Future<bool> tryAward(String awardKey); // e.g. 'billsAllPaid/2026-07' — false if already granted
}
```
- Quest toggle-off decrements `streakCount` symmetrically (and grace-day XP keys use the quest's *due date*, fixing `_xpAwardedToday` at `:215`).
- Bills +50 and installment +50/+20 awards go through `tryAward` keyed by month; `markUnpaid` never refunds (award stays burned — simplest non-exploitable rule).

**RPG Impact:** XP totals become monotonic and honest; streak-linked stat awards (21-day AGI/STR) no longer farmable. No new notifications.

**Acceptance:** unit tests — complete→untick→complete nets zero extra streak/XP; pay→unpay→pay awards once per month; persisted across restart (StorageService round-trip).

---

## Wave 3 — Batched follow-ups (separate PRs, lower urgency)

1. `chore/remove-data-backup-dump` (audit #9): `git rm -r nudgr_data_backup/` + gitignore. **Note:** history stays public — decide whether the exposure (activity telemetry, meal logs, no identity/secrets) warrants a history rewrite; recommend no rewrite, just removal, given prior audit's exposure assessment.
2. `fix/weight-log-sort` (audit #10): sort weight log by date on insert (`nutrition_presenter.dart:664`), mirroring `logMeasurement`.
3. `refactor/daily-net-presenter-getter`: move the ledger daily-net badge fold into `LedgerPresenter` with transfer + reimbursable exclusions (consistency med, three dimensions flagged it).
4. `refactor/savings-contribution-helper`: one shared savings-contribution function replacing the 3 hand-synced copies (dashboard/history/budget).
5. Remaining web parity lows (recurring toggle, partial payments, set-aside picker, thresholds) — fold into the existing Treasury web backlog rather than new one-off PRs.
6. Scalability meds (`_notifyDependents` double-decode, 4× boot decode, dashboard 21-scan card) — schedule with the deferred web-virtualization backlog from the 2026-06-23 audit.

---

## Global Risks
- PR-1 touches the sync spine — land it alone, soak it on a real device pair (phone + web) before stacking wave 2, since every later finance PR writes through it.
- All PRs target `dev`, one branch each, `dart format` before push, conventional commits (repo rules).

## Acceptance (plan-level)
- [ ] All 5 high findings closed by PRs 1–4.
- [ ] Ranks 6–8 + XP farming closed by PRs 5–8.
- [ ] Wave 3 items ticketed/planned, not silently dropped.
