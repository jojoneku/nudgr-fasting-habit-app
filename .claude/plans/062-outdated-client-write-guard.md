# Plan 062 — Stop outdated app builds from overwriting newer finance data

## Incident (2026-10-07)
A Treasury web tab opened on Oct 6 kept running its old code. The code was
older than `TransactionRecord.isInstallment` (#677). The tab read six ShopeePay
purchase records, which dropped the field, and wrote them back as ordinary
records. Then:
- The plans stopped being billed onto the October statement.
- The statement fell from ₱2,424.40 to ₱845.69.
- The edit form lost the installment split.

Data was repaired by hand. #700 makes the app restore that one flag itself.

## Why existing protection did not catch it
The sync conflict rule (`cloudCopyWins`) stops an *old queued edit* from
overwriting a *newer cloud row*. It compares edit times. The outdated tab made
a *fresh* edit with a current timestamp, so it won. Nothing compares the *code
version* that wrote a row. An old build drops every field it does not know.

## Proposal (3 parts, one PR each)

### A. Server-side write guard (the real safeguard)
1. **Constant:** add `kFinanceDataVersion` (an int) to the app. Raise it whenever
   a finance model gains a field that an older build would drop. Start at 1.
2. **Column:** every finance upsert and tombstone writes `data_version` in a new
   `finance_records.data_version int` column.
3. **Trigger:** a `BEFORE UPDATE` trigger on `finance_records` rejects an update
   when `coalesce(NEW.data_version, 0) < coalesce(OLD.data_version, 0)`.
   - An outdated build sends no `data_version` (0), so it can never overwrite a
     row that a current build wrote.
   - Inserts of new rows stay allowed.
4. **Rejected pushes:** the client treats a rejected push like `conflictLost`.
   It drops the push and pulls the row again. The client logs it and shows
   "This app is out of date — update to sync" once.
5. **Migration:** it is manual, as for every DB migration (see
   `project_deploy_workflow`). Ship the app part first, so that current builds
   already send `data_version` before the trigger goes live.

### B. Web: reload an outdated tab
1. **Check:** Flutter web publishes `version.json` with each deploy. On window
   focus, and every 10 minutes, fetch it with no cache and compare it with the
   build the tab is running.
2. **If newer:**
   - Pause sync pushes.
   - Show a banner: "A new version is ready — reload to keep syncing".
   - Reload automatically when no sheet or dialog is open.
3. **Effect:** an outdated tab stops writing right away, even before A is live.

### C. Keep unknown fields (forward compatibility)
1. **Change:** finance models keep the JSON keys they do not recognise in
   `fromJson` and write them back in `toJson`.
2. **Effect:** a build released after this change never strips a field that a
   later build adds.
3. **Limit:** this does not protect against builds released before it, which
   is why A is needed.

## Order
B first (small, app-only, fixes the exact case). Then A (needs the manual
migration). C is optional hardening.

## Tests
- **A:** a push from a client without `data_version` onto a row written at
  version 1 is rejected, and the client recovers by pulling. Trigger SQL is
  covered by a migration test script.
- **B:** a newer `version.json` pauses pushes and shows the banner. The same
  build does nothing.
- **C:** a record with an unknown key keeps that key after
  `fromJson` → `toJson`.
