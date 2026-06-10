# Plan 042 — Treasury Web Companion

> Status: PLANNED — NOT IMPLEMENTED
> Spec: [docs/treasury_web_spec.md](../../docs/treasury_web_spec.md)
> Branch: **`feat/042-treasury-web`** off `dev`. Own PR per phase (`--base dev`; dev→main auto-promotes).
> Authored: 2026-06-10

## Goal
Replace the laptop-side Google Sheet ("Personal_Financials_2026v2") with a **Flutter web build of the
Treasury module** — same Supabase backend the phone already syncs to, same presenters/views, deployed as
a website. One source of truth; every future treasury feature appears on web for free. See the spec's
**Decision Record** for why this beat a Sheets two-way sync (supersedes Plan 016's direction).

---

## Conflict Check

| Check | Finding |
|---|---|
| **File overlap** | Touches `fasting_app.dart` (theme extraction), `auth_service.dart`, `notification_service.dart`, `treasury_dashboard_presenter.dart`. No open plan edits these (041 finance portion merged; 039 merged). |
| **Model overlap** | No new models, no new StorageService keys (Phase 3 getters are pure computation). |
| **Presenter split** | Phase 3 getters land in `TreasuryDashboardPresenter` — its existing domain. |
| **XP routing** | No XP changes; web reuses existing presenter XP paths via `StatsPresenter`. |
| **HubScreen** | Untouched — web has its own shell, mobile hub unchanged. |
| **Supersedes** | **Plan 016 (Google Sheets Import) → mark SUPERSEDED** by this plan's Decision Record (Option B chosen; Phase 0 bridge covers the transition). |
| **Dependency order** | None hard. Phase 0 is optional and independent (no app code). Phases 1→4 are sequential. |

---

## Key architectural facts (verified in code, 2026-06-10)

- **Presenter graph is web-clean.** The seven treasury presenters (`ledger`, `treasury_dashboard`,
  `budget`, `bills_receivables`, `installment`, `grocery_cart`, `treasury_history`) depend only on
  `StorageService`, `StatsPresenter`, optional `AiCoachService`, and `NotificationService`. No sqflite,
  health, home_widget, or gemma imports anywhere in that graph.
- **The one web blocker is `NotificationService`** — a concrete singleton importing
  `flutter_local_notifications` + `flutter_timezone`, default-constructed inside `StatsPresenter`,
  `BudgetPresenter`, `BillsReceivablesPresenter`. Fix = `if (kIsWeb) return;` guards (see Phase 1),
  not a stub class — the singleton factory makes interface extraction noisier than guards.
- **`LocalStorageService` works on web unchanged** — pure `shared_preferences` (localStorage on web),
  `intl`, `dart:convert`. **`SyncService` works on web unchanged** — supabase_flutter,
  connectivity_plus, shared_preferences all have web implementations.
- **Auth needs a web branch.** `AuthService.signInWithGoogle()` uses the native `google_sign_in`
  ID-token flow; on web use `supabase.auth.signInWithOAuth(OAuthProvider.google)` redirect instead
  (`supabase_flutter` persists the session in localStorage and parses the redirect callback itself).
- **Non-web plugins never compile in.** `flutter build web -t lib/main_web.dart` only compiles the
  entrypoint's transitive imports; `health`, `home_widget`, `flutter_gemma`, `sqflite`,
  `path_provider`-dependent services (`FoodDbService`, `FoodPhotoStore`, `WidgetBridgeService`,
  `HealthService`, `OnDeviceAiCoachService`, `UpdateService`) are simply not imported by the web shell.
  The `NullAiCoachService` pattern already exists if an `AiCoachService` slot must be filled.
- Web project files don't exist yet (`flutter create . --platforms web` required once).

---

## Phasing (each its own PR)

### Phase 0 — OPTIONAL: one-way Sheets bridge (no app code)
A transition aid so the existing sheet's formulas can consume app-logged expenses while the web app
matures. Skippable if he's ready to cut over directly.
- Supabase **Edge Function `sheet-feed`** (Deno): reads `finance_records` rows
  (`table_name = 'transactions'`) with `updated_at > last_run`, appends `[date, account, description,
  category, inflow, outflow, note, record_id]` rows to a dedicated **"App Feed" tab** via the Google
  Sheets `values.append` API.
- Auth = **Google service account** (JWT, no OAuth refresh dance); the sheet is shared with the
  service-account email. Watermark stored in a small `sheet_feed_state` table. Scheduled via Supabase
  cron (every 30 min).
- **One-way, append-only.** Sheet edits never flow back. Duplicates impossible (`record_id` column +
  watermark). Per deploy-workflow memory: edge functions auto-deploy on main; the cron + state-table
  migration is applied manually.

### Phase 1 — Web entrypoint + service guards + auth
1. `flutter create . --platforms web` → `web/` (index.html, manifest, icons).
2. Extract `_darkTheme()`/`_lightTheme()` from `fasting_app.dart` into `lib/views/app_theme.dart`
   (pure refactor; mobile uses it too — zero behavior change).
3. `lib/main_web.dart` — minimal: `dotenv.load`, `runApp(TreasuryWebApp())`. **No** NotificationService
   init, no HomeWidget callback.
4. `lib/views/web/treasury_web_app.dart` — MaterialApp (themes from `app_theme.dart`) +
   `TreasuryWebShell`: builds `AuthService`, `LocalStorageService`, `SyncQueue`, `StatsPresenter`, the
   seven treasury presenters, `AuthPresenter`, and mirrors `AppShell._initSync`/`_tearDownSync`/
   `_reloadAll` minus widget-bridge/health/food-db/gemma wiring. Signed-out → web login screen.
5. `notification_service.dart`: `if (kIsWeb) return;` at top of `init()` and every schedule/cancel
   method (plus `?`-safe returns where a value is expected). Keeps Stats/Budget/Bills presenters
   constructible on web with zero call-site changes.
6. `auth_service.dart`: `kIsWeb` branch — `signInWithOAuth(OAuthProvider.google, redirectTo: <site
   URL>)`; skip `GoogleSignIn` construction on web. `AuthPresenter` already listens to
   `authStateChanges`, which fires after the redirect round-trip.
7. Verify: `flutter run -d chrome -t lib/main_web.dart` → sign in → `pullAll` populates treasury data
   logged from the phone; edits push through `SyncQueue` (3 s debounce) and appear on the phone.

### Phase 2 — Treasury module mount + responsive desktop layout
1. Mount the existing `TreasuryModuleView` as-is for narrow widths (< 840 dp) — free mobile-web parity.
2. ≥ 840 dp: `lib/views/web/treasury_web_scaffold.dart` — left `NavigationRail` (Dashboard / Ledger /
   Bills / Budget / History / Cart) replacing the bottom `TabBar`; content constrained to ~1200 dp;
   same per-tab `presenter.load()`-on-focus behavior as `TreasuryModuleView._onTabChanged`.
3. Wide-screen ledger: `lib/views/web/ledger_table_view.dart` — `PaginatedDataTable2`-style table
   (Date · Account · Description · Category · Inflow · Outflow · Note, monthly totals header) mirroring
   the sheet's "Detailed Records" tab; row click opens the existing `add_transaction_sheet.dart` as a
   dialog. Narrow widths keep the existing `LedgerView` list.
4. Two-pane patterns where they pay off: Bills (list | detail), Dashboard (metrics grid reflows from
   1-col to 3-col). All theme-aware (`Theme.of(context)` only), both modes.

### Phase 3 — Dashboard parity getters ("as detailed as the sheet")
All new math lives in **`TreasuryDashboardPresenter`** — so the mobile dashboard can surface these too.
Existing already: `netWorth`, `totalLiquidCash`, `monthTotalInflow/Outflow`, `monthUnpaidBills`,
`pendingReceivables`, `totalBudgetRemaining`, `forecastedNetBalance`, credit getters.
- New getters (pure, computed from already-loaded state):
  - `double get monthNetCashFlow` → `monthTotalInflow - monthTotalOutflow`
  - `double? get savingsRate` → `monthNetCashFlow / monthTotalInflow` (null when no income)
  - `double get totalAssets` (top-level non-liability, non-custodian — extract from `netWorth`)
  - `double get currentObligations` → `monthUnpaidBills + totalLiabilities`
  - `double get projectedSpareThisMonth` → alias of `forecastedNetBalance`, named for the UI
  - `AffordVerdict canAfford(double amount, {String? accountId})` → checks against
    `projectedSpareThisMonth` (and the account's spendable balance when given); returns
    verdict + spare-after figure for the "✅ YES — fits comfortably. About ₱19,855 spare left this
    month after bills & savings." copy.
- New web dashboard sections: Net-worth strip, This-Month strip (Income / Expenses / Net / Savings
  Rate), per-account balance table, "Can I afford it?" card (amount + account picker → verdict).
- Follow-up (separate small PR): surface savings rate + afford card on the **mobile** dashboard.

### Phase 4 — Deploy + CI
1. `.github/workflows/web-deploy.yml`: on push to `main` → `flutter build web --release
   -t lib/main_web.dart --base-href "/<repo>/"` (CI writes `.env` from secrets, as `ci.yml` already
   does) → deploy to **GitHub Pages** (`actions/deploy-pages`). Supabase has no first-class static
   hosting; Pages is free and already inside this repo's auth perimeter. (Custom domain later if wanted.)
2. Supabase dashboard: add the Pages URL to **Auth → URL Configuration** (site URL + redirect list).
3. Google Cloud console: add the Pages origin to the OAuth client's authorized JavaScript origins +
   redirect URIs (manual, one-time — document in `docs/setup`).
4. CORS: Supabase REST/auth allow browser origins by default — verify only; the cloud-AI API Gateway is
   NOT called from web in this plan (out of scope).
5. Extend `ci.yml` with a `flutter build web -t lib/main_web.dart` smoke job so mobile-first PRs can't
   silently break the web target.

---

## Affected Files

| File | Action | Phase | Layer |
|---|---|---|---|
| `supabase/functions/sheet-feed/index.ts` | Create (optional) | 0 | Backend |
| `web/` (index.html, manifest, icons) | Create (`flutter create`) | 1 | Platform |
| `lib/main_web.dart` | Create | 1 | Composition root |
| `lib/views/web/treasury_web_app.dart` | Create | 1 | View (shell) |
| `lib/views/web/web_login_view.dart` | Create | 1 | View |
| `lib/views/app_theme.dart` | Create (extracted) | 1 | Theme |
| `lib/views/fasting_app.dart` | Modify (use app_theme) | 1 | Theme |
| `lib/services/notification_service.dart` | Modify (kIsWeb guards) | 1 | Service |
| `lib/services/auth_service.dart` | Modify (web OAuth branch) | 1 | Service |
| `lib/views/web/treasury_web_scaffold.dart` | Create | 2 | View |
| `lib/views/web/ledger_table_view.dart` | Create | 2 | View |
| `lib/presenters/treasury_dashboard_presenter.dart` | Modify (parity getters) | 3 | Presenter |
| `lib/views/web/web_dashboard_view.dart` | Create | 3 | View |
| `lib/views/web/afford_calculator_card.dart` | Create | 3 | View |
| `.github/workflows/web-deploy.yml` | Create | 4 | CI |
| `.github/workflows/ci.yml` | Modify (web build smoke) | 4 | CI |
| `test/presenters/treasury_dashboard_presenter_test.dart` | Modify | 3 | Test |
| `docs/treasury_web_spec.md` | Create | — | Docs |

## RPG Impact
None new — web reuses existing presenter XP paths (`StatsPresenter` runs on web; level-ups simply show
no notification there thanks to the kIsWeb guards).

## Risks

| Risk | Mitigation |
|---|---|
| Plugin web-compat surprises (transitive `dart:io`) | Entrypoint isolation + Phase 4 CI web-build gate catches regressions on every PR. |
| Concurrent phone+web edits | Last-write-wins per record (existing sync semantics). Mitigate: pull-on-window-focus on web (mirror of `pullIfStale` on app resume); 3 s push debounce already batches. Documented as accepted for a single-user app. |
| Web session handling | supabase_flutter persists sessions in localStorage + auto-refreshes; PKCE default. Verify sign-out clears local data via existing `_tearDownSync` flush-before-wipe path. |
| RLS exposure (public site URL) | All tables already enforce `user_owns_row` policies (`docs/supabase_migration.sql`); anon key is public-by-design. Verify no service-role key ever enters `.env` assets. |
| `.env` shipped in web bundle | Contains only SUPABASE_URL/ANON_KEY/WEB_CLIENT_ID — all public-class values. RemoteSecrets (HF token) path not imported on web. |
| OAuth redirect misconfig (white-screen loop) | Documented one-time setup checklist in Phase 4; test on Pages preview before announcing cutover. |
| Theme extraction regression | Pure move; `flutter test` + visual smoke in both modes on mobile before merging Phase 1. |

## Test Plan
- **Unit:** Phase 3 getters (`savingsRate` null-income, `canAfford` verdict tiers/spare math,
  `totalAssets` vs `netWorth` consistency) in `treasury_dashboard_presenter_test.dart`.
  NotificationService guard test: methods are no-ops under `kIsWeb` (debugDefaultTargetPlatform aside,
  verify via injected fake in presenter tests as today).
- **Widget:** web scaffold renders rail ≥ 840 dp / tabs below; ledger table renders rows + monthly
  totals; afford card verdict strings; both themes.
- **Manual E2E:** phone logs expense → appears on web ≤ stale-pull window; web edit → phone on resume;
  sign-out on web wipes localStorage data; fresh browser + login restores everything from cloud;
  Phase 0 (if built): expense appears in "App Feed" tab within one cron tick, no duplicates on re-run.

## Out of scope (future)
- Two-way Google Sheets sync (rejected — see spec Decision Record); Phase 0 bridge is one-way only.
- AI chat logging on web (CloudAiCoachService is web-compatible — natural follow-up plan).
- Fasting/nutrition/quests on web; PWA install/offline-first packaging; multi-user sharing.
- Mobile dashboard surfacing of the new getters (small follow-up PR, noted in Phase 3).

## Acceptance Criteria
- [ ] `flutter build web -t lib/main_web.dart` succeeds in CI; mobile builds/tests unaffected.
- [ ] Google sign-in on the deployed site → treasury data pulled from Supabase appears.
- [ ] All six treasury tabs usable on web; ≥ 840 dp shows rail + data-table ledger.
- [ ] Edits on web sync to the phone and vice versa (same record, last write wins).
- [ ] Web dashboard shows Net Worth, Total Assets, Obligations, Income/Expenses/Net/Savings-rate,
      per-account balances, outstanding bills/budget, projected spare, receivables, afford calculator —
      full parity list in spec §4.
- [ ] No `AppColors.*` hardcoding; both themes verified on web.
- [ ] (If Phase 0 built) app expenses appear append-only in the sheet's "App Feed" tab, idempotently.
