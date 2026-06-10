# Data Export Spec — CSV + JSON Archive

> Status: PLANNED — NOT IMPLEMENTED · June 10, 2026 · Owner: Settings / Data
> Plan: [.claude/plans/044-data-export.md](../.claude/plans/044-data-export.md)
> Related: `StorageService`, `LocalStorageService`, `settings_screen.dart` Data section

## 1. Problem

All user data lives in SharedPreferences (+ Supabase mirror) with no real user-facing export.

What exists today (verified — do not rebuild blindly):
- `StorageService.exportAllData()` / `importAllData()` (`local_storage_service.dart:1578`) — a raw
  prefs dump: `{key: rawJsonString}` for the current user's scoped keys, double-encoded and
  unreadable outside the app.
- Settings → Data → "Export Data" (`settings_screen.dart:389`) surfaces that dump in a **dialog
  with copy-to-clipboard** via `FastingPresenter.exportData()`. Import is paste-from-clipboard.
- ⚠️ Wart: with no signed-in user, `exportAllData()` dumps **every** prefs key — including
  device-level keys and other users' `u/<id>/` scoped data.
- **No file-handling/share deps**: `pubspec.yaml` has `path_provider` and `http`, but **no
  `share_plus`**, no `csv`, no `dio`, no `open_file_plus`. `share_plus` must be added.

A clipboard JSON blob is not portability: it can't open in a spreadsheet, breaks on large
histories, and gives no peace of mind.

## 2. Goals

1. Settings → **Export Data** sheet with two products:
   - **CSV per domain** — spreadsheet-ready files shared via the Android share sheet.
   - **JSON archive** — one structured, human-readable file re-serialized from model `toJson`
     (not the raw prefs dump): `{meta: {app, version, exportedAt, schema}, domains: {...}}`.
2. Pure-I/O **`ExportService`**; thin presenter; zero logic in views.
3. Share-sheet first (`share_plus.shareXFiles`) — covers Drive, Files ("Save to device"), email.
4. Guest mode exports correctly (typed load methods are namespace-safe, unlike the raw dump).

### Non-goals (future work)
- **Import/restore from files** — explicitly out of scope; the existing clipboard import stays
  as-is. File-based restore is a follow-up (needs schema versioning + merge strategy).
- Food **photos** (file-based thumbnails) and AI **chat transcripts**.
- Scheduled/automatic backups; direct cloud uploads.
- Zip bundling (share multiple files in v1; `archive` package noted as a later nicety).

## 3. Export domains & CSV schemas

One file per domain, loaded through existing typed `StorageService` methods (all verified to
exist; every exported model already has `toJson`). Header row always present; empty domains are
skipped (and listed as "nothing to export" in the result toast).

| File | Source | Columns (order fixed) |
|---|---|---|
| `transactions.csv` | `loadTransactions()` | id, date, account_id, account_name, category_id, category_name, type, amount, description, note, transfer_group_id, bill_id, receivable_id, installment_id |
| `accounts.csv` | `loadAccounts()` | id, name, category, role, parent_account_id, balance, held_amount, credit_limit, archived |
| `bills.csv` | `loadBills()` | id, name, type, amount, due_day, is_paid, linked_account_id |
| `receivables.csv` | `loadReceivables()` | id, person, amount, due_date, is_settled, note |
| `budgets.csv` | `loadBudgets()` + `loadBudgetedExpenses()` | budget_id, name, month, limit, expense_id, expense_name, expense_amount |
| `installments.csv` | `loadInstallments()` | id, name, total, monthly, months_paid, months_total, next_due |
| `nutrition_log.csv` | `loadNutritionHistory()` | date, meal_slot, entry_id, name, grams, calories, protein_g, carbs_g, fat_g, estimation_source, confidence, logged_at |
| `weight_log.csv` | `loadWeightLog()` | id, logged_at, weight_kg |
| `body_measurements.csv` | `loadBodyMeasurements()` | id, logged_at, waist_cm, neck_cm, hips_cm, chest_cm, bicep_cm, thigh_cm, notes |
| `fasting_history.csv` | `loadState()['history']` (`FastingLog`) | fast_start, fast_end, fast_duration_h, goal_duration_h, success, eating_start, eating_end, eating_duration_h, note |
| `quests.csv` | `loadQuests()` + `loadRoutines()` + `loadAchievements()` | kind, id, title, schedule, is_enabled, detail |
| `activity_log.csv` | `loadActivityHistory()` | date, steps, active_minutes, source |
| `stats.csv` | `loadUserStats()` | level, xp, hp, streaks… (single row) |

Account/category **names are denormalized** into `transactions.csv` (ids alone are useless in a
spreadsheet); ids are kept for joinability. Exact nullable columns are finalized against the model
fields at implementation time — the schema above is the contract shape, not a frozen column list.

### Formatting rules
- **Amounts:** raw decimals, dot separator, **no ₱ symbol, no thousands separators** (`1523.5`).
- **Dates/times:** ISO 8601 as stored (`toIso8601String()`); date-only fields stay `yyyy-MM-dd`.
- **Encoding:** RFC 4180 — UTF-8, CRLF row endings, quote fields containing `,` `"` or newlines,
  double embedded quotes. Notes/descriptions are free text and **will** contain commas.
- **Booleans:** `true`/`false`. **Null:** empty cell.
- File names: `nudgr_<domain>_<yyyy-MM-dd>.csv`; archive: `nudgr_archive_<yyyy-MM-dd>.json`.

## 4. Architecture

| Layer | Piece |
|---|---|
| Utils | `lib/utils/csv_encoder.dart` — pure functions: `encodeCsvRow`, `encodeCsv(headers, rows)`. No package needed; RFC 4180 is ~20 lines. Fully unit-tested. |
| Service | `lib/services/export_service.dart` — pure I/O. Loads domains via injected `StorageService`, builds CSV/JSON strings, writes to `getTemporaryDirectory()/export/`, invokes `Share.shareXFiles`. Cleans up stale temp exports on each run. |
| Presenter | `lib/presenters/export_presenter.dart` — `isExporting`, per-domain selection, `error`, `lastResult`; delegates everything to the service. Constructor injection. |
| View | Export sheet under Settings → Data (replaces the clipboard dialog as the primary entry; clipboard JSON moves to an "Advanced" row, since import is still clipboard-based). `AppBottomSheet` + system widgets, theme-aware colors, targets ≥44px. |

```dart
// === ExportService (sketch) ===
class ExportService {
  ExportService({required StorageService storage});
  Future<ExportResult> exportCsv(Set<ExportDomain> domains);  // writes files + share sheet
  Future<ExportResult> exportJsonArchive();                   // single structured .json
}
// ExportResult: files written, rows per domain, skipped-empty domains.
```

No new `StorageService` methods are required — every domain already has a typed `load*()`.
No sync impact (export is read-only). New dependency: **`share_plus`** only.

### "Export to Downloads" fallback
The share sheet already offers "Save to device" via the Files app, which covers the requirement
without storage permissions. A direct MediaStore Downloads write (no permission needed on
API 29+) is noted as **optional future work** — it needs a platform channel or extra plugin and
is not worth the surface in v1.

## 5. Acceptance criteria

1. Settings → Export Data offers "Spreadsheet (CSV)" and "Archive (JSON)"; both end in the
   Android share sheet with correctly named, openable files.
2. `transactions.csv` opens in Google Sheets/Excel with intact columns despite commas, quotes,
   and newlines in descriptions/notes; amounts are raw decimals (no `₱`), dates ISO 8601.
3. Every domain in §3 exports; row counts match in-app data; empty domains are skipped and
   reported, never written as header-only mystery files.
4. JSON archive parses with `jsonDecode`, contains `meta.schema` + per-domain arrays of model
   `toJson` maps (no double-encoded strings).
5. Works signed-in **and** in guest mode; a guest export never includes another user's data.
6. Export of a large history (≥1 year of transactions + nutrition) completes without jank
   (service work off the build path; progress state on the presenter).
7. Existing clipboard export/import still functions (moved, not removed).
8. `flutter analyze` + `dart format` clean; unit tests for the CSV encoder, service, presenter.

## 6. Test plan

- `csv_encoder_test`: quoting, embedded quotes/commas/newlines, CRLF, unicode (₱ in notes stays
  literal text — only *amount* columns are symbol-free), null → empty.
- `export_service_test`: per-domain CSV golden strings from fixture models; JSON archive shape;
  empty-domain skip; temp-dir cleanup (mock `StorageService`, fake path provider).
- `export_presenter_test`: selection state, isExporting lifecycle, error surfacing.
- Manual: share to Drive + "Save to device"; open CSVs in Sheets; guest-mode export; both themes.
