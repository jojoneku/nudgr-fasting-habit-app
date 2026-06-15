# Treasury Web Companion Spec

> Status: PLANNED — NOT IMPLEMENTED · Owner: Treasury · Plan: [.claude/plans/042-treasury-web-companion.md](../.claude/plans/042-treasury-web-companion.md)
> Related: Plan 016 (Google Sheets Import — **superseded by this spec's Decision Record**), Plan 014/015 (Supabase sync), Plan 040 (credit accounts, shipped).
> Date: 2026-06-10

## 1. Problem

Finances live in two places: a Google Sheet (**Personal_Financials_2026v2**) on the laptop, and the
app's Treasury module on the phone. Both are "the ledger", neither is complete — expenses logged on the
phone never reach the sheet's running balances; sheet entries never reach the app's budgets, bills, or
net worth. Reconciling by hand defeats the point of tracking.

The data the app holds is already cloud-synced: every transaction, account, bill, budget, receivable,
and installment lands in Supabase `finance_records` via `SyncService`. What's missing is a **desktop
surface** as detailed as the sheet.

## 2. Decision Record — Sheets sync vs. Web Companion

| | **Option A — Google Sheets two-way sync** | **Option B — Treasury Web Companion (CHOSEN)** |
|---|---|---|
| What | App ↔ sheet via Sheets API (evolution of Plan 016) | Flutter **web** build of the Treasury module + read-only-rich dashboard, same Supabase backend |
| Short-term effort | Lower — keeps the familiar sheet | Higher — entrypoint, responsive layout, deploy |
| Format coupling | **Fragile.** The sheet has merged headers, computed running-balance and budget-remaining columns, "Jun-4" date strings; every sheet redesign breaks the column mapping | **None.** Data is structured app models; the sheet's look is reproduced by code, not parsed from cells |
| Auth | OAuth user tokens; refresh via Supabase provider-token is painful and expires | Existing Supabase Google sign-in; sessions auto-refresh |
| Conflict model | Two-way merge between a free-form grid and structured records — genuinely hard (which cell wins? how to diff a recomputed column?) | One backend; phone and web are just two clients of the same sync pipeline |
| Scalability | Every new treasury feature (credit accounts, cart, installments) needs new sheet mapping work | **Free.** Any new presenter/view ships on web with the next deploy |
| Verdict | Easier now, permanent maintenance tax | More work now, structurally correct |

**Decision: Option B.** The sheet stops being a data store and becomes, at most, a read-only consumer.

**Transition bridge (optional, Phase 0):** a one-way, append-only export — Supabase Edge Function +
Google **service account** (sheet shared with the service-account email) appends app-logged
transactions to a dedicated **"App Feed" tab** on a cron. Existing sheet formulas can reference that
tab during the migration. No app changes, no OAuth refresh, no write-back, trivially deletable once the
web app fully replaces the sheet.

## 3. Goals

1. **Web build of Treasury** — all six tabs (Dashboard, Ledger, Bills, Budget, History, Cart) usable in
   a browser, reading/writing the same Supabase data the phone syncs.
2. **Sheet-parity dashboard** (§4) — the web dashboard answers everything DASHBOARD answers today,
   including a **"Can I afford it?"** calculator.
3. **Desktop-grade layout** — NavigationRail ≥ 840 dp, data-table ledger, two-pane bills; phone-style
   layout below that (free mobile-web).
4. **Single codebase** — web is a second entrypoint (`main_web.dart`), not a fork. Presenters are
   shared; new dashboard math lands in `TreasuryDashboardPresenter` so mobile benefits too.

### Non-goals (this round)
- Two-way sheet sync; importing historical sheet rows (already handled by the archived historical
  importer); fasting/nutrition/quests on web; AI chat logging on web; offline-first PWA; multi-user.

## 4. Parity target — the Google Sheet

The sheet is the bar for "detailed enough". Mapping:

| Sheet tab | Web equivalent | Status of underlying data |
|---|---|---|
| **DASHBOARD** | Web dashboard (§7.2) | Mostly existing getters; gaps in §6 |
| **Detailed Records** (Date, Account, Description, Category, Inflow, Outflow, running Balance*, budget-remaining*, Notes; monthly totals on top) | Ledger data table; running balance & budget-remaining are computed columns (presenter-derived, never stored) | Exists (`LedgerPresenter`) |
| **Bills & Receivables** (Name, Type Installment/Credit Card/Bills, Amount, Due "15th", Status, Notes) | Bills tab (existing `BillsReceivablesView` + `InstallmentPresenter`) | Exists |
| **Budget & Expense** | Budget tab | Exists |
| **Allocation** | Budget groups (existing `BudgetGroup` breakdown) | Exists |
| **Setup and Accounts** | Account setup (existing `account_setup_view.dart`) | Exists |
| **Historical Summary** | History tab (`TreasuryHistoryPresenter` monthly summaries) | Exists |
| **Filtered View** | Ledger table filters (account/category/month) | Partial — table filters in Phase 2 |

\* computed in the sheet; stay computed in the app.

**DASHBOARD line-items to reproduce:** Liquid Cash · Total Assets · Current Obligations · Net Worth ·
this-month Income / Expenses / Net Cash Flow / Savings Rate · per-account liquid balances (BPI
Personal, GCASH, MAYA, CASH, Maribank, GoTyme, BPI Vybe, BPI Credit Card available limit) ·
Outstanding Bills · Outstanding Budget/Savings · Projected Spare (this month) · Total Receivables ·
**"Can I afford it?"** (amount + account → *"✅ YES — fits comfortably. About ₱19,855 spare left this
month after bills & savings."*).

## 5. Architecture

### 5.1 Entrypoint isolation (the core trick)
`flutter build web -t lib/main_web.dart` compiles only the entrypoint's transitive imports. The web
shell wires **auth + storage + sync + stats + the seven treasury presenters** and nothing else, so the
non-web plugins (`health`, `home_widget`, `flutter_gemma`, `sqflite`, `path_provider`,
`flutter_local_notifications`) never enter the build — no stub classes needed for services that are
simply not constructed (`FoodDbService`, `HealthService`, `WidgetBridgeService`,
`OnDeviceAiCoachService`, `UpdateService`). Constructor injection makes this clean; the
`NullAiCoachService` precedent covers the optional `AiCoachService` slot if ever needed.

**One exception:** `NotificationService` sits *inside* the treasury graph (default-constructed by
`StatsPresenter`, `BudgetPresenter`, `BillsReceivablesPresenter`). It gains `if (kIsWeb) return;`
guards in `init()` and every schedule/cancel method — zero call-site changes, mobile untouched.

```dart
// lib/main_web.dart (shape)
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');          // public-class values only
  runApp(const TreasuryWebApp());               // themes from lib/views/app_theme.dart (extracted)
}
```

`TreasuryWebShell` mirrors `AppShell`: `AuthService` → `LocalStorageService` → `SyncQueue` →
`StatsPresenter` → `LedgerPresenter(storage, stats)` → dashboard/budget/bills/history/installment/cart
presenters (same constructor order as `home_screen.dart`), `AuthPresenter` with
`onFirstSignIn → _initSync` / `onSignOut → _tearDownSync` (flush-before-wipe preserved).

### 5.2 Web service compatibility (verified against pubspec 2026-06-10)

| Works unchanged | Needs a web branch | Excluded by entrypoint |
|---|---|---|
| `shared_preferences` (localStorage) → `LocalStorageService` | `auth_service.dart` — google_sign_in native flow → `signInWithOAuth` redirect on web | `flutter_local_notifications`*, `health`, `home_widget`, `flutter_gemma`, `sqflite`, `path_provider`, `flutter_timezone` |
| `supabase_flutter`, `connectivity_plus`, `http` → `SyncService`/`SyncQueue` as-is | `notification_service.dart` — kIsWeb no-op guards* | `image_picker`/`flutter_image_compress` (photo logging — not on web) |
| `intl`, `google_fonts`, `flex_color_scheme`, `skeletonizer`, `url_launcher`, `table_calendar`, `crypto`, `flutter_dotenv` | | `flutter_secure_storage` (unused by treasury graph) |

\* guarded rather than excluded because it's reachable from treasury presenters.

### 5.3 Auth & session on web
- Sign-in: `supabase.auth.signInWithOAuth(OAuthProvider.google, redirectTo: siteUrl)` — full-page
  redirect; `supabase_flutter` parses the callback and emits on `authStateChanges`, which
  `AuthPresenter` already consumes. PKCE flow (SDK default), session persisted in localStorage,
  auto-refreshed.
- One-time config: site URL + redirect URLs in Supabase Auth settings; authorized JS origins/redirects
  on the existing Google OAuth client.
- Sign-out reuses the flush-before-wipe path (PR #185 semantics) so unsynced web edits are pushed
  before localStorage is cleared.

### 5.4 Sync flow (unchanged semantics)
Login → `setUserId` (scoped keys) → reload presenters → `SyncService.init()` → `pullAll()` →
`pushPending()` → `pushAll()`. Mutations mark dirty → `SyncQueue` → 3 s debounced push. Web addition:
**pull on window focus** (the browser analogue of `pullIfStale` on app resume) so a laptop tab left
open catches up with phone edits. Conflicts remain **last-write-wins per record** — acceptable for a
single user on two devices; called out in the UI nowhere (no UX cost), documented here.

## 6. New presenter API (`TreasuryDashboardPresenter`)

Already available: `netWorth`, `totalLiquidCash`(+gross/held), `monthTotalInflow/Outflow`,
`monthUnpaidBills`, `pendingReceivables`, `totalBudgetAllocated/Spent/Remaining`,
`forecastedNetBalance`, `endingCash`, credit getters (`totalCreditOwed/Available`, `creditDueInfo`,
`creditMinimumDue`). New (pure computation, no storage keys — **mobile gets these for free**):

```dart
double get monthNetCashFlow;        // monthTotalInflow − monthTotalOutflow
double get monthSavingsContributions; // net flow INTO locked (savings/goal/TD/investment) accounts this month
double? get savingsRate;            // monthSavingsContributions / monthTotalInflow; null when no income
// NB: monthTotalInflow/Outflow exclude internal transfer legs (transferGroupId != null) —
// moving money between your own accounts is neither income nor an expense.
double get totalAssets;             // top-level, non-liability, non-custodian (factored out of netWorth)
double get currentObligations;      // monthUnpaidBills + totalLiabilities
double get projectedSpareThisMonth; // forecastedNetBalance, named for the UI

AffordVerdict canAfford(double amount, {String? accountId});
// AffordVerdict { tier: yes | tight | no, spareAfter: double, accountShortfall: double? }
// yes:   amount ≤ projectedSpare × 0.8        → "✅ YES — fits comfortably. About ₱X spare left…"
// tight: amount ≤ projectedSpare              → "⚠️ Tight — possible, but only ₱X spare after bills & savings."
// no:    amount > projectedSpare or > account spendable (balance − held) → "❌ Not this month…"
```

Thresholds live in the presenter (Rule 1: no math in `build()`); copy strings live in the view layer.
All amounts render through the existing `finance_format.dart` peso formatting (₱, comma-grouped).

## 7. UI

### 7.1 Responsive shell
- **< 840 dp:** existing `TreasuryModuleView` (bottom tabs) — unchanged code path.
- **≥ 840 dp:** `NavigationRail` left (six destinations), content max-width ~1200 dp, per-tab
  `load()`-on-focus preserved. Theme-aware only (`Theme.of(context)`), dark default + light supported.

### 7.2 Web dashboard (sheet DASHBOARD parity)
Three bands, top to bottom: **Position** (Net Worth hero · Liquid Cash · Total Assets · Current
Obligations), **This Month** (Income · Expenses · Net Cash Flow · Savings Rate · Projected Spare ·
Outstanding Bills · Outstanding Budget/Savings · Receivables), **Accounts & tools** (per-account
balance table incl. credit available-limit rows, reusing `heldAmountByAccountId` for "yours vs held";
**Can I afford it?** card: amount field + account dropdown → verdict line). Cards on the background use
`surfaceContainerLow` per the house elevation rule.

### 7.3 Ledger data table (sheet "Detailed Records" parity)
Columns: Date · Account · Description · Category · Inflow · Outflow · Balance (computed running, per
the filtered account scope) · Notes. Month section headers with inflow/outflow totals (the sheet's
"monthly totals at top"). Filters: month, account, category — covers the sheet's "Filtered View" tab.
Row click → existing transaction sheet as a dialog. Below 840 dp the existing `LedgerView` renders.

## 8. Persistence, security, deploy

- **No schema changes.** Same `finance_records` table, same `SyncDomain.financeRecord`, same RLS
  (`user_owns_row` policies in `docs/supabase_migration.sql`) — the browser uses the same anon key +
  JWT as the phone, so a public site URL exposes nothing without a session.
- `.env` is bundled into the web build — contains only `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
  `GOOGLE_WEB_CLIENT_ID` (all public-class). The HF-token path (`RemoteSecretsService`) is not in the
  web graph; the service-role key must never enter `.env`.
- **Hosting: GitHub Pages** via a `web-deploy.yml` workflow on `main` (CI already writes `.env` from
  secrets). Supabase offers no first-class static hosting. CORS: Supabase REST/auth accept browser
  origins by default — verify only.
- `ci.yml` gains a `flutter build web -t lib/main_web.dart` smoke job so mobile PRs can't break web.

## 9. Acceptance criteria

1. Deployed site: Google sign-in completes (redirect flow) and pulls the same treasury data the phone
   shows; session survives a browser restart.
2. All six treasury tabs function on web; a transaction added on web appears on the phone (next
   resume/pull) and vice versa.
3. ≥ 840 dp shows rail + ledger data table with monthly totals, running balance, and filters; < 840 dp
   shows the phone layout.
4. Web dashboard shows every §4 DASHBOARD line-item; `canAfford(₱X, account)` returns the correct tier
   and spare-after figure (matches hand-computed sheet logic).
5. New getters covered by unit tests incl. zero-income (`savingsRate == null`) and over-spare cases.
6. Mobile app builds, tests, and behaves identically (theme extraction + notification guards are
   no-ops on device); no `AppColors.*` hardcoding in any new widget; both themes verified.
7. (If Phase 0 built) phone-logged expenses appear append-only in the sheet's "App Feed" tab within one
   cron tick, idempotent across re-runs.

## 10. Test plan (high level)
- `treasury_dashboard_presenter_test`: new getters + `canAfford` tiers/edges.
- Service tests: NotificationService methods no-op under web guard (via injected fake as today);
  AuthService web-branch selection.
- Widget: web scaffold breakpoint switch; ledger table rows/totals; afford card verdict rendering —
  light + dark.
- Manual E2E: cross-device sync both directions; sign-out flush-before-wipe on web; fresh-browser
  restore; OAuth redirect on the deployed Pages URL.
