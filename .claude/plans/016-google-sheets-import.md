# Plan 016: Google Sheets Import

## Overview
Allow users to import their existing expense data from a Google Sheets file directly into the app via Google Sheets API + OAuth 2.0. This eliminates manual re-entry for users who already track finances in Sheets.

## User's Sheet Structure
The user's file mirrors the app's own Treasury module:

| Sheet Tab | Action |
|-----------|--------|
| Transactions (detailed) | ✅ Import |
| Bills & Receivables | ✅ Import |
| Budgets & Expenses | ✅ Import |
| Dashboard | ⏭ Skip (calculated) |
| Historical Summary | ⏭ Skip (aggregate) |

### Transaction Sheet Columns
| Sheet Column | App Field | Notes |
|---|---|---|
| date | `TransactionRecord.date` | Parse multiple date formats |
| account | `accountId` | Match by name; prompt to create if missing |
| description | `description` | Direct map |
| category | `categoryId` | Match by name; prompt to create if missing |
| inflow | `amount` + `type: inflow` | When > 0 |
| outflow | `amount` + `type: outflow` | When > 0 |
| note | `note` | Direct map |
| balance | (skip) | Calculated by app |
| category budget remaining | (skip) | Calculated by app |

## Architecture

### New Files
| File | Role |
|---|---|
| `lib/services/google_sheets_service.dart` | Auth (Google Sign-In), Sheets API read, tab listing, sheet ID extraction from URL |
| `lib/presenters/sheets_import_presenter.dart` | Import orchestration: column detection, row parsing, duplicate detection, account/category resolution, preview list |
| `lib/models/finance/sheet_column_map.dart` | Maps sheet column index → app field; auto-detected from header row |
| `lib/views/settings/sheets_import/google_signin_screen.dart` | Step 1 — Google OAuth screen |
| `lib/views/settings/sheets_import/sheet_url_screen.dart` | Step 2 — Paste/enter sheet URL |
| `lib/views/settings/sheets_import/column_mapping_screen.dart` | Step 3 — Review/override column mapping |
| `lib/views/settings/sheets_import/import_preview_screen.dart` | Step 4 — Preview rows (new / duplicate badges) |
| `lib/views/settings/sheets_import/import_result_screen.dart` | Step 5 — Summary: X added, Y skipped, Z errors |

### Modified Files
| File | Change |
|---|---|
| `lib/views/settings_screen.dart` | Add "Import from Google Sheets" entry under new Data section |
| `pubspec.yaml` | Add `google_sign_in`, `googleapis` (or `extension_google_sign_in_as_googleapis_auth`) |
| `android/app/google-services.json` | New file (user provides from Google Cloud Console) |
| `android/app/build.gradle.kts` | Apply `google-services` plugin |

## Prerequisites (Manual — User Must Complete)
Before building, the user must set up Google Cloud:

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Create a new project (e.g. "Nudgr")
3. Enable **Google Sheets API** and **Google Drive API**
4. Go to **APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID**
5. Application type: **Android**
6. Package name: `com.nudgr.app`
7. SHA-1 fingerprint (run this):
   ```
   keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```
8. Download `google-services.json` → place at `android/app/google-services.json`

## Import Flow (UX)
```
Settings → "Import from Google Sheets"
  → [Step 1] Google Sign-In (OAuth)
  → [Step 2] Paste Sheet URL
  → [Step 3] Select tab (Transactions / Bills / Budgets)
  → [Step 4] Review column mapping (auto-detected, overridable)
  → [Step 5] Preview: list of rows with NEW / DUPLICATE badges
  → [Confirm] → Import
  → [Step 6] Result summary (added / skipped / errors)
```

## Duplicate Detection
A transaction is considered a duplicate if an existing record matches on:
- Same `date` (day precision)
- Same `amount`
- Same `description` (case-insensitive trim)

Duplicates are shown in preview but skipped on import (not an error).

## Account & Category Resolution
1. Try exact name match (case-insensitive) against existing accounts/categories
2. If no match → flag as "NEW" in preview → create on import
3. User can override the mapping in the column mapping screen

## Phases

### Phase 1: Foundation
- Add packages (`google_sign_in`, `googleapis`)
- Implement `GoogleSheetsService` (auth + read)
- Write `SheetColumnMap` model + auto-detection

### Phase 2: Import Logic
- Implement `SheetsImportPresenter`
  - Row parsing (Transactions, Bills, Budgets)
  - Duplicate detection
  - Account/category resolution

### Phase 3: UI
- Settings entry point
- 5-step import flow screens

### Phase 4: Polish
- Error handling (network, invalid URL, permission denied, empty sheet)
- Sign-out / disconnect in Settings
- Support re-running import (idempotent via duplicate detection)

## Open Questions
- Should Bills & Receivables import be in the same flow or a separate option?
- Should we support incremental sync (only import rows newer than last import date)?
- What date formats does the user's sheet use? (e.g. MM/DD/YYYY vs YYYY-MM-DD)
