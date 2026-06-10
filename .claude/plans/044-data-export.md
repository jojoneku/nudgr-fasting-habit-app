# Plan 044 — Data Export (CSV + JSON Archive)

> Status: PLANNED — NOT IMPLEMENTED · June 10, 2026
> Spec: [docs/data_export_spec.md](../../docs/data_export_spec.md)
> Branch: **`feat/044-data-export`** off `dev`. Own PR, `--base dev` (never bundle with 043).

## Goal
Replace the clipboard-JSON-blob "export" with real portability: per-domain CSV files
(transactions, bills, budgets, accounts, nutrition log, weight, body measurements, fasting
history, quests, activity, stats) and a structured single-file JSON archive, delivered through
the Android share sheet. Read-only, no business logic in views, no sync impact.

## Key findings (verified — shapes the plan)
- **An export/import path already exists**: `StorageService.exportAllData()/importAllData()`
  (`local_storage_service.dart:1578/1599`), surfaced via `FastingPresenter.exportData()` and a
  clipboard dialog in `settings_screen.dart:389` (`_dataSection`). It's a raw prefs dump
  (double-encoded, spreadsheet-hostile). We **keep it** (import depends on it) but demote it to
  an "Advanced" row — this plan does not modify those methods.
- Guest-mode wart in the old path: with `_userId == null` it dumps **all** prefs keys, including
  other users' scoped data. The new `ExportService` avoids this by construction — typed
  `load*()` methods are namespace-aware.
- **`share_plus` is NOT in pubspec** (checked); `path_provider` is. No `csv`/`dio`/`open_file_plus`
  either. Only new dep needed: `share_plus`. CSV encoding is hand-rolled (RFC 4180, ~20 lines,
  pure util) — no package.
- Every export domain already has a typed `StorageService` load method and model `toJson`
  (fasting history rides `loadState()['history']` as `List<FastingLog>`). **No storage interface
  changes required.**

## Conflict Check

| Check | Finding |
|---|---|
| **File overlap** | `settings_screen.dart` — **Plan 043 also adds a tile** there; merge 043 first (or rebase). No other plan touches the new files. |
| **Model overlap** | None — zero model changes; export reads existing `toJson`. |
| **StorageService keys** | None new. |
| **XP routing** | N/A — export awards nothing. |
| **HubScreen** | Untouched. |
| **Supersedes** | Demotes (not removes) the clipboard export UI; `exportAllData` API unchanged. |
| **Dependency order** | Standalone; soft-sequence after 043 for the settings file. |

## Affected Files

| File | Action | Layer |
|---|---|---|
| `pubspec.yaml` | Modify — add `share_plus` | — |
| `lib/utils/csv_encoder.dart` | Create | Utils |
| `lib/services/export_service.dart` | Create | Service |
| `lib/presenters/export_presenter.dart` | Create | Presenter |
| `lib/views/settings/export_sheet.dart` | Create | View |
| `lib/views/settings_screen.dart` | Modify — rework Data section (new entry; clipboard → Advanced) | View |
| `test/utils/csv_encoder_test.dart`, `test/services/export_service_test.dart`, `test/presenters/export_presenter_test.dart` | Create | Tests |

## Interface Definitions

```dart
// === Utils — pure functions, no state ===
String encodeCsvField(Object? value);                    // RFC 4180 quoting; null → ''
String encodeCsv(List<String> headers, Iterable<List<Object?>> rows); // CRLF, UTF-8

// === ExportService — pure I/O ===
enum ExportDomain { transactions, accounts, bills, receivables, budgets, installments,
  nutrition, weight, bodyMeasurements, fasting, quests, activity, stats }

class ExportResult {
  final List<String> filePaths;
  final Map<ExportDomain, int> rowCounts;
  final Set<ExportDomain> skippedEmpty;
}

class ExportService {
  ExportService({required StorageService storage});
  Future<ExportResult> exportCsv(Set<ExportDomain> domains); // build → write temp → shareXFiles
  Future<ExportResult> exportJsonArchive();                  // {meta, domains:{...}} single file
}

// === ExportPresenter ===
class ExportPresenter extends ChangeNotifier {
  ExportPresenter(ExportService service);
  bool get isExporting;
  Set<ExportDomain> get selected;            // default: all non-empty
  void toggle(ExportDomain d);
  ExportResult? get lastResult;
  String? get error;
  Future<void> exportCsv();
  Future<void> exportArchive();
}
```

## Implementation Order (each = one logical commit)

### Step 1 — CSV encoder util
- `csv_encoder.dart` + exhaustive unit tests: commas/quotes/newlines in fields, embedded-quote
  doubling, CRLF endings, unicode pass-through, null → empty cell, no thousands separators.
- ✅ Spec acceptance #2 (formatting half).

### Step 2 — ExportService: CSV builders
- One private builder per domain mapping models → header/row lists per the spec §3 schemas
  (denormalize account/category names into transactions; flatten `DailyNutritionLog.meals` to
  one row per `FoodEntry`; fasting rows from `loadState()['history']`).
- Amounts as raw decimals (no ₱), dates `toIso8601String()`, skip-empty-domain behavior.
- Golden-string tests per domain from fixture models (mock `StorageService`).

### Step 3 — ExportService: file I/O + share
- Add `share_plus`; write files to `getTemporaryDirectory()/export/` with
  `nudgr_<domain>_<date>.csv` names; `Share.shareXFiles(...)`; purge stale temp exports first.
- JSON archive: `{meta: {app, version, exportedAt, schema: 1}, domains: {…}}` from model
  `toJson` lists — structured, not the raw prefs dump.
- ✅ Acceptance #1, #4.

### Step 4 — ExportPresenter
- Selection set, `isExporting` lifecycle (notify-before-await per optimistic-UI house pattern),
  error capture, result for the success toast ("9 files · 2,340 rows"). Tests with mocked service.
- ✅ Acceptance #6 (no jank: heavy work in service futures, view only listens).

### Step 5 — Export sheet + Settings rewire
- `export_sheet.dart`: `AppBottomSheet` with domain checklist (`AppSelectableTile`), two CTAs
  ("Share CSV files", "Share JSON archive") in the bottom 30%, progress state, result toast via
  `AppToast`. Theme-aware colors only; targets ≥44px; `AppMotion` for sheet entrance.
- `settings_screen.dart` Data section: "Export Data" tile → new sheet; existing clipboard
  export/import dialogs move under an "Advanced (clipboard)" row — unchanged behavior.
- ✅ Acceptance #7.

### Step 6 — Verification gate
- Guest-mode export manual check (typed loaders keep it scoped — acceptance #5).
- Open `transactions.csv` + `nutrition_log.csv` in Google Sheets; share to Drive and
  "Save to device" (the Downloads-fallback requirement, no extra permissions).
- `dart format` validation, `flutter analyze`, full `flutter test`. PR `--base dev`.

## RPG Impact
- XP: none. Streaks/levels untouched. Notifications: none. Pure read-only feature.

## Risks
- **Schema drift** — CSV columns are hand-mapped from models; a later model field silently
  missing from export. Mitigation: golden tests built from full-field fixtures; a comment block
  in each builder pointing at the source model.
- **Large exports on low-end devices** — a year of nutrition rows is thousands of lines of
  string-building. Mitigation: build per-domain strings in `compute`/chunks **only if** profiling
  shows jank; don't pre-optimize. Acceptance #6 is the gate.
- **share_plus temp-file lifetime** — some share targets read the file after our flow returns;
  never delete the just-shared files, only purge stale ones on the *next* export.
- **`settings_screen.dart` merge with 043** — sequence PRs; the change is additive tiles.

## Out of scope (future work)
- **Import/restore from exported files** (schema versioning + merge strategy — own plan; the
  clipboard import remains the only restore path for now).
- Zip bundling (`archive` pkg), direct MediaStore Downloads write, scheduled backups,
  photo/chat-transcript export.

## UX Verification
- [ ] Primary CTAs in bottom 30% of the sheet
- [ ] All touch targets ≥ 44×44px
- [ ] Sheet entrance ≤ 300ms (`AppMotion.modal`); no animation > 400ms
- [ ] Result toast glanceable in < 1 second
- [ ] Dark + light themes verified

## Acceptance Criteria
- [ ] Spec §5 criteria 1–8 all pass.
- [ ] No changes to `exportAllData`/`importAllData` or sync behavior.
- [ ] New util/service/presenter tests green; `dart format` + `flutter analyze` clean.
